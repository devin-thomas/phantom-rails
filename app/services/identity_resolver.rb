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
      FieldReconciler.reconcile!(matched_posting)
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
      last_observed_at: first_obs
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

    # Find postings that have an official employer mention with same job_id and company
    SourceMention.joins(:source_revisions)
                 .where.not(id: mention.id)
                 .where.not(canonical_posting_id: nil)
                 .where(source_kind: "official_employer", job_id: mention.job_id)
                 .where("LOWER(source_revisions.company) = ?", rev.company.strip.downcase)
                 .map(&:canonical_posting)
                 .compact
                 .uniq
  end

  # Tier 2 (strong): Same canonicalized approved employer-host job URL
  def find_tier2_candidates(mention, rev)
    return [] unless rev.job_url.present?

    clean_url = Sanitizer.clean_url(rev.job_url)
    return [] unless clean_url.present?

    SourceRevision.joins(:source_mention)
                  .where.not(source_mentions: { id: mention.id })
                  .where.not(source_mentions: { canonical_posting_id: nil })
                  .where(job_url: clean_url)
                  .map { |r| r.source_mention.canonical_posting }
                  .compact
                  .uniq
  end

  # Tier 3 (strong, source-scoped): Same stable platform posting ID on same vetted platform
  def find_tier3_candidates(mention, _rev)
    return [] unless mention.source_domain.present? && mention.job_id.present?

    SourceMention.where.not(id: mention.id)
                 .where.not(canonical_posting_id: nil)
                 .where(source_domain: mention.source_domain, job_id: mention.job_id)
                 .map(&:canonical_posting)
                 .compact
                 .uniq
  end

  # Tier 4 (uncertain): Similar company & title without strong ID -> Record Potential Duplicate
  def check_and_record_potential_duplicates(posting)
    norm_company = posting.company.strip.downcase
    norm_title = posting.title.strip.downcase

    similar_postings = CanonicalPosting.where.not(id: posting.id)
                                       .where("LOWER(company) = ?", norm_company)
                                       .where("LOWER(title) = ? OR LOWER(location) = ?", norm_title, posting.location.strip.downcase)

    similar_postings.find_each do |other|
      # Verify they don't share a strong key
      shared_job_ids = (posting.source_mentions.pluck(:job_id) & other.source_mentions.pluck(:job_id)).compact.reject(&:empty?)
      if shared_job_ids.empty?
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
