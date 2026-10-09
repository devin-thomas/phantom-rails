require "digest"

class BatchImporter
  ImportReport = Struct.new(
    :import_run_id,
    :batch_id,
    :status,
    :total_input,
    :inserted_count,
    :updated_count,
    :unchanged_count,
    :invalid_count,
    :errors,
    keyword_init: true
  )

  def self.import_file(file_path)
    content = File.read(file_path, encoding: "UTF-8")
    format = file_path.to_s.end_with?(".jsonl") ? :jsonl : :json
    new.import(content, format: format)
  end

  def self.import_string(content, format: :auto)
    new.import(content, format: format)
  end

  def import(content, format: :auto)
    batch_digest = Digest::SHA256.hexdigest(content.to_s.strip)
    started_at = Time.now.utc

    parsed = SourceBatchParser.parse_string(content, format: format)

    unless parsed.success
      run = ImportRun.create!(
        batch_id: parsed.batch_id || "unknown-batch",
        batch_digest: batch_digest,
        origin_class: parsed.origin_class || "unknown",
        status: "failed",
        total_input: 0,
        inserted_count: 0,
        updated_count: 0,
        unchanged_count: 0,
        invalid_count: parsed.batch_errors.size,
        started_at: started_at,
        completed_at: Time.now.utc
      )

      parsed.batch_errors.each_with_index do |err, idx|
        run.import_errors.create!(
          item_index: idx,
          item_identifier: "batch-envelope",
          error_code: err[:code],
          error_message: err[:message]
        )
      end

      return ImportReport.new(
        import_run_id: run.id,
        batch_id: run.batch_id,
        status: run.status,
        total_input: 0,
        inserted_count: 0,
        updated_count: 0,
        unchanged_count: 0,
        invalid_count: parsed.batch_errors.size,
        errors: parsed.batch_errors
      )
    end

    total_input = parsed.valid_items.size + parsed.invalid_items.size

    run = ImportRun.create!(
      batch_id: parsed.batch_id,
      batch_digest: batch_digest,
      origin_class: parsed.origin_class,
      status: "pending",
      total_input: total_input,
      started_at: started_at
    )

    inserted = 0
    updated = 0
    unchanged = 0
    invalid_errors = []

    # Check for in-batch key conflicts: same (source_system, source_record_key, mention_key) with conflicting revisions
    grouped = parsed.valid_items.group_by { |i| [i["source_system"], i["source_record_key"], i["mention_key"]] }
    executable_items = []

    grouped.each do |key, items_for_key|
      if items_for_key.size > 1
        digests = items_for_key.map { |i| SourceRevision.compute_digest(i) }.uniq
        if digests.size > 1
          # Ambiguous revision order in unordered batch: quarantine all items for this key
          items_for_key.each_with_index do |item, offset|
            invalid_errors << {
              item_index: item["_batch_index"] || parsed.valid_items.index(item),
              item_identifier: "#{item['source_record_key']}/#{item['mention_key']}",
              error_code: "ambiguous_revision_order",
              error_message: "Conflicting revisions for same mention key within single unordered batch"
            }
          end
          next
        else
          # Identical duplicate observations in same batch: count duplicates as unchanged
          unchanged += (items_for_key.size - 1)
        end
      end
      # Keep single item
      executable_items << items_for_key.first
    end

    # Record errors from parser
    parsed.invalid_items.each do |inv|
      inv[:errors].each do |err|
        invalid_errors << {
          item_index: inv[:index],
          item_identifier: inv[:item_identifier],
          error_code: err[:code],
          error_message: err[:message]
        }
      end
    end

    # Process valid items transactionally
    executable_items.each do |raw_item|
      item = Sanitizer.sanitize_item(raw_item)
      ActiveRecord::Base.transaction(requires_new: true) do
        rec = SourceRecord.find_or_create_by!(
          source_system: item["source_system"],
          source_record_key: item["source_record_key"]
        ) do |r|
          r.origin_class = item["origin_class"]
        end

        mention = SourceMention.find_or_create_by!(
          source_record: rec,
          mention_key: item["mention_key"]
        ) do |m|
          m.source_kind = item["source_kind"]
          m.source_domain = item["source_domain"]
          m.job_id = item["job_id"]
        end

        # Update metadata if newer and not part of an approved posting
        unless mention.canonical_posting&.approved_release_id.present?
          mention.update!(source_domain: item["source_domain"], job_id: item["job_id"]) if item["job_id"].present?
        end

        rev_digest = SourceRevision.compute_digest(item)
        existing_rev = mention.source_revisions.find_by(revision_digest: rev_digest)

        if existing_rev
          unchanged += 1
        else
          is_first = mention.source_revisions.empty?

          mention.source_revisions.create!(
            revision_digest: rev_digest,
            observed_at: Time.iso8601(item["observed_at"]),
            posted_at: item["posted_at"] ? Time.iso8601(item["posted_at"]) : nil,
            title: item["title"],
            company: item["company"],
            location: item["location"],
            remote_type: item["remote_type"],
            employment_type: item["employment_type"],
            salary_min: item.dig("salary", "min"),
            salary_max: item.dig("salary", "max"),
            salary_currency: item.dig("salary", "currency"),
            salary_period: item.dig("salary", "period"),
            summary_excerpt: item["summary_excerpt"],
            job_url: item["job_url"],
            raw_safe_fields: item
          )

          if is_first
            inserted += 1
          else
            updated += 1
          end

          # Resolve canonical posting identity deterministically for new or updated revisions
          IdentityResolver.resolve_mention(mention)
        end
      end
    rescue StandardError => e
      idx = raw_item["_batch_index"] || -1
      ident = item ? "#{item['source_record_key']}/#{item['mention_key']}" : "#{raw_item['source_record_key']}/#{raw_item['mention_key']}"
      invalid_errors << {
        item_index: idx,
        item_identifier: ident,
        error_code: "item_persistence_error",
        error_message: e.message
      }
    end

    invalid_item_indices = invalid_errors.map { |e| e[:item_index] }.uniq
    invalid_count = invalid_item_indices.size

    final_status = if invalid_count == 0
      "complete"
    elsif (inserted + updated + unchanged) > 0
      "partial"
    else
      "failed"
    end

    # Record errors in DB
    invalid_errors.each do |err|
      run.import_errors.create!(
        item_index: err[:item_index],
        item_identifier: err[:item_identifier],
        error_code: err[:error_code],
        error_message: err[:error_message]
      )
    end

    run.update!(
      status: final_status,
      inserted_count: inserted,
      updated_count: updated,
      unchanged_count: unchanged,
      invalid_count: invalid_count,
      completed_at: Time.now.utc
    )

    ImportReport.new(
      import_run_id: run.id,
      batch_id: run.batch_id,
      status: final_status,
      total_input: total_input,
      inserted_count: inserted,
      updated_count: updated,
      unchanged_count: unchanged,
      invalid_count: invalid_count,
      errors: invalid_errors
    )
  end
end
