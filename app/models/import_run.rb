class ImportRun < ApplicationRecord
  has_many :import_errors, dependent: :destroy

  validates :batch_id, presence: true
  validates :batch_digest, presence: true
  validates :origin_class, presence: true
  validates :status, presence: true, inclusion: { in: %w[complete partial failed] }
  validates :started_at, presence: true
end
