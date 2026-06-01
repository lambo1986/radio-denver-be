class AddReviewNotesToPlaylists < ActiveRecord::Migration[7.1]
  def change
    change_table :playlists, bulk: true do |t|
      t.text :review_notes
      t.datetime :reviewed_at
    end
  end
end
