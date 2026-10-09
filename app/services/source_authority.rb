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
  VERIFIED_DOMAINS = {
    "acme aerospace" => %w[careers.acme.example.com acme.example.com],
    "globex software" => %w[careers.globex.com globex.example.com],
    "initech" => %w[careers.initech.example.com initech.example.com],
    "hooli" => %w[careers.hooli.example.com hooli.example.com]
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
    source_system = source_mention.source_record&.source_system.to_s.strip.downcase
    origin_class = source_mention.source_record&.origin_class.to_s

    # 1. Verified if source_domain matches operator-reviewed company domains
    if source_domain.present? && VERIFIED_DOMAINS[norm_company]&.include?(source_domain)
      return true
    end

    # 2. Verified if system is a trusted employer ATS with origin_class approved/reviewed
    if TRUSTED_SYSTEMS.include?(source_system) && (origin_class == "sanitized_historical" || origin_class == "adversarial_synthetic" || origin_class == "approved_public")
      # If domain is present, ensure it does not contradict known third-party boards
      unless source_domain.include?("board") || source_domain.include?("aggregator") || source_domain.include?("untrusted")
        return true
      end
    end

    false
  end

  def self.effective_authority_rank(source_mention, company_name)
    if source_mention.source_kind == "official_employer"
      verified_official?(source_mention, company_name) ? AUTHORITY_RANKS["verified_official"] : AUTHORITY_RANKS["unverified_claimed_official"]
    else
      AUTHORITY_RANKS[source_mention.source_kind] || 99
    end
  end
end
