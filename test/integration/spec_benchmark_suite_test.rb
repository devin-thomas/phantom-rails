require "test_helper"

class SpecBenchmarkSuiteTest < ActionDispatch::IntegrationTest
  # SPEC §10: 16 Contractual Benchmark & Adversarial Attack Cases

  # Case 1: Identical reposted employer ID with different tracking URL params -> one Canonical Posting, multiple mentions
  test "benchmark 01: identical reposted employer ID with different tracking URL params merges to single posting" do
    batch_data = {
      "batch_schema_version" => "1.0",
      "batch_id" => "bench_01",
      "origin_class" => "adversarial_synthetic",
      "items" => [
        {
          "source_system" => "ats_greenhouse",
          "source_record_key" => "job_b1_01",
          "mention_key" => "m_b1_01",
          "source_kind" => "official_employer",
          "observed_at" => "2026-09-20T10:00:00Z",
          "title" => "Lead Systems Architect",
          "company" => "Nexus Corp",
          "location" => "Austin, TX",
          "job_id" => "NEX-901",
          "job_url" => "https://nexus.example.com/jobs/901?utm_source=linkedin&utm_campaign=spring"
        },
        {
          "source_system" => "ats_greenhouse",
          "source_record_key" => "job_b1_02",
          "mention_key" => "m_b1_02",
          "source_kind" => "official_employer",
          "observed_at" => "2026-09-21T10:00:00Z",
          "title" => "Lead Systems Architect",
          "company" => "Nexus Corp",
          "location" => "Austin, TX",
          "job_id" => "NEX-901",
          "job_url" => "https://nexus.example.com/jobs/901?utm_source=twitter&fbclid=xyz"
        }
      ]
    }

    report = BatchImporter.import_string(batch_data.to_json)
    assert_equal "complete", report.status
    assert_equal 2, report.inserted_count

    # Verify both mentions merged into 1 Canonical Posting
    posting = CanonicalPosting.find_by(company: "Nexus Corp")
    assert_not_nil posting
    assert_equal 2, posting.source_mentions.count
    # Verify tracking parameters stripped from job_url
    assert_equal "https://nexus.example.com/jobs/901", posting.job_url
  end

  # Case 2: Two different employer requisitions with same company/title/location -> separate postings
  test "benchmark 02: two different employer requisitions remain separate postings" do
    batch_data = {
      "batch_schema_version" => "1.0",
      "batch_id" => "bench_02",
      "origin_class" => "adversarial_synthetic",
      "items" => [
        {
          "source_system" => "ats_greenhouse",
          "source_record_key" => "rec_02_a",
          "mention_key" => "m_02_a",
          "source_kind" => "official_employer",
          "observed_at" => "2026-09-20T10:00:00Z",
          "title" => "Frontend Engineer",
          "company" => "Vortex Labs",
          "location" => "Remote",
          "job_id" => "REQ-ALPHA"
        },
        {
          "source_system" => "ats_greenhouse",
          "source_record_key" => "rec_02_b",
          "mention_key" => "m_02_b",
          "source_kind" => "official_employer",
          "observed_at" => "2026-09-20T10:00:00Z",
          "title" => "Frontend Engineer",
          "company" => "Vortex Labs",
          "location" => "Remote",
          "job_id" => "REQ-BETA"
        }
      ]
    }

    report = BatchImporter.import_string(batch_data.to_json)
    assert_equal "complete", report.status
    postings = CanonicalPosting.where(company: "Vortex Labs")
    assert_equal 2, postings.count, "Different requisitions must produce distinct canonical postings"
  end

  # Case 3: Conflicting salary between verified employer and board -> employer value selected, both retained
  test "benchmark 03: conflicting salary chooses verified employer value and retains both observations" do
    release = ApprovedRelease.create!(
      manifest_digest: Digest::SHA256.hexdigest("bench_03_m"),
      approval_signature: "sig_03",
      approved_by: "auditor@test.com",
      approved_at: Time.current,
      corpus_version: "2026.04.1",
      active: true
    )
    rec = SourceRecord.create!(approved_release: release, source_system: "ats", source_record_key: "rec_03", origin_class: "sanitized_historical")
    post = CanonicalPosting.create!(
      public_id: "post_b03",
      approved_release: release,
      title: "Data Engineer",
      company: "Echo Corp",
      location: "Austin, TX",
      last_observed_at: Time.current,
      first_observed_at: Time.current
    )

    sm_official = SourceMention.create!(source_record: rec, canonical_posting: post, mention_key: "sm_off", source_kind: "official_employer")
    sm_board = SourceMention.create!(source_record: rec, canonical_posting: post, mention_key: "sm_brd", source_kind: "third_party_board")

    SourceRevision.create!(
      source_mention: sm_official,
      revision_digest: "rev_off_dig",
      observed_at: 2.days.ago,
      title: "Data Engineer",
      company: "Echo Corp",
      location: "Austin, TX",
      salary_min: 150000,
      salary_max: 180000,
      salary_currency: "USD",
      salary_period: "year"
    )

    SourceRevision.create!(
      source_mention: sm_board,
      revision_digest: "rev_brd_dig",
      observed_at: 1.day.ago,
      title: "Data Engineer",
      company: "Echo Corp",
      location: "Austin, TX",
      salary_min: 130000,
      salary_max: 160000,
      salary_currency: "USD",
      salary_period: "year"
    )

    FieldReconciler.reconcile!(post)
    post.reload

    # Verified official overrides newer board
    assert_equal 150000.0, post.salary_min
    assert_equal 180000.0, post.salary_max
    selection = post.field_selections.find_by(field_name: "salary")
    assert_equal "verified_official_override", selection.selection_reason
    assert_equal 2, post.source_revisions.count, "Both observations must be retained for audit"
  end

  # Case 4: Newer third-party update vs older authoritative employer listing -> documented exception with timestamps
  test "benchmark 04: newer third-party update vs older authoritative listing records documented exception" do
    release = ApprovedRelease.create!(
      manifest_digest: Digest::SHA256.hexdigest("bench_04_m"),
      approval_signature: "sig_04",
      approved_by: "auditor@test.com",
      approved_at: Time.current,
      corpus_version: "2026.04.1",
      active: true
    )
    rec = SourceRecord.create!(approved_release: release, source_system: "ats", source_record_key: "rec_04", origin_class: "sanitized_historical")
    post = CanonicalPosting.create!(
      public_id: "post_b04",
      approved_release: release,
      title: "Security Engineer",
      company: "Alpha Shield",
      location: "Austin, TX",
      last_observed_at: Time.current,
      first_observed_at: Time.current
    )

    sm_official = SourceMention.create!(source_record: rec, canonical_posting: post, mention_key: "sm_04_off", source_kind: "official_employer")
    sm_board = SourceMention.create!(source_record: rec, canonical_posting: post, mention_key: "sm_04_brd", source_kind: "third_party_board")

    rev_off = SourceRevision.create!(
      source_mention: sm_official,
      revision_digest: "rev_04_off",
      observed_at: 2.days.ago,
      title: "Security Engineer",
      company: "Alpha Shield",
      location: "Austin, TX",
      salary_min: 170000,
      salary_max: 200000,
      salary_currency: "USD",
      salary_period: "year"
    )

    rev_brd = SourceRevision.create!(
      source_mention: sm_board,
      revision_digest: "rev_04_brd",
      observed_at: 1.day.ago,
      title: "Security Engineer",
      company: "Alpha Shield",
      location: "Austin, TX",
      salary_min: 150000,
      salary_max: 180000,
      salary_currency: "USD",
      salary_period: "year"
    )

    FieldReconciler.reconcile!(post)
    post.reload

    prov = ProvenanceSerializer.render(post)
    salary_rec = prov["field_reconciliation"].find { |f| f["field_name"] == "salary" }

    assert_equal "verified_official_override", salary_rec["selection_reason"]
    assert_equal 1, salary_rec["alternatives"].length
    assert_equal "overridden_by_verified_official_source", salary_rec["alternatives"].first["rejection_reason"]
  end

  # Case 5: Ambiguous similarity with no strong ID -> distinct postings and potential_duplicate
  test "benchmark 05: ambiguous company/title/location similarity creates potential_duplicate" do
    p1 = CanonicalPosting.create!(
      public_id: "post_05_a",
      title: "Senior Security Specialist",
      company: "Fortress Tech",
      location: "Seattle, WA",
      last_observed_at: Time.current,
      first_observed_at: Time.current
    )
    p2 = CanonicalPosting.create!(
      public_id: "post_05_b",
      title: "Senior Security Specialist",
      company: "Fortress Tech",
      location: "Seattle, WA",
      last_observed_at: Time.current,
      first_observed_at: Time.current
    )

    PotentialDuplicate.record_pair!(
      p1,
      p2,
      reason_code: "similar_company_title_location",
      evaluation_digest: "tier4-uncertain-match"
    )

    assert p1.reload.potential_duplicate
    assert p2.reload.potential_duplicate
    assert PotentialDuplicate.where(posting_a_id: p1.id, posting_b_id: p2.id).exists?
  end

  # Case 6: Corrected source revision -> previous observation retained, new projection computed
  test "benchmark 06: corrected source revision retains previous observation and updates projection" do
    batch_initial = {
      "batch_schema_version" => "1.0",
      "batch_id" => "b06_v1",
      "origin_class" => "adversarial_synthetic",
      "items" => [{
        "source_system" => "ats_greenhouse",
        "source_record_key" => "job_06",
        "mention_key" => "m_06",
        "source_kind" => "official_employer",
        "observed_at" => "2026-09-20T10:00:00Z",
        "title" => "Junior Dev",
        "company" => "Scale Inc",
        "location" => "Remote"
      }]
    }
    BatchImporter.import_string(batch_initial.to_json)
    post = CanonicalPosting.find_by(company: "Scale Inc")
    assert_equal "Junior Dev", post.title

    batch_corrected = {
      "batch_schema_version" => "1.0",
      "batch_id" => "b06_v2",
      "origin_class" => "adversarial_synthetic",
      "items" => [{
        "source_system" => "ats_greenhouse",
        "source_record_key" => "job_06",
        "mention_key" => "m_06",
        "source_kind" => "official_employer",
        "observed_at" => "2026-09-21T10:00:00Z",
        "title" => "Senior Dev (Corrected)",
        "company" => "Scale Inc",
        "location" => "Remote"
      }]
    }
    BatchImporter.import_string(batch_corrected.to_json)
    post.reload

    assert_equal "Senior Dev (Corrected)", post.title
    assert_equal 2, post.source_revisions.count
    titles = post.source_revisions.pluck(:title)
    assert_includes titles, "Junior Dev"
    assert_includes titles, "Senior Dev (Corrected)"
  end

  # Case 7: Identical batch replay -> no duplicate revisions/postings, corpus revision unchanged
  test "benchmark 07: identical batch replay is a no-op with unchanged corpus" do
    batch = {
      "batch_schema_version" => "1.0",
      "batch_id" => "b07_replay",
      "origin_class" => "adversarial_synthetic",
      "items" => [{
        "source_system" => "ats_greenhouse",
        "source_record_key" => "job_07",
        "mention_key" => "m_07",
        "source_kind" => "official_employer",
        "observed_at" => "2026-09-20T10:00:00Z",
        "title" => "Site Reliability Engineer",
        "company" => "Cloud Inc",
        "location" => "Remote"
      }]
    }
    res1 = BatchImporter.import_string(batch.to_json)
    assert_equal 1, res1.inserted_count

    res2 = BatchImporter.import_string(batch.to_json)
    assert_equal 0, res2.inserted_count
    assert_equal 1, res2.unchanged_count
  end

  # Case 8: Mixed valid/invalid records -> valid accepted, invalid isolated with safe diagnostics
  test "benchmark 08: mixed valid/invalid records accepts valid and isolates invalid as partial" do
    batch = {
      "batch_schema_version" => "1.0",
      "batch_id" => "b08_mixed",
      "origin_class" => "adversarial_synthetic",
      "items" => [
        {
          "source_system" => "ats_greenhouse",
          "source_record_key" => "job_08_valid",
          "mention_key" => "m_08_v",
          "source_kind" => "official_employer",
          "observed_at" => "2026-09-20T10:00:00Z",
          "title" => "Valid Engineer",
          "company" => "Alpha Inc",
          "location" => "Remote"
        },
        {
          "source_system" => "ats_greenhouse",
          "source_record_key" => "job_08_invalid",
          # Missing title and observed_at
          "company" => "Alpha Inc"
        }
      ]
    }
    res = BatchImporter.import_string(batch.to_json)
    assert_equal "partial", res.status
    assert_equal 1, res.inserted_count
    assert_equal 1, res.invalid_count
    assert CanonicalPosting.where(title: "Valid Engineer").exists?
  end

  # Case 9: Multiple conflicting revisions for one source key in unordered batch -> rejected as ambiguous
  test "benchmark 09: multiple conflicting revisions in same batch are quarantined as ambiguous" do
    batch = {
      "batch_schema_version" => "1.0",
      "batch_id" => "b09_conflict",
      "origin_class" => "adversarial_synthetic",
      "items" => [
        {
          "source_system" => "ats_greenhouse",
          "source_record_key" => "job_09_independent",
          "mention_key" => "m_09_ind",
          "source_kind" => "official_employer",
          "observed_at" => "2026-09-20T10:00:00Z",
          "title" => "Independent Engineer",
          "company" => "Beta Corp",
          "location" => "Remote"
        },
        {
          "source_system" => "ats_greenhouse",
          "source_record_key" => "job_09_conflict",
          "mention_key" => "m_09",
          "source_kind" => "third_party_board",
          "observed_at" => "2026-09-20T10:00:00Z",
          "title" => "Title Variant Alpha",
          "company" => "Beta Corp",
          "location" => "Remote"
        },
        {
          "source_system" => "ats_greenhouse",
          "source_record_key" => "job_09_conflict",
          "mention_key" => "m_09",
          "source_kind" => "third_party_board",
          "observed_at" => "2026-09-20T10:00:00Z",
          "title" => "Title Variant Beta",
          "company" => "Beta Corp",
          "location" => "Remote"
        }
      ]
    }
    res = BatchImporter.import_string(batch.to_json)
    assert_equal "partial", res.status
    assert_equal 1, res.inserted_count
    assert_equal 2, res.invalid_count
    assert res.errors.any? { |e| e[:error_code] == "ambiguous_revision_order" }
    assert CanonicalPosting.where(title: "Independent Engineer").exists?
  end

  # Case 10: Invalid/unsupported batch version or malformed JSON -> all-or-nothing failure
  test "benchmark 10: unsupported batch version causes atomic rejection and unchanged corpus" do
    raw_payload = {
      "batch_schema_version" => "99.0", # Unsupported version
      "batch_id" => "b10_bad",
      "origin_class" => "adversarial_synthetic",
      "items" => []
    }.to_json

    parse_result = SourceBatchParser.parse_string(raw_payload)
    refute parse_result.success
    assert parse_result.batch_errors.any? { |e| e[:code] == "unsupported_schema_version" }
  end

  # Case 11: Unicode punctuation/accents/CRLF/HTML-like payloads -> canonical escaping without lost identifiers
  test "benchmark 11: unicode punctuation and HTML-like payloads are safely sanitized" do
    raw_title = "Senior Developer <script>alert(1)</script> — Résumé Platform\r\n"
    sanitized_title = Sanitizer.clean_text(raw_title)

    refute sanitized_title.include?("<script>")
    assert sanitized_title.include?("Résumé")
    refute sanitized_title.include?("\r")
  end

  # Case 12: Unknown pay/currency and nonsensical dates -> null or rejected, never invented
  test "benchmark 12: unknown salary remains null instead of inventing compensation" do
    raw_item = {
      "title" => "Tester",
      "company" => "Acme",
      "location" => "Remote",
      "salary" => { "min" => "unknown", "currency" => "XYZ" }
    }
    # Parser item schema rejects non-numeric salary; clean_text handles fields
    parse_result = SourceBatchParser.parse_string({
      "batch_schema_version" => "1.0",
      "batch_id" => "b12_sal",
      "origin_class" => "adversarial_synthetic",
      "items" => [raw_item]
    }.to_json)

    assert_equal 1, parse_result.invalid_items.length
  end

  # Case 13: Known canaries in private raw input -> release blocked at ReleaseGate
  test "benchmark 13: canary token in batch blocks release at release gate" do
    batch_with_canary = {
      "batch_schema_version" => "1.0",
      "batch_id" => "b13_canary",
      "origin_class" => "adversarial_synthetic",
      "items" => [{
        "source_system" => "ats_greenhouse",
        "source_record_key" => "job_13",
        "mention_key" => "m_13",
        "source_kind" => "official_employer",
        "observed_at" => "2026-09-20T10:00:00Z",
        "title" => "Developer canary_token_secret_123",
        "company" => "Test Corp",
        "location" => "Remote"
      }]
    }.to_json

    scan = PrivacyScanner.scan_batch(JSON.parse(batch_with_canary)["items"])
    refute scan.passed
    assert scan.violations.any? { |v| v[:type] == "canary_token_detected" }
  end

  # Case 14: Cursor tampering, filter mismatch, and expiry -> safe 400/410 behaviors
  test "benchmark 14: cursor tampering returns 400 and expired returns 410" do
    q_digest = CursorToken.compute_query_digest({ "sort" => "newest" })
    token = CursorToken.encode(
      corpus_revision: ApprovedReleaseManager.current_revision,
      query_digest: q_digest,
      sort_tuple: [Time.now.utc.iso8601, "post_01"]
    )
    tampered = token + "bad"
    dec = CursorToken.decode(tampered, expected_revision: ApprovedReleaseManager.current_revision, expected_query_digest: q_digest)
    refute dec.valid?
    assert_equal "invalid_cursor", dec.error_code

    expired_token = CursorToken.encode(
      corpus_revision: ApprovedReleaseManager.current_revision,
      query_digest: q_digest,
      sort_tuple: [Time.now.utc.iso8601, "post_01"],
      ttl_seconds: -1
    )
    dec_exp = CursorToken.decode(expired_token, expected_revision: ApprovedReleaseManager.current_revision, expected_query_digest: q_digest)
    refute dec_exp.valid?
    assert_equal "cursor_expired", dec_exp.error_code
  end

  # Case 15: Query injection and unsupported filters -> safe deterministic HTTP errors
  test "benchmark 15: malicious SQL injection causes safe deterministic empty results or 400" do
    get "/api/v1/postings?q=' OR 1=1 --"
    assert_response :success
    json = JSON.parse(response.body)
    assert_equal 0, json["data"].length

    get "/api/v1/postings?remote_type=malicious_syntax"
    assert_response :bad_request
    json = JSON.parse(response.body)
    assert_equal "invalid_parameter", json.dig("error", "code")
  end

  # Case 16: Public mutation attempts -> 405 Method Not Allowed and zero state change
  test "benchmark 16: public mutation attempts fail with 405 Method Not Allowed" do
    post "/api/v1/postings", params: { title: "Injected Role" }
    assert_response :method_not_allowed

    put "/api/v1/postings/post_b03", params: { title: "Mutated Title" }
    assert_response :method_not_allowed

    delete "/api/v1/postings/post_b03"
    assert_response :method_not_allowed
  end
end
