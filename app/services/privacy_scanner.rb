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
    if str =~ EMAIL_REGEX
      violations << { item_id: item_id, field: path, type: "email_detected", snippet: redact_match(str, EMAIL_REGEX) }
    end

    if str =~ CANARY_REGEX
      violations << { item_id: item_id, field: path, type: "canary_token_detected", snippet: redact_match(str, CANARY_REGEX) }
    end

    if str =~ TOKEN_REGEX
      violations << { item_id: item_id, field: path, type: "credential_or_token_detected", snippet: "REDACTED_CREDENTIAL" }
    end

    if str =~ HTML_TAG_REGEX
      violations << { item_id: item_id, field: path, type: "executable_html_detected", snippet: "REDACTED_HTML" }
    end

    if str =~ SSN_REGEX
      violations << { item_id: item_id, field: path, type: "ssn_detected", snippet: "REDACTED_SSN" }
    end

    # If this field is a URL, ensure tracking query parameters are absent
    if path.end_with?("job_url") && str.start_with?("http")
      begin
        uri = URI.parse(str)
        if uri.query
          params = CGI.parse(uri.query)
          bad_params = params.keys.select { |k| k.downcase.start_with?("utm_") || %w[gclid fbclid msclkid].include?(k.downcase) }
          if bad_params.any?
            violations << { item_id: item_id, field: path, type: "tracking_parameters_detected", snippet: bad_params.join(", ") }
          end
        end
        if uri.fragment
          violations << { item_id: item_id, field: path, type: "url_fragment_detected", snippet: uri.fragment }
        end
      rescue URI::InvalidURIError
        violations << { item_id: item_id, field: path, type: "malformed_url", snippet: str[0, 50] }
      end
    end
  end

  def redact_match(str, regex)
    str.match(regex).to_s
  end
end
