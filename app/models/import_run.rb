class ImportRun < ApplicationRecord
  has_many :import_errors, dependent: :destroy

  validates :batch_id, presence: true
  validates :batch_digest, presence: true
  validates :origin_class, presence: true
  validates :status, presence: true, inclusion: { in: %w[pending complete partial failed] }
  validates :started_at, presence: true

  def self.history_summary
    order(started_at: :desc).map do |run|
      {
        id: run.id,
        batch_id: run.batch_id,
        status: run.status,
        total_input: run.total_input,
        inserted: run.inserted_count,
        updated: run.updated_count,
        unchanged: run.unchanged_count,
        invalid: run.invalid_count,
        started_at: run.started_at&.iso8601,
        completed_at: run.completed_at&.iso8601,
        errors_count: run.import_errors.count
      }
    end
  end
end
