class ApprovedRelease < ApplicationRecord
  class UnsupportedRollbackError < StandardError; end
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
    # QA4-07: Strictly reject activation for releases with no explicit snapshot membership
    if approved_release_revisions.empty?
      raise "Release activation rejected: release #{corpus_version} has zero approved_release_revisions memberships"
    end

    # QA4-04: Release activation is forward-only; rollback to superseded release is unsupported
    active_release = ApprovedRelease.active.first
    if active_release && active_release.id != id && active_release.created_at > created_at
      raise UnsupportedRollbackError, "Release activation is forward-only; rollback to superseded release #{corpus_version} is unsupported to prevent mutable posting corruption."
    end

    transaction do
      ApprovedRelease.where.not(id: id).update_all(active: false)
      update!(active: true)
    end
  end
end
