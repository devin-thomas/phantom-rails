require "test_helper"

class ProvenanceDomainModelTest < ActiveSupport::TestCase
  test "canonical posting generates opaque public id with post_ prefix" do
    posting = CanonicalPosting.create!(
      title: "Staff Engineer",
      company: "Acme",
      location: "Chicago, IL",
      last_observed_at: Time.now.utc,
      first_observed_at: Time.now.utc
    )

    assert_match(/^post_[a-f0-9]{16}$/, posting.public_id)
    assert_not_equal posting.id.to_s, posting.public_id
  end

  test "unique constraints prevent duplicate source record and mention" do
    record1 = SourceRecord.create!(source_system: "ats", source_record_key: "rec-1", origin_class: "adversarial_synthetic")

    # Rails validation catches it
    assert_raises(ActiveRecord::RecordInvalid) do
      SourceRecord.create!(source_system: "ats", source_record_key: "rec-1", origin_class: "adversarial_synthetic")
    end

    # Database-level constraint catches it even when bypassing validation
    dup_record = SourceRecord.new(source_system: "ats", source_record_key: "rec-1", origin_class: "adversarial_synthetic")
    assert_raises(ActiveRecord::RecordNotUnique) do
      dup_record.save!(validate: false)
    end

    mention1 = SourceMention.create!(source_record: record1, mention_key: "m-1", source_kind: "official_employer")

    assert_raises(ActiveRecord::RecordInvalid) do
      SourceMention.create!(source_record: record1, mention_key: "m-1", source_kind: "official_employer")
    end

    dup_mention = SourceMention.new(source_record: record1, mention_key: "m-1", source_kind: "official_employer")
    assert_raises(ActiveRecord::RecordNotUnique) do
      dup_mention.save!(validate: false)
    end
  end

  test "unique constraints prevent duplicate source revision" do
    record = SourceRecord.create!(source_system: "ats", source_record_key: "rec-2", origin_class: "adversarial_synthetic")
    mention = SourceMention.create!(source_record: record, mention_key: "m-1", source_kind: "official_employer")

    SourceRevision.create!(
      source_mention: mention,
      revision_digest: "digest-123",
      observed_at: Time.now.utc,
      title: "Title",
      company: "Company",
      location: "Location"
    )

    dup_rev = SourceRevision.new(
      source_mention: mention,
      revision_digest: "digest-123",
      observed_at: Time.now.utc,
      title: "Title",
      company: "Company",
      location: "Location"
    )

    assert_raises(ActiveRecord::RecordInvalid) do
      dup_rev.save!
    end

    assert_raises(ActiveRecord::RecordNotUnique) do
      dup_rev.save!(validate: false)
    end
  end

  test "potential duplicate records canonical pair and marks both postings" do
    p1 = CanonicalPosting.create!(
      title: "Dev 1",
      company: "Corp",
      location: "Remote",
      last_observed_at: Time.now.utc,
      first_observed_at: Time.now.utc
    )
    p2 = CanonicalPosting.create!(
      title: "Dev 2",
      company: "Corp",
      location: "Remote",
      last_observed_at: Time.now.utc,
      first_observed_at: Time.now.utc
    )

    assert_not p1.potential_duplicate
    assert_not p2.potential_duplicate

    PotentialDuplicate.record_pair!(p2, p1, reason_code: "similar_title_company", evaluation_digest: "eval-01")

    p1.reload
    p2.reload

    assert p1.potential_duplicate
    assert p2.potential_duplicate
    assert_equal [p2.id], p1.potential_duplicates.pluck(:id)
    assert_equal [p1.id], p2.potential_duplicates.pluck(:id)
  end

  test "approved release activate! ensures single active release" do
    r1 = ApprovedRelease.create!(
      manifest_digest: "d1",
      approval_signature: "d1",
      approved_by: "devin",
      approved_at: Time.now.utc,
      corpus_version: "v1",
      active: true
    )
    r2 = ApprovedRelease.create!(
      manifest_digest: "d2",
      approval_signature: "d2",
      approved_by: "devin",
      approved_at: Time.now.utc,
      corpus_version: "v2",
      active: false
    )

    rec = SourceRecord.create!(source_system: "ats", source_record_key: "rec-test-act", origin_class: "sanitized_historical")
    sm = SourceMention.create!(source_record: rec, mention_key: "m1", source_kind: "official_employer")
    rev = sm.source_revisions.create!(revision_digest: "d1", observed_at: Time.now.utc, title: "T", company: "C", location: "L")
    ApprovedReleaseRevision.create!(approved_release: r1, source_revision: rev, snapshot_source_domain: "example.com")
    ApprovedReleaseRevision.create!(approved_release: r2, source_revision: rev, snapshot_source_domain: "example.com")

    assert r1.reload.active
    assert_not r2.reload.active

    r2.activate!

    assert_not r1.reload.active
    assert r2.reload.active
  end
end
