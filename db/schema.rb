# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_10_09_140000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "approved_release_revisions", force: :cascade do |t|
    t.bigint "approved_release_id", null: false
    t.bigint "source_revision_id", null: false
    t.string "snapshot_source_domain"
    t.string "snapshot_job_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "snapshot_origin_class"
    t.index ["approved_release_id", "source_revision_id"], name: "idx_on_approved_release_and_revision_unique", unique: true
    t.index ["approved_release_id"], name: "index_approved_release_revisions_on_approved_release_id"
    t.index ["source_revision_id"], name: "index_approved_release_revisions_on_source_revision_id"
  end

  create_table "approved_releases", force: :cascade do |t|
    t.string "manifest_digest", null: false
    t.string "approval_signature", null: false
    t.string "approved_by", null: false
    t.datetime "approved_at", null: false
    t.string "corpus_version", null: false
    t.integer "total_items", default: 0, null: false
    t.boolean "active", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "origin_class_counts", default: {}, null: false
    t.string "authority_fingerprint"
    t.index ["active"], name: "index_approved_releases_on_active"
    t.index ["manifest_digest"], name: "index_approved_releases_on_manifest_digest", unique: true
  end

  create_table "canonical_postings", force: :cascade do |t|
    t.string "public_id", null: false
    t.bigint "approved_release_id"
    t.string "title", null: false
    t.string "company", null: false
    t.string "location", null: false
    t.string "remote_type", default: "unknown", null: false
    t.string "employment_type", default: "unknown", null: false
    t.decimal "salary_min", precision: 12, scale: 2
    t.decimal "salary_max", precision: 12, scale: 2
    t.string "salary_currency", limit: 3
    t.string "salary_period"
    t.text "summary_excerpt"
    t.string "job_url"
    t.datetime "last_observed_at", null: false
    t.datetime "first_observed_at", null: false
    t.integer "mentions_count", default: 0, null: false
    t.boolean "potential_duplicate", default: false, null: false
    t.tsvector "search_vector"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["approved_release_id"], name: "index_canonical_postings_on_approved_release_id"
    t.index ["company"], name: "index_canonical_postings_on_company"
    t.index ["employment_type"], name: "index_canonical_postings_on_employment_type"
    t.index ["last_observed_at"], name: "index_canonical_postings_on_last_observed_at"
    t.index ["location"], name: "index_canonical_postings_on_location"
    t.index ["potential_duplicate"], name: "index_canonical_postings_on_potential_duplicate"
    t.index ["public_id"], name: "index_canonical_postings_on_public_id", unique: true
    t.index ["remote_type"], name: "index_canonical_postings_on_remote_type"
    t.index ["search_vector"], name: "index_canonical_postings_on_search_vector", using: :gin
  end

  create_table "field_selections", force: :cascade do |t|
    t.bigint "canonical_posting_id", null: false
    t.string "field_name", null: false
    t.bigint "source_revision_id", null: false
    t.string "selection_reason", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["canonical_posting_id", "field_name"], name: "index_field_selections_on_canonical_posting_id_and_field_name", unique: true
    t.index ["canonical_posting_id"], name: "index_field_selections_on_canonical_posting_id"
    t.index ["source_revision_id"], name: "index_field_selections_on_source_revision_id"
  end

  create_table "import_errors", force: :cascade do |t|
    t.bigint "import_run_id", null: false
    t.integer "item_index", null: false
    t.string "item_identifier"
    t.string "error_code", null: false
    t.text "error_message", null: false
    t.datetime "created_at", null: false
    t.index ["import_run_id", "item_index"], name: "index_import_errors_on_import_run_id_and_item_index"
    t.index ["import_run_id"], name: "index_import_errors_on_import_run_id"
  end

  create_table "import_runs", force: :cascade do |t|
    t.string "batch_id", null: false
    t.string "batch_digest", null: false
    t.string "origin_class", null: false
    t.string "status", null: false
    t.integer "total_input", default: 0, null: false
    t.integer "inserted_count", default: 0, null: false
    t.integer "updated_count", default: 0, null: false
    t.integer "unchanged_count", default: 0, null: false
    t.integer "invalid_count", default: 0, null: false
    t.datetime "started_at", null: false
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["batch_id"], name: "index_import_runs_on_batch_id"
    t.index ["status"], name: "index_import_runs_on_status"
  end

  create_table "potential_duplicates", force: :cascade do |t|
    t.bigint "posting_a_id", null: false
    t.bigint "posting_b_id", null: false
    t.string "reason_code", null: false
    t.string "evaluation_digest", null: false
    t.datetime "created_at", null: false
    t.index ["posting_a_id", "posting_b_id"], name: "index_potential_duplicates_on_posting_a_id_and_posting_b_id", unique: true
    t.index ["posting_a_id"], name: "index_potential_duplicates_on_posting_a_id"
    t.index ["posting_b_id"], name: "index_potential_duplicates_on_posting_b_id"
  end

  create_table "source_mentions", force: :cascade do |t|
    t.bigint "source_record_id", null: false
    t.bigint "canonical_posting_id"
    t.string "mention_key", null: false
    t.string "source_kind", null: false
    t.string "source_domain"
    t.string "job_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["canonical_posting_id"], name: "index_source_mentions_on_canonical_posting_id"
    t.index ["source_record_id", "mention_key"], name: "index_source_mentions_on_source_record_id_and_mention_key", unique: true
    t.index ["source_record_id"], name: "index_source_mentions_on_source_record_id"
  end

  create_table "source_records", force: :cascade do |t|
    t.bigint "approved_release_id"
    t.string "source_system", null: false
    t.string "source_record_key", null: false
    t.string "origin_class", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["approved_release_id"], name: "index_source_records_on_approved_release_id"
    t.index ["source_system", "source_record_key"], name: "index_source_records_on_source_system_and_source_record_key", unique: true
  end

  create_table "source_revisions", force: :cascade do |t|
    t.bigint "source_mention_id", null: false
    t.string "revision_digest", null: false
    t.datetime "observed_at", null: false
    t.datetime "posted_at"
    t.string "title", null: false
    t.string "company", null: false
    t.string "location", null: false
    t.string "remote_type"
    t.string "employment_type"
    t.decimal "salary_min", precision: 12, scale: 2
    t.decimal "salary_max", precision: 12, scale: 2
    t.string "salary_currency", limit: 3
    t.string "salary_period"
    t.text "summary_excerpt"
    t.string "job_url"
    t.jsonb "raw_safe_fields", default: {}, null: false
    t.datetime "created_at", null: false
    t.index ["observed_at"], name: "index_source_revisions_on_observed_at"
    t.index ["source_mention_id", "revision_digest"], name: "idx_on_source_mention_id_revision_digest_6dbb8995b0", unique: true
    t.index ["source_mention_id"], name: "index_source_revisions_on_source_mention_id"
  end

  add_foreign_key "approved_release_revisions", "approved_releases", on_delete: :cascade
  add_foreign_key "approved_release_revisions", "source_revisions", on_delete: :cascade
  add_foreign_key "canonical_postings", "approved_releases"
  add_foreign_key "field_selections", "canonical_postings", on_delete: :cascade
  add_foreign_key "field_selections", "source_revisions", on_delete: :cascade
  add_foreign_key "import_errors", "import_runs", on_delete: :cascade
  add_foreign_key "potential_duplicates", "canonical_postings", column: "posting_a_id", on_delete: :cascade
  add_foreign_key "potential_duplicates", "canonical_postings", column: "posting_b_id", on_delete: :cascade
  add_foreign_key "source_mentions", "canonical_postings", on_delete: :nullify
  add_foreign_key "source_mentions", "source_records", on_delete: :cascade
  add_foreign_key "source_records", "approved_releases"
  add_foreign_key "source_revisions", "source_mentions", on_delete: :cascade
end
