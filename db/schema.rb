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

ActiveRecord::Schema[7.1].define(version: 2026_07_03_194000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "audio_files", force: :cascade do |t|
    t.string "name"
    t.integer "size"
    t.string "s3_key"
    t.bigint "user_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "title"
    t.string "artist"
    t.string "album"
    t.string "genre"
    t.string "kind", default: "track", null: false
    t.string "visibility", default: "shared", null: false
    t.string "url"
    t.string "content_type"
    t.boolean "explicit", default: false, null: false
    t.text "notes"
    t.integer "duration"
    t.index ["kind"], name: "index_audio_files_on_kind"
    t.index ["user_id"], name: "index_audio_files_on_user_id"
    t.index ["visibility"], name: "index_audio_files_on_visibility"
  end

  create_table "host_invitations", force: :cascade do |t|
    t.string "code", null: false
    t.string "email"
    t.text "notes"
    t.bigint "invited_by_id"
    t.bigint "used_by_id"
    t.datetime "used_at"
    t.datetime "expires_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "revoked_at"
    t.index ["code"], name: "index_host_invitations_on_code", unique: true
    t.index ["email"], name: "index_host_invitations_on_email"
    t.index ["invited_by_id"], name: "index_host_invitations_on_invited_by_id"
    t.index ["used_at"], name: "index_host_invitations_on_used_at"
    t.index ["used_by_id"], name: "index_host_invitations_on_used_by_id"
  end

  create_table "playlist_timeline_events", force: :cascade do |t|
    t.bigint "playlist_id", null: false
    t.bigint "actor_id"
    t.string "event_type", null: false
    t.string "actor_name"
    t.text "message"
    t.boolean "system_generated", default: true, null: false
    t.jsonb "metadata", default: {}, null: false
    t.datetime "occurred_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["actor_id"], name: "index_playlist_timeline_events_on_actor_id"
    t.index ["playlist_id", "event_type", "occurred_at"], name: "index_playlist_timeline_on_playlist_event_time"
    t.index ["playlist_id"], name: "index_playlist_timeline_events_on_playlist_id"
  end

  create_table "playlists", force: :cascade do |t|
    t.string "name"
    t.bigint "user_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "description"
    t.string "host_name"
    t.string "status", default: "draft", null: false
    t.datetime "scheduled_at"
    t.bigint "full_show_audio_file_id"
    t.string "delivery_status", default: "not_sent", null: false
    t.string "delivery_target"
    t.datetime "delivered_at"
    t.string "delivery_reference"
    t.jsonb "delivery_manifest", default: {}, null: false
    t.text "review_notes"
    t.datetime "reviewed_at"
    t.boolean "audio_authorized", default: false, null: false
    t.boolean "metadata_confirmed", default: false, null: false
    t.boolean "explicit_content_confirmed", default: false, null: false
    t.boolean "contains_explicit_content", default: false, null: false
    t.datetime "confirmations_recorded_at"
    t.bigint "rendered_master_audio_file_id"
    t.string "render_status", default: "not_rendered", null: false
    t.text "render_error"
    t.datetime "rendered_at"
    t.index ["delivery_status"], name: "index_playlists_on_delivery_status"
    t.index ["full_show_audio_file_id"], name: "index_playlists_on_full_show_audio_file_id"
    t.index ["render_status"], name: "index_playlists_on_render_status"
    t.index ["rendered_master_audio_file_id"], name: "index_playlists_on_rendered_master_audio_file_id"
    t.index ["status"], name: "index_playlists_on_status"
    t.index ["user_id"], name: "index_playlists_on_user_id"
  end

  create_table "songs", force: :cascade do |t|
    t.string "name"
    t.string "artist"
    t.string "album"
    t.integer "duration"
    t.bigint "playlist_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "position"
    t.string "file_url"
    t.string "file_name"
    t.bigint "audio_file_id"
    t.index ["audio_file_id"], name: "index_songs_on_audio_file_id"
    t.index ["playlist_id"], name: "index_songs_on_playlist_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "first_name"
    t.string "last_name"
    t.string "password_digest"
    t.string "email"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "host_name"
    t.string "description"
    t.string "profile_image"
    t.string "phone_number"
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.string "role", default: "host", null: false
    t.string "account_status", default: "active", null: false
    t.index "lower((email)::text)", name: "index_users_on_lower_email", unique: true
    t.index ["account_status"], name: "index_users_on_account_status"
    t.index ["role"], name: "index_users_on_role"
  end

  add_foreign_key "audio_files", "users"
  add_foreign_key "host_invitations", "users", column: "invited_by_id"
  add_foreign_key "host_invitations", "users", column: "used_by_id"
  add_foreign_key "playlist_timeline_events", "playlists"
  add_foreign_key "playlist_timeline_events", "users", column: "actor_id"
  add_foreign_key "playlists", "audio_files", column: "full_show_audio_file_id"
  add_foreign_key "playlists", "audio_files", column: "rendered_master_audio_file_id"
  add_foreign_key "playlists", "users"
  add_foreign_key "songs", "audio_files"
  add_foreign_key "songs", "playlists"
end
