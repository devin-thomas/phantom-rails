require "securerandom"

class CanonicalPosting < ApplicationRecord
  belongs_to :approved_release, optional: true
  has_many :source_mentions, dependent: :nullify
  has_many :source_revisions, through: :source_mentions
  has_many :field_selections, dependent: :destroy

  has_many :potential_duplicates_as_a, class_name: "PotentialDuplicate", foreign_key: :posting_a_id, dependent: :destroy
  has_many :potential_duplicates_as_b, class_name: "PotentialDuplicate", foreign_key: :posting_b_id, dependent: :destroy

  scope :active_approved, -> { joins(:approved_release).where(approved_releases: { active: true }) }
  scope :unapproved_staging, -> { left_outer_joins(:approved_release).where("approved_releases.id IS NULL OR approved_releases.active = false") }

  before_validation :generate_public_id, on: :create
  before_save :update_search_vector

  validates :public_id, presence: true, uniqueness: true
  validates :title, presence: true
  validates :company, presence: true
  validates :location, presence: true
  validates :last_observed_at, presence: true
  validates :first_observed_at, presence: true

  def potential_duplicates
    ids = potential_duplicates_as_a.pluck(:posting_b_id) + potential_duplicates_as_b.pluck(:posting_a_id)
    CanonicalPosting.where(id: ids.uniq)
  end

  def potential_duplicate_records
    PotentialDuplicate.where("posting_a_id = :id OR posting_b_id = :id", id: id)
  end

  private

  def generate_public_id
    self.public_id ||= "post_#{SecureRandom.hex(8)}"
  end

  def update_search_vector
    # Build text vector from title, company, location, and summary
    text_content = [title, company, location, summary_excerpt].compact.join(" ")
    sanitized_sql = ActiveRecord::Base.sanitize_sql_array(["to_tsvector('english', ?)", text_content])
    self.search_vector = Arel.sql(sanitized_sql)
  end
end
