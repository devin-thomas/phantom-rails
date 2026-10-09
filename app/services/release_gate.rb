require "digest"
require "json"
require "json_schemer"

class ReleaseGate
  SCHEMA_PATH = Rails.root.join("schemas", "public-release-v1.schema.json")

  Result = Struct.new(:approved, :candidate_digest, :manifest, :errors, keyword_init: true)

  def self.schema
    @schema ||= JSONSchemer.schema(SCHEMA_PATH)
  end

  CANONICAL_ALGORITHMS = %w[sha256-exact sha256-normalized-text].freeze
  DEFAULT_ALGORITHM = "sha256-exact"

  def self.compute_digest(raw_content, algorithm: DEFAULT_ALGORITHM)
    case algorithm
    when "sha256-exact"
      Digest::SHA256.hexdigest(raw_content.to_s)
    when "sha256-normalized-text"
      Digest::SHA256.hexdigest(raw_content.to_s.strip)
    else
      Digest::SHA256.hexdigest(raw_content.to_s)
    end
  end

  def self.evaluate(candidate_content, manifest_content)
    new.evaluate(candidate_content, manifest_content)
  end

  def evaluate(candidate_content, manifest_content)
    errors = []

    manifest = nil
    begin
      manifest = JSON.parse(manifest_content.to_s)
    rescue JSON::ParserError => e
      computed_digest = self.class.compute_digest(candidate_content)
      return Result.new(approved: false, candidate_digest: computed_digest, manifest: nil, errors: ["Invalid manifest JSON: #{e.message}"])
    end

    unless manifest.is_a?(Hash)
      computed_digest = self.class.compute_digest(candidate_content)
      return Result.new(approved: false, candidate_digest: computed_digest, manifest: nil, errors: ["Manifest must be a JSON object"])
    end

    # 1. Digest check with algorithm support
    manifest_digest = manifest["candidate_digest"].to_s
    norm_digest = self.class.compute_digest(candidate_content, algorithm: "sha256-normalized-text")
    exact_digest = self.class.compute_digest(candidate_content, algorithm: "sha256-exact")

    algorithm = manifest["digest_algorithm"] || (manifest_digest == norm_digest ? "sha256-normalized-text" : "sha256-exact")
    computed_digest = (algorithm == "sha256-normalized-text") ? norm_digest : exact_digest

    if manifest_digest != computed_digest
      errors << "Manifest candidate_digest (#{manifest_digest}) does not match computed candidate digest (#{computed_digest}) using #{algorithm}"
    end
    schema_errors = self.class.schema.validate(manifest).to_a
    schema_errors.each do |err|
      prop = err["data_pointer"]
      type = err["type"]
      errors << "Manifest schema violation at '#{prop}': failed constraint '#{type}'"
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

    # 3. Cross-validate manifest total_items and origin_class_counts against parsed candidate items
    if manifest["total_items"].is_a?(Integer) && manifest["total_items"] != parsed_batch.valid_items.size
      errors << "Manifest total_items count (#{manifest['total_items']}) does not match candidate batch items count (#{parsed_batch.valid_items.size})"
    end

    if manifest["origin_class_counts"].is_a?(Hash)
      actual_hist = parsed_batch.valid_items.count { |i| i["origin_class"] == "sanitized_historical" }
      actual_synth = parsed_batch.valid_items.count { |i| i["origin_class"] == "adversarial_synthetic" }

      manifest_synth = manifest.dig("origin_class_counts", "adversarial_synthetic").to_i
      manifest_hist = manifest.dig("origin_class_counts", "sanitized_historical").to_i

      if manifest_synth != actual_synth
        errors << "Manifest adversarial_synthetic count (#{manifest_synth}) does not match candidate count (#{actual_synth})"
      end

      if manifest_hist != actual_hist
        errors << "Manifest sanitized_historical count (#{manifest_hist}) does not match candidate count (#{actual_hist})"
      end
    end

    scan_result = PrivacyScanner.scan_batch(parsed_batch.valid_items)
    unless scan_result.passed
      scan_errors = scan_result.violations.map { |v| "#{v[:type]} at #{v[:field]}" }
      errors << "Automated privacy scan failed: #{scan_errors.join('; ')}"
    end

    sanitized_items = parsed_batch.valid_items.map { |item| Sanitizer.sanitize_item(item) }
    sanitized_scan = PrivacyScanner.scan_batch(sanitized_items)
    unless sanitized_scan.passed
      scan_errors = sanitized_scan.violations.map { |v| "#{v[:type]} at #{v[:field]}" }
      errors << "Automated privacy scan failed on sanitized projection: #{scan_errors.join('; ')}"
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

  def self.build_manifest(candidate_content, approved_by:, corpus_version:, digest_algorithm: DEFAULT_ALGORITHM)
    computed_digest = compute_digest(candidate_content, algorithm: digest_algorithm)
    parsed = SourceBatchParser.parse_string(candidate_content)
    raise "Cannot build manifest for invalid candidate: #{parsed.batch_errors}" unless parsed.success

    scan = PrivacyScanner.scan_batch(parsed.valid_items)
    raise "Cannot build manifest for candidate with privacy violations: #{scan.violations.map { |v| v[:type] }.join(', ')}" unless scan.passed

    sanitized_items = parsed.valid_items.map { |item| Sanitizer.sanitize_item(item) }
    sanitized_scan = PrivacyScanner.scan_batch(sanitized_items)
    raise "Cannot build manifest for candidate with privacy violations in sanitized projection: #{sanitized_scan.violations.map { |v| v[:type] }.join(', ')}" unless sanitized_scan.passed

    hist_count = parsed.valid_items.count { |i| i["origin_class"] == "sanitized_historical" }
    synth_count = parsed.valid_items.count { |i| i["origin_class"] == "adversarial_synthetic" }

    counts = { "adversarial_synthetic" => synth_count }
    counts["sanitized_historical"] = hist_count if hist_count > 0

    res = {
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
    res["digest_algorithm"] = digest_algorithm if digest_algorithm != "sha256-exact"
    res
  end
end
