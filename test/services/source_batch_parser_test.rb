require "test_helper"

class SourceBatchParserTest < ActiveSupport::TestCase
  test "parses valid adversarial batch v1 JSON completely" do
    file_path = Rails.root.join("fixtures", "adversarial", "valid_batch_v1.json")
    result = SourceBatchParser.parse_file(file_path)

    assert result.success
    assert_equal "adversarial-suite-batch-001", result.batch_id
    assert_equal "adversarial_synthetic", result.origin_class
    assert_equal 5, result.valid_items.size
    assert_empty result.invalid_items
    assert_empty result.batch_errors

    first = result.valid_items.first
    assert_equal "rec-acme-101", first["source_record_key"]
    assert_equal "Denver, CO", first["location"]
    assert_equal "2026-09-20T10:00:00Z", first["observed_at"]
    assert_equal "2026-09-18T08:00:00Z", first["posted_at"]
    assert_not_equal first["observed_at"], Time.now.utc.iso8601
  end

  test "parses mixed adversarial batch isolating invalid items with diagnostics" do
    file_path = Rails.root.join("fixtures", "adversarial", "mixed_batch_v1.json")
    result = SourceBatchParser.parse_file(file_path)

    assert result.success
    assert_equal 2, result.valid_items.size
    assert_equal 3, result.invalid_items.size

    # Check that invalid items have indexed error codes
    item_errs = result.invalid_items
    assert_equal 1, item_errs[0][:index]
    assert_includes item_errs[0][:errors].map { |e| e[:code] }, "schema_violation"

    assert_equal 2, item_errs[1][:index]
    codes = item_errs[1][:errors].map { |e| e[:code] }
    assert codes.any? { |c| c.start_with?("invalid_timestamp") }, "Expected timestamp error code, got: #{codes.inspect}"

    assert_equal 3, item_errs[2][:index]
    assert_includes item_errs[2][:errors].map { |e| e[:code] }, "schema_violation"
  end

  test "fails atomically on unsupported schema version" do
    file_path = Rails.root.join("fixtures", "adversarial", "invalid_envelope_v1.json")
    result = SourceBatchParser.parse_file(file_path)

    assert_not result.success
    assert_empty result.valid_items
    assert_equal 1, result.batch_errors.size
    assert_equal "unsupported_schema_version", result.batch_errors.first[:code]
  end

  test "parses JSONL format correctly" do
    file_path = Rails.root.join("fixtures", "adversarial", "batch_v1.jsonl")
    result = SourceBatchParser.parse_file(file_path)

    assert result.success
    assert_equal "jsonl-adversarial-005", result.batch_id
    assert_equal 2, result.valid_items.size
    assert_empty result.invalid_items
  end

  test "rejects empty or malformed JSON payloads" do
    result_empty = SourceBatchParser.parse_string("")
    assert_not result_empty.success
    assert_equal "empty_payload", result_empty.batch_errors.first[:code]

    result_malformed = SourceBatchParser.parse_string("{not valid json}")
    assert_not result_malformed.success
    assert_equal "malformed_json", result_malformed.batch_errors.first[:code]
  end

  test "demonstrates external observed timestamp is preserved and differs from import time" do
    raw = {
      "batch_schema_version" => "1.0",
      "batch_id" => "timestamp-test",
      "origin_class" => "adversarial_synthetic",
      "items" => [
        {
          "source_record_key" => "key-1",
          "mention_key" => "m-1",
          "source_system" => "clock_test",
          "observed_at" => "2024-01-15T12:00:00Z",
          "source_kind" => "official_employer",
          "title" => "Observed Clock Engineer",
          "company" => "Time Corp",
          "location" => "Remote"
        }
      ]
    }

    result = SourceBatchParser.parse_string(JSON.generate(raw))
    assert result.success
    item = result.valid_items.first

    observed_time = Time.iso8601(item["observed_at"])
    now_time = Time.now.utc

    assert_equal 2024, observed_time.year
    assert_not_equal observed_time.to_i, now_time.to_i
  end
end
