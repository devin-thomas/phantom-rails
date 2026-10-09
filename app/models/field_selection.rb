class FieldSelection < ApplicationRecord
  belongs_to :canonical_posting
  belongs_to :source_revision

  validates :field_name, presence: true, uniqueness: { scope: :canonical_posting_id }
  validates :selection_reason, presence: true
end
