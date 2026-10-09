class SearchPostings
  ALLOWED_REMOTE_TYPES = %w[onsite hybrid remote unknown].freeze
  ALLOWED_EMPLOYMENT_TYPES = %w[full_time part_time contract internship temporary unknown].freeze
  ALLOWED_SORTS = %w[relevance newest company title].freeze

  Result = Struct.new(
    :success?,
    :postings,
    :scores,
    :sort,
    :query,
    :limit,
    :next_cursor,
    :corpus_revision,
    :error_code,
    :error_message,
    keyword_init: true
  )

  def self.call(params = {})
    new(params).call
  end

  def initialize(params = {})
    @params = params
  end

  def call
    validation_error = validate_params
    return validation_error if validation_error

    limit = parse_limit
    q_param = @params[:q]&.to_s&.strip
    lexemes = q_param.present? ? extract_lexemes(q_param) : []

    if q_param.present? && q_param.length > 120
      return fail_result("invalid_parameter", "q must be at most 120 characters")
    end

    if lexemes.length > 8
      return fail_result("invalid_parameter", "q contains too many query terms (max 8)")
    end

    sort = @params[:sort].presence
    if sort.present?
      unless ALLOWED_SORTS.include?(sort)
        return fail_result("invalid_parameter", "sort must be one of: #{ALLOWED_SORTS.join(', ')}")
      end

      if sort == "relevance" && lexemes.empty?
        return fail_result("invalid_parameter", "sort=relevance is only supported when a keyword query (q) is present")
      end
    else
      sort = lexemes.any? ? "relevance" : "newest"
    end

    # Query digest for cursor validation
    min_sal_val = nil
    if @params[:min_salary_usd].present?
      begin
        min_sal_val = Integer(@params[:min_salary_usd])
        if min_sal_val < 0
          return fail_result("invalid_parameter", "min_salary_usd must be a non-negative integer")
        end
      rescue ArgumentError, TypeError
        return fail_result("invalid_parameter", "min_salary_usd must be a non-negative integer")
      end
    end

    normalized_query_params = {
      "company" => @params[:company].to_s.strip.downcase.presence,
      "employment_type" => @params[:employment_type].to_s.strip.presence,
      "location" => @params[:location].to_s.strip.downcase.presence,
      "min_salary_usd" => min_sal_val,
      "q" => q_param.presence,
      "remote_type" => @params[:remote_type].to_s.strip.presence,
      "sort" => sort
    }
    query_digest = CursorToken.compute_query_digest(normalized_query_params)
    corpus_revision = ApprovedReleaseManager.current_revision

    cursor_tuple = nil
    if @params[:cursor].present?
      decode_result = CursorToken.decode(
        @params[:cursor],
        expected_revision: corpus_revision,
        expected_query_digest: query_digest
      )

      unless decode_result.valid?
        return fail_result(decode_result.error_code, decode_result.error_message)
      end

      cursor_tuple = decode_result.payload["tuple"]
    end

    scope = CanonicalPosting.active_approved.includes(source_mentions: :source_record)

    # 1. Full-text search candidate filter
    if lexemes.any?
      scope = scope.where(
        "canonical_postings.search_vector @@ plainto_tsquery('english', ?)",
        q_param
      )
    end

    # 2. Filters
    if @params[:company].present?
      company_val = @params[:company].to_s.strip
      if company_val.length > 120
        return fail_result("invalid_parameter", "company must be at most 120 characters")
      end
      scope = scope.where("LOWER(canonical_postings.company) = LOWER(?)", company_val)
    end

    if @params[:location].present?
      location_val = @params[:location].to_s.strip
      if location_val.length > 120
        return fail_result("invalid_parameter", "location must be at most 120 characters")
      end
      scope = scope.where("LOWER(canonical_postings.location) = LOWER(?)", location_val)
    end

    if @params[:remote_type].present?
      remote_val = @params[:remote_type].to_s.strip
      unless ALLOWED_REMOTE_TYPES.include?(remote_val)
        return fail_result("invalid_parameter", "remote_type must be one of: #{ALLOWED_REMOTE_TYPES.join(', ')}")
      end
      scope = scope.where(remote_type: remote_val)
    end

    if @params[:employment_type].present?
      emp_val = @params[:employment_type].to_s.strip
      unless ALLOWED_EMPLOYMENT_TYPES.include?(emp_val)
        return fail_result("invalid_parameter", "employment_type must be one of: #{ALLOWED_EMPLOYMENT_TYPES.join(', ')}")
      end
      scope = scope.where(employment_type: emp_val)
    end

    if min_sal_val.present?
      scope = scope.where(salary_currency: "USD", salary_period: "year")
                   .where("COALESCE(canonical_postings.salary_max, canonical_postings.salary_min) >= ?", min_sal_val)
    end

    # 3. Scoring
    score_sql = nil
    if lexemes.any?
      score_sql = build_score_sql(lexemes)
      scope = scope.select("canonical_postings.*, (#{score_sql}) AS relevance_score")
    end

    # 4. Keyset cursor filtering
    if cursor_tuple.present?
      scope = apply_keyset_filter(scope, sort, cursor_tuple, score_sql)
    end

    # 5. Ordering
    scope = case sort
            when "relevance"
              scope.order(Arel.sql("(#{score_sql}) DESC, canonical_postings.public_id ASC"))
            when "newest"
              scope.order(Arel.sql("canonical_postings.last_observed_at DESC, canonical_postings.public_id ASC"))
            when "company"
              scope.order(Arel.sql("LOWER(canonical_postings.company) ASC, canonical_postings.public_id ASC"))
            when "title"
              scope.order(Arel.sql("LOWER(canonical_postings.title) ASC, canonical_postings.public_id ASC"))
            end

    # Lookahead: fetch limit + 1 records to check if next page exists
    records = scope.limit(limit + 1).to_a
    scores = {}

    if records.length > limit
      postings = records[0...limit]
      last_item = postings.last
      next_tuple = build_sort_tuple(last_item, sort)
      next_cursor = CursorToken.encode(
        corpus_revision: corpus_revision,
        query_digest: query_digest,
        sort_tuple: next_tuple
      )
    else
      postings = records
      next_cursor = nil
    end

    if lexemes.any?
      postings.each do |p|
        scores[p.id] = p.attributes["relevance_score"].to_i
      end
    end

    Result.new(
      success?: true,
      postings: postings,
      scores: scores,
      sort: sort,
      query: q_param.presence,
      limit: limit,
      next_cursor: next_cursor,
      corpus_revision: corpus_revision
    )
  end

  private

  def validate_params
    if @params[:limit].present?
      begin
        parsed = Integer(@params[:limit])
        if parsed < 1 || parsed > 50
          return fail_result("invalid_parameter", "limit must be from 1 to 50")
        end
      rescue ArgumentError, TypeError
        return fail_result("invalid_parameter", "limit must be from 1 to 50")
      end
    end
    nil
  end

  def parse_limit
    return 20 if @params[:limit].blank?
    Integer(@params[:limit])
  rescue ArgumentError, TypeError
    20
  end

  def extract_lexemes(query_str)
    sanitized = ActiveRecord::Base.sanitize_sql_array([
      "SELECT unnest(tsvector_to_array(to_tsvector('english', ?)))",
      query_str
    ])
    ActiveRecord::Base.connection.select_values(sanitized)
  rescue StandardError
    []
  end

  def build_score_sql(lexemes)
    terms = lexemes.map do |lex|
      quoted = ActiveRecord::Base.connection.quote(lex)
      <<~SQL
        (CASE WHEN to_tsvector('english', coalesce(canonical_postings.title, '')) @@ to_tsquery('english', #{quoted}) THEN 8 ELSE 0 END) +
        (CASE WHEN to_tsvector('english', coalesce(canonical_postings.company, '')) @@ to_tsquery('english', #{quoted}) THEN 5 ELSE 0 END) +
        (CASE WHEN to_tsvector('english', coalesce(canonical_postings.location, '')) @@ to_tsquery('english', #{quoted}) THEN 3 ELSE 0 END) +
        (CASE WHEN to_tsvector('english', coalesce(canonical_postings.summary_excerpt, '')) @@ to_tsquery('english', #{quoted}) THEN 1 ELSE 0 END)
      SQL
    end
    "(#{terms.join(' + ')})"
  end

  def apply_keyset_filter(scope, sort, tuple, score_sql)
    last_id = ActiveRecord::Base.connection.quote(tuple[1].to_s)

    case sort
    when "relevance"
      last_score = tuple[0].to_i
      scope.where("((#{score_sql}) < :score) OR (((#{score_sql}) = :score) AND canonical_postings.public_id > :id)", score: last_score, id: tuple[1].to_s)
    when "newest"
      last_time = Time.parse(tuple[0].to_s).utc
      scope.where("canonical_postings.last_observed_at < :time OR (canonical_postings.last_observed_at = :time AND canonical_postings.public_id > :id)", time: last_time, id: tuple[1].to_s)
    when "company"
      last_comp = tuple[0].to_s.downcase
      scope.where("LOWER(canonical_postings.company) > :comp OR (LOWER(canonical_postings.company) = :comp AND canonical_postings.public_id > :id)", comp: last_comp, id: tuple[1].to_s)
    when "title"
      last_title = tuple[0].to_s.downcase
      scope.where("LOWER(canonical_postings.title) > :title OR (LOWER(canonical_postings.title) = :title AND canonical_postings.public_id > :id)", title: last_title, id: tuple[1].to_s)
    else
      scope
    end
  end

  def build_sort_tuple(posting, sort)
    case sort
    when "relevance"
      [posting.attributes["relevance_score"].to_i, posting.public_id]
    when "newest"
      [posting.last_observed_at.iso8601, posting.public_id]
    when "company"
      [posting.company.downcase, posting.public_id]
    when "title"
      [posting.title.downcase, posting.public_id]
    end
  end

  def fail_result(code, message)
    Result.new(
      success?: false,
      error_code: code,
      error_message: message
    )
  end
end
