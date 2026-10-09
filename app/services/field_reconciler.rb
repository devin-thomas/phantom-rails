class FieldReconciler
  AUTHORITY_RANKS = {
    "official_employer" => 1,
    "third_party_board" => 2,
    "email_digest" => 3,
    "other_reviewed" => 4
  }.freeze

  ReconciliationResult = Struct.new(:chosen_fields, :selections, :conflicts, keyword_init: true)

  def self.reconcile!(canonical_posting)
    new(canonical_posting).reconcile!
  end

  def initialize(posting)
    @posting = posting
  end

  def reconcile!
    revisions_scope = if @posting.approved_release_id.present?
      @posting.approved_revisions
    else
      SourceRevision.joins(source_mention: :source_record)
                    .where(source_mentions: { canonical_posting_id: @posting.id })
    end
    revisions = revisions_scope.includes(source_mention: :source_record).to_a

    return ReconciliationResult.new(chosen_fields: {}, selections: {}, conflicts: {}) if revisions.empty?

    chosen = {}
    selections = {}
    conflicts = {}

    # Fields to reconcile
    reconcile_simple_field("title", revisions, chosen, selections, conflicts) { |r| r.title }
    reconcile_simple_field("company", revisions, chosen, selections, conflicts) { |r| r.company }
    reconcile_simple_field("location", revisions, chosen, selections, conflicts) { |r| r.location }
    reconcile_simple_field("remote_type", revisions, chosen, selections, conflicts) { |r| r.remote_type }
    reconcile_simple_field("employment_type", revisions, chosen, selections, conflicts) { |r| r.employment_type }
    reconcile_simple_field("summary_excerpt", revisions, chosen, selections, conflicts) { |r| r.summary_excerpt }
    reconcile_simple_field("job_url", revisions, chosen, selections, conflicts) { |r| r.job_url }
    reconcile_salary_field(revisions, chosen, selections, conflicts)

    # Persist FieldSelections
    selections.each do |field_name, sel_data|
      fs = @posting.field_selections.find_or_initialize_by(field_name: field_name)
      fs.source_revision = sel_data[:revision]
      fs.selection_reason = sel_data[:reason]
      fs.save!
    end

    # Update CanonicalPosting projections
    obs_times = revisions.map(&:observed_at).compact
    @posting.update!(
      title: chosen["title"] || @posting.title,
      company: chosen["company"] || @posting.company,
      location: chosen["location"] || @posting.location,
      remote_type: chosen["remote_type"] || "unknown",
      employment_type: chosen["employment_type"] || "unknown",
      summary_excerpt: chosen["summary_excerpt"],
      job_url: chosen["job_url"],
      salary_min: chosen.dig("salary", "min"),
      salary_max: chosen.dig("salary", "max"),
      salary_currency: chosen.dig("salary", "currency"),
      salary_period: chosen.dig("salary", "period"),
      first_observed_at: obs_times.min || @posting.first_observed_at,
      last_observed_at: obs_times.max || @posting.last_observed_at
    )

    ReconciliationResult.new(
      chosen_fields: chosen,
      selections: selections,
      conflicts: conflicts
    )
  end

  private

  def reconcile_simple_field(field_name, revisions, chosen, selections, conflicts)
    candidates = revisions.select { |r| yield(r).present? }
    return if candidates.empty?

    distinct_values = candidates.map { |r| yield(r) }.uniq
    has_conflict = distinct_values.size > 1

    winner, reason = select_winning_revision(candidates, field_name, has_conflict) { |r| yield(r) }

    chosen[field_name] = yield(winner)
    selections[field_name] = { revision: winner, reason: reason, value: yield(winner) }

    if has_conflict
      alternatives = candidates.reject { |r| yield(r) == yield(winner) }.map do |r|
        {
          value: yield(r),
          observed_at: r.observed_at.iso8601,
          source_kind: r.source_mention.source_kind
        }
      end
      conflicts[field_name] = {
        chosen_value: yield(winner),
        selection_reason: reason,
        alternatives: alternatives
      }
    end
  end

  def reconcile_salary_field(revisions, chosen, selections, conflicts)
    candidates = revisions.select { |r| r.salary_min.present? || r.salary_max.present? }
    return if candidates.empty?

    distinct_salaries = candidates.map { |r| [r.salary_min, r.salary_max, r.salary_currency, r.salary_period] }.uniq
    has_conflict = distinct_salaries.size > 1

    winner, reason = select_winning_revision(candidates, "salary", has_conflict) do |r|
      [r.salary_min, r.salary_max, r.salary_currency, r.salary_period]
    end

    chosen["salary"] = {
      "min" => winner.salary_min,
      "max" => winner.salary_max,
      "currency" => winner.salary_currency,
      "period" => winner.salary_period
    }
    selections["salary"] = { revision: winner, reason: reason }

    if has_conflict
      alternatives = candidates.reject { |r| [r.salary_min, r.salary_max] == [winner.salary_min, winner.salary_max] }.map do |r|
        {
          min: r.salary_min,
          max: r.salary_max,
          currency: r.salary_currency,
          period: r.salary_period,
          observed_at: r.observed_at.iso8601,
          source_kind: r.source_mention.source_kind
        }
      end
      conflicts["salary"] = {
        chosen_salary: chosen["salary"],
        selection_reason: reason,
        alternatives: alternatives
      }
    end
  end

  def select_winning_revision(candidates, _field_name, has_conflict)
    # Check for verified official employer exception:
    official_candidates = candidates.select do |r|
      SourceAuthority.verified_official?(r.source_mention, r.company)
    end
    third_party_candidates = candidates.reject do |r|
      SourceAuthority.verified_official?(r.source_mention, r.company)
    end

    if official_candidates.any? && third_party_candidates.any? && has_conflict
      # If verified official employer disagrees with a newer third-party observation:
      # Verified official employer listing overrides newer third-party observation!
      official_winner = sort_candidates(official_candidates).first
      newer_third_party = third_party_candidates.any? { |tp| tp.observed_at > official_winner.observed_at && yield(tp) != yield(official_winner) }
      if newer_third_party
        return [official_winner, "verified_official_override"]
      end
    end

    # Baseline: latest credible observation wins
    sorted = sort_candidates(candidates)
    winner = sorted.first
    reason = candidates.size == 1 ? "single_observation" : "newest_credible"
    [winner, reason]
  end

  # Deterministic tie-breaking:
  # 1. observed_at DESC
  # 2. authority rank ASC (verified official rank 1)
  # 3. revision_digest ASC (lexicographical)
  def sort_candidates(candidates)
    candidates.sort do |a, b|
      time_cmp = b.observed_at <=> a.observed_at
      next time_cmp unless time_cmp == 0

      rank_a = SourceAuthority.effective_authority_rank(a.source_mention, a.company)
      rank_b = SourceAuthority.effective_authority_rank(b.source_mention, b.company)
      rank_cmp = rank_a <=> rank_b
      next rank_cmp unless rank_cmp == 0

      a.revision_digest <=> b.revision_digest
    end
  end
end
