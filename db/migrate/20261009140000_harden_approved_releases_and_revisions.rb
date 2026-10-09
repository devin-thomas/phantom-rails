class HardenApprovedReleasesAndRevisions < ActiveRecord::Migration[8.1]
  def change
    add_column :approved_releases, :authority_fingerprint, :string
    add_column :approved_release_revisions, :snapshot_origin_class, :string

    reversible do |dir|
      dir.up do
        execute <<~SQL
          UPDATE approved_releases
          SET active = false
          WHERE active = true
            AND NOT EXISTS (
              SELECT 1 FROM approved_release_revisions
              WHERE approved_release_revisions.approved_release_id = approved_releases.id
            );
        SQL
      end
    end
  end
end
