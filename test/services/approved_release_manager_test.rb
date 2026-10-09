require "test_helper"

class ApprovedReleaseManagerTest < ActiveSupport::TestCase
  setup do
    @batch_path = Rails.root.join("fixtures", "public-approved", "approved-batch-v1.json")
    @manifest_path = Rails.root.join("fixtures", "public-approved", "approved-manifest-v1.json")
    @batch_content = File.read(@batch_path, encoding: "UTF-8")
    @manifest_content = File.read(@manifest_path, encoding: "UTF-8")
  end

  test "publishes valid approved release and activates its postings" do
    result = ApprovedReleaseManager.new.publish!(@batch_content, @manifest_content)

    assert result.success, "Publish failed with errors: #{result.errors.inspect}"
    assert_not_nil result.approved_release
    assert result.approved_release.active
    assert_not_nil result.corpus_revision

    # Postings must be present in active_approved
    active_postings = CanonicalPosting.active_approved
    assert active_postings.count > 0
    assert_equal result.postings_count, active_postings.count
  end

  test "unapproved staging items are excluded from active_approved scope" do
    # Publish official release
    ApprovedReleaseManager.new.publish!(@batch_content, @manifest_content)

    # Insert an unapproved staging posting directly (not attached to active release)
    staging_post = CanonicalPosting.create!(
      title: "Secret Unapproved Staging Job",
      company: "Staging Corp",
      location: "Private Location",
      last_observed_at: Time.now.utc,
      first_observed_at: Time.now.utc,
      approved_release: nil
    )

    assert CanonicalPosting.where(id: staging_post.id).exists?

    # Must NOT be in active_approved!
    active_ids = CanonicalPosting.active_approved.pluck(:id)
    assert_not_includes active_ids, staging_post.id
  end

  test "tampered approval hash fails closed and preserves previous active release" do
    # 1. Establish valid active release
    init_res = ApprovedReleaseManager.new.publish!(@batch_content, @manifest_content)
    assert init_res.success
    prev_release = init_res.approved_release
    prev_rev = init_res.corpus_revision

    # 2. Attempt publishing tampered candidate
    tampered_content = @batch_content.sub("Denver, CO", "Boulder, CO")
    fail_res = ApprovedReleaseManager.new.publish!(tampered_content, @manifest_content)

    assert_not fail_res.success
    assert_not_empty fail_res.errors

    # Previous release must remain active and unchanged
    assert prev_release.reload.active
    assert_equal prev_rev, ApprovedReleaseManager.current_revision
  end

  test "replaying identical batch does not alter corpus revision" do
    res1 = ApprovedReleaseManager.new.publish!(@batch_content, @manifest_content)
    rev1 = res1.corpus_revision

    res2 = ApprovedReleaseManager.new.publish!(@batch_content, @manifest_content)
    rev2 = res2.corpus_revision

    assert_equal rev1, rev2
  end
end
