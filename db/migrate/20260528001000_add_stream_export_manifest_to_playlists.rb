class AddStreamExportManifestToPlaylists < ActiveRecord::Migration[7.1]
  def change
    change_table :playlists, bulk: true do |t|
      t.string :delivery_reference
      t.jsonb :delivery_manifest, null: false, default: {}
    end
  end
end
