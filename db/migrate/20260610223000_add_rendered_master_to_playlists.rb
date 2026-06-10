class AddRenderedMasterToPlaylists < ActiveRecord::Migration[7.1]
  def change
    add_reference :playlists, :rendered_master_audio_file, foreign_key: { to_table: :audio_files }
    add_column :playlists, :render_status, :string, null: false, default: 'not_rendered'
    add_column :playlists, :render_error, :text
    add_column :playlists, :rendered_at, :datetime
    add_index :playlists, :render_status
  end
end
