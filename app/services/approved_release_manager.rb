class ApprovedReleaseManager
  PublishResult = Struct.new(:success, :approved_release, :corpus_revision, :postings_count, :errors, keyword_init: true)

  def self.publish_files!(batch_file_path, manifest_file_path)
    batch_content = File.read(batch_file_path, encoding: "UTF-8")
    manifest_content = File.read(manifest_file_path, encoding: "UTF-8")
    new.publish!(batch_content, manifest_content)
  end

  def self.current_revision
    active = ApprovedRelease.active.first
    return nil unless active

    Digest::SHA256.hexdigest("#{active.manifest_digest}|#{active.corpus_version}|#{CanonicalPosting.active_approved.count}|#{active.authority_fingerprint}")
  end

  def publish!(batch_content, manifest_content)
    # Step 1: Strict release gate validation
    gate_result = ReleaseGate.evaluate(batch_content, manifest_content)
    unless gate_result.approved
      return PublishResult.new(
        success: false,
        approved_release: nil,
        corpus_revision: nil,
        postings_count: 0,
        errors: gate_result.errors
      )
    end

    manifest = gate_result.manifest

    # Step 2: Atomic transaction to import, resolve, reconcile, and activate
    ActiveRecord::Base.transaction do
      # Ingest batch
      import_report = BatchImporter.import_string(batch_content)
      if import_report.status != "complete"
        raise "Release publication rejected: candidate batch must import with complete status; got '#{import_report.status}' (#{import_report.invalid_count} invalid items)"
      end

      # Find or create ApprovedRelease record
      release = ApprovedRelease.find_or_initialize_by(manifest_digest: manifest["candidate_digest"])
      release.assign_attributes(
        approval_signature: manifest["approval_signature"],
        approved_by: manifest["approved_by"],
        approved_at: Time.iso8601(manifest["approved_at"]),
        corpus_version: manifest["corpus_version"],
        total_items: manifest["total_items"],
        origin_class_counts: manifest["origin_class_counts"] || {},
        authority_fingerprint: SourceAuthority.authority_fingerprint
      )
      release.save!

      # Associate SourceRecords from this batch with the release using [source_system, source_record_key]
      pairs = import_report_pairs(batch_content)
      pairs.each do |sys, key|
        SourceRecord.where(source_system: sys, source_record_key: key)
                    .update_all(approved_release_id: release.id)
      end

      # Explicitly bind approved release to exact SourceRevisions and record snapshot metadata
      parsed_batch = SourceBatchParser.parse_string(batch_content)
      parsed_batch.valid_items.each do |item|
        rec = SourceRecord.find_by(source_system: item["source_system"], source_record_key: item["source_record_key"])
        next unless rec

        mention = rec.source_mentions.find_by(mention_key: item["mention_key"])
        next unless mention

        digest = SourceRevision.compute_digest(item)
        rev = mention.source_revisions.find_by(revision_digest: digest)
        next unless rev

        app_rev = release.approved_release_revisions.find_or_initialize_by(source_revision_id: rev.id)
        app_rev.snapshot_source_domain = item["source_domain"]
        app_rev.snapshot_job_id = item["job_id"]
        app_rev.snapshot_origin_class = item["origin_class"] || rec.origin_class
        app_rev.save!
      end

      # Associate CanonicalPostings containing the approved revisions with the release
      posting_ids = CanonicalPosting.joins(source_mentions: { source_revisions: :approved_release_revisions })
                                     .where(approved_release_revisions: { approved_release_id: release.id })
                                     .distinct
                                     .pluck(:id)

      CanonicalPosting.where(id: posting_ids).update_all(approved_release_id: release.id)
      postings = CanonicalPosting.where(id: posting_ids)

      # Reconcile fields for all associated postings using approved revisions
      postings.find_each do |p|
        FieldReconciler.reconcile!(p)
      end

      # Activate this release (atomically deactivating previous)
      release.activate!

      corpus_rev = self.class.current_revision

      PublishResult.new(
        success: true,
        approved_release: release,
        corpus_revision: corpus_rev,
        postings_count: postings.count,
        errors: []
      )
    end
  rescue StandardError => e
    PublishResult.new(
      success: false,
      approved_release: nil,
      corpus_revision: nil,
      postings_count: 0,
      errors: [e.message]
    )
  end

  private

  def import_report_pairs(batch_content)
    data = JSON.parse(batch_content)
    data["items"].map { |i| [i["source_system"], i["source_record_key"]] }.uniq
  rescue StandardError
    []
  end
end
