class CreateProvenanceDomainModel < ActiveRecord::Migration[8.1]
  def change
    create_table :approved_releases do |t|
      t.string :manifest_digest, null: false
      t.string :approval_signature, null: false
      t.string :approved_by, null: false
      t.datetime :approved_at, null: false
      t.string :corpus_version, null: false
      t.integer :total_items, default: 0, null: false
      t.boolean :active, default: false, null: false

      t.timestamps
    end
    add_index :approved_releases, :manifest_digest, unique: true
    add_index :approved_releases, :active

    create_table :canonical_postings do |t|
      t.string :public_id, null: false
      t.references :approved_release, foreign_key: true
      t.string :title, null: false
      t.string :company, null: false
      t.string :location, null: false
      t.string :remote_type, default: "unknown", null: false
      t.string :employment_type, default: "unknown", null: false
      t.decimal :salary_min, precision: 12, scale: 2
      t.decimal :salary_max, precision: 12, scale: 2
      t.string :salary_currency, limit: 3
      t.string :salary_period
      t.text :summary_excerpt
      t.string :job_url
      t.datetime :last_observed_at, null: false
      t.datetime :first_observed_at, null: false
      t.integer :mentions_count, default: 0, null: false
      t.boolean :potential_duplicate, default: false, null: false
      t.tsvector :search_vector

      t.timestamps
    end
    add_index :canonical_postings, :public_id, unique: true
    add_index :canonical_postings, :company
    add_index :canonical_postings, :location
    add_index :canonical_postings, :remote_type
    add_index :canonical_postings, :employment_type
    add_index :canonical_postings, :last_observed_at
    add_index :canonical_postings, :potential_duplicate
    add_index :canonical_postings, :search_vector, using: :gin

    create_table :source_records do |t|
      t.references :approved_release, foreign_key: true
      t.string :source_system, null: false
      t.string :source_record_key, null: false
      t.string :origin_class, null: false

      t.timestamps
    end
    add_index :source_records, [:source_system, :source_record_key], unique: true

    create_table :source_mentions do |t|
      t.references :source_record, null: false, foreign_key: { on_delete: :cascade }
      t.references :canonical_posting, foreign_key: { on_delete: :nullify }
      t.string :mention_key, null: false
      t.string :source_kind, null: false
      t.string :source_domain
      t.string :job_id

      t.timestamps
    end
    add_index :source_mentions, [:source_record_id, :mention_key], unique: true

    create_table :source_revisions do |t|
      t.references :source_mention, null: false, foreign_key: { on_delete: :cascade }
      t.string :revision_digest, null: false
      t.datetime :observed_at, null: false
      t.datetime :posted_at
      t.string :title, null: false
      t.string :company, null: false
      t.string :location, null: false
      t.string :remote_type
      t.string :employment_type
      t.decimal :salary_min, precision: 12, scale: 2
      t.decimal :salary_max, precision: 12, scale: 2
      t.string :salary_currency, limit: 3
      t.string :salary_period
      t.text :summary_excerpt
      t.string :job_url
      t.jsonb :raw_safe_fields, default: {}, null: false

      t.datetime :created_at, null: false
    end
    add_index :source_revisions, [:source_mention_id, :revision_digest], unique: true
    add_index :source_revisions, :observed_at

    create_table :field_selections do |t|
      t.references :canonical_posting, null: false, foreign_key: { on_delete: :cascade }
      t.string :field_name, null: false
      t.references :source_revision, null: false, foreign_key: { on_delete: :cascade }
      t.string :selection_reason, null: false

      t.timestamps
    end
    add_index :field_selections, [:canonical_posting_id, :field_name], unique: true

    create_table :potential_duplicates do |t|
      t.references :posting_a, null: false, foreign_key: { to_table: :canonical_postings, on_delete: :cascade }
      t.references :posting_b, null: false, foreign_key: { to_table: :canonical_postings, on_delete: :cascade }
      t.string :reason_code, null: false
      t.string :evaluation_digest, null: false

      t.datetime :created_at, null: false
    end
    add_index :potential_duplicates, [:posting_a_id, :posting_b_id], unique: true

    create_table :import_runs do |t|
      t.string :batch_id, null: false
      t.string :batch_digest, null: false
      t.string :origin_class, null: false
      t.string :status, null: false
      t.integer :total_input, default: 0, null: false
      t.integer :inserted_count, default: 0, null: false
      t.integer :updated_count, default: 0, null: false
      t.integer :unchanged_count, default: 0, null: false
      t.integer :invalid_count, default: 0, null: false
      t.datetime :started_at, null: false
      t.datetime :completed_at

      t.timestamps
    end
    add_index :import_runs, :batch_id
    add_index :import_runs, :status

    create_table :import_errors do |t|
      t.references :import_run, null: false, foreign_key: { on_delete: :cascade }
      t.integer :item_index, null: false
      t.string :item_identifier
      t.string :error_code, null: false
      t.text :error_message, null: false

      t.datetime :created_at, null: false
    end
    add_index :import_errors, [:import_run_id, :item_index]
  end
end
