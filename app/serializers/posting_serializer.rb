class PostingSerializer
  def self.render_one(posting, score: nil)
    origin_class = posting.source_mentions.first&.source_record&.origin_class || "adversarial_synthetic"

    {
      "id" => posting.public_id,
      "title" => posting.title,
      "company" => posting.company,
      "location" => posting.location,
      "remote_type" => posting.remote_type,
      "employment_type" => posting.employment_type,
      "salary" => (posting.salary_min || posting.salary_max) ? {
        "min" => posting.salary_min&.to_f,
        "max" => posting.salary_max&.to_f,
        "currency" => posting.salary_currency,
        "period" => posting.salary_period
      } : nil,
      "summary_excerpt" => posting.summary_excerpt,
      "job_url" => posting.job_url,
      "relevance_score" => score,
      "origin_class" => origin_class,
      "potential_duplicate" => posting.potential_duplicate,
      "provenance_url" => "/api/v1/postings/#{posting.public_id}/provenance",
      "first_observed_at" => posting.first_observed_at&.iso8601,
      "last_observed_at" => posting.last_observed_at&.iso8601
    }
  end

  def self.render_many(postings, scores: {})
    postings.map do |p|
      render_one(p, score: scores[p.id])
    end
  end

  def self.render_provenance(posting)
    {
      "id" => posting.public_id,
      "title" => posting.title,
      "company" => posting.company,
      "potential_duplicate" => posting.potential_duplicate,
      "source_mentions" => posting.source_mentions.map do |sm|
        {
          "mention_key" => sm.mention_key,
          "source_kind" => sm.source_kind,
          "source_domain" => sm.source_domain,
          "origin_class" => sm.source_record&.origin_class
        }
      end,
      "field_selections" => posting.field_selections.map do |fs|
        {
          "field_name" => fs.field_name,
          "selection_reason" => fs.selection_reason,
          "selected_from_source" => fs.source_revision&.source_mention&.source_kind
        }
      end
    }
  end
end
