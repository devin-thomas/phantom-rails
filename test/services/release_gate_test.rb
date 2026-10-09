require "test_helper"

class ReleaseGateTest < ActiveSupport::TestCase
  setup do
    @approved_batch_path = Rails.root.join("fixtures", "public-approved", "approved-batch-v1.json")
    @approved_manifest_path = Rails.root.join("fixtures", "public-approved", "approved-manifest-v1.json")
    @batch_content = File.read(@approved_batch_path, encoding: "UTF-8")
    @manifest_content = File.read(@approved_manifest_path, encoding: "UTF-8")
  end

  test "approves valid approved release candidate with exact digest and signature" do
    result = ReleaseGate.evaluate(@batch_content, @manifest_content)

    assert result.approved, "Expected approved release gate, got errors: #{result.errors.inspect}"
    assert_empty result.errors
    assert_equal JSON.parse(@manifest_content)["candidate_digest"], result.candidate_digest
  end

  test "rejects release candidate when content is tampered by even one byte" do
    tampered_content = @batch_content.sub("Denver, CO", "Denver, CO ")
    result = ReleaseGate.evaluate(tampered_content, @manifest_content)

    assert_not result.approved
    assert result.errors.any? { |e| e.include?("Digest mismatch") }
  end

  test "rejects release candidate when privacy violations are present" do
    canary_path = Rails.root.join("fixtures", "adversarial", "tracking_and_canaries_v1.json")
    canary_content = File.read(canary_path, encoding: "UTF-8")

    manifest = {
      "manifest_version" => "1.0",
      "corpus_version" => "v1.0.0",
      "candidate_digest" => ReleaseGate.compute_digest(canary_content),
      "total_items" => 1,
      "origin_class_counts" => { "adversarial_synthetic" => 1 },
      "automated_checks_passed" => true,
      "approved_by" => "operator",
      "approved_at" => Time.now.utc.iso8601,
      "approval_signature" => ReleaseGate.compute_digest(canary_content)
    }

    result = ReleaseGate.evaluate(canary_content, JSON.generate(manifest))
    assert_not result.approved
    assert result.errors.any? { |e| e.include?("Automated privacy scan failed") }
  end

  test "sanitizer strips tracking parameters, fragments, userinfo, and html safely" do
    dirty_url = "https://user:pass@example.com/jobs/123?utm_source=google&utm_campaign=winter&valid_param=keep_me&gclid=secret#tracking-frag"
    cleaned_url = Sanitizer.clean_url(dirty_url)

    assert_equal "https://example.com/jobs/123?valid_param=keep_me", cleaned_url
    assert_no_match(/utm_/, cleaned_url)
    assert_no_match(/gclid/, cleaned_url)
    assert_no_match(/tracking-frag/, cleaned_url)
    assert_no_match(/user:pass/, cleaned_url)

    dirty_text = "<script>alert('bad')</script> Lead Engineer &amp; Architect <img src=x onerror=bad()> with very long description..."
    cleaned_text = Sanitizer.clean_text(dirty_text)

    assert_no_match(/<script>/, cleaned_text)
    assert_no_match(/<img/, cleaned_text)
    assert_includes cleaned_text, "Lead Engineer & Architect"
  end

  test "sanitizer enforces length bounds without inventing facts" do
    long_excerpt = "a" * 300
    cleaned = Sanitizer.clean_text(long_excerpt, max_length: 220)

    assert_equal 220, cleaned.length
    assert_equal "a" * 220, cleaned
  end
end
