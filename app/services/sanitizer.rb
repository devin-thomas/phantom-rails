require "uri"
require "cgi"

class Sanitizer
  TRACKING_PARAMS = %w[
    utm_source utm_medium utm_campaign utm_term utm_content
    gclid fbclid msclkid mc_cid mc_eid ref tracking_token session_id token
  ].freeze

  def self.clean_url(url_string)
    return nil if url_string.nil? || url_string.to_s.strip.empty?

    uri = URI.parse(url_string.to_s.strip)
    return nil unless uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)

    # Disallow userinfo (user:pass@)
    uri.user = nil
    uri.password = nil

    # Strip fragment
    uri.fragment = nil

    # Clean query parameters
    if uri.query
      params = CGI.parse(uri.query)
      filtered = params.reject do |k, _|
        lower_k = k.downcase
        TRACKING_PARAMS.include?(lower_k) || lower_k.start_with?("utm_") || lower_k.include?("token")
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
    # Strip HTML tags
    cleaned = cleaned.gsub(/<[^>]*>/, " ")
    # Decode HTML entities
    cleaned = CGI.unescapeHTML(cleaned)
    # Normalize whitespaces
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
