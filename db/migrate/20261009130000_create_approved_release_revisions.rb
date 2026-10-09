class CreateApprovedReleaseRevisions < ActiveRecord::Migration[8.1]
  def change
    create_table :approved_release_revisions do |t|
      t.references :approved_release, null: false, foreign_key: { on_delete: :cascade }
      t.references :source_revision, null: false, foreign_key: { on_delete: :cascade }
      t.string :snapshot_source_domain
      t.string :snapshot_job_id

      t.timestamps
    end

    add_index :approved_release_revisions,
              [:approved_release_id, :source_revision_id],
              unique: true,
              name: "idx_on_approved_release_and_revision_unique"
  end
end
