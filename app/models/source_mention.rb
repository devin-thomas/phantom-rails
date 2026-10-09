class SourceMention < ApplicationRecord
  belongs_to :source_record
  belongs_to :canonical_posting, optional: true, counter_cache: :mentions_count
  has_many :source_revisions, dependent: :destroy

  validates :mention_key, presence: true, uniqueness: { scope: :source_record_id }
  validates :source_kind, presence: true, inclusion: { in: %w[official_employer third_party_board email_digest other_reviewed] }

  def latest_revision
    source_revisions.order(observed_at: :desc, id: :desc).first
  end
end
