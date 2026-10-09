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

    if @params[:min_salary_usd].present?
      begin
        min_salary = Integer(@params[:min_salary_usd])
        if min_salary < 0
          return fail_result("invalid_parameter", "min_salary_usd must be a non-negative integer")
        end
      rescue ArgumentError, TypeError
        return fail_result("invalid_parameter", "min_salary_usd must be a non-negative integer")
      end

      # Must be annual USD compensation meeting or exceeding minimum
      scope = scope.where(salary_currency: "USD", salary_period: "year")
                   .where("COALESCE(canonical_postings.salary_max, canonical_postings.salary_min) >= ?", min_salary)
    end

    # 3. Scoring and ordering
    scores = {}
    if lexemes.any?
      score_sql = build_score_sql(lexemes)
      scope = scope.select("canonical_postings.*, (#{score_sql}) AS relevance_score")
    end

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

    postings = scope.limit(limit).to_a

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
      limit: limit
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

  def fail_result(code, message)
    Result.new(
      success?: false,
      error_code: code,
      error_message: message
    )
  end
end
