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
      "potential_duplicate" => posting.has_active_approved_potential_duplicates?,
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
    ProvenanceSerializer.render(posting)
  end
end
