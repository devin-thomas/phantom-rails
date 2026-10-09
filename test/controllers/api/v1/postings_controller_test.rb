require "test_helper"

class Api::V1::PostingsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @release = ApprovedRelease.create!(
      manifest_digest: Digest::SHA256.hexdigest("mock_manifest_data"),
      approval_signature: "sig_test_123456",
      approved_by: "auditor@phantomrails.dev",
      approved_at: Time.current,
      corpus_version: "2026.04.1",
      total_items: 1,
      active: true
    )

    @record = SourceRecord.create!(
      approved_release: @release,
      source_system: "ats_greenhouse",
      source_record_key: "rec_100",
      origin_class: "sanitized_historical"
    )

    @unapproved_record = SourceRecord.create!(
      approved_release: nil,
      source_system: "ats_greenhouse",
      source_record_key: "rec_unapproved_999",
      origin_class: "adversarial_synthetic"
    )

    @approved_posting = CanonicalPosting.create!(
      public_id: "post_approved_001",
      approved_release: @release,
      title: "Senior Rails Engineer",
      company: "Acme Corp",
      location: "San Francisco, CA",
      remote_type: "hybrid",
      employment_type: "full_time",
      salary_min: 140000,
      salary_max: 180000,
      salary_currency: "USD",
      salary_period: "year",
      summary_excerpt: "Build robust distributed Rails systems.",
      job_url: "https://example.com/jobs/post-001",
      first_observed_at: 2.days.ago,
      last_observed_at: 1.day.ago
    )

    @unapproved_posting = CanonicalPosting.create!(
      public_id: "post_unapproved_002",
      approved_release: nil,
      title: "Secret Unapproved Role",
      company: "Stealth Corp",
      location: "Remote",
      first_observed_at: 1.day.ago,
      last_observed_at: 1.day.ago
    )

    @mention = SourceMention.create!(
      source_record: @record,
      canonical_posting: @approved_posting,
      mention_key: "rec_100:job_100",
      source_kind: "official_employer",
      source_domain: "example.com",
      job_id: "job_100"
    )

    @unapproved_mention = SourceMention.create!(
      source_record: @unapproved_record,
      canonical_posting: @unapproved_posting,
      mention_key: "rec_999:job_999",
      source_kind: "third_party_board",
      source_domain: "board.com",
      job_id: "job_999"
    )
  end

  test "GET /api/v1/postings returns only active approved postings and valid envelope" do
    get "/api/v1/postings"

    assert_response :success
    json = JSON.parse(response.body)

    assert json.key?("data")
    assert json.key?("page")
    assert json.key?("meta")

    ids = json["data"].map { |p| p["id"] }
    assert_includes ids, "post_approved_001"
    refute_includes ids, "post_unapproved_002", "Unapproved staging postings must never leak in search results"

    item = json["data"].find { |p| p["id"] == "post_approved_001" }
    assert_equal "Senior Rails Engineer", item["title"]
    assert_equal "Acme Corp", item["company"]
    assert_equal "sanitized_historical", item["origin_class"]
    assert_equal "/api/v1/postings/post_approved_001/provenance", item["provenance_url"]

    # Ensure internal DB integer ID and search_vector are not leaked
    refute item.key?("search_vector")
    refute item.key?("raw_json")
  end

  test "GET /api/v1/postings honors valid limit parameter" do
    get "/api/v1/postings?limit=1"

    assert_response :success
    json = JSON.parse(response.body)
    assert_equal 1, json["page"]["limit"]
    assert_equal 1, json["data"].length
  end

  test "GET /api/v1/postings rejects invalid limit parameters with 400" do
    [-1, 0, 51, 999, "invalid"].each do |bad_limit|
      get "/api/v1/postings?limit=#{bad_limit}"
      assert_response :bad_request
      json = JSON.parse(response.body)
      assert_equal "invalid_parameter", json.dig("error", "code")
      assert_equal "limit must be from 1 to 50", json.dig("error", "message")
      assert json.dig("error", "request_id").present?
    end
  end

  test "GET /api/v1/postings/:id returns detail for approved posting" do
    get "/api/v1/postings/post_approved_001"

    assert_response :success
    json = JSON.parse(response.body)
    assert json.key?("data")
    assert_equal "post_approved_001", json.dig("data", "id")
    assert_equal "Senior Rails Engineer", json.dig("data", "title")
    assert_equal 140000.0, json.dig("data", "salary", "min")
  end

  test "GET /api/v1/postings/:id returns 404 for missing or unapproved posting" do
    get "/api/v1/postings/nonexistent_id"
    assert_response :not_found
    json = JSON.parse(response.body)
    assert_equal "not_found", json.dig("error", "code")
    assert json.dig("error", "request_id").present?

    # Attempting to fetch unapproved posting returns 404
    get "/api/v1/postings/post_unapproved_002"
    assert_response :not_found
    json = JSON.parse(response.body)
    assert_equal "not_found", json.dig("error", "code")
  end

  test "GET /api/v1/postings/:id/provenance returns provenance details" do
    get "/api/v1/postings/post_approved_001/provenance"

    assert_response :success
    json = JSON.parse(response.body)
    assert json.key?("data")
    assert_equal "post_approved_001", json.dig("data", "id")
    assert json.dig("data", "source_mentions").is_a?(Array)
    assert_equal "official_employer", json.dig("data", "source_mentions", 0, "source_kind")
  end

  test "GET /api/v1/meta returns corpus revision and data origin counts" do
    get "/api/v1/meta"

    assert_response :success
    json = JSON.parse(response.body)
    assert json["corpus_revision"].present?
    assert_equal "2026.04.1", json["corpus_version"]
    assert_equal 1, json["active_approved_postings"]
    assert json["origin_class_counts"].key?("sanitized_historical")
    assert json["disclaimer"].include?("Phantom Rails is an inspectable portfolio search API")
  end

  test "Public mutation methods fail with 405 Method Not Allowed" do
    post "/api/v1/postings", params: { title: "Hacked Job" }
    assert_response :method_not_allowed
    json = JSON.parse(response.body)
    assert_equal "method_not_allowed", json.dig("error", "code")

    put "/api/v1/postings/post_approved_001", params: { title: "Modified Title" }
    assert_response :method_not_allowed

    delete "/api/v1/postings/post_approved_001"
    assert_response :method_not_allowed

    # Verify no state changes occurred
    assert_equal "Senior Rails Engineer", @approved_posting.reload.title
  end

  test "All responses pass PrivacyScanner check" do
    get "/api/v1/postings"
    report = PrivacyScanner.scan_string(response.body)
    assert report.clean?, "Public response must not contain PII or secret leaks: #{report.violations.inspect}"

    get "/api/v1/postings/post_approved_001"
    report = PrivacyScanner.scan_string(response.body)
    assert report.clean?, "Public detail response must be clean: #{report.violations.inspect}"

    get "/api/v1/meta"
    report = PrivacyScanner.scan_string(response.body)
    assert report.clean?, "Public meta response must be clean: #{report.violations.inspect}"
  end

  test "GET /api/v1/postings with q and compound filters returns filtered results" do
    get "/api/v1/postings?q=Rails&company=Acme%20Corp&min_salary_usd=100000"
    assert_response :success
    json = JSON.parse(response.body)
    assert_equal 1, json["data"].length
    assert_equal "post_approved_001", json["data"].first["id"]
    assert_equal "relevance", json["meta"]["sort"]
    assert_equal "Rails", json["meta"]["query"]
    assert json["data"].first["relevance_score"] > 0
  end

  test "GET /api/v1/postings with invalid filters returns 400 invalid_parameter" do
    get "/api/v1/postings?remote_type=invalid_remote"
    assert_response :bad_request
    json = JSON.parse(response.body)
    assert_equal "invalid_parameter", json.dig("error", "code")

    get "/api/v1/postings?min_salary_usd=not_a_number"
    assert_response :bad_request
    json = JSON.parse(response.body)
    assert_equal "invalid_parameter", json.dig("error", "code")
  end
end
