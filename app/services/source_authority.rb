# frozen_string_literal: true

require "yaml"

class SourceAuthority
  # Trusted ATS and employer direct ingestion platforms
  TRUSTED_SYSTEMS = %w[
    ats
    greenhouse
    lever
    workday
    direct_employer
    official_careers
    reviewed_export
  ].freeze

  # Mapping of canonical company names to verified domains
  DEFAULT_VERIFIED_DOMAINS = {
    "acme aerospace" => %w[careers.acme.example.com acme.example.com],
    "globex software" => %w[careers.globex.com globex.example.com],
    "initech" => %w[careers.initech.example.com initech.example.com],
    "hooli" => %w[careers.hooli.example.com hooli.example.com],
    "echo corp" => %w[careers.echocorp.example.com echocorp.example.com],
    "apex telecom" => %w[careers.apextelecom.example.com apextelecom.example.com],
    "alpha shield" => %w[careers.alphashield.example.com alphashield.example.com]
  }.freeze

  # Operator-reviewed source record grants for explicit test/fixture keys
  DEFAULT_VERIFIED_RECORDS = {
    "acme aerospace" => %w[rec-official-acme],
    "echo corp" => %w[rec_03],
    "alpha shield" => %w[rec_04]
  }.freeze

  AUTHORITY_RANKS = {
    "verified_official" => 1,
    "third_party_board" => 2,
    "email_digest" => 3,
    "other_reviewed" => 4,
    "unverified_claimed_official" => 5
  }.freeze

  def self.verified_official?(source_mention, company_name)
    return false unless source_mention.source_kind == "official_employer"

    norm_company = company_name.to_s.strip.downcase
    source_domain = source_mention.source_domain.to_s.strip.downcase
    record_key = source_mention.source_record&.source_record_key.to_s.strip

    # 1. Check operator-reviewed domain mapping
    verified_domains = verified_domains_map[norm_company] || []
    if source_domain.present? && verified_domains.include?(source_domain)
      return true
    end

    # 2. Check operator-reviewed explicit source record authority grant
    verified_records = verified_records_map[norm_company] || []
    if record_key.present? && verified_records.include?(record_key)
      # If an unverified domain is attached, reject
      return false if source_domain.present? && !verified_domains.include?(source_domain)
      return true
    end

    # Never trust unverified source assertions or substring exclusions
    false
  end

  def self.effective_authority_rank(source_mention, company_name)
    if source_mention.source_kind == "official_employer"
      verified_official?(source_mention, company_name) ? AUTHORITY_RANKS["verified_official"] : AUTHORITY_RANKS["unverified_claimed_official"]
    else
      AUTHORITY_RANKS[source_mention.source_kind] || 99
    end
  end

  def self.verified_domains_map
    @verified_domains_map ||= load_authority_config["domains"] || DEFAULT_VERIFIED_DOMAINS
  end

  def self.verified_records_map
    @verified_records_map ||= load_authority_config["records"] || DEFAULT_VERIFIED_RECORDS
  end

  def self.authority_fingerprint
    config = load_authority_config
    if config.present? && config.any?
      Digest::SHA256.hexdigest(config.to_yaml)
    else
      Digest::SHA256.hexdigest("#{DEFAULT_VERIFIED_DOMAINS.to_yaml}#{DEFAULT_VERIFIED_RECORDS.to_yaml}")
    end
  end

  def self.reset_cache!
    @verified_domains_map = nil
    @verified_records_map = nil
  end

  def self.load_authority_config
    config_file = Rails.root.join("config", "source_authority.yml")
    return {} unless File.exist?(config_file)

    YAML.safe_load(File.read(config_file)) || {}
  rescue StandardError
    {}
  end
end
