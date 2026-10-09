class AddOriginClassCountsToApprovedReleases < ActiveRecord::Migration[8.1]
  def change
    add_column :approved_releases, :origin_class_counts, :jsonb, default: {}, null: false
  end
end
