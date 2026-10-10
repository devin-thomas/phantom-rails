require "uri"
require "cgi"

class Sanitizer
  TRACKING_PARAMS = %w[
    utm_source utm_medium utm_campaign utm_term utm_content
    gclid fbclid msclkid mc_cid mc_eid ref tracking_token session_id token
  ].freeze

  def self.clean_url(url_string)
    return nil if url_string.nil? || url_string.to_s.strip.empty?

    # Strip zero-width spaces and control characters
    clean_str = url_string.to_s.strip.gsub(/[\u200B-\u200D\uFEFF\u2060]/, "").gsub(/[\x00-\x1F\x7F]/, "")
    uri = URI.parse(clean_str)
    return nil unless uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)

    # Disallow userinfo (user:pass@)
    uri.user = nil
    uri.password = nil

    # Strip fragment
    uri.fragment = nil

    # Clean query parameters
    if uri.query
      params = CGI.parse(uri.query)
      filtered = {}

      params.each do |k, values|
        lower_k = k.to_s.downcase.strip
        next if TRACKING_PARAMS.include?(lower_k)
        next if lower_k.start_with?("utm_")
        next if %w[contact email user applicant candidate author secret bearer token auth session].any? { |bad| lower_k.include?(bad) }

        clean_values = values.map do |val|
          decoded = val.to_s
          3.times do
            prev = decoded
            decoded = begin
              CGI.unescape(decoded)
            rescue StandardError
              decoded
            end
            break if decoded == prev
          end

          # Drop parameter if decoded value contains email, canary, token, or SSN
          if decoded =~ PrivacyScanner::EMAIL_REGEX ||
             decoded =~ PrivacyScanner::CANARY_REGEX ||
             decoded =~ PrivacyScanner::TOKEN_REGEX ||
             decoded =~ PrivacyScanner::SSN_REGEX
            nil
          else
            val
          end
        end.compact

        filtered[k] = clean_values if clean_values.any?
      end

      uri.query = filtered.empty? ? nil : URI.encode_www_form(filtered)
    end

    cleaned = uri.to_s
    cleaned.length <= 512 ? cleaned : nil
  rescue URI::InvalidURIError
    nil
  end

  def self.clean_text(text, max_length: 220)
    return nil if text.nil?

    cleaned = text.to_s
    # 1. Strip zero-width spaces and control characters
    cleaned = cleaned.gsub(/[\u200B-\u200D\uFEFF\u2060]/, "")
    cleaned = cleaned.gsub(/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/, "")

    # 2. Normalize Unicode compatibility forms (e.g. full-width characters)
    begin
      cleaned = cleaned.unicode_normalize(:nfkc)
    rescue StandardError
    end

    # 3. Iteratively decode HTML entities (up to 3 passes to handle nested encoding)
    3.times do
      prev = cleaned
      cleaned = CGI.unescapeHTML(cleaned)
      cleaned = cleaned.gsub(/&commat;/i, "@").gsub(/&period;/i, ".")
      break if cleaned == prev
    end

    # 4. Strip HTML tags AFTER unescaping entities, so encoded tags are caught and removed
    cleaned = cleaned.gsub(/<[^>]*>/, " ")

    # 4. Normalize whitespaces
    cleaned = cleaned.gsub(/\s+/, " ").strip

    return nil if cleaned.empty?
    cleaned.length <= max_length ? cleaned : cleaned[0, max_length].strip
  end

  def self.sanitize_item(item)
    sanitized = item.dup
    sanitized["title"] = clean_text(item["title"], max_length: 200)
    sanitized["company"] = clean_text(item["company"], max_length: 200)
    sanitized["location"] = clean_text(item["location"], max_length: 200)
    sanitized["summary_excerpt"] = clean_text(item["summary_excerpt"], max_length: 220) if item["summary_excerpt"]
    sanitized["job_url"] = clean_url(item["job_url"]) if item["job_url"]
    sanitized
  end
end
