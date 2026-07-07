class CreatePlaylistTimelineEvents < ActiveRecord::Migration[7.1]
  def change
    create_table :playlist_timeline_events do |t|
      t.references :playlist, null: false, foreign_key: true
      t.references :actor, foreign_key: { to_table: :users }
      t.string :event_type, null: false
      t.string :actor_name
      t.text :message
      t.boolean :system_generated, null: false, default: true
      t.jsonb :metadata, null: false, default: {}
      t.datetime :occurred_at, null: false

      t.timestamps
    end

    add_index :playlist_timeline_events, [:playlist_id, :event_type, :occurred_at], name: 'index_playlist_timeline_on_playlist_event_time'
  end
end
