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
end
