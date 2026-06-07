class AddHostConfirmationsToPlaylists < ActiveRecord::Migration[7.1]
  def change
    add_column :playlists, :audio_authorized, :boolean, null: false, default: false
    add_column :playlists, :metadata_confirmed, :boolean, null: false, default: false
    add_column :playlists, :explicit_content_confirmed, :boolean, null: false, default: false
    add_column :playlists, :contains_explicit_content, :boolean, null: false, default: false
    add_column :playlists, :confirmations_recorded_at, :datetime
  end
end
