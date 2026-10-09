class SourceRecord < ApplicationRecord
  belongs_to :approved_release, optional: true
  has_many :source_mentions, dependent: :destroy

  validates :source_system, presence: true
  validates :source_record_key, presence: true, uniqueness: { scope: :source_system }
  validates :origin_class, presence: true, inclusion: { in: %w[sanitized_historical adversarial_synthetic] }
end
