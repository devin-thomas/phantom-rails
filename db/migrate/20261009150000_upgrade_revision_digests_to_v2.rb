class UpgradeRevisionDigestsToV2 < ActiveRecord::Migration[8.1]
  def up
    add_column :source_revisions, :digest_version, :string, default: "v2" unless column_exists?(:source_revisions, :digest_version)

    # Recompute canonical v2 digests for any existing revisions
    SourceRevision.reset_column_information
    SourceRevision.includes(source_mention: :source_record).find_each do |rev|
      sm = rev.source_mention
      sr = sm&.source_record

      attrs = {
        "source_system" => sr&.source_system,
        "source_record_key" => sr&.source_record_key,
        "mention_key" => sm&.mention_key,
        "origin_class" => sr&.origin_class,
        "source_kind" => sm&.source_kind,
        "source_domain" => sm&.source_domain,
        "job_id" => sm&.job_id,
        "observed_at" => rev.observed_at&.iso8601,
        "posted_at" => rev.posted_at&.iso8601,
        "title" => rev.title,
        "company" => rev.company,
        "location" => rev.location,
        "remote_type" => rev.remote_type,
        "employment_type" => rev.employment_type,
        "salary_min" => rev.salary_min,
        "salary_max" => rev.salary_max,
        "salary_currency" => rev.salary_currency,
        "salary_period" => rev.salary_period,
        "summary_excerpt" => rev.summary_excerpt,
        "job_url" => rev.job_url
      }

      v2_digest = SourceRevision.compute_digest(attrs, version: "v2")

      existing = SourceRevision.where(source_mention_id: rev.source_mention_id, revision_digest: v2_digest).where.not(id: rev.id).first
      if existing
        # Re-point foreign keys and collapse duplicate row safely
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
        rev.update_columns(revision_digest: v2_digest, digest_version: "v2")
      end
    end
  end

  def down
    remove_column :source_revisions, :digest_version if column_exists?(:source_revisions, :digest_version)
  end
end
