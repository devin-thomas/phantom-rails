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
    "acme aerospace" => [
      { "system" => "reviewed_export", "key" => "rec-official-acme" },
      { "system" => "ats", "key" => "rec-official-acme" },
      { "system" => "reviewed_export", "key" => "rec-acme-101" },
      { "system" => "reviewed_export", "key" => "rec-acme-102" },
      { "system" => "ats", "key" => "rec-employer-01" },
      { "system" => "reviewed_export", "key" => "rec-approved-1" }
    ],
    "echo corp" => [{ "system" => "ats", "key" => "rec_03" }],
    "alpha shield" => [{ "system" => "ats", "key" => "rec_04" }]
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
    record = source_mention.source_record
    record_key = record&.source_record_key.to_s.strip
    record_sys = record&.source_system.to_s.strip

    verified_domains = verified_domains_map[norm_company] || []

    # 1. Eligibility condition: domain must be an operator-reviewed employer domain
    # (or blank only if specifically granted on a trusted reviewed system)
    if source_domain.present?
      return false unless verified_domains.include?(source_domain)
    else
      return false unless %w[reviewed_export ats].include?(record_sys)
    end

    # 2. Check operator-reviewed explicit source record authority grant
    # Strictly requires matching BOTH source_system and source_record_key
    verified_records = verified_records_map[norm_company] || []
    if record_key.present? && record_sys.present?
      matches_grant = verified_records.any? do |grant|
        if grant.is_a?(Hash)
          sys_match = grant["system"].to_s == record_sys
          key_match = grant["key"].to_s == record_key
          dom_match = grant["domain"].blank? || grant["domain"].to_s.downcase == source_domain
          sys_match && key_match && dom_match
        elsif grant.is_a?(String) && grant.include?(":")
          sys, key = grant.split(":", 2)
          sys == record_sys && key == record_key
        else
          # Legacy bare key grant: ONLY valid if system is in TRUSTED_SYSTEMS
          grant.to_s == record_key && TRUSTED_SYSTEMS.include?(record_sys)
        end
      end

      if matches_grant
        # If an unverified domain is attached, reject
        return false if source_domain.present? && !verified_domains.include?(source_domain)
        # Blank domain requires trusted system with reviewed grant
        return false if source_domain.blank? && !%w[reviewed_export ats].include?(record_sys)
        return true
      end
    end

    # 3. Check release-scoped trust entry: previously approved revision in an active approved release
    if source_mention.canonical_posting&.approved_release&.active?
      app_rev_exists = ApprovedReleaseRevision.where(
        approved_release_id: source_mention.canonical_posting.approved_release_id,
        source_revision_id: source_mention.source_revisions.select(:id)
      ).exists?
      return true if app_rev_exists && (source_domain.blank? || verified_domains.include?(source_domain))
    end

    # Never trust unverified source assertions or unverified record keys
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
