require "test_helper"

class BatchImporterTest < ActiveSupport::TestCase
  test "imports clean valid batch with complete status" do
    file_path = Rails.root.join("fixtures", "adversarial", "valid_batch_v1.json")
    report = BatchImporter.import_file(file_path)

    assert_equal "complete", report.status
    assert_equal 5, report.total_input
    assert_equal 5, report.inserted_count
    assert_equal 0, report.updated_count
    assert_equal 0, report.unchanged_count
    assert_equal 0, report.invalid_count
    assert_empty report.errors

    # Total accounting check
    assert_equal report.total_input, (report.inserted_count + report.updated_count + report.unchanged_count + report.invalid_count)

    run = ImportRun.find(report.import_run_id)
    assert_equal "complete", run.status
    assert_equal 5, run.inserted_count
  end

  test "imports mixed batch accepting valid items and isolating errors with partial status" do
    file_path = Rails.root.join("fixtures", "adversarial", "mixed_batch_v1.json")
    report = BatchImporter.import_file(file_path)

    assert_equal "partial", report.status
    assert_equal 5, report.total_input
    assert_equal 2, report.inserted_count
    assert_equal 3, report.invalid_count

    # Verify invalid records are not stored
    assert_not SourceRecord.where(source_record_key: "rec-invalid-missing-company").exists?
    assert_not SourceRecord.where(source_record_key: "rec-invalid-timezone").exists?
    assert_not SourceRecord.where(source_record_key: "rec-invalid-unknown-keys").exists?

    # Verify valid records are stored
    assert SourceRecord.where(source_record_key: "rec-valid-001").exists?
    assert SourceRecord.where(source_record_key: "rec-valid-002").exists?

    # Accounting check
    assert_equal report.total_input, (report.inserted_count + report.updated_count + report.unchanged_count + report.invalid_count)
  end

  test "aborts unsupported batch version with failed status and 0 imported rows" do
    file_path = Rails.root.join("fixtures", "adversarial", "invalid_envelope_v1.json")
    report = BatchImporter.import_file(file_path)

    assert_equal "failed", report.status
    assert_equal 0, report.inserted_count
    assert_equal 0, report.updated_count
    assert_equal 0, report.unchanged_count
    assert_not_empty report.errors

    assert_not SourceRecord.where(source_record_key: "rec-001").exists?
  end

  test "quarantines ambiguous unordered conflicting revisions for same mention key" do
    batch = {
      "batch_schema_version" => "1.0",
      "batch_id" => "collision-batch",
      "origin_class" => "adversarial_synthetic",
      "items" => [
        {
          "source_record_key" => "collision-rec",
          "mention_key" => "m1",
          "source_system" => "board_x",
          "observed_at" => "2026-09-20T10:00:00Z",
          "source_kind" => "third_party_board",
          "title" => "Title Revision A",
          "company" => "Collision Corp",
          "location" => "Remote"
        },
        {
          "source_record_key" => "collision-rec",
          "mention_key" => "m1",
          "source_system" => "board_x",
          "observed_at" => "2026-09-20T11:00:00Z",
          "source_kind" => "third_party_board",
          "title" => "Title Revision B with Disagreement",
          "company" => "Collision Corp",
          "location" => "Remote"
        },
        {
          "source_record_key" => "clean-rec",
          "mention_key" => "m2",
          "source_system" => "board_x",
          "observed_at" => "2026-09-20T12:00:00Z",
          "source_kind" => "third_party_board",
          "title" => "Clean Unrelated Job",
          "company" => "Clean Corp",
          "location" => "Austin, TX"
        }
      ]
    }

    report = BatchImporter.import_string(JSON.generate(batch))

    assert_equal "partial", report.status
    assert_equal 1, report.inserted_count
    assert_equal 2, report.invalid_count

    err_codes = report.errors.map { |e| e[:error_code] }
    assert_includes err_codes, "ambiguous_revision_order"

    assert SourceRecord.where(source_record_key: "clean-rec").exists?
    assert_not SourceRecord.where(source_record_key: "collision-rec").exists?
  end
end
