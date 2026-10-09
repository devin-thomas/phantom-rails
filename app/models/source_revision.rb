class SourceRevision < ApplicationRecord
  belongs_to :source_mention
  has_many :field_selections, dependent: :destroy
  has_many :approved_release_revisions, dependent: :destroy
  has_many :approved_releases, through: :approved_release_revisions

  validates :revision_digest, presence: true, uniqueness: { scope: :source_mention_id }
  validates :observed_at, presence: true
  validates :title, presence: true
  validates :company, presence: true
  validates :location, presence: true

  def self.compute_digest(attrs, version: "v2")
    case version.to_s
    when "v2"
      payload = {
        "v" => "2",
        "source_system" => attrs["source_system"].to_s.strip,
        "source_record_key" => attrs["source_record_key"].to_s.strip,
        "mention_key" => attrs["mention_key"].to_s.strip,
        "origin_class" => attrs["origin_class"].to_s.strip,
        "source_kind" => attrs["source_kind"].to_s.strip,
        "source_domain" => attrs["source_domain"].to_s.strip,
        "job_id" => attrs["job_id"].to_s.strip,
        "observed_at" => attrs["observed_at"].to_s.strip,
        "posted_at" => attrs["posted_at"].to_s.strip,
        "title" => attrs["title"].to_s.strip,
        "company" => attrs["company"].to_s.strip,
        "location" => attrs["location"].to_s.strip,
        "remote_type" => attrs["remote_type"].to_s.strip,
        "employment_type" => attrs["employment_type"].to_s.strip,
        "salary_min" => (attrs.dig("salary", "min") || attrs["salary_min"])&.to_f,
        "salary_max" => (attrs.dig("salary", "max") || attrs["salary_max"])&.to_f,
        "salary_currency" => (attrs.dig("salary", "currency") || attrs["salary_currency"]).to_s.strip.presence,
        "salary_period" => (attrs.dig("salary", "period") || attrs["salary_period"]).to_s.strip.presence,
        "summary_excerpt" => attrs["summary_excerpt"].to_s.strip,
        "job_url" => attrs["job_url"].to_s.strip
      }
      Digest::SHA256.hexdigest(JSON.generate(payload.sort.to_h))
    when "v1"
      canonical_str = [
        attrs["source_system"],
        attrs["source_record_key"],
        attrs["mention_key"],
        attrs["origin_class"],
        attrs["source_kind"],
        attrs["source_domain"],
        attrs["job_id"],
        attrs["observed_at"],
        attrs["posted_at"],
        attrs["title"],
        attrs["company"],
        attrs["location"],
        attrs["remote_type"],
        attrs["employment_type"],
        attrs.dig("salary", "min") || attrs["salary_min"],
        attrs.dig("salary", "max") || attrs["salary_max"],
        attrs.dig("salary", "currency") || attrs["salary_currency"],
        attrs.dig("salary", "period") || attrs["salary_period"],
        attrs["summary_excerpt"],
        attrs["job_url"]
      ].map { |v| v.to_s.strip }.join("|")
      Digest::SHA256.hexdigest(canonical_str)
    else
      raise ArgumentError, "Unknown digest version: #{version}"
    end
  end
end
