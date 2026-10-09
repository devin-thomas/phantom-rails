require "json"
require "json_schemer"
require "time"

class SourceBatchParser
  SCHEMA_PATH = Rails.root.join("schemas", "batch-v1.schema.json")

  Result = Struct.new(:success, :batch_id, :origin_class, :valid_items, :invalid_items, :batch_errors, keyword_init: true)

  def self.schema
    @schema ||= JSONSchemer.schema(SCHEMA_PATH)
  end

  def self.parse_string(content, format: :auto)
    new.parse(content, format: format)
  end

  def self.parse_file(file_path)
    content = File.read(file_path, encoding: "UTF-8")
    format = file_path.to_s.end_with?(".jsonl") ? :jsonl : :json
    new.parse(content, format: format)
  end

  def parse(content, format: :auto)
    batch_raw = nil
    items = []

    trimmed = content.to_s.strip
    if trimmed.empty?
      return Result.new(
        success: false,
        batch_id: nil,
        origin_class: nil,
        valid_items: [],
        invalid_items: [],
        batch_errors: [{ code: "empty_payload", message: "Batch payload is empty" }]
      )
    end

    is_jsonl = format == :jsonl || (format == :auto && (trimmed.start_with?("{") && trimmed.include?("\n") && !trimmed.end_with?("]")))

    if is_jsonl
      begin
        lines = trimmed.lines.map(&:strip).reject(&:empty?)
        parsed_lines = lines.map.with_index do |line, idx|
          JSON.parse(line)
        rescue JSON::ParserError => e
          return Result.new(
            success: false,
            batch_id: nil,
            origin_class: nil,
            valid_items: [],
            invalid_items: [],
            batch_errors: [{ code: "malformed_jsonl", message: "Malformed JSON on line #{idx + 1}: #{e.message}" }]
          )
        end

        first_line = parsed_lines.first || {}
        batch_id = first_line["batch_id"] || "jsonl-batch-#{Time.now.utc.to_i}"
        origin_class = first_line["origin_class"] || "adversarial_synthetic"
        version = first_line["batch_schema_version"] || "1.0"

        batch_raw = {
          "batch_schema_version" => version,
          "batch_id" => batch_id,
          "origin_class" => origin_class,
          "items" => parsed_lines.map { |l| l.key?("items") ? l["items"] : l }.flatten
        }
      rescue StandardError => e
        return Result.new(
          success: false,
          batch_id: nil,
          origin_class: nil,
          valid_items: [],
          invalid_items: [],
          batch_errors: [{ code: "jsonl_parse_error", message: e.message }]
        )
      end
    else
      begin
        batch_raw = JSON.parse(content)
      rescue JSON::ParserError => e
        return Result.new(
          success: false,
          batch_id: nil,
          origin_class: nil,
          valid_items: [],
          invalid_items: [],
          batch_errors: [{ code: "malformed_json", message: "Invalid JSON format: #{e.message}" }]
        )
      end
    end

    unless batch_raw.is_a?(Hash)
      return Result.new(
        success: false,
        batch_id: nil,
        origin_class: nil,
        valid_items: [],
        invalid_items: [],
        batch_errors: [{ code: "invalid_batch_container", message: "Batch root must be a JSON object" }]
      )
    end

    # Check batch envelope version
    version = batch_raw["batch_schema_version"]
    if version != "1.0"
      return Result.new(
        success: false,
        batch_id: batch_raw["batch_id"],
        origin_class: batch_raw["origin_class"],
        valid_items: [],
        invalid_items: [],
        batch_errors: [{ code: "unsupported_schema_version", message: "Expected batch_schema_version '1.0', got '#{version}'" }]
      )
    end

    # Validate envelope properties (batch_id, origin_class, items)
    batch_errors = []
    unless batch_raw["batch_id"].is_a?(String) && !batch_raw["batch_id"].strip.empty?
      batch_errors << { code: "invalid_batch_id", message: "batch_id is required and must be non-empty string" }
    end

    unless %w[sanitized_historical adversarial_synthetic].include?(batch_raw["origin_class"])
      batch_errors << { code: "invalid_origin_class", message: "origin_class must be sanitized_historical or adversarial_synthetic" }
    end

    unless batch_raw["items"].is_a?(Array)
      batch_errors << { code: "invalid_items_collection", message: "items must be a JSON array" }
    end

    # Disallow unexpected envelope fields
    allowed_envelope_keys = %w[batch_schema_version batch_id origin_class items]
    unexpected_keys = batch_raw.keys - allowed_envelope_keys
    if unexpected_keys.any?
      batch_errors << { code: "unexpected_envelope_properties", message: "Unexpected properties in batch envelope: #{unexpected_keys.join(', ')}" }
    end

    if batch_errors.any?
      return Result.new(
        success: false,
        batch_id: batch_raw["batch_id"],
        origin_class: batch_raw["origin_class"],
        valid_items: [],
        invalid_items: [],
        batch_errors: batch_errors
      )
    end

    # Validate individual items
    valid_items = []
    invalid_items = []

    item_schema = self.class.schema.ref("#/$defs/item")
    envelope_keys = %w[batch_schema_version batch_id origin_class]

    batch_raw["items"].each_with_index do |raw_item, idx|
      item_data = raw_item.is_a?(Hash) ? raw_item.except(*envelope_keys) : raw_item
      item_errors = validate_item(item_data, item_schema)
      if item_errors.empty?
        valid_items << normalize_item(item_data, batch_raw["origin_class"])
      else
        invalid_items << {
          index: idx,
          item_identifier: raw_item.is_a?(Hash) ? "#{raw_item['source_record_key']}/#{raw_item['mention_key']}" : "item-#{idx}",
          errors: item_errors
        }
      end
    end

    Result.new(
      success: true,
      batch_id: batch_raw["batch_id"],
      origin_class: batch_raw["origin_class"],
      valid_items: valid_items,
      invalid_items: invalid_items,
      batch_errors: []
    )
  end

  private

  def validate_item(raw_item, item_schema)
    errors = []
    unless raw_item.is_a?(Hash)
      return [{ code: "invalid_item_type", message: "Item must be a JSON object" }]
    end

    # Check against JSON schema
    schema_errors = item_schema.validate(raw_item).to_a
    schema_errors.each do |err|
      prop = err["data_pointer"]
      type = err["type"]
      errors << { code: "schema_violation", message: "Field '#{prop}' failed constraint '#{type}'" }
    end

    # Additional strict RFC3339 timezone checks
    if raw_item["observed_at"].is_a?(String)
      begin
        parsed = Time.iso8601(raw_item["observed_at"])
        # Ensure UTC or offset is present
        unless raw_item["observed_at"] =~ /(Z|[+-]\d{2}:\d{2})$/
          errors << { code: "invalid_timestamp_timezone", message: "observed_at must include explicit UTC or timezone offset" }
        end
      rescue ArgumentError
        errors << { code: "invalid_timestamp_format", message: "observed_at is not a valid ISO8601/RFC3339 timestamp" }
      end
    end

    if raw_item["posted_at"].is_a?(String)
      begin
        Time.iso8601(raw_item["posted_at"])
        unless raw_item["posted_at"] =~ /(Z|[+-]\d{2}:\d{2})$/
          errors << { code: "invalid_timestamp_timezone", message: "posted_at must include explicit UTC or timezone offset" }
        end
      rescue ArgumentError
        errors << { code: "invalid_timestamp_format", message: "posted_at is not a valid ISO8601/RFC3339 timestamp" }
      end
    end

    errors
  end

  def normalize_item(raw, origin_class)
    {
      "source_record_key" => raw["source_record_key"].to_s.strip,
      "mention_key" => raw["mention_key"].to_s.strip,
      "source_system" => raw["source_system"].to_s.strip,
      "origin_class" => origin_class,
      "observed_at" => Time.iso8601(raw["observed_at"]).utc.iso8601,
      "posted_at" => raw["posted_at"] ? Time.iso8601(raw["posted_at"]).utc.iso8601 : nil,
      "source_kind" => raw["source_kind"],
      "source_domain" => raw["source_domain"]&.strip,
      "job_id" => raw["job_id"]&.strip,
      "title" => raw["title"].to_s.strip,
      "company" => raw["company"].to_s.strip,
      "location" => raw["location"].to_s.strip,
      "remote_type" => raw["remote_type"] || "unknown",
      "employment_type" => raw["employment_type"] || "unknown",
      "salary" => raw["salary"] ? {
        "min" => raw["salary"]["min"],
        "max" => raw["salary"]["max"],
        "currency" => raw["salary"]["currency"]&.upcase,
        "period" => raw["salary"]["period"]
      } : nil,
      "summary_excerpt" => raw["summary_excerpt"]&.strip,
      "job_url" => raw["job_url"]&.strip
    }
  end
end
