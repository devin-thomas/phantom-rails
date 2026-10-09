class PotentialDuplicate < ApplicationRecord
  belongs_to :posting_a, class_name: "CanonicalPosting"
  belongs_to :posting_b, class_name: "CanonicalPosting"

  validates :reason_code, presence: true
  validates :evaluation_digest, presence: true
  validates :posting_b_id, uniqueness: { scope: :posting_a_id }
  validate :canonical_pair_order

  after_create :mark_postings_as_potential_duplicates
  after_destroy :recalculate_potential_duplicate_flags

  def self.record_pair!(posting_1, posting_2, reason_code:, evaluation_digest:)
    return if posting_1.id == posting_2.id

    a_id, b_id = [posting_1.id, posting_2.id].sort
    rec = find_or_initialize_by(posting_a_id: a_id, posting_b_id: b_id)
    rec.reason_code = reason_code
    rec.evaluation_digest = evaluation_digest
    rec.save!
  end

  private

  def canonical_pair_order
    if posting_a_id.present? && posting_b_id.present? && posting_a_id >= posting_b_id
      errors.add(:base, "posting_a_id must be strictly less than posting_b_id for canonical pairing")
    end
  end

  def mark_postings_as_potential_duplicates
    posting_a.update_column(:potential_duplicate, true) if posting_a
    posting_b.update_column(:potential_duplicate, true) if posting_b
  end

  def recalculate_potential_duplicate_flags
    [posting_a, posting_b].compact.each do |p|
      has_dups = PotentialDuplicate.where("posting_a_id = :id OR posting_b_id = :id", id: p.id).exists?
      p.update_column(:potential_duplicate, has_dups)
    end
  end
end
