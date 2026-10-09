require "test_helper"

class CursorTokenTest < ActiveSupport::TestCase
  setup do
    @revision = "rev_test_abcdef123456"
    @query_params = {
      "company" => "acme",
      "q" => "rails engineer",
      "sort" => "relevance"
    }
    @query_digest = CursorToken.compute_query_digest(@query_params)
    @tuple = [16, "post_test_001"]
  end

  test "encodes and decodes valid cursor token" do
    token = CursorToken.encode(
      corpus_revision: @revision,
      query_digest: @query_digest,
      sort_tuple: @tuple,
      ttl_seconds: 60
    )

    assert token.is_a?(String)
    assert token.include?(".")

    result = CursorToken.decode(
      token,
      expected_revision: @revision,
      expected_query_digest: @query_digest
    )

    assert result.valid?
    assert_equal 1, result.payload["v"]
    assert_equal @revision, result.payload["rev"]
    assert_equal @query_digest, result.payload["qd"]
    assert_equal @tuple, result.payload["tuple"]
  end

  test "detects tampered cursor token" do
    token = CursorToken.encode(
      corpus_revision: @revision,
      query_digest: @query_digest,
      sort_tuple: @tuple
    )

    # Corrupt the payload part
    payload_b64, sig_b64 = token.split(".")
    tampered_token = "eyJoYWNrZWQiOnRydWV9.#{sig_b64}"

    result = CursorToken.decode(
      tampered_token,
      expected_revision: @revision,
      expected_query_digest: @query_digest
    )

    refute result.valid?
    assert_equal "invalid_cursor", result.error_code
  end

  test "rejects cursor when query parameters differ" do
    token = CursorToken.encode(
      corpus_revision: @revision,
      query_digest: @query_digest,
      sort_tuple: @tuple
    )

    different_digest = CursorToken.compute_query_digest({ "q" => "other search" })

    result = CursorToken.decode(
      token,
      expected_revision: @revision,
      expected_query_digest: different_digest
    )

    refute result.valid?
    assert_equal "cursor_query_mismatch", result.error_code
  end

  test "rejects expired cursor token" do
    # Encode with negative TTL
    token = CursorToken.encode(
      corpus_revision: @revision,
      query_digest: @query_digest,
      sort_tuple: @tuple,
      ttl_seconds: -10
    )

    result = CursorToken.decode(
      token,
      expected_revision: @revision,
      expected_query_digest: @query_digest
    )

    refute result.valid?
    assert_equal "cursor_expired", result.error_code
  end

  test "rejects cursor when corpus revision changes" do
    token = CursorToken.encode(
      corpus_revision: @revision,
      query_digest: @query_digest,
      sort_tuple: @tuple
    )

    new_revision = "rev_new_9876543210"

    result = CursorToken.decode(
      token,
      expected_revision: new_revision,
      expected_query_digest: @query_digest
    )

    refute result.valid?
    assert_equal "stale_cursor", result.error_code
  end
end
