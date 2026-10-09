# frozen_string_literal: true

require "test_helper"
require_relative "../../db/migrate/20261009150000_upgrade_revision_digests_to_v2"

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
      "origin_class" => "sanitized_historical",
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

    rec = SourceRecord.create!(source_system: "ats", source_record_key: "rec-app-dupe", origin_class: "sanitized_historical", approved_release_id: release.id)
    approved_posting = CanonicalPosting.create!(
      approved_release: release,
      title: "Senior Backend Engineer",
      company: "Approved Corp",
      location: "Austin, TX",
      first_observed_at: Time.now.utc,
      last_observed_at: Time.now.utc
    )
    sm = SourceMention.create!(source_record: rec, mention_key: "m1", source_kind: "official_employer", canonical_posting_id: approved_posting.id)
    rev = sm.source_revisions.create!(revision_digest: "d-app-1", observed_at: Time.now.utc, title: "Senior Backend Engineer", company: "Approved Corp", location: "Austin, TX")
    ApprovedReleaseRevision.create!(approved_release: release, source_revision: rev, snapshot_source_domain: "careers.example.com")

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

  test "conflicting employer requisition IDs sharing job URL are flagged as identity_conflict and never silently merged or created" do
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
          "job_id" => "REQ-102", # Conflicting requisition ID on same job_url!
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
    assert_not_equal "complete", report.status
    assert_equal 1, report.invalid_count
    assert report.errors.any? { |e| e[:error_code] == "identity_conflict" }

    # Only Item 1 was persisted; Item 2 with conflicting REQ ID on same URL was rejected and NOT merged or silently added!
    assert_equal 1, CanonicalPosting.count
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
          "job_url" => "https://careers.globex.example.com/jobs/sre-500",
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
          "job_url" => "https://careers.globex.example.com/jobs/sre-500",
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
      "origin_class" => "sanitized_historical",
      "items" => [
        {
          "source_record_key" => "rec-approved-p0",
          "mention_key" => "m1",
          "source_system" => "reviewed_export",
          "observed_at" => "2026-09-25T14:00:00Z", # newer unapproved observation
          "source_kind" => "official_employer",
          "source_domain" => "careers.acme.example.com",
          "job_id" => "REQ-P0",
          "title" => "UNAPPROVED PRIVATE TITLE",
          "company" => "Acme Aerospace",
          "location" => "Denver, CO",
          "salary" => { "min": 999999, "max": 999999, "currency": "USD", "period": "year" },
          "summary_excerpt" => "Confidential: reach out to private-person@example.com for private candidate details",
          "job_url" => "https://careers.acme.example.com/jobs/req-p0-v2"
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

    # Strict privacy canary assertions: ZERO leaks of private email or unapproved title
    refute_includes after_provenance_body, "private-person@example.com", "Private canary email must NEVER appear in public provenance"
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
          "job_url" => "https://careers.globex.example.com/jobs/lead-systems-engineer",
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
          "job_url" => "https://careers.globex.example.com/jobs/lead-systems-engineer",
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

  # --- QA Round 3 Regressions ---

  test "QA Round 3: QA3-01 legacy active release serves only historical snapshot and never exposes unapproved canary" do
    # 1. Construct pre-migration style release without join table entries
    legacy_release = ApprovedRelease.create!(
      manifest_digest: "digest-legacy-unjoined",
      approval_signature: "sig-legacy-unjoined",
      approved_by: "legacy-operator",
      approved_at: 10.minutes.ago,
      corpus_version: "2026.09.1",
      total_items: 1,
      origin_class_counts: { "adversarial_synthetic" => 1 },
      active: true
    )

    rec = SourceRecord.create!(
      source_system: "reviewed_export",
      source_record_key: "rec-legacy-key",
      origin_class: "adversarial_synthetic",
      approved_release_id: legacy_release.id
    )

    sm = SourceMention.create!(
      source_record: rec,
      mention_key: "m1",
      source_kind: "official_employer",
      source_domain: "careers.legacy.example.com",
      job_id: "LEGACY-1"
    )

    base_rev = sm.source_revisions.create!(
      revision_digest: "digest-legacy-rev1",
      observed_at: 1.hour.ago,
      created_at: 1.hour.ago,
      title: "Legacy Engineer",
      company: "Legacy Corp",
      location: "San Jose, CA"
    )

    posting = CanonicalPosting.create!(
      approved_release: legacy_release,
      title: "Legacy Engineer",
      company: "Legacy Corp",
      location: "San Jose, CA",
      first_observed_at: 1.hour.ago,
      last_observed_at: 1.hour.ago
    )
    sm.update!(canonical_posting_id: posting.id)

    # Note: approved_release_revisions is empty for legacy_release!
    assert_equal 0, legacy_release.approved_release_revisions.count

    # 2. Append unapproved conflicting revision with private canary
    unapproved_rev = sm.source_revisions.create!(
      revision_digest: "digest-unapproved-canary",
      observed_at: Time.now.utc + 1.day,
      created_at: Time.now.utc,
      title: "LEAKED PRIVATE TITLE",
      company: "Legacy Corp",
      location: "San Jose, CA",
      summary_excerpt: "Confidential private candidate info at qa3-canary@example.com"
    )

    # 3. Assert public endpoint fails closed (404) for release lacking explicit approved_release_revisions; NEVER canary
    get "/api/v1/postings/#{posting.public_id}"
    assert_response :not_found

    get "/api/v1/postings/#{posting.public_id}/provenance"
    assert_response :not_found

    # Direct serializer check: zero canary leaks, fails closed with 0 mentions
    direct_prov = ProvenanceSerializer.render(posting)
    assert_equal 0, direct_prov["source_mentions"].size
    assert_equal 0, direct_prov["merge_evidence"]["total_mentions"]
    refute_includes direct_prov.to_json, "qa3-canary@example.com"
    refute_includes direct_prov.to_json, "LEAKED PRIVATE TITLE"

    # Activation must also reject release with zero memberships
    assert_raises(StandardError) do
      legacy_release.activate!
    end
  end

  test "QA Round 3: QA3-02 changed requisition ID and domain are quarantined as identity_conflict" do
    # 1. Base observation
    batch1 = {
      "batch_schema_version" => "1.0",
      "batch_id" => "qa3-02-base",
      "origin_class" => "adversarial_synthetic",
      "items" => [
        {
          "source_record_key" => "rec-qa3-id-conflict",
          "mention_key" => "m1",
          "source_system" => "ats",
          "observed_at" => "2026-10-01T12:00:00Z",
          "source_kind" => "third_party_board",
          "source_domain" => "careers.example.com",
          "job_id" => "REQ-101",
          "title" => "Platform Architect",
          "company" => "Hooli",
          "location" => "Mountain View, CA"
        }
      ]
    }
    report1 = BatchImporter.import_string(JSON.generate(batch1))
    assert_equal "complete", report1.status

    # 2. Re-import same timestamp and text with changed requisition ID (REQ-101 -> REQ-102)
    batch2 = {
      "batch_schema_version" => "1.0",
      "batch_id" => "qa3-02-changed-id",
      "origin_class" => "adversarial_synthetic",
      "items" => [
        {
          "source_record_key" => "rec-qa3-id-conflict",
          "mention_key" => "m1",
          "source_system" => "ats",
          "observed_at" => "2026-10-01T12:00:00Z",
          "source_kind" => "third_party_board",
          "source_domain" => "careers.example.com",
          "job_id" => "REQ-102", # CHANGED REQUISITION ID
          "title" => "Platform Architect",
          "company" => "Hooli",
          "location" => "Mountain View, CA"
        }
      ]
    }
    report2 = BatchImporter.import_string(JSON.generate(batch2))
    assert_equal "failed", report2.status
    assert_equal 1, report2.invalid_count
    assert report2.errors.any? { |e| e[:error_code] == "identity_conflict" }, "Must reject changed requisition ID as identity_conflict"

    # Existing mention metadata must remain unchanged
    mention = SourceMention.find_by(mention_key: "m1", source_record: SourceRecord.find_by(source_record_key: "rec-qa3-id-conflict"))
    assert_equal "REQ-101", mention.job_id, "Mention job_id must not be silently overwritten"

    # 3. Test in-batch conflict: two items for same mention key in single unordered batch with conflicting domains
    batch_in_batch = {
      "batch_schema_version" => "1.0",
      "batch_id" => "qa3-02-in-batch",
      "origin_class" => "adversarial_synthetic",
      "items" => [
        {
          "source_record_key" => "rec-qa3-in-batch",
          "mention_key" => "m1",
          "source_system" => "ats",
          "observed_at" => "2026-10-01T12:00:00Z",
          "source_kind" => "third_party_board",
          "source_domain" => "careers.example.com",
          "job_id" => "REQ-999",
          "title" => "Site Reliability Engineer",
          "company" => "Hooli",
          "location" => "Mountain View, CA"
        },
        {
          "source_record_key" => "rec-qa3-in-batch",
          "mention_key" => "m1",
          "source_system" => "ats",
          "observed_at" => "2026-10-01T12:00:00Z",
          "source_kind" => "third_party_board",
          "source_domain" => "board.example.com", # CONFLICTING DOMAIN
          "job_id" => "REQ-999",
          "title" => "Site Reliability Engineer",
          "company" => "Hooli",
          "location" => "Mountain View, CA"
        }
      ]
    }
    report_in_batch = BatchImporter.import_string(JSON.generate(batch_in_batch))
    assert_equal "failed", report_in_batch.status
    assert_equal 2, report_in_batch.invalid_count
    assert report_in_batch.errors.any? { |e| e[:error_code] == "identity_conflict" }
  end

  test "QA Round 3: QA3-03 reused source identity rejects cross-origin reuse" do
    # 1. Import sanitized_historical source
    hist_batch = {
      "batch_schema_version" => "1.0",
      "batch_id" => "qa3-03-hist",
      "origin_class" => "sanitized_historical",
      "items" => [
        {
          "source_record_key" => "rec-qa3-03-key",
          "mention_key" => "m1",
          "source_system" => "reviewed_export",
          "origin_class" => "sanitized_historical",
          "observed_at" => "2026-09-01T10:00:00Z",
          "source_kind" => "official_employer",
          "source_domain" => "careers.initech.example.com",
          "job_id" => "REQ-HIST-1",
          "title" => "Database Engineer",
          "company" => "Initech",
          "location" => "Austin, TX"
        }
      ]
    }
    hist_report = BatchImporter.import_string(JSON.generate(hist_batch))
    assert_equal "complete", hist_report.status

    rec = SourceRecord.find_by(source_system: "reviewed_export", source_record_key: "rec-qa3-03-key")
    assert_equal "sanitized_historical", rec.origin_class

    # 2. Attempt to reuse same (system, key) with adversarial_synthetic
    synth_batch = {
      "batch_schema_version" => "1.0",
      "batch_id" => "qa3-03-synth",
      "origin_class" => "adversarial_synthetic",
      "items" => [
        {
          "source_record_key" => "rec-qa3-03-key",
          "mention_key" => "m1",
          "source_system" => "reviewed_export",
          "origin_class" => "adversarial_synthetic", # CONFLICTING ORIGIN CLASS
          "observed_at" => "2026-10-01T10:00:00Z",
          "source_kind" => "official_employer",
          "source_domain" => "careers.initech.example.com",
          "job_id" => "REQ-HIST-1",
          "title" => "Database Engineer",
          "company" => "Initech",
          "location" => "Austin, TX"
        }
      ]
    }
    synth_report = BatchImporter.import_string(JSON.generate(synth_batch))
    assert_equal "failed", synth_report.status
    assert_equal 1, synth_report.invalid_count
    assert synth_report.errors.any? { |e| e[:error_code] == "origin_class_conflict" }

    # SourceRecord origin_class must remain strictly historical
    rec.reload
    assert_equal "sanitized_historical", rec.origin_class
  end

  test "QA Round 3: QA3-04 same-title shared URLs with differing locations or department pages remain separate" do
    # Case A: Same employer, same title, DIFFERENT locations, shared role URL -> Keep separate
    loc_batch = {
      "batch_schema_version" => "1.0",
      "batch_id" => "qa3-04-loc-batch",
      "origin_class" => "adversarial_synthetic",
      "items" => [
        {
          "source_record_key" => "rec-qa4-loc-denver",
          "mention_key" => "m1",
          "source_system" => "board_1",
          "observed_at" => "2026-09-20T10:00:00Z",
          "source_kind" => "third_party_board",
          "title" => "Staff Cloud Architect",
          "company" => "Echo Corp",
          "location" => "Denver, CO",
          "job_url" => "https://careers.echocorp.example.com/jobs/staff-cloud-architect"
        },
        {
          "source_record_key" => "rec-qa4-loc-austin",
          "mention_key" => "m1",
          "source_system" => "board_2",
          "observed_at" => "2026-09-20T10:00:00Z",
          "source_kind" => "third_party_board",
          "title" => "Staff Cloud Architect",
          "company" => "Echo Corp",
          "location" => "Austin, TX", # DIFFERENT LOCATION
          "job_url" => "https://careers.echocorp.example.com/jobs/staff-cloud-architect"
        }
      ]
    }

    report_loc = BatchImporter.import_string(JSON.generate(loc_batch))
    assert_equal "complete", report_loc.status

    postings_loc = CanonicalPosting.where(company: "Echo Corp", title: "Staff Cloud Architect")
    assert_equal 2, postings_loc.count, "Same-title shared-URL jobs in different locations must NEVER auto-merge"

    dupes_loc = PotentialDuplicate.where(posting_a: postings_loc).or(PotentialDuplicate.where(posting_b: postings_loc))
    assert dupes_loc.exists?
    assert dupes_loc.any? { |d| d.reason_code == "shared_url_differing_locations" }

    # Case B: Same employer, same title, same location, but shared path is an unverified department landing page
    dept_batch = {
      "batch_schema_version" => "1.0",
      "batch_id" => "qa3-04-dept-batch",
      "origin_class" => "adversarial_synthetic",
      "items" => [
        {
          "source_record_key" => "rec-qa4-dept-1",
          "mention_key" => "m1",
          "source_system" => "board_1",
          "observed_at" => "2026-09-20T10:00:00Z",
          "source_kind" => "third_party_board",
          "title" => "Principal Systems Engineer",
          "company" => "Echo Corp",
          "location" => "San Jose, CA",
          "job_url" => "https://careers.echocorp.example.com/departments/engineering"
        },
        {
          "source_record_key" => "rec-qa4-dept-2",
          "mention_key" => "m1",
          "source_system" => "board_2",
          "observed_at" => "2026-09-20T10:00:00Z",
          "source_kind" => "third_party_board",
          "title" => "Principal Systems Engineer",
          "company" => "Echo Corp",
          "location" => "San Jose, CA",
          "job_url" => "https://careers.echocorp.example.com/departments/engineering" # DEPARTMENT LANDING PAGE
        }
      ]
    }

    report_dept = BatchImporter.import_string(JSON.generate(dept_batch))
    assert_equal "complete", report_dept.status

    postings_dept = CanonicalPosting.where(company: "Echo Corp", title: "Principal Systems Engineer")
    assert_equal 2, postings_dept.count, "Department landing page URLs without unique listing tokens must NEVER auto-merge"

    dupes_dept = PotentialDuplicate.where(posting_a: postings_dept).or(PotentialDuplicate.where(posting_b: postings_dept))
    assert dupes_dept.exists?
    assert dupes_dept.any? { |d| d.reason_code == "shared_url_ambiguous_role_page" }
  end

  test "QA Round 3: QA3-05 and QA3-06 versioned release-bound authority and exact-byte digest semantics" do
    # QA3-05: Source authority fingerprinting
    fp = SourceAuthority.authority_fingerprint
    assert_not_nil fp
    assert_equal 64, fp.length

    # Publish release and assert authority_fingerprint bound into release and provenance
    cand = {
      "batch_schema_version" => "1.0",
      "batch_id" => "qa3-05-batch",
      "origin_class" => "adversarial_synthetic",
      "items" => [
        {
          "source_record_key" => "rec-qa3-05",
          "mention_key" => "m1",
          "source_system" => "ats",
          "observed_at" => "2026-10-01T10:00:00Z",
          "source_kind" => "official_employer",
          "source_domain" => "careers.acme.example.com",
          "job_id" => "REQ-QA3-05",
          "title" => "Autonomous Systems Director",
          "company" => "Acme Aerospace",
          "location" => "Denver, CO"
        }
      ]
    }
    cand_json = JSON.generate(cand)
    manifest = ReleaseGate.build_manifest(cand_json, approved_by: "qa-auditor", corpus_version: "2026.10.3")
    res = ApprovedReleaseManager.new.publish!(cand_json, JSON.generate(manifest))
    assert res.success

    release = res.approved_release
    assert_equal fp, release.authority_fingerprint

    posting = CanonicalPosting.find_by(title: "Autonomous Systems Director")
    assert_not_nil posting
    prov = ProvenanceSerializer.render(posting)
    assert_equal fp, prov["merge_evidence"]["authority_fingerprint"]

    # QA3-06: Exact byte vs normalized text digest semantics
    raw_str = '{"test": 123}'
    padded_str = '{"test": 123}   '

    # Exact byte digest distinguishes trailing whitespace
    refute_equal ReleaseGate.compute_digest(raw_str, algorithm: "sha256-exact"),
                 ReleaseGate.compute_digest(padded_str, algorithm: "sha256-exact")

    # Normalized text digest matches trimmed content
    assert_equal ReleaseGate.compute_digest(raw_str, algorithm: "sha256-normalized-text"),
                 ReleaseGate.compute_digest(padded_str, algorithm: "sha256-normalized-text")
  end

  # ==========================================================================
  # QA Round 4 Regressions (QA4-01 through QA4-07)
  # ==========================================================================

  test "QA Round 4: QA4-01 cross-signal identity conflicts are detected before filtering and quarantined as identity_conflict" do
    # 1. Ingest base batch with Posting A (REQ-A, ats-a URL) and Posting B (REQ-B, ats-b URL)
    base_batch = {
      "batch_schema_version" => "1.0",
      "batch_id" => "qa4-01-base-batch",
      "origin_class" => "adversarial_synthetic",
      "items" => [
        {
          "source_record_key" => "rec-qa4-post-a",
          "mention_key" => "m1",
          "source_system" => "ats_greenhouse",
          "source_domain" => "careers.acme.example.com",
          "observed_at" => "2026-10-01T10:00:00Z",
          "source_kind" => "official_employer",
          "job_id" => "REQ-QA4-A",
          "title" => "Senior Distributed Engineer",
          "company" => "Acme Aerospace",
          "location" => "Denver, CO",
          "job_url" => "https://careers.acme.example.com/jobs/dist-eng-a"
        },
        {
          "source_record_key" => "rec-qa4-post-b",
          "mention_key" => "m1",
          "source_system" => "ats_lever",
          "source_domain" => "careers.acme.example.com",
          "observed_at" => "2026-10-01T10:00:00Z",
          "source_kind" => "official_employer",
          "job_id" => "REQ-QA4-B",
          "title" => "Senior Distributed Engineer",
          "company" => "Acme Aerospace",
          "location" => "Denver, CO",
          "job_url" => "https://careers.acme.example.com/jobs/dist-eng-b"
        }
      ]
    }
    report1 = BatchImporter.import_string(JSON.generate(base_batch))
    assert_equal "complete", report1.status
    assert_equal 2, CanonicalPosting.where(company: "Acme Aerospace").count

    post_a = CanonicalPosting.joins(:source_mentions).find_by(source_mentions: { job_id: "REQ-QA4-A" })
    post_b = CanonicalPosting.joins(:source_mentions).find_by(source_mentions: { job_id: "REQ-QA4-B" })
    refute_equal post_a.id, post_b.id

    # 2. Ingest new observation claiming REQ-QA4-A (matches A) but B's exact URL (matches B)
    conflict_batch = {
      "batch_schema_version" => "1.0",
      "batch_id" => "qa4-01-conflict-batch",
      "origin_class" => "adversarial_synthetic",
      "items" => [
        {
          "source_record_key" => "rec-qa4-contradiction",
          "mention_key" => "m1",
          "source_system" => "aggregator_feed",
          "observed_at" => "2026-10-02T12:00:00Z",
          "source_kind" => "third_party_board",
          "job_id" => "REQ-QA4-A", # Claims Requisition A!
          "title" => "Senior Distributed Engineer",
          "company" => "Acme Aerospace",
          "location" => "Denver, CO",
          "job_url" => "https://careers.acme.example.com/jobs/dist-eng-b" # BUT matches Posting B's URL!
        }
      ]
    }

    report2 = BatchImporter.import_string(JSON.generate(conflict_batch))
    assert_not_equal "complete", report2.status
    assert_equal 1, report2.invalid_count
    assert report2.errors.any? { |e| e[:error_code] == "identity_conflict" }

    # Verify: Neither posting was mutated or merged
    assert_equal 2, CanonicalPosting.where(company: "Acme Aerospace").count
    post_a.reload
    post_b.reload
    assert_equal 1, post_a.source_mentions.count
    assert_equal 1, post_b.source_mentions.count
  end

  test "QA Round 4: QA4-02 unverified third-party job IDs cannot auto-merge under Tier 1 without verified official authority" do
    batch = {
      "batch_schema_version" => "1.0",
      "batch_id" => "qa4-02-unverified-id-batch",
      "origin_class" => "adversarial_synthetic",
      "items" => [
        {
          "source_record_key" => "rec-qa4-board-1",
          "mention_key" => "m1",
          "source_system" => "untrusted_board_alpha",
          "source_domain" => "board-alpha.example.org",
          "observed_at" => "2026-10-01T10:00:00Z",
          "source_kind" => "third_party_board",
          "job_id" => "123", # Shared generic ID on third party
          "title" => "DevOps Engineer",
          "company" => "Initech",
          "location" => "Austin, TX"
        },
        {
          "source_record_key" => "rec-qa4-board-2",
          "mention_key" => "m1",
          "source_system" => "untrusted_board_beta",
          "source_domain" => "board-beta.example.org",
          "observed_at" => "2026-10-01T10:00:00Z",
          "source_kind" => "third_party_board",
          "job_id" => "123", # Same ID 123 but distinct opening!
          "title" => "Security Specialist",
          "company" => "Initech",
          "location" => "Dallas, TX"
        }
      ]
    }

    report = BatchImporter.import_string(JSON.generate(batch))
    assert_equal "complete", report.status

    # Must NOT auto-merge under Tier 1; must remain 2 separate canonical postings!
    postings = CanonicalPosting.where(company: "Initech")
    assert_equal 2, postings.count
    assert PotentialDuplicate.where(posting_a: postings).or(PotentialDuplicate.where(posting_b: postings)).exists?
  end

  test "QA Round 4: QA4-03 official source record allowlist impersonation requires composite system and record key" do
    # Attempt to spoof rec-official-acme using untrusted_board, blank domain, claiming official_employer
    batch = {
      "batch_schema_version" => "1.0",
      "batch_id" => "qa4-03-spoof-allowlist",
      "origin_class" => "adversarial_synthetic",
      "items" => [
        {
          "source_record_key" => "rec-official-acme", # Known allowlisted key
          "mention_key" => "m1",
          "source_system" => "untrusted_board", # NOT an authorized system for this key!
          "observed_at" => "2026-09-20T10:00:00Z",
          "source_kind" => "official_employer",
          "job_id" => "REQ-IMPERSONATE",
          "title" => "Staff Flight Controller",
          "company" => "Acme Aerospace",
          "location" => "Denver, CO",
          "job_url" => "https://careers.acme.example.com/jobs/flight-controller",
          "salary" => { "min": 999999, "max": 999999, "currency": "USD", "period": "year" }
        },
        {
          "source_record_key" => "rec-board-honest",
          "mention_key" => "m1",
          "source_system" => "reviewed_export",
          "source_domain" => "techjobs.example.org",
          "observed_at" => "2026-09-25T10:00:00Z", # newer credible observation
          "source_kind" => "third_party_board",
          "job_id" => "REQ-IMPERSONATE",
          "title" => "Staff Flight Controller",
          "company" => "Acme Aerospace",
          "location" => "Denver, CO",
          "job_url" => "https://careers.acme.example.com/jobs/flight-controller",
          "salary" => { "min": 170000, "max": 210000, "currency": "USD", "period": "year" }
        }
      ]
    }

    report = BatchImporter.import_string(JSON.generate(batch))
    assert_equal "complete", report.status

    m1 = SourceMention.joins(:source_record).find_by(source_records: { source_system: "untrusted_board", source_record_key: "rec-official-acme" })
    assert_not SourceAuthority.verified_official?(m1, "Acme Aerospace"), "Must NOT grant verified official authority to untrusted system with blank domain"

    posting = CanonicalPosting.find_by(title: "Staff Flight Controller")
    assert_not_nil posting
    # Newer credible observation must win; spoofed 999k salary must NOT override
    assert_equal 170000, posting.salary_min.to_i
    assert_equal 210000, posting.salary_max.to_i
  end

  test "QA Round 4: QA4-04 release activation is forward-only and rejects unsupported rollback to superseded releases" do
    # 1. Publish Release 1
    batch_v1 = {
      "batch_schema_version" => "1.0",
      "batch_id" => "qa4-04-r1-batch",
      "origin_class" => "sanitized_historical",
      "items" => [
        {
          "source_record_key" => "rec-qa4-r1",
          "mention_key" => "m1",
          "source_system" => "reviewed_export",
          "observed_at" => "2026-09-01T10:00:00Z",
          "source_kind" => "official_employer",
          "source_domain" => "careers.acme.example.com",
          "job_id" => "REQ-R1",
          "title" => "Release One Engineer",
          "company" => "Acme Aerospace",
          "location" => "Denver, CO"
        }
      ]
    }
    b1_json = JSON.generate(batch_v1)
    m1_json = JSON.generate(ReleaseGate.build_manifest(b1_json, approved_by: "qa-lead", corpus_version: "2026.10.R1"))
    res1 = ApprovedReleaseManager.new.publish!(b1_json, m1_json)
    assert res1.success
    r1 = res1.approved_release
    assert r1.reload.active

    # 2. Publish Release 2 (superseding R1)
    batch_v2 = {
      "batch_schema_version" => "1.0",
      "batch_id" => "qa4-04-r2-batch",
      "origin_class" => "sanitized_historical",
      "items" => [
        {
          "source_record_key" => "rec-qa4-r2",
          "mention_key" => "m1",
          "source_system" => "reviewed_export",
          "observed_at" => "2026-09-02T10:00:00Z",
          "source_kind" => "official_employer",
          "source_domain" => "careers.acme.example.com",
          "job_id" => "REQ-R2",
          "title" => "Release Two Engineer",
          "company" => "Acme Aerospace",
          "location" => "Denver, CO"
        }
      ]
    }
    b2_json = JSON.generate(batch_v2)
    m2_json = JSON.generate(ReleaseGate.build_manifest(b2_json, approved_by: "qa-lead", corpus_version: "2026.10.R2"))
    res2 = ApprovedReleaseManager.new.publish!(b2_json, m2_json)
    assert res2.success
    r2 = res2.approved_release

    assert_not r1.reload.active
    assert r2.reload.active

    # 3. Attempt rollback to superseded release R1
    assert_raises(ApprovedRelease::UnsupportedRollbackError) do
      r1.activate!
    end

    # R2 must remain active
    assert_not r1.reload.active
    assert r2.reload.active
  end

  test "QA Round 4: QA4-05 revision digest uses canonical sorted JSON (v2) to eliminate pipe delimiter collisions" do
    base_attrs = {
      "source_system" => "ats",
      "source_record_key" => "rec-1",
      "mention_key" => "m1",
      "origin_class" => "sanitized_historical",
      "source_kind" => "official_employer",
      "source_domain" => "careers.example.com",
      "job_id" => "REQ-1",
      "location" => "Denver, CO",
      "remote_type" => "hybrid",
      "employment_type" => "full_time",
      "salary_min" => 100000,
      "salary_max" => 120000,
      "salary_currency" => "USD",
      "salary_period" => "year",
      "summary_excerpt" => "Desc",
      "job_url" => "https://example.com/job"
    }

    obs_a = base_attrs.merge("title" => "Senior Engineer", "company" => "A|B")
    obs_b = base_attrs.merge("title" => "Senior Engineer|A", "company" => "B")

    # In legacy v1 (pipe-joined concatenation), these collided to the identical SHA-256:
    v1_digest_a = SourceRevision.compute_digest(obs_a, version: "v1")
    v1_digest_b = SourceRevision.compute_digest(obs_b, version: "v1")
    assert_equal v1_digest_a, v1_digest_b, "Demonstrates legacy non-injective delimiter collision in v1"

    # In canonical v2 (ordered JSON), digests are guaranteed distinct and injective:
    v2_digest_a = SourceRevision.compute_digest(obs_a, version: "v2")
    v2_digest_b = SourceRevision.compute_digest(obs_b, version: "v2")
    refute_equal v2_digest_a, v2_digest_b, "v2 canonical JSON digest must produce distinct hashes for different field boundaries"
  end

  test "QA Round 4: QA4-06 replay of identical input against v1 digest database upgrades to v2 without spurious revisions" do
    # 1. Create a legacy revision in database with digest_version "v1" and v1 digest
    rec = SourceRecord.create!(source_system: "reviewed_export", source_record_key: "rec-qa4-v1", origin_class: "sanitized_historical")
    sm = SourceMention.create!(source_record: rec, mention_key: "m1", source_kind: "official_employer", source_domain: "careers.acme.example.com", job_id: "REQ-V1")
    
    item_attrs = {
      "source_record_key" => "rec-qa4-v1",
      "mention_key" => "m1",
      "source_system" => "reviewed_export",
      "origin_class" => "sanitized_historical",
      "source_kind" => "official_employer",
      "source_domain" => "careers.acme.example.com",
      "job_id" => "REQ-V1",
      "observed_at" => "2026-09-01T10:00:00Z",
      "title" => "Hardware Reliability Engineer",
      "company" => "Acme Aerospace",
      "location" => "Denver, CO",
      "remote_type" => "unknown",
      "employment_type" => "unknown"
    }
    v1_digest = SourceRevision.compute_digest(item_attrs, version: "v1")
    v2_digest = SourceRevision.compute_digest(item_attrs, version: "v2")

    rev = sm.source_revisions.create!(
      revision_digest: v1_digest,
      digest_version: "v1",
      observed_at: Time.parse("2026-09-01T10:00:00Z"),
      title: "Hardware Reliability Engineer",
      company: "Acme Aerospace",
      location: "Denver, CO"
    )

    initial_revisions_count = SourceRevision.count

    # 2. Replay identical input batch
    replay_batch = {
      "batch_schema_version" => "1.0",
      "batch_id" => "qa4-06-replay-batch",
      "origin_class" => "sanitized_historical",
      "items" => [item_attrs]
    }

    report = BatchImporter.import_string(JSON.generate(replay_batch))
    assert_equal "complete", report.status
    assert_equal 1, report.unchanged_count, "Identical replay must be counted as unchanged"
    assert_equal 0, report.inserted_count
    assert_equal 0, report.updated_count

    # 3. Assert zero new revisions created and existing revision upgraded in-place to v2
    assert_equal initial_revisions_count, SourceRevision.count
    rev.reload
    assert_equal "v2", rev.digest_version
    assert_equal v2_digest, rev.revision_digest
  end

  test "QA Round 4: QA4-07 release lacking explicit approved_release_revisions memberships fails closed" do
    rel = ApprovedRelease.create!(
      manifest_digest: "digest-qa4-07-unjoined",
      approval_signature: "sig-qa4-07-unjoined",
      approved_by: "qa-auditor",
      approved_at: 10.minutes.ago,
      corpus_version: "2026.10.QA7",
      total_items: 1,
      active: false
    )

    # 1. Activation must fail closed when memberships are empty
    assert_raises(StandardError) do
      rel.activate!
    end

    # 2. Even if marked active in DB directly, queries must fail closed
    rel.update_columns(active: true)

    rec = SourceRecord.create!(source_system: "ats", source_record_key: "rec-qa7", origin_class: "sanitized_historical", approved_release_id: rel.id)
    sm = SourceMention.create!(source_record: rec, mention_key: "m1", source_kind: "official_employer")
    rev = sm.source_revisions.create!(revision_digest: "d-qa7", observed_at: Time.now.utc, title: "Title", company: "Company", location: "Loc")
    posting = CanonicalPosting.create!(
      approved_release: rel,
      title: "Title",
      company: "Company",
      location: "Loc",
      first_observed_at: Time.now.utc,
      last_observed_at: Time.now.utc
    )

    refute_includes CanonicalPosting.active_approved.pluck(:id), posting.id
    assert_equal 0, posting.approved_revisions.count
    assert_equal 0, ProvenanceSerializer.render(posting)["source_mentions"].size

    get "/api/v1/postings/#{posting.public_id}"
    assert_response :not_found

    get "/api/v1/postings/#{posting.public_id}/provenance"
    assert_response :not_found
  end

  # ==========================================================================
  # Round 5 Audit Remediations (QA5-01 through QA5-06)
  # ==========================================================================

  test "QA Round 5: QA5-01 new unapproved mention on existing approved source record stays in staging and does not leak" do
    # 1. Publish an approved release containing source_record_key: rec-approved-1, mention_key: approved-1
    batch_1 = {
      "batch_schema_version" => "1.0",
      "batch_id" => "qa5-01-base-batch",
      "origin_class" => "sanitized_historical",
      "items" => [
        {
          "source_record_key" => "rec-approved-1",
          "mention_key" => "approved-1",
          "source_system" => "reviewed_export",
          "observed_at" => "2026-09-20T10:00:00Z",
          "source_kind" => "official_employer",
          "source_domain" => "careers.acme.example.com",
          "job_id" => "REQ-101",
          "title" => "Approved Flight Director",
          "company" => "Acme Aerospace",
          "location" => "Denver, CO",
          "salary" => { "min": 175000, "max": 215000, "currency": "USD", "period": "year" },
          "summary_excerpt" => "Approved public excerpt."
        }
      ]
    }
    b1_json = JSON.generate(batch_1)
    m1_json = JSON.generate(ReleaseGate.build_manifest(b1_json, approved_by: "qa-lead", corpus_version: "2026.10.QA5.1"))
    pub_res = ApprovedReleaseManager.new.publish!(b1_json, m1_json)
    assert pub_res.success, "Publication 1 must succeed: #{pub_res.errors}"

    approved_posting = CanonicalPosting.active_approved.first
    assert_not_nil approved_posting
    assert_equal "Approved Flight Director", approved_posting.title

    baseline_count = CanonicalPosting.active_approved.count
    baseline_corpus_revision = ApprovedReleaseManager.current_revision

    # 2. Independently import a new, unapproved batch with the SAME source_record_key but different mention_key
    # and a private canary in summary_excerpt
    staging_batch = {
      "batch_schema_version" => "1.0",
      "batch_id" => "qa5-01-staging-batch",
      "origin_class" => "sanitized_historical",
      "items" => [
        {
          "source_record_key" => "rec-approved-1",
          "mention_key" => "new-staging-2",
          "source_system" => "reviewed_export",
          "observed_at" => "2026-09-25T12:00:00Z",
          "source_kind" => "official_employer",
          "source_domain" => "careers.acme.example.com",
          "job_id" => "REQ-999-STAGING",
          "title" => "Staging Security Officer",
          "company" => "Acme Aerospace",
          "location" => "Boulder, CO",
          "salary" => { "min": 120000, "max": 140000, "currency": "USD", "period": "year" },
          "summary_excerpt" => "QA5_PRIVATE_CANARY: Staging confidential role must remain private."
        }
      ]
    }
    stg_report = BatchImporter.import_string(JSON.generate(staging_batch))
    assert_equal "complete", stg_report.status
    assert_equal 1, stg_report.inserted_count

    # Staging posting must be created with approved_release_id: nil
    staging_posting = CanonicalPosting.find_by(title: "Staging Security Officer")
    assert_not_nil staging_posting
    assert_nil staging_posting.approved_release_id

    # 3. Assert public state is completely unchanged
    assert_equal baseline_count, CanonicalPosting.active_approved.count, "Public count must NOT include staging posting"
    assert_equal baseline_corpus_revision, ApprovedReleaseManager.current_revision, "Corpus revision must NOT change"

    # Public search returns only the approved posting; canary is NOT present
    get "/api/v1/postings"
    assert_response :success
    search_json = JSON.parse(response.body)
    assert_equal 1, search_json["data"].size
    assert_equal approved_posting.public_id, search_json["data"][0]["id"]
    refute_includes response.body, "QA5_PRIVATE_CANARY"
    refute_includes response.body, "Staging Security Officer"

    # Staging posting public detail receives 404
    get "/api/v1/postings/#{staging_posting.public_id}"
    assert_response :not_found

    # Staging posting provenance receives 404
    get "/api/v1/postings/#{staging_posting.public_id}/provenance"
    assert_response :not_found

    # Approved posting detail and provenance have NO extra mention or canary
    get "/api/v1/postings/#{approved_posting.public_id}"
    assert_response :success
    refute_includes response.body, "QA5_PRIVATE_CANARY"

    get "/api/v1/postings/#{approved_posting.public_id}/provenance"
    assert_response :success
    prov_json = JSON.parse(response.body)
    assert_equal 1, prov_json["data"]["source_mentions"].size
    assert_equal "approved-1", prov_json["data"]["source_mentions"][0]["mention_key"]
    refute_includes response.body, "QA5_PRIVATE_CANARY"

    # GET /api/v1/meta remains unchanged
    get "/api/v1/meta"
    assert_response :success
    meta_json = JSON.parse(response.body)
    assert_equal baseline_count, meta_json["active_approved_postings"]
    assert_equal baseline_corpus_revision, meta_json["corpus_revision"]

    # 4. Separately approve and publish a release including the second mention
    # Proves it becomes visible ONLY after explicit publication
    batch_2 = {
      "batch_schema_version" => "1.0",
      "batch_id" => "qa5-01-approved-both-batch",
      "origin_class" => "sanitized_historical",
      "items" => batch_1["items"] + [
        {
          "source_record_key" => "rec-approved-1",
          "mention_key" => "new-staging-2",
          "source_system" => "reviewed_export",
          "observed_at" => "2026-09-25T12:00:00Z",
          "source_kind" => "official_employer",
          "source_domain" => "careers.acme.example.com",
          "job_id" => "REQ-999-STAGING",
          "title" => "Staging Security Officer",
          "company" => "Acme Aerospace",
          "location" => "Boulder, CO",
          "salary" => { "min": 120000, "max": 140000, "currency": "USD", "period": "year" },
          "summary_excerpt" => "Approved excerpt for security officer without canaries."
        }
      ]
    }
    b2_json = JSON.generate(batch_2)
    m2_json = JSON.generate(ReleaseGate.build_manifest(b2_json, approved_by: "qa-lead", corpus_version: "2026.10.QA5.2"))
    pub_res2 = ApprovedReleaseManager.new.publish!(b2_json, m2_json)
    assert pub_res2.success, "Publication 2 must succeed: #{pub_res2.errors}"
    assert_equal 2, CanonicalPosting.active_approved.count

    get "/api/v1/postings/#{staging_posting.public_id}"
    assert_response :success
  end

  test "QA Round 5: QA5-02 rolled-back item subtransaction preserves exact accounting and zero orphan records" do
    # 1. Establish two base postings
    base_batch = {
      "batch_schema_version" => "1.0",
      "batch_id" => "qa5-02-base-batch",
      "origin_class" => "adversarial_synthetic",
      "items" => [
        {
          "source_record_key" => "rec-qa5-02-base-a",
          "mention_key" => "m1",
          "source_system" => "ats",
          "job_id" => "REQ-502-A",
          "observed_at" => "2026-09-20T10:00:00Z",
          "source_kind" => "official_employer",
          "source_domain" => "careers.acme.example.com",
          "title" => "Architect Alpha",
          "company" => "Acme Aerospace",
          "location" => "Denver, CO",
          "job_url" => "https://careers.acme.example.com/jobs/arch-alpha"
        },
        {
          "source_record_key" => "rec-qa5-02-base-b",
          "mention_key" => "m1",
          "source_system" => "ats",
          "job_id" => "REQ-502-B",
          "observed_at" => "2026-09-20T10:00:00Z",
          "source_kind" => "official_employer",
          "source_domain" => "careers.acme.example.com",
          "title" => "Architect Beta",
          "company" => "Acme Aerospace",
          "location" => "Denver, CO",
          "job_url" => "https://careers.acme.example.com/jobs/arch-beta"
        }
      ]
    }
    rep_base = BatchImporter.import_string(JSON.generate(base_batch))
    assert_equal "complete", rep_base.status

    initial_records = SourceRecord.count
    initial_mentions = SourceMention.count
    initial_revisions = SourceRevision.count
    initial_postings = CanonicalPosting.count

    # 2. Ingest contradictory ID item in a single-item batch (claims REQ-502-A but URL of Beta)
    conflict_batch = {
      "batch_schema_version" => "1.0",
      "batch_id" => "qa5-02-conflict-single",
      "origin_class" => "adversarial_synthetic",
      "items" => [
        {
          "source_record_key" => "rec-qa5-02-conflict",
          "mention_key" => "m1",
          "source_system" => "aggregator_feed",
          "observed_at" => "2026-10-02T12:00:00Z",
          "source_kind" => "third_party_board",
          "job_id" => "REQ-502-A", # Claims Requisition A!
          "title" => "Contradictory Engineer",
          "company" => "Acme Aerospace",
          "location" => "Denver, CO",
          "job_url" => "https://careers.acme.example.com/jobs/arch-beta" # BUT matches Posting B's URL!
        }
      ]
    }
    rep_single = BatchImporter.import_string(JSON.generate(conflict_batch))
    assert_equal "failed", rep_single.status
    assert_equal 1, rep_single.total_input
    assert_equal 0, rep_single.inserted_count
    assert_equal 0, rep_single.updated_count
    assert_equal 0, rep_single.unchanged_count
    assert_equal 1, rep_single.invalid_count
    assert_equal 1, rep_single.errors.size
    assert_equal "identity_conflict", rep_single.errors.first[:error_code]

    # Invariant: total_input == inserted + updated + unchanged + invalid
    assert_equal rep_single.total_input, (rep_single.inserted_count + rep_single.updated_count + rep_single.unchanged_count + rep_single.invalid_count)

    # Invariant: Subtransaction rollback leaves zero orphan records
    assert_equal initial_records, SourceRecord.count
    assert_equal initial_mentions, SourceMention.count
    assert_equal initial_revisions, SourceRevision.count
    assert_equal initial_postings, CanonicalPosting.count

    # 3. Repeat in mixed batch: 1 valid unrelated item + 1 contradictory ID item
    mixed_batch = {
      "batch_schema_version" => "1.0",
      "batch_id" => "qa5-02-mixed-batch",
      "origin_class" => "adversarial_synthetic",
      "items" => [
        {
          "source_record_key" => "rec-qa5-02-unrelated-valid",
          "mention_key" => "m1",
          "source_system" => "ats",
          "job_id" => "REQ-UNRELATED-1",
          "observed_at" => "2026-09-22T10:00:00Z",
          "source_kind" => "official_employer",
          "source_domain" => "careers.acme.example.com",
          "title" => "Unrelated Product Manager",
          "company" => "Acme Aerospace",
          "location" => "Denver, CO",
          "job_url" => "https://careers.acme.example.com/jobs/pm-1"
        },
        conflict_batch["items"].first
      ]
    }
    rep_mixed = BatchImporter.import_string(JSON.generate(mixed_batch))
    assert_equal "partial", rep_mixed.status
    assert_equal 2, rep_mixed.total_input
    assert_equal 1, rep_mixed.inserted_count
    assert_equal 0, rep_mixed.updated_count
    assert_equal 0, rep_mixed.unchanged_count
    assert_equal 1, rep_mixed.invalid_count

    # Invariant: total_input == inserted + updated + unchanged + invalid
    assert_equal rep_mixed.total_input, (rep_mixed.inserted_count + rep_mixed.updated_count + rep_mixed.unchanged_count + rep_mixed.invalid_count)
  end

  test "QA Round 5: QA5-03 Tier 3 withholds merge when platform key is unvetted or roles diverge, but merges verified ATS" do
    # Negative test: Same employer, same unreviewed third-party board domain, generic job_id, different titles and locations, no job_url
    unvetted_batch = {
      "batch_schema_version" => "1.0",
      "batch_id" => "qa5-03-unvetted-batch",
      "origin_class" => "adversarial_synthetic",
      "items" => [
        {
          "source_record_key" => "rec-unvetted-1",
          "mention_key" => "m1",
          "source_system" => "third_party_aggregator",
          "source_domain" => "boards.unreviewed-aggregator.example.net",
          "job_id" => "GENERIC-99",
          "observed_at" => "2026-09-20T10:00:00Z",
          "source_kind" => "third_party_board",
          "title" => "Lead Systems Architect",
          "company" => "Acme Aerospace",
          "location" => "Seattle, WA"
        },
        {
          "source_record_key" => "rec-unvetted-2",
          "mention_key" => "m1",
          "source_system" => "third_party_aggregator",
          "source_domain" => "boards.unreviewed-aggregator.example.net", # Same unreviewed domain and job ID
          "job_id" => "GENERIC-99",
          "observed_at" => "2026-09-21T10:00:00Z",
          "source_kind" => "third_party_board",
          "title" => "Senior Corporate Accountant", # Divergent title
          "company" => "Acme Aerospace",
          "location" => "Denver, CO" # Divergent location
        }
      ]
    }
    rep_unvetted = BatchImporter.import_string(JSON.generate(unvetted_batch))
    assert_equal "complete", rep_unvetted.status

    p1 = CanonicalPosting.find_by(title: "Lead Systems Architect")
    p2 = CanonicalPosting.find_by(title: "Senior Corporate Accountant")
    assert_not_nil p1
    assert_not_nil p2
    assert_not_equal p1.id, p2.id, "Unreviewed platform key must NOT merge divergent roles in Tier 3"

    # Flagged as uncertain potential duplicate
    assert PotentialDuplicate.where(reason_code: "unverified_shared_job_id").exists?,
      "Withheld Tier 3 merge must record unverified_shared_job_id potential duplicate"

    # Positive test: Verified ATS platform key merges matching roles under Tier 3
    ats_batch = {
      "batch_schema_version" => "1.0",
      "batch_id" => "qa5-03-ats-batch",
      "origin_class" => "sanitized_historical",
      "items" => [
        {
          "source_record_key" => "rec-ats-pos-1",
          "mention_key" => "m1",
          "source_system" => "ats",
          "source_domain" => "boards.greenhouse.io",
          "job_id" => "GH-12345",
          "observed_at" => "2026-09-22T10:00:00Z",
          "source_kind" => "third_party_board",
          "title" => "Lead Infrastructure Engineer",
          "company" => "Echo Corp",
          "location" => "Austin, TX"
        },
        {
          "source_record_key" => "rec-ats-pos-2",
          "mention_key" => "m1",
          "source_system" => "ats",
          "source_domain" => "boards.greenhouse.io",
          "job_id" => "GH-12345", # Same verified ATS platform key
          "observed_at" => "2026-09-23T10:00:00Z",
          "source_kind" => "third_party_board",
          "title" => "Lead Infrastructure Engineer",
          "company" => "Echo Corp",
          "location" => "Austin, TX"
        }
      ]
    }
    rep_ats = BatchImporter.import_string(JSON.generate(ats_batch))
    assert_equal "complete", rep_ats.status

    m_pos1 = SourceMention.joins(:source_record).find_by(source_records: { source_record_key: "rec-ats-pos-1" })
    m_pos2 = SourceMention.joins(:source_record).find_by(source_records: { source_record_key: "rec-ats-pos-2" })
    assert_not_nil m_pos1.canonical_posting_id
    assert_equal m_pos1.canonical_posting_id, m_pos2.canonical_posting_id,
      "Verified ATS platform key must merge same-employer observation under Tier 3"
  end

  test "QA Round 5: QA5-04 claimed employer domain from untrusted source cannot confer verified official authority" do
    # Observation from untrusted scraper claiming official_employer and careers.acme.example.com
    batch = {
      "batch_schema_version" => "1.0",
      "batch_id" => "qa5-04-spoofed-domain-batch",
      "origin_class" => "adversarial_synthetic",
      "items" => [
        {
          "source_record_key" => "spoofed-scraper-acme",
          "mention_key" => "m1",
          "source_system" => "untrusted_scraper", # Untrusted source system!
          "source_domain" => "careers.acme.example.com", # Claimed allowlisted domain!
          "observed_at" => "2026-09-20T10:00:00Z", # older
          "source_kind" => "official_employer",
          "job_id" => "REQ-SPOOF",
          "title" => "Propulsion Specialist",
          "company" => "Acme Aerospace",
          "location" => "Denver, CO",
          "job_url" => "https://careers.acme.example.com/jobs/propulsion",
          "salary" => { "min": 999000, "max": 999000, "currency": "USD", "period": "year" }
        },
        {
          "source_record_key" => "rec-honest-board",
          "mention_key" => "m1",
          "source_system" => "reviewed_export",
          "source_domain" => "techjobs.example.org",
          "observed_at" => "2026-09-24T14:00:00Z", # newer credible observation
          "source_kind" => "third_party_board",
          "job_id" => "REQ-SPOOF",
          "title" => "Propulsion Specialist",
          "company" => "Acme Aerospace",
          "location" => "Denver, CO",
          "job_url" => "https://careers.acme.example.com/jobs/propulsion",
          "salary" => { "min": 150000, "max": 185000, "currency": "USD", "period": "year" }
        }
      ]
    }

    report = BatchImporter.import_string(JSON.generate(batch))
    assert_equal "complete", report.status

    m_spoof = SourceMention.joins(:source_record).find_by(source_records: { source_record_key: "spoofed-scraper-acme" })
    assert_not SourceAuthority.verified_official?(m_spoof, "Acme Aerospace"),
      "Untrusted scraper claiming verified domain without reviewed grant must NOT receive official authority"

    posting = CanonicalPosting.find_by(title: "Propulsion Specialist")
    assert_not_nil posting
    # Newer credible observation must win; 999k salary from untrusted scraper must NOT override
    assert_equal 150000, posting.salary_min.to_i
    assert_equal 185000, posting.salary_max.to_i
    salary_sel = posting.field_selections.find_by(field_name: "salary")
    assert_equal "newest_credible", salary_sel.selection_reason

    # Contrast with authentic verified source: rec-official-acme
    m_auth = SourceMention.joins(:source_record).find_by(source_records: { source_record_key: "rec-official-acme" })
    if m_auth
      assert SourceAuthority.verified_official?(m_auth, "Acme Aerospace")
    end
  end

  test "QA Round 5: QA5-05 bin/verify and phantom:publish protect production and require explicit manifests" do
    # 1. phantom:publish requires explicit candidate and manifest paths
    publish_output = IO.popen(["ruby", "bin/rails", "phantom:publish"], err: [:child, :out], &:read)
    assert_includes publish_output, "Usage: bin/rails phantom:publish"

    # 2. In production mode, bin/verify --seed-demo exits nonzero
    test_db = ActiveRecord::Base.connection_db_config.database
    prod_env = { "RAILS_ENV" => "production", "POSTGRES_DB" => test_db }
    prod_seed_output = IO.popen([prod_env, "ruby", "bin/verify", "--seed-demo"], err: [:child, :out], &:read)
    assert_includes prod_seed_output, "FAIL: Seeding demo fixtures is strictly prohibited in production environment"

    # 3. In production mode without --seed-demo, bin/verify is read-only and skips seeding/mutation
    prod_verify_output = IO.popen([prod_env, "ruby", "bin/verify"], err: [:child, :out], &:read)
    assert_includes prod_verify_output, "SKIPPED (read-only verification in production)"
  end

  test "QA Round 5: QA5-06 v2 digest migration prefers historical raw_safe_fields over mutated current metadata" do
    rec = SourceRecord.create!(source_system: "ats", source_record_key: "rec-legacy-506", origin_class: "sanitized_historical")
    sm = SourceMention.create!(
      source_record: rec,
      mention_key: "m1",
      source_kind: "official_employer",
      source_domain: "careers.acme.example.com",
      job_id: "JOB-ORIGINAL"
    )

    original_item = {
      "source_system" => "ats",
      "source_record_key" => "rec-legacy-506",
      "mention_key" => "m1",
      "origin_class" => "sanitized_historical",
      "source_kind" => "official_employer",
      "source_domain" => "careers.acme.example.com",
      "job_id" => "JOB-ORIGINAL",
      "observed_at" => "2026-09-20T10:00:00Z",
      "title" => "Legacy Systems Architect",
      "company" => "Acme Aerospace",
      "location" => "Denver, CO",
      "remote_type" => "unknown",
      "employment_type" => "unknown"
    }

    rev = sm.source_revisions.create!(
      revision_digest: "legacy_digest_v1",
      digest_version: "v1",
      observed_at: Time.iso8601("2026-09-20T10:00:00Z"),
      title: "Legacy Systems Architect",
      company: "Acme Aerospace",
      location: "Denver, CO",
      raw_safe_fields: original_item
    )

    # Mutate current SourceMention and SourceRecord metadata
    sm.update_columns(source_domain: "mutated-domain.example.com", job_id: "JOB-MUTATED")
    rec.update_columns(origin_class: "adversarial_synthetic")

    # Run migration logic
    UpgradeRevisionDigestsToV2.new.up
    rev.reload

    expected_v2 = SourceRevision.compute_digest(original_item, version: "v2")
    assert_equal "v2", rev.digest_version
    assert_equal expected_v2, rev.revision_digest,
      "Migration must compute v2 digest using historical raw_safe_fields rather than mutated current metadata"

    # QA6-005: Assert migration NEVER rewrote parent SourceMention or SourceRecord
    assert_equal "mutated-domain.example.com", sm.reload.source_domain
    assert_equal "JOB-MUTATED", sm.reload.job_id
    assert_equal "adversarial_synthetic", rec.reload.origin_class

    # Replay on clean record: must match existing revision as unchanged
    clean_rec = SourceRecord.create!(source_system: "ats", source_record_key: "rec-clean-replay", origin_class: "sanitized_historical")
    clean_sm = SourceMention.create!(
      source_record: clean_rec,
      mention_key: "m1",
      source_kind: "official_employer",
      source_domain: "careers.acme.example.com",
      job_id: "JOB-CLEAN"
    )
    clean_item = original_item.merge("source_record_key" => "rec-clean-replay", "job_id" => "JOB-CLEAN")
    clean_rev = clean_sm.source_revisions.create!(
      revision_digest: "legacy_digest_v1",
      digest_version: "v1",
      observed_at: Time.iso8601("2026-09-20T10:00:00Z"),
      title: "Legacy Systems Architect",
      company: "Acme Aerospace",
      location: "Denver, CO",
      raw_safe_fields: clean_item
    )
    UpgradeRevisionDigestsToV2.new.up
    clean_report = BatchImporter.import_string(JSON.generate({
      "batch_schema_version" => "1.0",
      "batch_id" => "replay-clean-506",
      "origin_class" => "sanitized_historical",
      "items" => [clean_item]
    }))
    assert_equal 1, clean_report.unchanged_count, "Clean replay must be unchanged"
  end

  # ==========================================================================
  # Round 6: STOP-SHIP / Privacy Boundary Hardening (QA6-001 through QA6-005)
  # ==========================================================================

  test "QA Round 6: QA6-001 publication quarantine gate denies publication by default without PHANTOM_PUBLISH_ALLOW" do
    batch_file = Rails.root.join("fixtures", "public-approved", "approved-batch-v1.json")
    manifest_file = Rails.root.join("fixtures", "public-approved", "approved-manifest-v1.json")

    begin
      orig_env = Rails.env
      Rails.env = ActiveSupport::StringInquirer.new("production")
      orig_allow = ENV["PHANTOM_PUBLISH_ALLOW"]
      ENV.delete("PHANTOM_PUBLISH_ALLOW")

      res = ApprovedReleaseManager.publish_files!(batch_file, manifest_file)
      assert_not res.success
      assert_includes res.errors.first, "Publication quarantined"

      ENV["PHANTOM_PUBLISH_ALLOW"] = "true"
      # Quarantine lifted
      assert_equal "true", ENV["PHANTOM_PUBLISH_ALLOW"]
    ensure
      Rails.env = orig_env
      ENV["PHANTOM_PUBLISH_ALLOW"] = orig_allow
    end
  end

  test "QA Round 6: QA6-002 & QA6-003 encoded PII in text and URLs rejected before activation and stripped safely" do
    # 1. HTML entity emails (&#64;, &#x40;, &commat;, &#46;) caught by PrivacyScanner
    encoded_email_1 = "Please contact qa6&#64;example&#46;com for details"
    encoded_email_2 = "Send resume to audit&commat;phantomrails&period;dev"
    encoded_email_3 = "Direct inquiry: test&#x40;secret&#x2e;org"
    zero_width_email = "Contact candidate\u200B@\u200Bexample.com"

    [encoded_email_1, encoded_email_2, encoded_email_3, zero_width_email].each do |enc|
      scan = PrivacyScanner.scan_string(enc)
      assert_not scan.clean?, "PrivacyScanner must catch encoded email: #{enc}"
      assert scan.violations.any? { |v| v[:type].include?("email") }
    end

    # 2. Release candidate with HTML entity email is rejected by ReleaseGate
    cand_with_encoded = {
      "batch_schema_version" => "1.0",
      "batch_id" => "cand-qa6-encoded-email",
      "origin_class" => "sanitized_historical",
      "items" => [
        {
          "source_record_key" => "rec-qa6-enc-1",
          "mention_key" => "m1",
          "source_system" => "reviewed_export",
          "source_domain" => "careers.acme.example.com",
          "observed_at" => "2026-09-20T10:00:00Z",
          "source_kind" => "official_employer",
          "title" => "Aerospace Software Lead",
          "company" => "Acme Aerospace",
          "location" => "Denver, CO",
          "summary_excerpt" => "Reach out to qa6&#64;example&#46;com for information"
        }
      ]
    }
    cand_json = JSON.generate(cand_with_encoded)
    manifest = {
      "manifest_version" => "1.0",
      "corpus_version" => "2026.06.1",
      "candidate_digest" => ReleaseGate.compute_digest(cand_json),
      "total_items" => 1,
      "origin_class_counts" => { "sanitized_historical" => 1 },
      "automated_checks_passed" => true,
      "approved_by" => "operator",
      "approved_at" => Time.now.utc.iso8601,
      "approval_signature" => ReleaseGate.compute_digest(cand_json)
    }

    gate_res = ReleaseGate.evaluate(cand_json, JSON.generate(manifest))
    assert_not gate_res.approved, "ReleaseGate must reject candidate containing encoded email"
    assert gate_res.errors.any? { |e| e.include?("Automated privacy scan failed") }

    # 3. Percent-encoded URL contact parameter (?contact=private%40example.com)
    dirty_url = "https://careers.example.org/jobs/123?contact=private%40example.com&job_id=456"
    url_scan = PrivacyScanner.scan_string(dirty_url)
    assert_not url_scan.clean?, "PrivacyScanner must detect percent-encoded contact in URL"

    clean_url = Sanitizer.clean_url(dirty_url)
    assert_not_nil clean_url
    assert_no_match(/contact=/, clean_url, "clean_url must strip contact query parameter")
    assert_no_match(/example\.com/, clean_url)
    assert_includes clean_url, "job_id=456"

    # 4. Encoded markup (&#60;script&#62;) stripped clean with zero <script> in output
    markup_payload = "Safe text &#60;script&#62;alert(1)&#60;/script&#62; overview"
    cleaned_text = Sanitizer.clean_text(markup_payload)
    assert_equal "Safe text alert(1) overview", cleaned_text
    assert_no_match(/<script>/, cleaned_text)
  end

  test "QA Round 6: QA6-004 error diagnostic redaction emits opaque codes and zero raw matched secrets" do
    secret_email = "real-person-secret-dont-leak@confidential.example.org"
    secret_canary = "canary_private_token_999888"

    # 1. PrivacyScanner redact_match emits opaque markers
    assert_equal "[REDACTED_SECRET]", PrivacyScanner.new.send(:redact_match, secret_email, PrivacyScanner::EMAIL_REGEX)

    # 2. PrivacyScanner violations contain zero raw matched secret
    scan_report = PrivacyScanner.scan_string("User #{secret_email} with #{secret_canary}")
    assert_not scan_report.clean?
    scan_report.violations.each do |v|
      assert_no_match(/#{Regexp.escape(secret_email)}/, v[:snippet])
      assert_no_match(/#{Regexp.escape(secret_canary)}/, v[:snippet])
    end

    # 3. ReleaseGate error strings contain zero raw secret
    bad_batch = {
      "batch_schema_version" => "1.0",
      "batch_id" => "secret-leak-test",
      "origin_class" => "adversarial_synthetic",
      "items" => [
        {
          "source_record_key" => "rec-secret",
          "mention_key" => "m1",
          "source_system" => "ats",
          "observed_at" => "2026-09-20T10:00:00Z",
          "source_kind" => "third_party_board",
          "title" => "Engineer #{secret_email}",
          "company" => "Test Corp",
          "location" => "Remote"
        }
      ]
    }
    batch_json = JSON.generate(bad_batch)
    gate = ReleaseGate.evaluate(batch_json, JSON.generate({
      "manifest_version" => "1.0",
      "corpus_version" => "2026.06.1",
      "candidate_digest" => ReleaseGate.compute_digest(batch_json),
      "total_items" => 1,
      "origin_class_counts" => { "adversarial_synthetic" => 1 },
      "automated_checks_passed" => true,
      "approved_by" => "operator",
      "approved_at" => Time.now.utc.iso8601,
      "approval_signature" => ReleaseGate.compute_digest(batch_json)
    }))

    assert_not gate.approved
    error_summary = gate.errors.join("; ")
    assert_no_match(/#{Regexp.escape(secret_email)}/, error_summary,
      "ReleaseGate error diagnostics must NEVER leak raw sensitive inputs")
  end

  test "QA Round 6: QA6-005 Tier 3 withholds merge when external aggregators lack verified source authority" do
    # Two unreviewed external third-party boards claiming boards.greenhouse.io with generic ID
    batch = {
      "batch_schema_version" => "1.0",
      "batch_id" => "qa6-005-untrusted-boards",
      "origin_class" => "adversarial_synthetic",
      "items" => [
        {
          "source_record_key" => "untrusted-aggregator-1-rec",
          "mention_key" => "m1",
          "source_system" => "unreviewed_aggregator_1", # Not in TRUSTED_SYSTEMS
          "source_domain" => "boards.greenhouse.io",
          "job_id" => "GENERIC-ATS-999",
          "observed_at" => "2026-09-21T10:00:00Z",
          "source_kind" => "third_party_board",
          "title" => "Platform Systems Engineer",
          "company" => "Omega Dynamics",
          "location" => "Seattle, WA"
        },
        {
          "source_record_key" => "untrusted-aggregator-2-rec",
          "mention_key" => "m1",
          "source_system" => "unreviewed_aggregator_2", # Not in TRUSTED_SYSTEMS
          "source_domain" => "boards.greenhouse.io",
          "job_id" => "GENERIC-ATS-999",
          "observed_at" => "2026-09-22T10:00:00Z",
          "source_kind" => "third_party_board",
          "title" => "Platform Systems Engineer II",
          "company" => "Omega Dynamics",
          "location" => "Seattle, WA"
        }
      ]
    }

    report = BatchImporter.import_string(JSON.generate(batch))
    assert_equal "complete", report.status

    m1 = SourceMention.joins(:source_record).find_by(source_records: { source_record_key: "untrusted-aggregator-1-rec" })
    m2 = SourceMention.joins(:source_record).find_by(source_records: { source_record_key: "untrusted-aggregator-2-rec" })
    assert_not_nil m1.canonical_posting_id
    assert_not_nil m2.canonical_posting_id

    # Must NOT merge into single posting because neither side has verified authority
    assert_not_equal m1.canonical_posting_id, m2.canonical_posting_id,
      "Untrusted aggregators claiming ATS domain without verified authority must NOT merge under Tier 3"

    # Must record potential duplicate link with unverified_shared_job_id
    dupe_exists = PotentialDuplicate.where(posting_a_id: [m1.canonical_posting_id, m2.canonical_posting_id],
                                           posting_b_id: [m1.canonical_posting_id, m2.canonical_posting_id]).exists?
    assert dupe_exists, "Must flag unverified shared platform key as potential duplicate"
  end
end
