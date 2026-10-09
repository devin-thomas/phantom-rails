class SourceRevision < ApplicationRecord
  belongs_to :source_mention
  has_many :field_selections, dependent: :destroy

  validates :revision_digest, presence: true, uniqueness: { scope: :source_mention_id }
  validates :observed_at, presence: true
  validates :title, presence: true
  validates :company, presence: true
  validates :location, presence: true

  def self.compute_digest(attrs)
    # Canonical string representation of fields
    canonical_str = [
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
