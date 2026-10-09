require "test_helper"

class IdentityResolverTest < ActiveSupport::TestCase
  test "tier 1 merges mentions sharing verified company and requisition ID" do
    batch = {
      "batch_schema_version" => "1.0",
      "batch_id" => "tier1-test-batch",
      "origin_class" => "adversarial_synthetic",
      "items" => [
        {
          "source_record_key" => "rec-employer-01",
          "mention_key" => "m1",
          "source_system" => "ats",
          "observed_at" => "2026-09-20T10:00:00Z",
          "source_kind" => "official_employer",
          "job_id" => "REQ-101",
          "title" => "Lead Engineer",
          "company" => "Acme Aerospace",
          "location" => "Denver, CO"
        },
        {
          "source_record_key" => "rec-board-01",
          "mention_key" => "m1",
          "source_system" => "board",
          "observed_at" => "2026-09-21T10:00:00Z",
          "source_kind" => "third_party_board",
          "job_id" => "REQ-101",
          "title" => "Lead Engineer",
          "company" => "Acme Aerospace",
          "location" => "Denver, CO"
        }
      ]
    }

    report = BatchImporter.import_string(JSON.generate(batch))
    assert_equal "complete", report.status

    m1 = SourceMention.joins(:source_record).find_by(source_records: { source_record_key: "rec-employer-01" })
    m2 = SourceMention.joins(:source_record).find_by(source_records: { source_record_key: "rec-board-01" })

    assert_not_nil m1.canonical_posting_id
    assert_equal m1.canonical_posting_id, m2.canonical_posting_id
    assert_equal 2, m1.canonical_posting.mentions_count
  end

  test "distinct requisition IDs at same employer stay separate postings" do
    batch = {
      "batch_schema_version" => "1.0",
      "batch_id" => "separate-req-batch",
      "origin_class" => "adversarial_synthetic",
      "items" => [
        {
          "source_record_key" => "rec-req-101",
          "mention_key" => "m1",
          "source_system" => "ats",
          "observed_at" => "2026-09-20T10:00:00Z",
          "source_kind" => "official_employer",
          "job_id" => "REQ-101",
          "title" => "Staff Engineer",
          "company" => "Acme Aerospace",
          "location" => "Denver, CO"
        },
        {
          "source_record_key" => "rec-req-102",
          "mention_key" => "m1",
          "source_system" => "ats",
          "observed_at" => "2026-09-20T11:00:00Z",
          "source_kind" => "official_employer",
          "job_id" => "REQ-102",
          "title" => "Staff Engineer",
          "company" => "Acme Aerospace",
          "location" => "Denver, CO"
        }
      ]
    }

    report = BatchImporter.import_string(JSON.generate(batch))
    assert_equal "complete", report.status

    m1 = SourceMention.joins(:source_record).find_by(source_records: { source_record_key: "rec-req-101" })
    m2 = SourceMention.joins(:source_record).find_by(source_records: { source_record_key: "rec-req-102" })

    assert_not_equal m1.canonical_posting_id, m2.canonical_posting_id
  end

  test "tier 4 uncertain similarity creates separate postings and attaches potential duplicate record" do
    batch = {
      "batch_schema_version" => "1.0",
      "batch_id" => "tier4-test-batch",
      "origin_class" => "adversarial_synthetic",
      "items" => [
        {
          "source_record_key" => "rec-globex-01",
          "mention_key" => "m1",
          "source_system" => "board_a",
          "observed_at" => "2026-09-22T10:00:00Z",
          "source_kind" => "third_party_board",
          "job_id" => "GX-999",
          "title" => "Senior Reliability Engineer",
          "company" => "Globex Software",
          "location" => "Austin, TX"
        },
        {
          "source_record_key" => "rec-globex-digest",
          "mention_key" => "m1",
          "source_system" => "digest_b",
          "observed_at" => "2026-09-23T10:00:00Z",
          "source_kind" => "email_digest",
          "job_id" => nil,
          "title" => "Senior Reliability Engineer",
          "company" => "Globex Software",
          "location" => "Austin, TX"
        }
      ]
    }

    report = BatchImporter.import_string(JSON.generate(batch))
    assert_equal "complete", report.status

    m1 = SourceMention.joins(:source_record).find_by(source_records: { source_record_key: "rec-globex-01" })
    m2 = SourceMention.joins(:source_record).find_by(source_records: { source_record_key: "rec-globex-digest" })

    # Must stay separate
    assert_not_equal m1.canonical_posting_id, m2.canonical_posting_id

    p1 = m1.canonical_posting
    p2 = m2.canonical_posting

    # Must be flagged as potential duplicates
    assert p1.potential_duplicate
    assert p2.potential_duplicate
    assert_equal [p2.id], p1.potential_duplicates.pluck(:id)
    assert_equal [p1.id], p2.potential_duplicates.pluck(:id)
  end

  test "tier 2 merges mentions on matching cleaned canonical job URL" do
    batch = {
      "batch_schema_version" => "1.0",
      "batch_id" => "tier2-url-batch",
      "origin_class" => "adversarial_synthetic",
      "items" => [
        {
          "source_record_key" => "rec-url-01",
          "mention_key" => "m1",
          "source_system" => "board_1",
          "observed_at" => "2026-09-20T10:00:00Z",
          "source_kind" => "third_party_board",
          "title" => "API Architect",
          "company" => "Url Corp",
          "location" => "Chicago, IL",
          "job_url" => "https://careers.urlcorp.com/jobs/api-arch?utm_source=linkedin"
        },
        {
          "source_record_key" => "rec-url-02",
          "mention_key" => "m1",
          "source_system" => "board_2",
          "observed_at" => "2026-09-21T10:00:00Z",
          "source_kind" => "third_party_board",
          "title" => "API Architect",
          "company" => "Url Corp",
          "location" => "Chicago, IL",
          "job_url" => "https://careers.urlcorp.com/jobs/api-arch?utm_source=twitter&gclid=123#frag"
        }
      ]
    }

    report = BatchImporter.import_string(JSON.generate(batch))
    assert_equal "complete", report.status

    m1 = SourceMention.joins(:source_record).find_by(source_records: { source_record_key: "rec-url-01" })
    m2 = SourceMention.joins(:source_record).find_by(source_records: { source_record_key: "rec-url-02" })

    assert_equal m1.canonical_posting_id, m2.canonical_posting_id
  end
end
