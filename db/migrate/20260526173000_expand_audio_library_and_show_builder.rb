class ExpandAudioLibraryAndShowBuilder < ActiveRecord::Migration[7.1]
  def change
    change_table :audio_files, bulk: true do |t|
      t.string :title
      t.string :artist
      t.string :album
      t.string :genre
      t.string :kind, null: false, default: 'track'
      t.string :visibility, null: false, default: 'private'
      t.string :url
      t.string :content_type
      t.boolean :explicit, null: false, default: false
      t.text :notes
    end

    add_index :audio_files, :visibility
    add_index :audio_files, :kind

    change_table :playlists, bulk: true do |t|
      t.string :status, null: false, default: 'draft'
      t.datetime :scheduled_at
      t.references :full_show_audio_file, foreign_key: { to_table: :audio_files }
    end

    add_index :playlists, :status

    change_table :songs, bulk: true do |t|
      t.integer :position
      t.string :file_url
      t.string :file_name
      t.references :audio_file, foreign_key: true
    end
  end
end
