require "securerandom"

class CanonicalPosting < ApplicationRecord
  belongs_to :approved_release, optional: true
  has_many :source_mentions, dependent: :nullify
  has_many :source_revisions, through: :source_mentions
  has_many :field_selections, dependent: :destroy

  has_many :potential_duplicates_as_a, class_name: "PotentialDuplicate", foreign_key: :posting_a_id, dependent: :destroy
  has_many :potential_duplicates_as_b, class_name: "PotentialDuplicate", foreign_key: :posting_b_id, dependent: :destroy

  scope :active_approved, -> {
    joins(:approved_release)
      .where(approved_releases: { active: true })
      .where(<<~SQL)
        EXISTS (
          SELECT 1
          FROM approved_release_revisions arr
          JOIN source_revisions sr ON sr.id = arr.source_revision_id
          JOIN source_mentions sm ON sm.id = sr.source_mention_id
          WHERE arr.approved_release_id = approved_releases.id
            AND sm.canonical_posting_id = canonical_postings.id
        )
      SQL
  }
  scope :unapproved_staging, -> {
    left_outer_joins(:approved_release)
      .where(<<~SQL)
        approved_releases.id IS NULL
        OR approved_releases.active = false
        OR NOT EXISTS (
          SELECT 1
          FROM approved_release_revisions arr
          JOIN source_revisions sr ON sr.id = arr.source_revision_id
          JOIN source_mentions sm ON sm.id = sr.source_mention_id
          WHERE arr.approved_release_id = approved_releases.id
            AND sm.canonical_posting_id = canonical_postings.id
        )
      SQL
  }

  before_validation :generate_public_id, on: :create
  before_save :update_search_vector

  validates :public_id, presence: true, uniqueness: true
  validates :title, presence: true
  validates :company, presence: true
  validates :location, presence: true
  validates :last_observed_at, presence: true
  validates :first_observed_at, presence: true

  def approved_revisions
    return source_revisions.none unless approved_release_id.present?

    source_revisions.joins(:approved_release_revisions)
                    .where(approved_release_revisions: { approved_release_id: approved_release_id })
  end

  def potential_duplicates
    ids = potential_duplicates_as_a.pluck(:posting_b_id) + potential_duplicates_as_b.pluck(:posting_a_id)
    CanonicalPosting.where(id: ids.uniq)
  end

  def active_approved_potential_duplicates
    ids = potential_duplicates_as_a.pluck(:posting_b_id) + potential_duplicates_as_b.pluck(:posting_a_id)
    CanonicalPosting.active_approved.where(id: ids.uniq)
  end

  def has_active_approved_potential_duplicates?
    active_approved_potential_duplicates.exists?
  end

  def potential_duplicate_records
    PotentialDuplicate.where("posting_a_id = :id OR posting_b_id = :id", id: id)
  end

  private

  def generate_public_id
    self.public_id ||= "post_#{SecureRandom.hex(8)}"
  end

  def update_search_vector
    text_content = [title, company, location, summary_excerpt].compact.join(" ")
    res = ActiveRecord::Base.connection.select_value(
      ActiveRecord::Base.sanitize_sql_array(["SELECT to_tsvector('english', ?)::text", text_content])
    )
    self.search_vector = res
  end
end
