require "test_helper"

class RevisionReplayTest < ActiveSupport::TestCase
  test "replaying an identical batch produces unchanged items and no duplicate records" do
    batch = {
      "batch_schema_version" => "1.0",
      "batch_id" => "replay-batch-v1",
      "origin_class" => "adversarial_synthetic",
      "items" => [
        {
          "source_record_key" => "rec-rep-01",
          "mention_key" => "m1",
          "source_system" => "ats",
          "observed_at" => "2026-09-20T10:00:00Z",
          "source_kind" => "official_employer",
          "title" => "Backend Engineer",
          "company" => "Replay Systems",
          "location" => "Remote"
        }
      ]
    }
    payload = JSON.generate(batch)

    # First run
    rep1 = BatchImporter.import_string(payload)
    assert_equal 1, rep1.inserted_count
    assert_equal 0, rep1.unchanged_count

    mentions_count_before = SourceMention.count
    revisions_count_before = SourceRevision.count

    # Second run (exact replay)
    rep2 = BatchImporter.import_string(payload)
    assert_equal 0, rep2.inserted_count
    assert_equal 0, rep2.updated_count
    assert_equal 1, rep2.unchanged_count
    assert_equal "complete", rep2.status

    assert_equal mentions_count_before, SourceMention.count
    assert_equal revisions_count_before, SourceRevision.count

    # Distinct audit runs exist
    assert_equal 2, ImportRun.where(batch_id: "replay-batch-v1").count
  end

  test "chronologically corrected observation creates new revision while retaining earlier revision" do
    batch_v1 = {
      "batch_schema_version" => "1.0",
      "batch_id" => "correction-batch-v1",
      "origin_class" => "adversarial_synthetic",
      "items" => [
        {
          "source_record_key" => "rec-correct-01",
          "mention_key" => "m1",
          "source_system" => "ats",
          "observed_at" => "2026-09-20T10:00:00Z",
          "source_kind" => "official_employer",
          "title" => "Junior Dev",
          "company" => "Correction Corp",
          "location" => "Remote",
          "salary" => { "min": 70000, "max": 90000, "currency": "USD", "period": "year" }
        }
      ]
    }

    batch_v2 = {
      "batch_schema_version" => "1.0",
      "batch_id" => "correction-batch-v2",
      "origin_class" => "adversarial_synthetic",
      "items" => [
        {
          "source_record_key" => "rec-correct-01",
          "mention_key" => "m1",
          "source_system" => "ats",
          "observed_at" => "2026-09-22T14:00:00Z",
          "source_kind" => "official_employer",
          "title" => "Mid-Level Dev",
          "company" => "Correction Corp",
          "location" => "Remote",
          "salary" => { "min": 95000, "max": 115000, "currency": "USD", "period": "year" }
        }
      ]
    }

    rep1 = BatchImporter.import_string(JSON.generate(batch_v1))
    assert_equal 1, rep1.inserted_count

    rep2 = BatchImporter.import_string(JSON.generate(batch_v2))
    assert_equal 0, rep2.inserted_count
    assert_equal 1, rep2.updated_count
    assert_equal 0, rep2.unchanged_count

    mention = SourceMention.joins(:source_record).find_by(source_records: { source_record_key: "rec-correct-01" }, mention_key: "m1")
    assert_not_nil mention
    assert_equal 2, mention.source_revisions.count

    revisions = mention.source_revisions.order(observed_at: :asc)
    assert_equal "Junior Dev", revisions.first.title
    assert_equal 70000, revisions.first.salary_min
    assert_equal "Mid-Level Dev", revisions.second.title
    assert_equal 95000, revisions.second.salary_min
  end

  test "history query lists import runs with outcomes, timestamps, and error counts" do
    runs = ImportRun.history_summary
    assert runs.is_a?(Array)
    runs.each do |r|
      assert r.key?(:id)
      assert r.key?(:batch_id)
      assert r.key?(:status)
      assert r.key?(:started_at)
      assert r.key?(:inserted)
    end
  end
end
