namespace :phantom do
  desc "Import a versioned batch file (JSON or JSONL) into the relational store"
  task :import, [:file_path] => :environment do |_t, args|
    file_path = args[:file_path]
    unless file_path.present? && File.exist?(file_path)
      puts "Usage: bin/rails phantom:import[path/to/batch.json]"
      exit 1
    end

    report = BatchImporter.import_file(file_path)

    puts "Import Run ##{report.import_run_id} finished."
    puts "Batch ID:        #{report.batch_id}"
    puts "Status:          #{report.status.upcase}"
    puts "Total Input:     #{report.total_input}"
    puts "Inserted:        #{report.inserted_count}"
    puts "Updated:         #{report.updated_count}"
    puts "Unchanged:       #{report.unchanged_count}"
    puts "Invalid:         #{report.invalid_count}"

    if report.errors.any?
      puts "\nIsolated Errors (#{report.errors.size}):"
      report.errors.each do |err|
        puts "  - [Item #{err[:item_index]} / #{err[:item_identifier]}] #{err[:error_code]}: #{err[:error_message]}"
      end
    end

    exit(report.status == "failed" ? 1 : 0)
  end

  desc "Publish an approved release candidate with signed manifest"
  task :publish, [:batch_file, :manifest_file] => :environment do |_t, args|
    batch_file = args[:batch_file] || Rails.root.join("fixtures", "public-approved", "approved-batch-v1.json")
    manifest_file = args[:manifest_file] || Rails.root.join("fixtures", "public-approved", "approved-manifest-v1.json")

    res = ApprovedReleaseManager.publish_files!(batch_file, manifest_file)
    if res.success
      puts "Successfully published Approved Release ##{res.approved_release.id}"
      puts "Corpus Revision:  #{res.corpus_revision}"
      puts "Active Postings:  #{res.postings_count}"
      exit 0
    else
      puts "Failed to publish release:"
      res.errors.each { |e| puts "  - #{e}" }
      exit 1
    end
  end

  desc "Display audit history of all import runs"
  task history: :environment do
    runs = ImportRun.history_summary
    if runs.empty?
      puts "No import runs recorded yet."
      exit 0
    end

    puts sprintf("%-4s %-28s %-10s %-8s %-8s %-8s %-8s %-8s", "ID", "BATCH_ID", "STATUS", "INPUT", "INS", "UPD", "UNCH", "ERRS")
    puts "-" * 88
    runs.each do |r|
      puts sprintf("%-4d %-28s %-10s %-8d %-8d %-8d %-8d %-8d",
        r[:id],
        r[:batch_id][0, 27],
        r[:status].upcase,
        r[:total_input],
        r[:inserted],
        r[:updated],
        r[:unchanged],
        r[:invalid]
      )
    end
  end
end
