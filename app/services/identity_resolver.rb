# frozen_string_literal: true

require "uri"

class IdentityResolver
  ResolveResult = Struct.new(:canonical_posting, :tier, :status, :potential_duplicates_found, :conflict_reason, keyword_init: true)

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

    # Step 1: Detect candidate matches across strong tiers
    tier1_candidates = find_tier1_candidates(mention, latest_rev)
    tier2_candidates = find_tier2_candidates(mention, latest_rev)
    tier3_candidates = find_tier3_candidates(mention, latest_rev)

    strong_candidate_ids = (tier1_candidates + tier2_candidates + tier3_candidates).map(&:id).uniq

    # Conflict check: If strong tiers point to different existing postings
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
      approved_release_id: mention.source_record&.approved_release_id
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

  # Tier 1 (strong): Same verified employer identity and employer requisition ID
  def find_tier1_candidates(mention, rev)
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

    candidates.select { |p| scope.where(id: p.id).exists? && !has_conflicting_identifiers?(mention, rev, p) }
  end

  # Tier 2 (strong): Same canonicalized approved employer-host job URL + same employer
  def find_tier2_candidates(mention, rev)
    return [] unless rev.job_url.present? && rev.company.present?

    clean_url = Sanitizer.clean_url(rev.job_url)
    return [] unless clean_url.present? && specific_job_url?(clean_url)

    scope = candidate_posting_scope(mention)
    candidates = SourceRevision.joins(:source_mention)
                               .where.not(source_mentions: { id: mention.id })
                               .where.not(source_mentions: { canonical_posting_id: nil })
                               .where(job_url: clean_url)
                               .map { |r| r.source_mention.canonical_posting }
                               .compact
                               .uniq

    candidates.select do |p|
      scope.where(id: p.id).exists? &&
        !has_conflicting_identifiers?(mention, rev, p) &&
        tier2_compatible_titles_or_requisition?(mention, rev, p)
    end
  end

  # Tier 3 (strong, source-scoped): Same stable platform posting ID on same vetted platform + same employer
  def find_tier3_candidates(mention, rev)
    return [] unless mention.source_domain.present? && mention.job_id.present? && rev.company.present?

    scope = candidate_posting_scope(mention)
    candidates = SourceMention.where.not(id: mention.id)
                              .where.not(canonical_posting_id: nil)
                              .where(source_domain: mention.source_domain, job_id: mention.job_id)
                              .map(&:canonical_posting)
                              .compact
                              .uniq

    candidates.select { |p| scope.where(id: p.id).exists? && !has_conflicting_identifiers?(mention, rev, p) }
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

  def tier2_compatible_titles_or_requisition?(mention, rev, candidate_posting)
    cand_job_ids = candidate_posting.source_mentions.pluck(:job_id).compact.map(&:strip).reject(&:empty?).uniq
    # If they share an explicit verified job requisition ID, titles may vary (e.g. level prefix)
    if mention.job_id.present? && cand_job_ids.include?(mention.job_id.strip)
      return true
    end

    # Without a shared explicit requisition ID, titles MUST match
    norm_rev_title = normalize_title_for_comparison(rev.title)
    norm_cand_title = normalize_title_for_comparison(candidate_posting.title)

    norm_rev_title == norm_cand_title
  end

  def normalize_title_for_comparison(title)
    title.to_s.strip.downcase.gsub(/[^a-z0-9]/, " ").squeeze(" ")
  end

  def specific_job_url?(url)
    return false unless url.present?
    uri = URI.parse(url)
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
    norm_title = posting.title.strip.downcase

    # Check 1: Same company & shared job_url but differing titles (prevented Tier 2 merge)
    posting_urls = posting.source_revisions.pluck(:job_url).compact.map { |u| Sanitizer.clean_url(u) }.reject(&:blank?).uniq
    if posting_urls.any?
      url_postings = CanonicalPosting.joins(source_mentions: :source_revisions)
                                     .where.not(id: posting.id)
                                     .where("LOWER(canonical_postings.company) = ?", norm_company)
                                     .where(source_revisions: { job_url: posting_urls })
                                     .distinct
      url_postings.find_each do |other|
        PotentialDuplicate.record_pair!(
          posting,
          other,
          reason_code: "shared_url_differing_titles",
          evaluation_digest: "tier4-shared-url-divergent"
        )
      end
    end

    # Check 2: Similar company & title/location without strong ID
    similar_postings = CanonicalPosting.where.not(id: posting.id)
                                       .where("LOWER(company) = ?", norm_company)
                                       .where("LOWER(title) = ? OR LOWER(location) = ?", norm_title, posting.location.strip.downcase)

    similar_postings.find_each do |other|
      # Verify they don't share a strong key
      shared_job_ids = (posting.source_mentions.pluck(:job_id) & other.source_mentions.pluck(:job_id)).compact.reject(&:empty?)
      if shared_job_ids.empty?
        a_id, b_id = [posting.id, other.id].sort
        existing = PotentialDuplicate.find_by(posting_a_id: a_id, posting_b_id: b_id)
        unless existing&.reason_code == "shared_url_differing_titles"
          PotentialDuplicate.record_pair!(
            posting,
            other,
            reason_code: "similar_company_title_location",
            evaluation_digest: "tier4-uncertain-match"
          )
        end
      end
    end
  end
end
