require "test_helper"

class SearchPostingsTest < ActiveSupport::TestCase
  setup do
    @release = ApprovedRelease.create!(
      manifest_digest: Digest::SHA256.hexdigest("mock_manifest_search"),
      approval_signature: "sig_search_test",
      approved_by: "auditor@phantomrails.dev",
      approved_at: Time.current,
      corpus_version: "2026.04.1",
      total_items: 4,
      active: true
    )

    @record = SourceRecord.create!(
      approved_release: @release,
      source_system: "ats_greenhouse",
      source_record_key: "rec_search_01",
      origin_class: "sanitized_historical"
    )

    # Posting A: Matches "technical" and "support" in title (+8 + 8 = 16)
    @post_a = CanonicalPosting.create!(
      public_id: "post_search_a",
      approved_release: @release,
      title: "Technical Support Engineer",
      company: "Example Systems",
      location: "Austin, TX",
      remote_type: "hybrid",
      employment_type: "full_time",
      salary_min: 85000,
      salary_max: 105000,
      salary_currency: "USD",
      salary_period: "year",
      summary_excerpt: "Investigate customer API issues.",
      last_observed_at: 1.day.ago,
      first_observed_at: 2.days.ago
    )

    # Posting B: Matches "technical" in company (+5) and "support" in excerpt (+1) -> Total 6
    @post_b = CanonicalPosting.create!(
      public_id: "post_search_b",
      approved_release: @release,
      title: "Senior Software Architect",
      company: "Technical Systems Inc",
      location: "Denver, CO",
      remote_type: "remote",
      employment_type: "full_time",
      salary_min: 160000,
      salary_max: 200000,
      salary_currency: "USD",
      salary_period: "year",
      summary_excerpt: "Provide escalated tier 3 support architecture.",
      last_observed_at: 2.days.ago,
      first_observed_at: 3.days.ago
    )

    # Posting C: Hourly wage ($75/hour) -> Must NOT satisfy annual USD minimum
    @post_c = CanonicalPosting.create!(
      public_id: "post_search_c",
      approved_release: @release,
      title: "Contract DevOps Consultant",
      company: "Cloud Operations",
      location: "Austin, TX",
      remote_type: "onsite",
      employment_type: "contract",
      salary_min: 75,
      salary_max: 95,
      salary_currency: "USD",
      salary_period: "hour",
      summary_excerpt: "Assist cloud infrastructure migrations.",
      last_observed_at: 3.days.ago,
      first_observed_at: 4.days.ago
    )

    # Posting D: Null salary
    @post_d = CanonicalPosting.create!(
      public_id: "post_search_d",
      approved_release: @release,
      title: "Product Manager",
      company: "Beta Systems",
      location: "New York, NY",
      remote_type: "hybrid",
      employment_type: "full_time",
      salary_min: nil,
      salary_max: nil,
      salary_currency: nil,
      salary_period: nil,
      summary_excerpt: "Technical roadmap execution.",
      last_observed_at: 4.days.ago,
      first_observed_at: 5.days.ago
    )

    [@post_a, @post_b, @post_c, @post_d].each_with_index do |post, idx|
      SourceMention.create!(
        source_record: @record,
        canonical_posting: post,
        mention_key: "rec_search_01:m_#{idx}",
        source_kind: "official_employer"
      )
    end
  end

  test "multiple lexemes match across fields and rank by stated weights" do
    result = SearchPostings.call(q: "technical support")

    assert result.success?, "Search failed: #{result.error_message}"
    assert_equal 2, result.postings.length
    assert_equal "post_search_a", result.postings.first.public_id
    assert_equal "post_search_b", result.postings.second.public_id

    # Title match (8 + 8 = 16)
    assert_equal 16, result.scores[@post_a.id]
    # Company (5) + Excerpt (1) = 6
    assert_equal 6, result.scores[@post_b.id]
  end

  test "requires all meaningful lexemes across combined fields" do
    # "technical" is in A and B, but "nonexistent" is in neither
    result = SearchPostings.call(q: "technical nonexistentterm")

    assert result.success?
    assert_empty result.postings
  end

  test "unknown salaries and hourly pay cannot satisfy min_salary_usd filter" do
    result = SearchPostings.call(min_salary_usd: 50000)

    assert result.success?
    ids = result.postings.map(&:public_id)
    assert_includes ids, "post_search_a"
    assert_includes ids, "post_search_b"
    refute_includes ids, "post_search_c", "Hourly rate ($75/hr) must not satisfy annual USD min filter"
    refute_includes ids, "post_search_d", "Null salary must not satisfy annual USD min filter"
  end

  test "compound AND filtering works with multiple criteria" do
    result = SearchPostings.call(
      location: "Austin, TX",
      remote_type: "hybrid",
      min_salary_usd: 80000
    )

    assert result.success?
    assert_equal 1, result.postings.length
    assert_equal "post_search_a", result.postings.first.public_id
  end

  test "ordering by company and title is stable and deterministic" do
    result = SearchPostings.call(sort: "company")
    assert result.success?
    companies = result.postings.map(&:company)
    assert_equal companies.sort, companies

    result_title = SearchPostings.call(sort: "title")
    assert result_title.success?
    titles = result_title.postings.map(&:title)
    assert_equal titles.sort, titles
  end

  test "caps complexity and rejects invalid parameters deterministically" do
    # > 120 chars
    long_q = "a" * 125
    res = SearchPostings.call(q: long_q)
    refute res.success?
    assert_equal "invalid_parameter", res.error_code
    assert_equal "q must be at most 120 characters", res.error_message

    # > 8 lexemes
    many_terms = "ruby rails postgres redis docker sidekiq rspec linux kubernetes"
    res = SearchPostings.call(q: many_terms)
    refute res.success?
    assert_equal "invalid_parameter", res.error_code
    assert_equal "q contains too many query terms (max 8)", res.error_message

    # Invalid remote_type
    res = SearchPostings.call(remote_type: "mars_orbit")
    refute res.success?
    assert_equal "invalid_parameter", res.error_code

    # Invalid sort without q
    res = SearchPostings.call(sort: "relevance")
    refute res.success?
    assert_equal "invalid_parameter", res.error_code

    # Negative salary
    res = SearchPostings.call(min_salary_usd: -500)
    refute res.success?
    assert_equal "invalid_parameter", res.error_code
  end

  test "resists SQL injection safely" do
    malicious_inputs = [
      "' OR 1=1 --",
      "'; DROP TABLE canonical_postings; --",
      "1 UNION SELECT * FROM users --",
      "' AND 1=(SELECT COUNT(*) FROM approved_releases) --"
    ]

    malicious_inputs.each do |input|
      res_q = SearchPostings.call(q: input)
      assert res_q.success? || res_q.error_code == "invalid_parameter"

      res_comp = SearchPostings.call(company: input)
      assert res_comp.success?
      assert_empty res_comp.postings

      res_sal = SearchPostings.call(min_salary_usd: input)
      refute res_sal.success?
      assert_equal "invalid_parameter", res_sal.error_code
    end

    # Ensure table canonical_postings was not dropped or corrupted
    assert CanonicalPosting.count >= 4
  end
end
