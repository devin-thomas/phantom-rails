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

  def self.compute_digest(attrs)
    # Canonical string representation of observation and identity fields (contract v2)
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
      attrs.dig("salary", "min"),
      attrs.dig("salary", "max"),
      attrs.dig("salary", "currency"),
      attrs.dig("salary", "period"),
      attrs["summary_excerpt"],
      attrs["job_url"]
    ].map { |v| v.to_s.strip }.join("|")

    Digest::SHA256.hexdigest(canonical_str)
  end
end
