class ApprovedReleaseRevision < ApplicationRecord
  belongs_to :approved_release
  belongs_to :source_revision

  validates :source_revision_id, uniqueness: { scope: :approved_release_id }
end
