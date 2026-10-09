require "test_helper"

class Api::V1::CursorPaginationTest < ActionDispatch::IntegrationTest
  setup do
    @release = ApprovedRelease.create!(
      manifest_digest: Digest::SHA256.hexdigest("mock_manifest_pagination"),
      approval_signature: "sig_pagination_test",
      approved_by: "auditor@phantomrails.dev",
      approved_at: Time.current,
      corpus_version: "2026.04.1",
      total_items: 5,
      active: true
    )

    @record = SourceRecord.create!(
      approved_release: @release,
      source_system: "ats_greenhouse",
      source_record_key: "rec_pages_01",
      origin_class: "sanitized_historical"
    )

    @created_postings = []
    5.times do |i|
      post = CanonicalPosting.create!(
        public_id: "post_page_#{format('%03d', i + 1)}",
        approved_release: @release,
        title: "Engineer #{i + 1}",
        company: "Alpha Corp",
        location: "Denver, CO",
        remote_type: "hybrid",
        employment_type: "full_time",
        last_observed_at: (10 - i).days.ago,
        first_observed_at: 12.days.ago
      )
      SourceMention.create!(
        source_record: @record,
        canonical_posting: post,
        mention_key: "rec_pages_01:m_#{i}",
        source_kind: "official_employer"
      )
      @created_postings << post
    end
  end

  test "paginates across multiple pages returning every ID exactly once" do
    # Fetch page 1 (limit 2)
    get "/api/v1/postings?sort=newest&limit=2"
    assert_response :success
    page1 = JSON.parse(response.body)
    assert_equal 2, page1["data"].length
    cursor1 = page1.dig("page", "next_cursor")
    assert cursor1.present?, "Next cursor must be present on page 1"

    # Fetch page 2 (limit 2)
    get "/api/v1/postings?sort=newest&limit=2&cursor=#{cursor1}"
    assert_response :success
    page2 = JSON.parse(response.body)
    assert_equal 2, page2["data"].length
    cursor2 = page2.dig("page", "next_cursor")
    assert cursor2.present?, "Next cursor must be present on page 2"

    # Fetch page 3 (limit 2) - should only have 1 item left
    get "/api/v1/postings?sort=newest&limit=2&cursor=#{cursor2}"
    assert_response :success
    page3 = JSON.parse(response.body)
    assert_equal 1, page3["data"].length
    cursor3 = page3.dig("page", "next_cursor")
    assert_nil cursor3, "Final page must have next_cursor: null"

    all_ids = (page1["data"] + page2["data"] + page3["data"]).map { |p| p["id"] }
    assert_equal 5, all_ids.length
    assert_equal all_ids.uniq.length, all_ids.length, "Every ID must be returned exactly once without duplicates or gaps"
  end

  test "returns 400 cursor_query_mismatch when query parameters change" do
    get "/api/v1/postings?sort=newest&limit=2"
    cursor = JSON.parse(response.body).dig("page", "next_cursor")

    # Reuse cursor with a different company filter
    get "/api/v1/postings?sort=newest&limit=2&company=Beta&cursor=#{cursor}"
    assert_response :bad_request
    json = JSON.parse(response.body)
    assert_equal "cursor_query_mismatch", json.dig("error", "code")
  end

  test "returns 400 invalid_cursor when cursor is tampered with" do
    get "/api/v1/postings?sort=newest&limit=2"
    cursor = JSON.parse(response.body).dig("page", "next_cursor")
    tampered_cursor = cursor[0...-5] + "XXXXX"

    get "/api/v1/postings?sort=newest&limit=2&cursor=#{tampered_cursor}"
    assert_response :bad_request
    json = JSON.parse(response.body)
    assert_equal "invalid_cursor", json.dig("error", "code")
  end

  test "returns 410 cursor_expired when cursor TTL has elapsed" do
    # Fabricate an expired token
    query_digest = CursorToken.compute_query_digest({ "sort" => "newest" })
    expired_token = CursorToken.encode(
      corpus_revision: ApprovedReleaseManager.current_revision,
      query_digest: query_digest,
      sort_tuple: [Time.now.utc.iso8601, "post_001"],
      ttl_seconds: -100
    )

    get "/api/v1/postings?sort=newest&cursor=#{expired_token}"
    assert_response :gone
    json = JSON.parse(response.body)
    assert_equal "cursor_expired", json.dig("error", "code")
  end

  test "returns 409 stale_cursor when corpus revision has advanced" do
    get "/api/v1/postings?sort=newest&limit=2"
    cursor = JSON.parse(response.body).dig("page", "next_cursor")

    # Advance the corpus revision by activating a new release
    @release.update!(active: false)
    ApprovedRelease.create!(
      manifest_digest: Digest::SHA256.hexdigest("mock_manifest_pagination_v2"),
      approval_signature: "sig_pagination_v2",
      approved_by: "auditor@phantomrails.dev",
      approved_at: Time.current,
      corpus_version: "2026.04.2",
      total_items: 5,
      active: true
    )

    get "/api/v1/postings?sort=newest&limit=2&cursor=#{cursor}"
    assert_response :conflict
    json = JSON.parse(response.body)
    assert_equal "stale_cursor", json.dig("error", "code")
  end
end
