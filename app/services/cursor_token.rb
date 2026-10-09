require "openssl"
require "base64"
require "json"

class CursorToken
  SECRET = Rails.application.secret_key_base || "phantom_rails_cursor_hmac_secret_2026"

  DecodeResult = Struct.new(:valid?, :payload, :error_code, :error_message, keyword_init: true)

  def self.encode(corpus_revision:, query_digest:, sort_tuple:, ttl_seconds: 900)
    expires_at = (Time.now.utc + ttl_seconds).to_i
    payload = {
      "v" => 1,
      "rev" => corpus_revision,
      "qd" => query_digest,
      "tuple" => sort_tuple,
      "exp" => expires_at
    }
    json_bytes = payload.to_json
    payload_b64 = Base64.urlsafe_encode64(json_bytes, padding: false)
    signature = OpenSSL::HMAC.digest("SHA256", SECRET, payload_b64)
    sig_b64 = Base64.urlsafe_encode64(signature, padding: false)

    "#{payload_b64}.#{sig_b64}"
  end

  def self.decode(token, expected_revision:, expected_query_digest:)
    parts = token.to_s.split(".")
    unless parts.length == 2
      return DecodeResult.new(valid?: false, error_code: "invalid_cursor", error_message: "The provided cursor format is malformed")
    end

    payload_b64, sig_b64 = parts

    # 1. Verify HMAC signature
    expected_sig = OpenSSL::HMAC.digest("SHA256", SECRET, payload_b64)
    expected_sig_b64 = Base64.urlsafe_encode64(expected_sig, padding: false)

    unless Rack::Utils.secure_compare(sig_b64, expected_sig_b64)
      return DecodeResult.new(valid?: false, error_code: "invalid_cursor", error_message: "Cursor signature verification failed")
    end

    # 2. Parse payload
    begin
      json_bytes = Base64.urlsafe_decode64(payload_b64)
      payload = JSON.parse(json_bytes)
    rescue StandardError
      return DecodeResult.new(valid?: false, error_code: "invalid_cursor", error_message: "Failed to decode cursor payload")
    end

    # 3. Check expiration
    if payload["exp"].to_i < Time.now.utc.to_i
      return DecodeResult.new(valid?: false, error_code: "cursor_expired", error_message: "Cursor has expired. Please restart your search.")
    end

    # 4. Check query digest match
    if payload["qd"] != expected_query_digest
      return DecodeResult.new(valid?: false, error_code: "cursor_query_mismatch", error_message: "Cursor query parameters do not match the current search query")
    end

    # 5. Check corpus revision match
    if payload["rev"] != expected_revision
      return DecodeResult.new(valid?: false, error_code: "stale_cursor", error_message: "Corpus revision has changed. Please restart search from the first page.")
    end

    DecodeResult.new(valid?: true, payload: payload)
  end

  def self.compute_query_digest(normalized_params)
    Digest::SHA256.hexdigest(normalized_params.sort.to_h.to_json)
  end
end
