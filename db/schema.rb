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

ActiveRecord::Schema[7.1].define(version: 2026_05_26_173000) do
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
    t.string "visibility", default: "private", null: false
    t.string "url"
    t.string "content_type"
    t.boolean "explicit", default: false, null: false
    t.text "notes"
    t.index ["kind"], name: "index_audio_files_on_kind"
    t.index ["user_id"], name: "index_audio_files_on_user_id"
    t.index ["visibility"], name: "index_audio_files_on_visibility"
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
    t.index ["full_show_audio_file_id"], name: "index_playlists_on_full_show_audio_file_id"
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
  end

  add_foreign_key "audio_files", "users"
  add_foreign_key "playlists", "audio_files", column: "full_show_audio_file_id"
  add_foreign_key "playlists", "users"
  add_foreign_key "songs", "audio_files"
  add_foreign_key "songs", "playlists"
end
