class UpgradeRevisionDigestsToV2 < ActiveRecord::Migration[8.1]
  def up
    add_column :source_revisions, :digest_version, :string, default: "v2" unless column_exists?(:source_revisions, :digest_version)

    # Recompute canonical v2 digests for any existing revisions
    SourceRevision.reset_column_information
    SourceRevision.includes(source_mention: :source_record).find_each do |rev|
      sm = rev.source_mention
      sr = sm&.source_record
      raw = rev.raw_safe_fields.is_a?(Hash) ? rev.raw_safe_fields : {}

      # QA5-06: Prefer per-revision historical raw_safe_fields for original metadata
      origin_class = raw["origin_class"].presence || sr&.origin_class
      source_domain = raw["source_domain"].presence || sm&.source_domain
      job_id = raw["job_id"].presence || sm&.job_id
      source_kind = raw["source_kind"].presence || sm&.source_kind
      source_system = raw["source_system"].presence || sr&.source_system
      source_record_key = raw["source_record_key"].presence || sr&.source_record_key
      mention_key = raw["mention_key"].presence || sm&.mention_key

      # Reconcile discrepancies deterministically and maintain audit trail
      if sm && raw["source_domain"].present? && sm.source_domain != raw["source_domain"]
        Rails.logger.info("UpgradeRevisionDigestsToV2: Reconciling mention #{sm.id} source_domain '#{sm.source_domain}' -> '#{raw['source_domain']}'")
        sm.update_columns(source_domain: raw["source_domain"])
      end
      if sm && raw["job_id"].present? && sm.job_id != raw["job_id"]
        Rails.logger.info("UpgradeRevisionDigestsToV2: Reconciling mention #{sm.id} job_id '#{sm.job_id}' -> '#{raw['job_id']}'")
        sm.update_columns(job_id: raw["job_id"])
      end
      if sr && raw["origin_class"].present? && sr.origin_class != raw["origin_class"]
        Rails.logger.info("UpgradeRevisionDigestsToV2: Reconciling record #{sr.id} origin_class '#{sr.origin_class}' -> '#{raw['origin_class']}'")
        sr.update_columns(origin_class: raw["origin_class"])
      end

      attrs = {
        "source_system" => source_system,
        "source_record_key" => source_record_key,
        "mention_key" => mention_key,
        "origin_class" => origin_class,
        "source_kind" => source_kind,
        "source_domain" => source_domain,
        "job_id" => job_id,
        "observed_at" => raw["observed_at"].presence || rev.observed_at&.iso8601,
        "posted_at" => raw["posted_at"].presence || rev.posted_at&.iso8601,
        "title" => raw["title"].presence || rev.title,
        "company" => raw["company"].presence || rev.company,
        "location" => raw["location"].presence || rev.location,
        "remote_type" => raw["remote_type"].presence || rev.remote_type.presence || "unknown",
        "employment_type" => raw["employment_type"].presence || rev.employment_type.presence || "unknown",
        "salary_min" => raw.dig("salary", "min") || rev.salary_min,
        "salary_max" => raw.dig("salary", "max") || rev.salary_max,
        "salary_currency" => raw.dig("salary", "currency") || rev.salary_currency,
        "salary_period" => raw.dig("salary", "period") || rev.salary_period,
        "summary_excerpt" => raw["summary_excerpt"].presence || rev.summary_excerpt,
        "job_url" => raw["job_url"].presence || rev.job_url
      }

      v2_digest = SourceRevision.compute_digest(attrs, version: "v2")

      existing = SourceRevision.where(source_mention_id: rev.source_mention_id, revision_digest: v2_digest).where.not(id: rev.id).first
      if existing
        # Re-point foreign keys and collapse duplicate row safely
        Rails.logger.info("UpgradeRevisionDigestsToV2: Collapsing duplicate revision #{rev.id} into #{existing.id} for digest #{v2_digest}")
        ApprovedReleaseRevision.where(source_revision_id: rev.id).find_each do |arr|
          if ApprovedReleaseRevision.where(approved_release_id: arr.approved_release_id, source_revision_id: existing.id).exists?
            arr.destroy
          else
            arr.update_columns(source_revision_id: existing.id)
          end
        end

        FieldSelection.where(source_revision_id: rev.id).find_each do |fs|
          if FieldSelection.where(canonical_posting_id: fs.canonical_posting_id, field_name: fs.field_name).where.not(id: fs.id).exists?
            fs.destroy
          else
            fs.update_columns(source_revision_id: existing.id)
          end
        end

        rev.destroy
      else
        Rails.logger.info("UpgradeRevisionDigestsToV2: Upgraded revision #{rev.id} to v2 digest #{v2_digest}")
        rev.update_columns(revision_digest: v2_digest, digest_version: "v2")
      end
    end
  end

  def down
    remove_column :source_revisions, :digest_version if column_exists?(:source_revisions, :digest_version)
  end
end
