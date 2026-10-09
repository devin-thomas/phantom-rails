class ImportError < ApplicationRecord
  belongs_to :import_run

  validates :item_index, presence: true
  validates :error_code, presence: true
  validates :error_message, presence: true
end
