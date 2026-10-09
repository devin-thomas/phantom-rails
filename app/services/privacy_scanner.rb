require "uri"
require "cgi"

class PrivacyScanner
  EMAIL_REGEX = /\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b/
  CANARY_REGEX = /\b(canary_[a-z0-9_]+|secret_[a-z0-9_]+|private_[a-z0-9_]+)\b/i
  TOKEN_REGEX = /\b(bearer\s+[a-z0-9_\-\.]+|ghp_[a-z0-9]+|ey[a-z0-9_\-]{10,}\.[a-z0-9_\-]{10,})\b/i
  HTML_TAG_REGEX = /<script\b[^<]*(?:(?!<\/script>)<[^<]*)*<\/script>|<img\b[^>]*onerror/i
  SSN_REGEX = /\b\d{3}-\d{2}-\d{4}\b/

  ScanResult = Struct.new(:passed, :violations, keyword_init: true) do
    def clean?
      passed
    end
  end

  def self.scan_batch(items)
    new.scan(items)
  end

  def self.scan_string(str)
    violations = []
    scanner = new
    scanner.send(:check_string, str, path: "string", item_id: "raw", violations: violations)
    ScanResult.new(passed: violations.empty?, violations: violations)
  end

  def scan(items)
    violations = []

    items.each_with_index do |item, idx|
      item_id = item.is_a?(Hash) ? "#{item['source_record_key']}/#{item['mention_key']}" : "item-#{idx}"

      # Traverse all string fields
      scan_object(item, path: "item[#{idx}]", item_id: item_id, violations: violations)
    end

    ScanResult.new(
      passed: violations.empty?,
      violations: violations
    )
  end

  def self.canonicalize_text(str)
    return "" if str.nil?

    cleaned = str.to_s
    # 1. Strip zero-width spaces and control characters
    cleaned = cleaned.gsub(/[\u200B-\u200D\uFEFF\u2060]/, "")
    cleaned = cleaned.gsub(/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/, "")

    # 2. Iteratively decode HTML entities (up to 3 passes to handle nested encoding)
    3.times do
      prev = cleaned
      cleaned = CGI.unescapeHTML(cleaned)
      cleaned = cleaned.gsub(/&commat;/i, "@").gsub(/&period;/i, ".")
      break if cleaned == prev
    end

    # 3. Decode percent-encoded components if present
    if cleaned.include?("%")
      begin
        cleaned = URI.decode_www_form_component(cleaned)
      rescue StandardError
        # ignore percent decoding error
      end
    end

    cleaned
  end

  private

  def scan_object(obj, path:, item_id:, violations:)
    case obj
    when Hash
      obj.each do |k, v|
        scan_object(v, path: "#{path}.#{k}", item_id: item_id, violations: violations)
      end
    when Array
      obj.each_with_index do |v, i|
        scan_object(v, path: "#{path}[#{i}]", item_id: item_id, violations: violations)
      end
    when String
      check_string(obj, path: path, item_id: item_id, violations: violations)
    end
  end

  def check_string(str, path:, item_id:, violations:)
    canonical = self.class.canonicalize_text(str)

    if str =~ EMAIL_REGEX || canonical =~ EMAIL_REGEX
      type = (str =~ EMAIL_REGEX) ? "email_detected" : "encoded_email_detected"
      violations << { item_id: item_id, field: path, type: type, snippet: "[REDACTED_EMAIL]" }
    end

    if str =~ CANARY_REGEX || canonical =~ CANARY_REGEX
      type = (str =~ CANARY_REGEX) ? "canary_token_detected" : "encoded_canary_detected"
      violations << { item_id: item_id, field: path, type: type, snippet: "[REDACTED_CANARY]" }
    end

    if str =~ TOKEN_REGEX || canonical =~ TOKEN_REGEX
      type = (str =~ TOKEN_REGEX) ? "credential_or_token_detected" : "encoded_token_detected"
      violations << { item_id: item_id, field: path, type: type, snippet: "[REDACTED_TOKEN]" }
    end

    if str =~ HTML_TAG_REGEX || canonical =~ HTML_TAG_REGEX
      type = (str =~ HTML_TAG_REGEX) ? "executable_html_detected" : "encoded_html_detected"
      violations << { item_id: item_id, field: path, type: type, snippet: "[REDACTED_HTML]" }
    end

    if str =~ SSN_REGEX || canonical =~ SSN_REGEX
      type = (str =~ SSN_REGEX) ? "ssn_detected" : "encoded_ssn_detected"
      violations << { item_id: item_id, field: path, type: type, snippet: "[REDACTED_SSN]" }
    end

    # If this field is a URL or contains URL structure, inspect tracking and query arguments
    if path.end_with?("job_url") || str.start_with?("http://") || str.start_with?("https://")
      begin
        clean_url_str = str.gsub(/[\u200B-\u200D\uFEFF\u2060]/, "")
        uri = URI.parse(clean_url_str)
        if uri.query
          params = CGI.parse(uri.query)
          bad_params = params.keys.select { |k| k.downcase.start_with?("utm_") || %w[gclid fbclid msclkid].include?(k.downcase) }
          if bad_params.any?
            violations << { item_id: item_id, field: path, type: "tracking_parameters_detected", snippet: "[REDACTED_PARAMS]" }
          end

          params.each do |k, values|
            lower_k = k.to_s.downcase.strip
            if %w[contact email user applicant candidate author secret bearer token auth].any? { |bad| lower_k.include?(bad) }
              violations << { item_id: item_id, field: "#{path}?#{k}", type: "sensitive_query_parameter_detected", snippet: "[REDACTED_PARAM_KEY]" }
            end

            values.each do |val|
              decoded = begin
                CGI.unescape(val)
              rescue StandardError
                val
              end

              if decoded =~ EMAIL_REGEX
                violations << { item_id: item_id, field: "#{path}?#{k}", type: "email_in_url_detected", snippet: "[REDACTED_EMAIL]" }
              end
              if decoded =~ CANARY_REGEX
                violations << { item_id: item_id, field: "#{path}?#{k}", type: "canary_in_url_detected", snippet: "[REDACTED_CANARY]" }
              end
              if decoded =~ TOKEN_REGEX
                violations << { item_id: item_id, field: "#{path}?#{k}", type: "token_in_url_detected", snippet: "[REDACTED_TOKEN]" }
              end
            end
          end
        end
        if uri.fragment
          violations << { item_id: item_id, field: path, type: "url_fragment_detected", snippet: "[REDACTED_FRAGMENT]" }
        end
      rescue URI::InvalidURIError
        violations << { item_id: item_id, field: path, type: "malformed_url", snippet: "[REDACTED_URL]" }
      end
    end
  end

  def redact_match(str, regex)
    "[REDACTED_SECRET]"
  end
end
