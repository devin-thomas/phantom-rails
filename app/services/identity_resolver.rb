# frozen_string_literal: true

require "uri"

class IdentityResolver
  ResolveResult = Struct.new(:canonical_posting, :tier, :status, :potential_duplicates_found, :conflict_reason, keyword_init: true)

  VETTED_ATS_DOMAINS = %w[
    greenhouse.io
    lever.co
    workday.com
    myworkdayjobs.com
    ashbyhq.com
    smartrecruiters.com
    icims.com
    taleo.net
    jobvite.com
  ].freeze

  def self.resolve_mention(mention)
    new.resolve(mention)
  end

  def self.resolve_all_unassigned!
    resolved_count = 0
    SourceMention.where(canonical_posting_id: nil).find_each do |m|
      res = new.resolve(m)
      resolved_count += 1 if res.status == :resolved
    end
    resolved_count
  end

  def resolve(mention)
    if mention.canonical_posting_id.present?
      posting = mention.canonical_posting
      # Immutable approved projection guard:
      # If posting belongs to an approved release, unapproved staging imports MUST NOT mutate it!
      if posting.approved_release_id.present?
        return ResolveResult.new(
          canonical_posting: posting,
          tier: 0,
          status: :resolved,
          potential_duplicates_found: posting.has_active_approved_potential_duplicates?
        )
      end

      FieldReconciler.reconcile!(posting)
      return ResolveResult.new(
        canonical_posting: posting,
        tier: 0,
        status: :resolved,
        potential_duplicates_found: posting.potential_duplicate
      )
    end

    latest_rev = mention.latest_revision
    return ResolveResult.new(status: :no_revisions, tier: nil) unless latest_rev

    # Step 1: Detect raw candidate matches across strong tiers
    raw_t1 = raw_tier1_candidates(mention, latest_rev)
    raw_t2 = raw_tier2_candidates(mention, latest_rev)
    raw_t3 = raw_tier3_candidates(mention, latest_rev)

    # Cross-signal contradiction detection:
    # If distinct strong signals (req ID, clean URL, platform ID) identify different existing postings
    t1_ids = raw_t1.map(&:id)
    t2_ids = raw_t2.map(&:id)
    t3_ids = raw_t3.map(&:id)

    if (raw_t1.any? && raw_t2.any? && (t1_ids & t2_ids).empty?) ||
       (raw_t1.any? && raw_t3.any? && (t1_ids & t3_ids).empty?) ||
       (raw_t2.any? && raw_t3.any? && (t2_ids & t3_ids).empty?)
      all_conflicting_ids = (t1_ids + t2_ids + t3_ids).uniq
      return ResolveResult.new(
        status: :identity_conflict,
        tier: nil,
        conflict_reason: "Cross-signal identity conflict: strong match tiers point to distinct postings: #{all_conflicting_ids.join(', ')}"
      )
    end

    # Contradiction on matched candidate (e.g. matched by URL or Req ID but has conflicting identifiers)
    all_raw = (raw_t1 + raw_t2 + raw_t3).uniq
    all_raw.each do |cand|
      if has_conflicting_identifiers?(mention, latest_rev, cand)
        return ResolveResult.new(
          status: :identity_conflict,
          tier: nil,
          conflict_reason: "Strong candidate #{cand.public_id} has conflicting identifiers with incoming observation"
        )
      end
    end

    # Filtered candidate matches
    tier1_candidates = find_tier1_candidates(mention, latest_rev, raw_t1)
    tier2_candidates = find_tier2_candidates(mention, latest_rev, raw_t2)
    tier3_candidates = find_tier3_candidates(mention, latest_rev, raw_t3)

    strong_candidate_ids = (tier1_candidates + tier2_candidates + tier3_candidates).map(&:id).uniq

    # Conflict check: If surviving strong tiers point to different existing postings
    if strong_candidate_ids.size > 1
      return ResolveResult.new(
        status: :identity_conflict,
        tier: nil,
        conflict_reason: "Strong match tiers point to distinct postings: #{strong_candidate_ids.join(', ')}"
      )
    end

    matched_posting = nil
    matched_tier = nil

    if tier1_candidates.any?
      matched_posting = tier1_candidates.first
      matched_tier = 1
    elsif tier2_candidates.any?
      matched_posting = tier2_candidates.first
      matched_tier = 2
    elsif tier3_candidates.any?
      matched_posting = tier3_candidates.first
      matched_tier = 3
    end

    if matched_posting
      mention.update!(canonical_posting: matched_posting)
      # Only reconcile if posting is not part of an immutable approved release
      FieldReconciler.reconcile!(matched_posting) unless matched_posting.approved_release_id.present?
      check_and_record_potential_duplicates(matched_posting)
      return ResolveResult.new(
        canonical_posting: matched_posting,
        tier: matched_tier,
        status: :resolved,
        potential_duplicates_found: matched_posting.potential_duplicate
      )
    end

    # Step 2: No strong match found -> Create new Canonical Posting
    first_obs = latest_rev.observed_at
    new_posting = CanonicalPosting.create!(
      title: latest_rev.title,
      company: latest_rev.company,
      location: latest_rev.location,
      remote_type: latest_rev.remote_type || "unknown",
      employment_type: latest_rev.employment_type || "unknown",
      salary_min: latest_rev.salary_min,
      salary_max: latest_rev.salary_max,
      salary_currency: latest_rev.salary_currency,
      salary_period: latest_rev.salary_period,
      summary_excerpt: latest_rev.summary_excerpt,
      job_url: latest_rev.job_url,
      first_observed_at: first_obs,
      last_observed_at: first_obs,
      approved_release_id: nil
    )

    mention.update!(canonical_posting: new_posting)
    FieldReconciler.reconcile!(new_posting)

    # Step 3: Check for Tier 4 uncertain similarity (Potential Duplicate)
    check_and_record_potential_duplicates(new_posting)

    ResolveResult.new(
      canonical_posting: new_posting,
      tier: 4,
      status: :resolved,
      potential_duplicates_found: new_posting.potential_duplicate
    )
  end

  private

  def raw_tier1_candidates(mention, rev)
    return [] unless mention.job_id.present? && rev.company.present?
    norm_company = rev.company.strip.downcase
    scope = candidate_posting_scope(mention)

    candidates = SourceMention.joins(:source_revisions)
                              .where.not(id: mention.id)
                              .where.not(canonical_posting_id: nil)
                              .where(job_id: mention.job_id)
                              .where("LOWER(source_revisions.company) = ?", norm_company)
                              .map(&:canonical_posting)
                              .compact
                              .uniq
    candidates.select { |p| scope.where(id: p.id).exists? }
  end

  def raw_tier2_candidates(mention, rev)
    return [] unless rev.job_url.present? && rev.company.present?
    clean_url = Sanitizer.clean_url(rev.job_url)
    return [] unless clean_url.present? && specific_job_url?(clean_url)
    norm_company = rev.company.strip.downcase
    scope = candidate_posting_scope(mention)

    candidates = SourceRevision.joins(:source_mention)
                               .where.not(source_mentions: { id: mention.id })
                               .where.not(source_mentions: { canonical_posting_id: nil })
                               .where(job_url: clean_url)
                               .where("LOWER(source_revisions.company) = ?", norm_company)
                               .map { |r| r.source_mention.canonical_posting }
                               .compact
                               .uniq
    candidates.select { |p| scope.where(id: p.id).exists? }
  end

  def raw_tier3_candidates(mention, rev)
    return [] unless mention.source_domain.present? && mention.job_id.present? && rev.company.present?
    # QA5-03: Platform key must be vetted before treating as strong candidate
    return [] unless vetted_platform_key?(mention, rev)

    norm_company = rev.company.strip.downcase
    scope = candidate_posting_scope(mention)

    candidates = SourceMention.joins(:source_revisions)
                              .where.not(id: mention.id)
                              .where.not(canonical_posting_id: nil)
                              .where(source_domain: mention.source_domain, job_id: mention.job_id)
                              .where("LOWER(source_revisions.company) = ?", norm_company)
                              .map(&:canonical_posting)
                              .compact
                              .uniq
    candidates.select { |p| scope.where(id: p.id).exists? }
  end

  # Tier 1 (strong): Same verified employer identity and employer requisition ID
  def find_tier1_candidates(mention, rev, raw_candidates = nil)
    candidates = raw_candidates || raw_tier1_candidates(mention, rev)
    return [] if candidates.empty?

    # QA4-02: Verified employer requisition authority required on at least one side
    mention_is_official = SourceAuthority.verified_official?(mention, rev.company)

    candidates.select do |p|
      (mention_is_official || p.source_mentions.any? { |sm| SourceAuthority.verified_official?(sm, p.company) }) &&
        !has_conflicting_identifiers?(mention, rev, p)
    end
  end

  # Tier 2 (strong): Same canonicalized approved employer-host job URL + same employer
  def find_tier2_candidates(mention, rev, raw_candidates = nil)
    candidates = raw_candidates || raw_tier2_candidates(mention, rev)
    return [] if candidates.empty?

    clean_url = Sanitizer.clean_url(rev.job_url)
    candidates.select do |p|
      !has_conflicting_identifiers?(mention, rev, p) &&
        tier2_strong_match?(mention, rev, p, clean_url)
    end
  end

  # Tier 3 (strong, source-scoped): Same stable platform posting ID on same vetted platform + same employer
  def find_tier3_candidates(mention, rev, raw_candidates = nil)
    candidates = raw_candidates || raw_tier3_candidates(mention, rev)
    return [] if candidates.empty?
    return [] unless vetted_platform_key?(mention, rev)

    candidates.select do |p|
      p.source_mentions.any? { |sm| vetted_platform_key?(sm, rev) } &&
        !tier3_incompatible?(rev, p) &&
        !has_conflicting_identifiers?(mention, rev, p)
    end
  end

  def vetted_platform_key?(mention, rev)
    return false if mention.source_domain.blank? || mention.job_id.blank?

    norm_company = rev.company.to_s.strip.downcase
    dom = mention.source_domain.to_s.strip.downcase
    sys = mention.source_record&.source_system.to_s.strip.downcase

    # 1. Recognized ATS domain host or subdomain
    is_vetted_ats_domain = VETTED_ATS_DOMAINS.any? do |ats_dom|
      dom == ats_dom || dom.end_with?(".#{ats_dom}")
    end
    return true if is_vetted_ats_domain

    # 2. Operator-reviewed verified employer domain for this employer
    verified_domains = SourceAuthority.verified_domains_map[norm_company] || []
    return true if verified_domains.include?(dom)

    # 3. Trusted ATS / direct employer ingestion system
    return true if SourceAuthority::TRUSTED_SYSTEMS.include?(sys)

    false
  end

  def tier3_incompatible?(rev, candidate_posting)
    norm_rev_title = normalize_title_for_comparison(rev.title)
    norm_cand_title = normalize_title_for_comparison(candidate_posting.title)
    titles_diverge = norm_rev_title.present? && norm_cand_title.present? && norm_rev_title != norm_cand_title

    norm_rev_loc = rev.location.to_s.strip.downcase
    norm_cand_loc = candidate_posting.location.to_s.strip.downcase
    locs_diverge = norm_rev_loc.present? && norm_cand_loc.present? && norm_rev_loc != norm_cand_loc

    # Differing title AND differing location indicate completely separate roles
    return true if titles_diverge && locs_diverge

    # Incompatible titles with no overlapping words
    if titles_diverge
      rev_words = norm_rev_title.split
      cand_words = norm_cand_title.split
      return true if (rev_words & cand_words).empty?
    end

    false
  end

  def candidate_posting_scope(mention)
    if mention.source_record&.approved_release_id.present?
      CanonicalPosting.where(approved_release_id: mention.source_record.approved_release_id)
    else
      CanonicalPosting.where(approved_release_id: nil)
    end
  end

  def has_conflicting_identifiers?(mention, rev, candidate_posting)
    norm_company = rev.company.to_s.strip.downcase

    # 1. Employer identity mismatch
    return true if candidate_posting.company.to_s.strip.downcase != norm_company

    # 2. Conflicting requisition IDs
    cand_job_ids = candidate_posting.source_mentions.pluck(:job_id).compact.map(&:strip).reject(&:empty?).uniq
    if mention.job_id.present? && cand_job_ids.any?
      return true unless cand_job_ids.include?(mention.job_id.strip)
    end

    # 3. Conflicting employer job URLs (if on the same host with different specific paths)
    clean_url = Sanitizer.clean_url(rev.job_url)
    if clean_url.present? && specific_job_url?(clean_url)
      host_a = URI.parse(clean_url).host.to_s.downcase rescue nil
      cand_urls = candidate_posting.source_revisions.pluck(:job_url).compact.map { |u| Sanitizer.clean_url(u) }.reject(&:blank?).uniq
      cand_urls.each do |cand_url|
        next unless specific_job_url?(cand_url)
        host_b = URI.parse(cand_url).host.to_s.downcase rescue nil
        if host_a.present? && host_b.present? && host_a == host_b && clean_url != cand_url
          return true
        end
      end
    end

    false
  end

  def tier2_strong_match?(mention, rev, candidate_posting, clean_url)
    cand_job_ids = candidate_posting.source_mentions.pluck(:job_id).compact.map(&:strip).reject(&:empty?).uniq
    has_shared_req = mention.job_id.present? && cand_job_ids.include?(mention.job_id.strip)

    # If they share an explicit verified job requisition ID, title/location variants may merge
    return true if has_shared_req

    # Without a shared explicit requisition ID:
    # 1. Titles MUST match exactly
    norm_rev_title = normalize_title_for_comparison(rev.title)
    norm_cand_title = normalize_title_for_comparison(candidate_posting.title)
    return false if norm_rev_title != norm_cand_title

    # 2. Locations MUST match exactly (differing locations indicate distinct openings)
    norm_rev_loc = rev.location.to_s.strip.downcase
    norm_cand_loc = candidate_posting.location.to_s.strip.downcase
    return false if norm_rev_loc.present? && norm_cand_loc.present? && norm_rev_loc != norm_cand_loc

    # 3. URL must be a vetted specific job listing pattern (not a department landing page or shared role page)
    return false unless vetted_job_url_pattern?(clean_url)

    true
  end

  def vetted_job_url_pattern?(url)
    return false unless specific_job_url?(url)
    uri = URI.parse(url) rescue nil
    return false unless uri

    path = uri.path.to_s.sub(/\/$/, "").downcase

    # Reject department / team / category / organization landing pages
    department_keywords = %w[
      departments teams groups categories divisions business-units
      engineering product design sales marketing finance legal operations people hr
    ]
    path_segments = path.split("/").reject(&:blank?)

    return false if (path_segments & %w[departments teams groups categories divisions business-units roles]).any?
    return false if path_segments.length == 1 && department_keywords.include?(path_segments.first)
    return false if path_segments.length == 2 && %w[careers jobs openings positions].include?(path_segments.first) &&
                    %w[engineering product design sales marketing finance legal operations people hr all general].include?(path_segments.second)

    true
  end

  def normalize_title_for_comparison(title)
    title.to_s.strip.downcase.gsub(/[^a-z0-9]/, " ").squeeze(" ")
  end

  def specific_job_url?(url)
    return false unless url.present?
    uri = URI.parse(url) rescue nil
    return false unless uri

    path = uri.path.to_s.sub(/\/$/, "").downcase
    return false if path.blank?

    generic_prefixes = %w[
      / /jobs /careers /search /openings /positions /work-with-us /join-us /all-jobs
      /openings/all /careers/all /jobs/all /positions/all
      /openings/list /careers/list /jobs/list /positions/list
      /engineering/careers /tech/careers
    ]
    return false if generic_prefixes.include?(path)
    return false if path.end_with?("/all") || path.end_with?("/list")

    true
  rescue URI::InvalidURIError
    false
  end

  def check_and_record_potential_duplicates(posting)
    posting.reload if posting.persisted?
    norm_company = posting.company.strip.downcase
    norm_title = normalize_title_for_comparison(posting.title)
    norm_loc = posting.location.strip.downcase

    # Check 1: Same company & shared job_url (where strong Tier 2 merge was not performed)
    posting_urls = posting.source_revisions.pluck(:job_url).compact.map { |u| Sanitizer.clean_url(u) }.reject(&:blank?).uniq
    if posting_urls.any?
      url_postings = CanonicalPosting.joins(source_mentions: :source_revisions)
                                     .where.not(id: posting.id)
                                     .where("LOWER(canonical_postings.company) = ?", norm_company)
                                     .where(source_revisions: { job_url: posting_urls })
                                     .distinct
      url_postings.find_each do |other|
        other_title = normalize_title_for_comparison(other.title)
        other_loc = other.location.strip.downcase

        reason = if norm_title != other_title
          "shared_url_differing_titles"
        elsif norm_loc != other_loc
          "shared_url_differing_locations"
        else
          "shared_url_ambiguous_role_page"
        end

        PotentialDuplicate.record_pair!(
          posting,
          other,
          reason_code: reason,
          evaluation_digest: "tier4-shared-url-divergent"
        )
      end
    end

    # Check 2: Similar company & title/location without strong ID
    similar_postings = CanonicalPosting.where.not(id: posting.id)
                                       .where("LOWER(company) = ?", norm_company)
                                       .where("LOWER(title) = ? OR LOWER(location) = ?", posting.title.strip.downcase, norm_loc)

    similar_postings.find_each do |other|
      shared_job_ids = (posting.source_mentions.pluck(:job_id) & other.source_mentions.pluck(:job_id)).compact.reject(&:empty?)
      if shared_job_ids.empty?
        a_id, b_id = [posting.id, other.id].sort
        existing = PotentialDuplicate.find_by(posting_a_id: a_id, posting_b_id: b_id)
        unless existing&.reason_code&.start_with?("shared_url_")
          PotentialDuplicate.record_pair!(
            posting,
            other,
            reason_code: "similar_company_title_location",
            evaluation_digest: "tier4-uncertain-match"
          )
        end
      end
    end

    # Check 3: Same company & shared unverified job_id (where Tier 1 merge was withheld)
    posting_job_ids = posting.source_mentions.pluck(:job_id).compact.map(&:strip).reject(&:empty?)
    if posting_job_ids.any?
      shared_id_postings = CanonicalPosting.joins(:source_mentions)
                                           .where.not(id: posting.id)
                                           .where("LOWER(canonical_postings.company) = ?", norm_company)
                                           .where(source_mentions: { job_id: posting_job_ids })
                                           .distinct
      shared_id_postings.find_each do |other|
        a_id, b_id = [posting.id, other.id].sort
        existing = PotentialDuplicate.find_by(posting_a_id: a_id, posting_b_id: b_id)
        unless existing
          PotentialDuplicate.record_pair!(
            posting,
            other,
            reason_code: "unverified_shared_job_id",
            evaluation_digest: "tier4-unverified-id-overlap"
          )
        end
      end
    end
  end
end
