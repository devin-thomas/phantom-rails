require "digest"
require "json"

class ReleaseGate
  Result = Struct.new(:approved, :candidate_digest, :manifest, :errors, keyword_init: true)

  def self.compute_digest(raw_content)
    # Digest canonical UTF-8 bytes
    Digest::SHA256.hexdigest(raw_content.to_s.strip)
  end

  def self.evaluate(candidate_content, manifest_content)
    new.evaluate(candidate_content, manifest_content)
  end

  def evaluate(candidate_content, manifest_content)
    errors = []

    # 1. Digest check
    computed_digest = self.class.compute_digest(candidate_content)

    manifest = nil
    begin
      manifest = JSON.parse(manifest_content.to_s)
    rescue JSON::ParserError => e
      return Result.new(approved: false, candidate_digest: computed_digest, manifest: nil, errors: ["Invalid manifest JSON: #{e.message}"])
    end

    # Check manifest digest
    if manifest["candidate_digest"] != computed_digest
      errors << "Digest mismatch: candidate SHA256 is '#{computed_digest}' but manifest specifies '#{manifest['candidate_digest']}'"
    end

    # Check operator signature against exact digest
    if manifest["approval_signature"] != computed_digest
      errors << "Signature mismatch: operator approval signature does not match exact candidate digest"
    end

    unless manifest["approved_by"].is_a?(String) && !manifest["approved_by"].strip.empty?
      errors << "Operator approval missing: approved_by must be explicitly specified"
    end

    # 2. Parse candidate items and run automated privacy scan
    parsed_batch = SourceBatchParser.parse_string(candidate_content)
    unless parsed_batch.success
      errors << "Candidate batch parse error: #{parsed_batch.batch_errors.map { |e| e[:message] }.join('; ')}"
      return Result.new(approved: false, candidate_digest: computed_digest, manifest: manifest, errors: errors)
    end

    if parsed_batch.invalid_items.any?
      inv_messages = parsed_batch.invalid_items.flat_map { |inv| inv[:errors].map { |e| "#{inv[:item_identifier]}: #{e[:message]}" } }
      errors << "Candidate batch contains #{parsed_batch.invalid_items.size} invalid items; release candidate must be 100% valid: #{inv_messages.join('; ')}"
    end

    scan_result = PrivacyScanner.scan_batch(parsed_batch.valid_items)
    unless scan_result.passed
      scan_errors = scan_result.violations.map { |v| "#{v[:type]} at #{v[:field]} (#{v[:snippet]})" }
      errors << "Automated privacy scan failed: #{scan_errors.join('; ')}"
    end

    unless manifest["automated_checks_passed"] == true
      errors << "Manifest does not indicate automated checks passed"
    end

    Result.new(
      approved: errors.empty?,
      candidate_digest: computed_digest,
      manifest: manifest,
      errors: errors
    )
  end

  def self.build_manifest(candidate_content, approved_by:, corpus_version:)
    computed_digest = compute_digest(candidate_content)
    parsed = SourceBatchParser.parse_string(candidate_content)
    raise "Cannot build manifest for invalid candidate: #{parsed.batch_errors}" unless parsed.success

    scan = PrivacyScanner.scan_batch(parsed.valid_items)
    raise "Cannot build manifest for candidate with privacy violations: #{scan.violations}" unless scan.passed

    hist_count = parsed.valid_items.count { |i| i["origin_class"] == "sanitized_historical" }
    synth_count = parsed.valid_items.count { |i| i["origin_class"] == "adversarial_synthetic" }

    counts = { "adversarial_synthetic" => synth_count }
    counts["sanitized_historical"] = hist_count if hist_count > 0

    {
      "manifest_version" => "1.0",
      "corpus_version" => corpus_version,
      "candidate_digest" => computed_digest,
      "total_items" => parsed.valid_items.size,
      "origin_class_counts" => counts,
      "automated_checks_passed" => true,
      "approved_by" => approved_by,
      "approved_at" => Time.now.utc.iso8601,
      "approval_signature" => computed_digest
    }
  end
end
