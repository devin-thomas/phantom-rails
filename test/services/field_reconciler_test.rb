require "test_helper"

class FieldReconcilerTest < ActiveSupport::TestCase
  test "verified official employer listing overrides newer conflicting third party board observation" do
    batch = {
      "batch_schema_version" => "1.0",
      "batch_id" => "override-test-batch",
      "origin_class" => "adversarial_synthetic",
      "items" => [
        {
          "source_record_key" => "rec-official-acme",
          "mention_key" => "m1",
          "source_system" => "ats",
          "observed_at" => "2026-09-20T10:00:00Z",
          "source_kind" => "official_employer",
          "job_id" => "REQ-101",
          "title" => "Principal Systems Architect",
          "company" => "Acme Aerospace",
          "location" => "Denver, CO",
          "salary" => { "min": 175000, "max": 215000, "currency": "USD", "period": "year" }
        },
        {
          "source_record_key" => "rec-board-acme",
          "mention_key" => "m1",
          "source_system" => "aggregator",
          "observed_at" => "2026-09-23T14:00:00Z", # newer
          "source_kind" => "third_party_board",
          "job_id" => "REQ-101",
          "title" => "Principal Systems Architect",
          "company" => "Acme Aerospace",
          "location" => "Denver, CO",
          "salary" => { "min": 160000, "max": 195000, "currency": "USD", "period": "year" } # conflicting
        }
      ]
    }

    report = BatchImporter.import_string(JSON.generate(batch))
    assert_equal "complete", report.status

    m1 = SourceMention.joins(:source_record).find_by(source_records: { source_record_key: "rec-official-acme" })
    posting = m1.canonical_posting

    # Reconciled salary should be the official employer value
    assert_equal 175000, posting.salary_min
    assert_equal 215000, posting.salary_max

    salary_selection = posting.field_selections.find_by(field_name: "salary")
    assert_equal "verified_official_override", salary_selection.selection_reason
    assert_equal m1.source_revisions.first.id, salary_selection.source_revision_id
  end

  test "baseline newest credible observation wins between equal authority sources" do
    batch = {
      "batch_schema_version" => "1.0",
      "batch_id" => "recency-test-batch",
      "origin_class" => "adversarial_synthetic",
      "items" => [
        {
          "source_record_key" => "rec-board-old",
          "mention_key" => "m1",
          "source_system" => "board_1",
          "observed_at" => "2026-09-20T10:00:00Z",
          "source_kind" => "third_party_board",
          "job_id" => "ID-55",
          "title" => "Software Engineer I",
          "company" => "Recency Corp",
          "location" => "Austin, TX",
          "job_url" => "https://recency.example.com/job/55"
        },
        {
          "source_record_key" => "rec-board-new",
          "mention_key" => "m1",
          "source_system" => "board_2",
          "observed_at" => "2026-09-24T10:00:00Z",
          "source_kind" => "third_party_board",
          "job_id" => "ID-55",
          "title" => "Software Engineer II (Updated)",
          "company" => "Recency Corp",
          "location" => "Austin, TX",
          "job_url" => "https://recency.example.com/job/55"
        }
      ]
    }

    report = BatchImporter.import_string(JSON.generate(batch))
    assert_equal "complete", report.status

    m_new = SourceMention.joins(:source_record).find_by(source_records: { source_record_key: "rec-board-new" })
    posting = m_new.canonical_posting

    assert_equal "Software Engineer II (Updated)", posting.title
    title_selection = posting.field_selections.find_by(field_name: "title")
    assert_equal "newest_credible", title_selection.selection_reason
  end

  test "tie breaking is deterministic regardless of database order" do
    p = CanonicalPosting.create!(
      title: "Initial",
      company: "Tie Corp",
      location: "Denver, CO",
      last_observed_at: Time.now.utc,
      first_observed_at: Time.now.utc
    )

    m = SourceMention.create!(
      source_record: SourceRecord.create!(source_system: "s", source_record_key: "k", origin_class: "adversarial_synthetic"),
      mention_key: "m1",
      source_kind: "official_employer",
      canonical_posting: p
    )

    t = Time.parse("2026-09-20 12:00:00 UTC")
    rev1 = m.source_revisions.create!(
      revision_digest: "aaa_digest",
      observed_at: t,
      title: "Title A",
      company: "Tie Corp",
      location: "Denver, CO"
    )
    rev2 = m.source_revisions.create!(
      revision_digest: "bbb_digest",
      observed_at: t,
      title: "Title B",
      company: "Tie Corp",
      location: "Denver, CO"
    )

    res = FieldReconciler.reconcile!(p)
    assert_equal "Title A", res.chosen_fields["title"] # 'aaa_digest' comes before 'bbb_digest'
  end
end
