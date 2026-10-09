class ProvenanceSerializer
  def self.render(posting)
    new(posting).as_json
  end

  def initialize(posting)
    @posting = posting
  end

  def as_json
    origin_class = @posting.source_mentions.first&.source_record&.origin_class || "adversarial_synthetic"

    {
      "id" => @posting.public_id,
      "posting_id" => @posting.public_id,
      "title" => @posting.title,
      "company" => @posting.company,
      "location" => @posting.location,
      "origin_class" => origin_class,
      "potential_duplicate" => @posting.potential_duplicate,
      "potential_duplicates" => render_potential_duplicates,
      "source_mentions" => render_mentions,
      "merge_evidence" => {
        "total_mentions" => @posting.source_mentions.count,
        "mentions" => render_mentions
      },
      "field_reconciliation" => render_field_reconciliation
    }
  end

  private

  def render_potential_duplicates
    @posting.potential_duplicate_records.map do |pd|
      other = (pd.posting_a_id == @posting.id) ? pd.posting_b : pd.posting_a
      next unless other

      {
        "id" => other.public_id,
        "title" => other.title,
        "company" => other.company,
        "reason_code" => pd.reason_code
      }
    end.compact
  end

  def render_mentions
    @posting.source_mentions.order(:id).map do |sm|
      {
        "mention_key" => sm.mention_key,
        "source_kind" => sm.source_kind,
        "source_domain" => sm.source_domain,
        "origin_class" => sm.source_record&.origin_class,
        "revisions_count" => sm.source_revisions.count
      }
    end
  end

  def render_field_reconciliation
    reconciliations = []

    # Map of field selections
    selections = @posting.field_selections.includes(source_revision: :source_mention).index_by(&:field_name)

    # All unique revisions for this posting
    all_revisions = @posting.source_revisions.includes(:source_mention).order(observed_at: :desc, id: :desc)

    %w[title company location remote_type employment_type salary summary_excerpt job_url].each do |field|
      selection = selections[field]
      chosen_rev = selection&.source_revision

      next unless chosen_rev

      chosen_val = extract_field_value(chosen_rev, field)
      alternatives = []

      all_revisions.each do |rev|
        next if rev.id == chosen_rev.id

        alt_val = extract_field_value(rev, field)
        next if alt_val.nil? || alt_val == chosen_val

        rejection_reason = determine_rejection_reason(selection.selection_reason, rev, chosen_rev)

        alternatives << {
          "value" => alt_val,
          "source_kind" => rev.source_mention.source_kind,
          "observed_at" => rev.observed_at&.iso8601,
          "rejection_reason" => rejection_reason
        }
      end

      reconciliations << {
        "field_name" => field,
        "chosen_value" => chosen_val,
        "selection_reason" => selection.selection_reason,
        "chosen_source" => {
          "source_kind" => chosen_rev.source_mention.source_kind,
          "observed_at" => chosen_rev.observed_at&.iso8601
        },
        "alternatives" => alternatives
      }
    end

    reconciliations
  end

  def extract_field_value(rev, field)
    case field
    when "salary"
      return nil if rev.salary_min.nil? && rev.salary_max.nil?

      {
        "min" => rev.salary_min&.to_f,
        "max" => rev.salary_max&.to_f,
        "currency" => rev.salary_currency,
        "period" => rev.salary_period
      }
    when "summary_excerpt"
      rev.summary_excerpt&.truncate(200)
    else
      rev.public_send(field)
    end
  end

  def determine_rejection_reason(selection_reason, rev, chosen_rev)
    case selection_reason
    when "verified_official_override"
      "overridden_by_verified_official_source"
    when "newest_credible"
      rev.observed_at < chosen_rev.observed_at ? "older_observation" : "lower_priority"
    when "tie_breaker_authority"
      "lower_authority_rank"
    else
      "alternative_not_selected"
    end
  end
end
