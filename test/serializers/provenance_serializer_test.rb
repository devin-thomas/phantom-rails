require "test_helper"

class ProvenanceSerializerTest < ActiveSupport::TestCase
  setup do
    @release = ApprovedRelease.create!(
      manifest_digest: Digest::SHA256.hexdigest("mock_manifest_provenance"),
      approval_signature: "sig_prov_test",
      approved_by: "auditor@phantomrails.dev",
      approved_at: Time.current,
      corpus_version: "2026.04.1",
      total_items: 2,
      active: true
    )

    @record = SourceRecord.create!(
      approved_release: @release,
      source_system: "ats_greenhouse",
      source_record_key: "rec_prov_01",
      origin_class: "sanitized_historical"
    )

    @posting = CanonicalPosting.create!(
      public_id: "post_prov_001",
      approved_release: @release,
      title: "Staff Infrastructure Engineer",
      company: "Apex Telecom",
      location: "Dallas, TX",
      remote_type: "hybrid",
      employment_type: "full_time",
      salary_min: 175000,
      salary_max: 215000,
      salary_currency: "USD",
      salary_period: "year",
      summary_excerpt: "Lead telecommunications infrastructure software.",
      job_url: "https://example.com/jobs/apex-101",
      potential_duplicate: true,
      last_observed_at: Time.utc(2026, 9, 23, 12, 0, 0),
      first_observed_at: Time.utc(2026, 9, 20, 10, 0, 0)
    )

    @other_posting = CanonicalPosting.create!(
      public_id: "post_prov_002",
      approved_release: @release,
      title: "Staff Infrastructure Engineer",
      company: "Apex Telecom Inc",
      location: "Dallas, TX",
      potential_duplicate: true,
      last_observed_at: Time.utc(2026, 9, 22, 10, 0, 0),
      first_observed_at: Time.utc(2026, 9, 22, 10, 0, 0)
    )

    # Potential duplicate link
    PotentialDuplicate.create!(
      posting_a_id: @posting.id,
      posting_b_id: @other_posting.id,
      reason_code: "ambiguous_company_title_similarity",
      evaluation_digest: Digest::SHA256.hexdigest("eval_dupe_1")
    )

    # Official mention and revision
    @mention_official = SourceMention.create!(
      source_record: @record,
      canonical_posting: @posting,
      mention_key: "apex:req_101",
      source_kind: "official_employer",
      source_domain: "apextelecom.com",
      job_id: "req_101"
    )

    @rev_official = SourceRevision.create!(
      source_mention: @mention_official,
      revision_digest: Digest::SHA256.hexdigest("rev_official"),
      observed_at: Time.utc(2026, 9, 20, 10, 0, 0),
      title: "Staff Infrastructure Engineer",
      company: "Apex Telecom",
      location: "Dallas, TX",
      salary_min: 175000,
      salary_max: 215000,
      salary_currency: "USD",
      salary_period: "year"
    )

    # Third party board mention and revision (newer date, conflicting lower salary)
    @mention_board = SourceMention.create!(
      source_record: @record,
      canonical_posting: @posting,
      mention_key: "board:apex_101",
      source_kind: "third_party_board",
      source_domain: "aggregator.com",
      job_id: "agg_101"
    )

    @rev_board = SourceRevision.create!(
      source_mention: @mention_board,
      revision_digest: Digest::SHA256.hexdigest("rev_board"),
      observed_at: Time.utc(2026, 9, 23, 14, 0, 0),
      title: "Staff Infrastructure Engineer",
      company: "Apex Telecom",
      location: "Dallas, TX",
      salary_min: 160000,
      salary_max: 195000,
      salary_currency: "USD",
      salary_period: "year"
    )

    # Field selection recording verified_official_override
    FieldSelection.create!(
      canonical_posting: @posting,
      field_name: "salary",
      source_revision: @rev_official,
      selection_reason: "verified_official_override"
    )
  end

  test "serializes chosen field value, alternative, source timestamp, and selection reason" do
    result = ProvenanceSerializer.render(@posting)

    assert_equal "post_prov_001", result["id"]
    assert_equal "Apex Telecom", result["company"]
    assert_equal true, result["potential_duplicate"]

    # Verify potential duplicate details
    assert_equal 1, result["potential_duplicates"].length
    dupe = result["potential_duplicates"].first
    assert_equal "post_prov_002", dupe["id"]
    assert_equal "ambiguous_company_title_similarity", dupe["reason_code"]

    # Verify merge evidence
    assert_equal 2, result["merge_evidence"]["total_mentions"]
    assert_equal 2, result["merge_evidence"]["mentions"].length

    # Verify field reconciliation for salary conflict
    salary_reconcile = result["field_reconciliation"].find { |f| f["field_name"] == "salary" }
    assert_not_nil salary_reconcile

    assert_equal 175000.0, salary_reconcile.dig("chosen_value", "min")
    assert_equal 215000.0, salary_reconcile.dig("chosen_value", "max")
    assert_equal "verified_official_override", salary_reconcile["selection_reason"]
    assert_equal "official_employer", salary_reconcile.dig("chosen_source", "source_kind")

    # Check documented alternative from third party board
    assert_equal 1, salary_reconcile["alternatives"].length
    alt = salary_reconcile["alternatives"].first
    assert_equal 160000.0, alt.dig("value", "min")
    assert_equal 195000.0, alt.dig("value", "max")
    assert_equal "third_party_board", alt["source_kind"]
    assert_equal "overridden_by_verified_official_source", alt["rejection_reason"]
  end

  test "provenance JSON passes PrivacyScanner and leaks no private identifiers" do
    json_str = ProvenanceSerializer.render(@posting).to_json
    report = PrivacyScanner.scan_string(json_str)

    assert report.clean?, "Provenance payload must not contain PII or secrets: #{report.violations.inspect}"
    refute json_str.include?("outlook.office365.com")
    refute json_str.include?("canary_")
    refute json_str.include?("utm_")
  end
end
