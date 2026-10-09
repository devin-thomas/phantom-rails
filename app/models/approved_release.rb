class ApprovedRelease < ApplicationRecord
  has_many :canonical_postings, dependent: :nullify
  has_many :source_records, dependent: :nullify
  has_many :approved_release_revisions, dependent: :destroy
  has_many :source_revisions, through: :approved_release_revisions

  scope :active, -> { where(active: true) }

  validates :manifest_digest, presence: true, uniqueness: true
  validates :approval_signature, presence: true
  validates :approved_by, presence: true
  validates :approved_at, presence: true
  validates :corpus_version, presence: true

  def activate!
    transaction do
      ApprovedRelease.where.not(id: id).update_all(active: false)
      update!(active: true)
    end
  end
end
