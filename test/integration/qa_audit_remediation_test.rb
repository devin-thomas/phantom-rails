# frozen_string_literal: true

require "test_helper"

class QaAuditRemediationTest < ActionDispatch::IntegrationTest
  setup do
    PotentialDuplicate.delete_all
    FieldSelection.delete_all
    SourceRevision.delete_all
    SourceMention.delete_all
    SourceRecord.delete_all
    CanonicalPosting.delete_all
    ApprovedRelease.delete_all
    ImportError.delete_all
    ImportRun.delete_all
  end

  # ==========================================================================
  # Finding 1: Public Data Isolation & Approved Release Immutability (P0)
  # ==========================================================================

  test "unapproved staging import with conflicting revision cannot mutate approved public posting or its field selections" do
    # 1. Publish an approved release with 1 posting
    batch = {
      "batch_schema_version" => "1.0",
      "batch_id" => "approved-base-batch",
      "origin_class" => "sanitized_historical",
      "items" => [
        {
          "source_record_key" => "rec-approved-1",
          "mention_key" => "m1",
          "source_system" => "reviewed_export",
          "observed_at" => "2026-09-20T10:00:00Z",
          "source_kind" => "official_employer",
          "source_domain" => "careers.acme.example.com",
          "job_id" => "REQ-101",
          "title" => "Senior Ruby Architect",
          "company" => "Acme Aerospace",
          "location" => "Denver, CO",
          "salary" => { "min": 175000, "max": 215000, "currency": "USD", "period": "year" }
        }
      ]
    }
    batch_json = JSON.generate(batch)
    manifest = ReleaseGate.build_manifest(batch_json, approved_by: "qa-lead", corpus_version: "v1.0.0")
    manifest_json = JSON.generate(manifest)

    pub_res = ApprovedReleaseManager.new.publish!(batch_json, manifest_json)
    assert pub_res.success, "Publication must succeed: #{pub_res.errors}"
    assert_equal 1, pub_res.postings_count

    approved_posting = CanonicalPosting.active_approved.first
    assert_equal "Senior Ruby Architect", approved_posting.title
    assert_equal 175000, approved_posting.salary_min.to_i

    # 2. Ingest an UNAPPROVED staging batch with a newer conflicting observation on the same mention
    unapproved_batch = {
      "batch_schema_version" => "1.0",
      "batch_id" => "unapproved-staging-batch",
      "origin_class" => "adversarial_synthetic",
      "items" => [
        {
          "source_record_key" => "rec-approved-1",
          "mention_key" => "m1",
          "source_system" => "reviewed_export",
          "observed_at" => "2026-09-25T12:00:00Z", # newer unapproved observation
          "source_kind" => "official_employer",
          "source_domain" => "careers.acme.example.com",
          "job_id" => "REQ-101",
          "title" => "CORRUPTED STAGING TITLE",
          "company" => "Acme Aerospace",
          "location" => "Denver, CO",
          "salary" => { "min": 999999, "max": 999999, "currency": "USD", "period": "year" }
        }
      ]
    }

    import_report = BatchImporter.import_string(JSON.generate(unapproved_batch))
    assert_equal "complete", import_report.status

    # 3. Verify: Approved posting is IMMUTABLE and was NOT updated by unapproved staging data!
    approved_posting.reload
    assert_equal "Senior Ruby Architect", approved_posting.title, "Approved title must not be mutated by unapproved staging import"
    assert_equal 175000, approved_posting.salary_min.to_i, "Approved salary must not be mutated by unapproved staging import"

    # Field selections must still point to approved revision
    title_sel = approved_posting.field_selections.find_by(field_name: "title")
    assert_equal "Senior Ruby Architect", title_sel.source_revision.title

    # 4. Verify: Public HTTP endpoints serve immutable approved projection
    get "/api/v1/postings/#{approved_posting.public_id}"
    assert_response :success
    data = JSON.parse(response.body)["data"]
    assert_equal "Senior Ruby Architect", data["title"]
    assert_equal 175000.0, data["salary"]["min"]
  end

  test "unapproved staging potential duplicates are never leaked through approved posting provenance" do
    # 1. Create active approved posting
    release = ApprovedRelease.create!(
      manifest_digest: "digest-approved-test",
      approval_signature: "digest-approved-test",
      approved_by: "qa-lead",
      approved_at: Time.now.utc,
      corpus_version: "v1.0.0",
      active: true
    )

    approved_posting = CanonicalPosting.create!(
      approved_release: release,
      title: "Senior Backend Engineer",
      company: "Approved Corp",
      location: "Austin, TX",
      first_observed_at: Time.now.utc,
      last_observed_at: Time.now.utc
    )

    # 2. Create unapproved staging posting
    staging_posting = CanonicalPosting.create!(
      approved_release: nil, # Unapproved
      title: "Senior Backend Engineer",
      company: "Approved Corp",
      location: "Austin, TX",
      first_observed_at: Time.now.utc,
      last_observed_at: Time.now.utc
    )

    # 3. Link them as potential duplicates
    PotentialDuplicate.record_pair!(
      approved_posting,
      staging_posting,
      reason_code: "similar_company_title_location",
      evaluation_digest: "test-digest"
    )

    # 4. Request public provenance endpoint for approved posting
    get "/api/v1/postings/#{approved_posting.public_id}/provenance"
    assert_response :success
    json = JSON.parse(response.body)["data"]

    # Verify: Staging duplicate details are completely filtered from public response
    assert_equal false, json["potential_duplicate"], "Must not flag potential_duplicate when linked only to unapproved staging"
    assert_equal [], json["potential_duplicates"], "Must not expose unapproved staging postings in public provenance"

    # Also verify search serializer doesn't leak duplicate flag
    get "/api/v1/postings?q=Backend"
    assert_response :success
    search_json = JSON.parse(response.body)["data"]
    assert_equal 1, search_json.size
    assert_equal false, search_json.first["potential_duplicate"]
  end

  # ==========================================================================
  # Finding 2: Conservative Duplicate Resolution Hardening (P1)
  # ==========================================================================

  test "different employers sharing generic job URL are never merged under Tier 2" do
    batch = {
      "batch_schema_version" => "1.0",
      "batch_id" => "generic-url-batch",
      "origin_class" => "adversarial_synthetic",
      "items" => [
        {
          "source_record_key" => "rec-co-a",
          "mention_key" => "m1",
          "source_system" => "scraper",
          "observed_at" => "2026-09-20T10:00:00Z",
          "source_kind" => "third_party_board",
          "title" => "DevOps Engineer",
          "company" => "Company Alpha",
          "location" => "Remote",
          "job_url" => "https://generic-board.example.com/jobs"
        },
        {
          "source_record_key" => "rec-co-b",
          "mention_key" => "m1",
          "source_system" => "scraper",
          "observed_at" => "2026-09-21T10:00:00Z",
          "source_kind" => "third_party_board",
          "title" => "DevOps Engineer",
          "company" => "Company Beta", # Different employer!
          "location" => "Remote",
          "job_url" => "https://generic-board.example.com/jobs"
        }
      ]
    }

    report = BatchImporter.import_string(JSON.generate(batch))
    assert_equal "complete", report.status

    # Must create two separate canonical postings, NOT merge
    assert_equal 2, CanonicalPosting.count
    p_alpha = CanonicalPosting.find_by(company: "Company Alpha")
    p_beta = CanonicalPosting.find_by(company: "Company Beta")
    assert_not_nil p_alpha
    assert_not_nil p_beta
    assert_not_equal p_alpha.id, p_beta.id
  end

  test "different employers sharing platform domain and job ID are never merged under Tier 3" do
    batch = {
      "batch_schema_version" => "1.0",
      "batch_id" => "platform-id-collision-batch",
      "origin_class" => "adversarial_synthetic",
      "items" => [
        {
          "source_record_key" => "rec-ats-1",
          "mention_key" => "m1",
          "source_system" => "ats",
          "source_domain" => "greenhouse.io",
          "job_id" => "GH-9999",
          "observed_at" => "2026-09-20T10:00:00Z",
          "source_kind" => "third_party_board",
          "title" => "Product Manager",
          "company" => "First Company",
          "location" => "San Francisco, CA"
        },
        {
          "source_record_key" => "rec-ats-2",
          "mention_key" => "m1",
          "source_system" => "ats",
          "source_domain" => "greenhouse.io",
          "job_id" => "GH-9999", # Same platform ID
          "observed_at" => "2026-09-21T10:00:00Z",
          "source_kind" => "third_party_board",
          "title" => "Product Manager",
          "company" => "Second Company", # Different company!
          "location" => "San Francisco, CA"
        }
      ]
    }

    report = BatchImporter.import_string(JSON.generate(batch))
    assert_equal "complete", report.status

    # Must create two separate canonical postings, NOT merge
    assert_equal 2, CanonicalPosting.count
  end

  test "conflicting employer requisition IDs never merge even if sharing employer and job URL" do
    batch = {
      "batch_schema_version" => "1.0",
      "batch_id" => "conflicting-req-id-batch",
      "origin_class" => "adversarial_synthetic",
      "items" => [
        {
          "source_record_key" => "rec-req-101",
          "mention_key" => "m1",
          "source_system" => "ats",
          "job_id" => "REQ-101",
          "observed_at" => "2026-09-20T10:00:00Z",
          "source_kind" => "official_employer",
          "title" => "Staff Engineer",
          "company" => "Acme Corp",
          "location" => "Denver, CO",
          "job_url" => "https://careers.acme.example.com/engineering/openings"
        },
        {
          "source_record_key" => "rec-req-102",
          "mention_key" => "m1",
          "source_system" => "ats",
          "job_id" => "REQ-102", # Conflicting requisition ID!
          "observed_at" => "2026-09-21T10:00:00Z",
          "source_kind" => "official_employer",
          "title" => "Staff Engineer",
          "company" => "Acme Corp",
          "location" => "Denver, CO",
          "job_url" => "https://careers.acme.example.com/engineering/openings"
        }
      ]
    }

    report = BatchImporter.import_string(JSON.generate(batch))
    assert_equal "complete", report.status

    # Requisitions REQ-101 and REQ-102 must remain separate postings!
    assert_equal 2, CanonicalPosting.count
  end

  # ==========================================================================
  # Finding 3: Source Authority Verification (P1)
  # ==========================================================================

  test "unverified third party claiming official_employer cannot override newer credible observation" do
    batch = {
      "batch_schema_version" => "1.0",
      "batch_id" => "fake-official-override-batch",
      "origin_class" => "adversarial_synthetic",
      "items" => [
        {
          "source_record_key" => "rec-fake-official",
          "mention_key" => "m1",
          "source_system" => "untrusted_web_scraper", # Untrusted scraper
          "source_domain" => "sketchy-aggregator.net", # NOT a verified company domain
          "observed_at" => "2026-09-20T10:00:00Z", # older
          "source_kind" => "official_employer", # Untrusted assertion!
          "job_id" => "ENG-500",
          "title" => "Site Reliability Engineer",
          "company" => "Globex Software",
          "location" => "Austin, TX",
          "salary" => { "min": 250000, "max": 300000, "currency": "USD", "period": "year" }
        },
        {
          "source_record_key" => "rec-credible-board",
          "mention_key" => "m1",
          "source_system" => "reviewed_export",
          "source_domain" => "techjobs.example.org",
          "observed_at" => "2026-09-24T14:00:00Z", # newer
          "source_kind" => "third_party_board",
          "job_id" => "ENG-500",
          "title" => "Site Reliability Engineer",
          "company" => "Globex Software",
          "location" => "Austin, TX",
          "salary" => { "min": 150000, "max": 180000, "currency": "USD", "period": "year" }
        }
      ]
    }

    report = BatchImporter.import_string(JSON.generate(batch))
    assert_equal "complete", report.status

    posting = CanonicalPosting.find_by(company: "Globex Software")
    assert_not_nil posting

    # Because 'sketchy-aggregator.net' is NOT a verified official domain for Globex,
    # its claimed 'official_employer' label is unverified and CANNOT override the newer credible observation!
    assert_equal 150000, posting.salary_min.to_i, "Newer credible observation must win when claimed official source is unverified"
    assert_equal 180000, posting.salary_max.to_i

    salary_sel = posting.field_selections.find_by(field_name: "salary")
    assert_equal "newest_credible", salary_sel.selection_reason
  end

  # ==========================================================================
  # Finding 4: Validation Edge Cases & Accounting (P1)
  # ==========================================================================

  test "ReleaseGate and ApprovedReleaseManager strictly reject candidate batches with invalid items" do
    mixed_batch = {
      "batch_schema_version" => "1.0",
      "batch_id" => "mixed-for-release-gate",
      "origin_class" => "adversarial_synthetic",
      "items" => [
        {
          "source_record_key" => "valid-item-1",
          "mention_key" => "m1",
          "source_system" => "reviewed_export",
          "observed_at" => "2026-09-20T10:00:00Z",
          "source_kind" => "third_party_board",
          "title" => "Valid Job",
          "company" => "Valid Co",
          "location" => "Denver, CO"
        },
        {
          # Invalid item missing required 'company'
          "source_record_key" => "invalid-item-2",
          "mention_key" => "m2",
          "source_system" => "reviewed_export",
          "observed_at" => "2026-09-20T10:00:00Z",
          "source_kind" => "third_party_board",
          "title" => "Invalid Job Without Company",
          "location" => "Denver, CO"
        }
      ]
    }
    batch_json = JSON.generate(mixed_batch)
    manifest = {
      "manifest_version" => "1.0",
      "corpus_version" => "v1.0.0",
      "candidate_digest" => ReleaseGate.compute_digest(batch_json),
      "total_items" => 1,
      "origin_class_counts" => { "adversarial_synthetic" => 1 },
      "automated_checks_passed" => true,
      "approved_by" => "qa-lead",
      "approved_at" => Time.now.utc.iso8601,
      "approval_signature" => ReleaseGate.compute_digest(batch_json)
    }

    # ReleaseGate must evaluate to approved: false
    gate_res = ReleaseGate.evaluate(batch_json, JSON.generate(manifest))
    assert_equal false, gate_res.approved
    assert gate_res.errors.any? { |e| e.include?("release candidate must be 100% valid") }

    # ApprovedReleaseManager must reject publication
    pub_res = ApprovedReleaseManager.new.publish!(batch_json, JSON.generate(manifest))
    assert_equal false, pub_res.success
    assert pub_res.errors.any? { |e| e.include?("release candidate must be 100% valid") }
  end

  test "BatchImporter preserves total_input accounting invariant on in-batch identical duplicate items" do
    batch = {
      "batch_schema_version" => "1.0",
      "batch_id" => "duplicate-items-batch",
      "origin_class" => "adversarial_synthetic",
      "items" => [
        {
          "source_record_key" => "rec-dup",
          "mention_key" => "m1",
          "source_system" => "test_system",
          "observed_at" => "2026-09-20T10:00:00Z",
          "source_kind" => "third_party_board",
          "title" => "Duplicate Item Title",
          "company" => "Duplicate Corp",
          "location" => "Austin, TX"
        },
        { # Exactly identical observation in same batch
          "source_record_key" => "rec-dup",
          "mention_key" => "m1",
          "source_system" => "test_system",
          "observed_at" => "2026-09-20T10:00:00Z",
          "source_kind" => "third_party_board",
          "title" => "Duplicate Item Title",
          "company" => "Duplicate Corp",
          "location" => "Austin, TX"
        },
        { # Separate distinct item
          "source_record_key" => "rec-unique",
          "mention_key" => "m1",
          "source_system" => "test_system",
          "observed_at" => "2026-09-20T10:00:00Z",
          "source_kind" => "third_party_board",
          "title" => "Unique Title",
          "company" => "Unique Corp",
          "location" => "Austin, TX"
        }
      ]
    }

    report = BatchImporter.import_string(JSON.generate(batch))
    assert_equal "complete", report.status
    assert_equal 3, report.total_input

    # Documented accounting invariant: total_input == inserted + updated + unchanged + invalid
    sum = report.inserted_count + report.updated_count + report.unchanged_count + report.invalid_count
    assert_equal report.total_input, sum, "total_input (#{report.total_input}) must exactly match sum (#{sum})"
    assert_equal 2, report.inserted_count
    assert_equal 1, report.unchanged_count # Collapsed in-batch duplicate counted as unchanged
  end

  # ==========================================================================
  # QA Round 2 Audit Remediation Tests
  # ==========================================================================

  test "QA Round 2: P0 reproduction - unapproved staging revision leaves approved public posting and provenance completely invariant" do
    # 1. Publish one approved source
    approved_batch = {
      "batch_schema_version" => "1.0",
      "batch_id" => "approved-p0-v1",
      "origin_class" => "sanitized_historical",
      "items" => [
        {
          "source_record_key" => "rec-approved-p0",
          "mention_key" => "m1",
          "source_system" => "reviewed_export",
          "observed_at" => "2026-09-20T10:00:00Z",
          "source_kind" => "official_employer",
          "source_domain" => "careers.acme.example.com",
          "job_id" => "REQ-P0",
          "title" => "Staff Systems Engineer",
          "company" => "Acme Aerospace",
          "location" => "Denver, CO",
          "salary" => { "min": 175000, "max": 215000, "currency": "USD", "period": "year" },
          "summary_excerpt" => "Approved public description of systems role",
          "job_url" => "https://careers.acme.example.com/jobs/req-p0"
        }
      ]
    }
    batch_json = JSON.generate(approved_batch)
    manifest = ReleaseGate.build_manifest(batch_json, approved_by: "auditor-p0", corpus_version: "2026.10.1")
    manifest_json = JSON.generate(manifest)

    pub_res = ApprovedReleaseManager.new.publish!(batch_json, manifest_json)
    assert pub_res.success, "Release publication must succeed: #{pub_res.errors}"
    assert_equal 1, pub_res.postings_count

    posting = CanonicalPosting.active_approved.first
    assert_not_nil posting

    # Fetch baseline public posting, provenance, and metadata responses
    get "/api/v1/postings/#{posting.public_id}"
    assert_response :success
    baseline_posting_json = JSON.parse(response.body)

    get "/api/v1/postings/#{posting.public_id}/provenance"
    assert_response :success
    baseline_provenance_json = JSON.parse(response.body)

    get "/api/v1/meta"
    assert_response :success
    baseline_meta_json = JSON.parse(response.body)

    baseline_corpus_revision = ApprovedReleaseManager.current_revision

    # 2. Ingest staging-only subsequent revision for the SAME stable source identity
    # Contains changed title, changed domain, changed job_id, and summary_excerpt with private canary email
    staging_batch = {
      "batch_schema_version" => "1.0",
      "batch_id" => "staging-unapproved-p0",
      "origin_class" => "adversarial_synthetic",
      "items" => [
        {
          "source_record_key" => "rec-approved-p0",
          "mention_key" => "m1",
          "source_system" => "reviewed_export",
          "observed_at" => "2026-09-25T14:00:00Z", # newer unapproved observation
          "source_kind" => "official_employer",
          "source_domain" => "leaked.example.com", # changed domain
          "job_id" => "REQ-LEAKED-999", # changed job_id
          "title" => "UNAPPROVED PRIVATE TITLE",
          "company" => "Acme Aerospace",
          "location" => "Denver, CO",
          "salary" => { "min": 999999, "max": 999999, "currency": "USD", "period": "year" },
          "summary_excerpt" => "Confidential: reach out to private-person@example.com for private candidate details",
          "job_url" => "https://leaked.example.com/jobs/999"
        }
      ]
    }
    staging_report = BatchImporter.import_string(JSON.generate(staging_batch))
    assert_equal "complete", staging_report.status
    assert_equal 1, staging_report.updated_count

    # 3. Assert public projection, provenance, metadata, and corpus revision remain byte/semantically invariant
    get "/api/v1/postings/#{posting.public_id}"
    assert_response :success
    after_posting_json = JSON.parse(response.body)
    assert_equal baseline_posting_json, after_posting_json, "Public posting projection must remain strictly invariant after staging import"

    get "/api/v1/postings/#{posting.public_id}/provenance"
    assert_response :success
    after_provenance_json = JSON.parse(response.body)
    after_provenance_body = response.body
    assert_equal baseline_provenance_json, after_provenance_json, "Public provenance must remain strictly invariant after staging import"

    get "/api/v1/meta"
    assert_response :success
    after_meta_json = JSON.parse(response.body)
    assert_equal baseline_meta_json, after_meta_json, "Public meta response must remain strictly invariant after staging import"

    # Strict privacy canary assertions: ZERO leaks of private email or unapproved domain/title
    refute_includes after_provenance_body, "private-person@example.com", "Private canary email must NEVER appear in public provenance"
    refute_includes after_provenance_body, "leaked.example.com", "Unapproved staging domain must not leak into approved provenance"
    refute_includes after_provenance_body, "UNAPPROVED PRIVATE TITLE", "Unapproved staging title must not leak into approved provenance"

    # Provenance source counts and metadata must reflect ONLY approved revisions
    mentions_data = after_provenance_json["data"]["source_mentions"]
    assert_equal 1, mentions_data.size
    assert_equal 1, mentions_data.first["revisions_count"], "revisions_count in approved provenance must NOT count unapproved revisions"
    assert_equal "careers.acme.example.com", mentions_data.first["source_domain"]

    # Corpus revision must not change
    assert_equal baseline_corpus_revision, ApprovedReleaseManager.current_revision
  end

  test "QA Round 2: P1 authority spoofing - unverified domain claiming official_employer cannot override newer third party observation" do
    batch = {
      "batch_schema_version" => "1.0",
      "batch_id" => "spoof-authority-batch",
      "origin_class" => "adversarial_synthetic",
      "items" => [
        {
          "source_record_key" => "rec-evil-official",
          "mention_key" => "m1",
          "source_system" => "ats",
          "observed_at" => "2026-09-20T10:00:00Z", # older
          "source_kind" => "official_employer",
          "source_domain" => "evil.example", # unverified domain!
          "job_id" => "REQ-SPOOF",
          "title" => "Lead Systems Engineer",
          "company" => "Globex Software",
          "location" => "Austin, TX",
          "salary" => { "min": 999999, "max": 999999, "currency": "USD", "period": "year" }
        },
        {
          "source_record_key" => "rec-board-genuine",
          "mention_key" => "m1",
          "source_system" => "aggregator",
          "observed_at" => "2026-09-25T10:00:00Z", # newer observation
          "source_kind" => "third_party_board",
          "source_domain" => "board.example",
          "job_id" => "REQ-SPOOF",
          "title" => "Lead Systems Engineer",
          "company" => "Globex Software",
          "location" => "Austin, TX",
          "salary" => { "min": 140000, "max": 170000, "currency": "USD", "period": "year" }
        }
      ]
    }

    report = BatchImporter.import_string(JSON.generate(batch))
    assert_equal "complete", report.status

    posting = CanonicalPosting.find_by(company: "Globex Software")
    assert_not_nil posting

    # Assert: evil.example was NOT granted verified official authority
    # The newer credible observation must win!
    assert_equal 140000.0, posting.salary_min.to_f
    assert_equal 170000.0, posting.salary_max.to_f

    selection = posting.field_selections.find_by(field_name: "salary")
    assert_not_equal "verified_official_override", selection.selection_reason
  end

  test "QA Round 2: P1 generic careers URL auto-merge guard - distinct jobs sharing generic openings URL remain separate" do
    batch = {
      "batch_schema_version" => "1.0",
      "batch_id" => "generic-url-batch",
      "origin_class" => "adversarial_synthetic",
      "items" => [
        {
          "source_record_key" => "rec-backend-role",
          "mention_key" => "m1",
          "source_system" => "board_1",
          "observed_at" => "2026-09-20T10:00:00Z",
          "source_kind" => "third_party_board",
          "title" => "Staff Backend Engineer",
          "company" => "Acme Aerospace",
          "location" => "Denver, CO",
          "job_url" => "https://careers.acme.example.com/openings/all"
        },
        {
          "source_record_key" => "rec-designer-role",
          "mention_key" => "m1",
          "source_system" => "board_2",
          "observed_at" => "2026-09-20T10:00:00Z",
          "source_kind" => "third_party_board",
          "title" => "Senior Product Designer",
          "company" => "Acme Aerospace",
          "location" => "Denver, CO",
          "job_url" => "https://careers.acme.example.com/openings/all"
        }
      ]
    }

    report = BatchImporter.import_string(JSON.generate(batch))
    assert_equal "complete", report.status

    postings = CanonicalPosting.where(company: "Acme Aerospace")
    assert_equal 2, postings.count, "Distinct job titles sharing a generic openings URL must NEVER auto-merge"

    # PotentialDuplicate record must be established
    dupes = PotentialDuplicate.where(posting_a: postings).or(PotentialDuplicate.where(posting_b: postings))
    assert dupes.exists?, "Potential duplicate must be recorded for postings sharing a generic URL"
    assert dupes.any? { |d| d.reason_code == "shared_url_differing_titles" }
  end

  test "QA Round 2: P1 release manifest schema validation and cross-validation against candidate items" do
    valid_candidate = {
      "batch_schema_version" => "1.0",
      "batch_id" => "gate-validation-batch",
      "origin_class" => "adversarial_synthetic",
      "items" => [
        {
          "source_record_key" => "rec-gate-1",
          "mention_key" => "m1",
          "source_system" => "ats",
          "observed_at" => "2026-09-20T10:00:00Z",
          "source_kind" => "official_employer",
          "title" => "Security Engineer",
          "company" => "Acme Aerospace",
          "location" => "Denver, CO"
        }
      ]
    }
    cand_json = JSON.generate(valid_candidate)
    correct_manifest = ReleaseGate.build_manifest(cand_json, approved_by: "qa-auditor", corpus_version: "2026.10.1")

    # 1. Invalid schema version
    bad_schema_manifest = correct_manifest.merge("manifest_version" => "2.0")
    gate_res1 = ReleaseGate.evaluate(cand_json, JSON.generate(bad_schema_manifest))
    assert_equal false, gate_res1.approved
    assert gate_res1.errors.any? { |e| e.include?("Manifest schema violation") }

    # 2. Tampered total_items
    bad_count_manifest = correct_manifest.merge("total_items" => 999)
    bad_count_manifest["approval_signature"] = ReleaseGate.compute_digest(cand_json)
    gate_res2 = ReleaseGate.evaluate(cand_json, JSON.generate(bad_count_manifest))
    assert_equal false, gate_res2.approved
    assert gate_res2.errors.any? { |e| e.include?("total_items count (999) does not match") }

    # 3. Tampered origin_class_counts
    bad_origin_manifest = correct_manifest.merge("origin_class_counts" => { "adversarial_synthetic" => 0, "sanitized_historical" => 1 })
    gate_res3 = ReleaseGate.evaluate(cand_json, JSON.generate(bad_origin_manifest))
    assert_equal false, gate_res3.approved
    assert gate_res3.errors.any? { |e| e.include?("adversarial_synthetic count") }
  end

  test "QA Round 2: P2 persistence failure accounting retains exact batch item indices" do
    batch = {
      "batch_schema_version" => "1.0",
      "batch_id" => "persistence-accounting-batch",
      "origin_class" => "adversarial_synthetic",
      "items" => [
        {
          "source_record_key" => "rec-acc-0",
          "mention_key" => "m1",
          "source_system" => "ats",
          "observed_at" => "2026-09-20T10:00:00Z",
          "source_kind" => "third_party_board",
          "title" => "Title 0",
          "company" => "Corp A",
          "location" => "Remote"
        },
        {
          "source_record_key" => "rec-acc-1",
          "mention_key" => "m1",
          "source_system" => "ats",
          "observed_at" => "2026-09-20T10:00:00Z",
          "source_kind" => "third_party_board",
          "title" => "Title 1",
          "company" => "Corp B",
          "location" => "Remote"
        },
        {
          "source_record_key" => "rec-acc-2",
          "mention_key" => "m1",
          "source_system" => "ats",
          "observed_at" => "2026-09-20T10:00:00Z",
          "source_kind" => "third_party_board",
          "title" => "Title 2",
          "company" => "Corp C",
          "location" => "Remote"
        }
      ]
    }

    # Inject failure on item with index 1
    original_sanitize = Sanitizer.method(:sanitize_item)
    Sanitizer.define_singleton_method(:sanitize_item) do |raw_item|
      if raw_item["source_record_key"] == "rec-acc-1"
        raise StandardError, "Injected database persistence failure on rec-acc-1"
      end
      original_sanitize.call(raw_item)
    end

    begin
      report = BatchImporter.import_string(JSON.generate(batch))
      assert_equal "partial", report.status
      assert_equal 3, report.total_input
      assert_equal 2, report.inserted_count
      assert_equal 1, report.invalid_count

      # Verify exact item index was preserved, not -1
      err = report.errors.find { |e| e[:error_code] == "item_persistence_error" }
      assert_not_nil err
      assert_equal 1, err[:item_index], "Item index must match the exact batch index (1), never collapsed to -1"

      # Accounting invariant holds
      sum = report.inserted_count + report.updated_count + report.unchanged_count + report.invalid_count
      assert_equal report.total_input, sum
    ensure
      Sanitizer.define_singleton_method(:sanitize_item, original_sanitize)
    end
  end
end
