class AddDeliveryFieldsToPlaylists < ActiveRecord::Migration[7.1]
  def change
    change_table :playlists, bulk: true do |t|
      t.string :delivery_status, null: false, default: 'not_sent'
      t.string :delivery_target
      t.datetime :delivered_at
    end

    add_index :playlists, :delivery_status
  end
end
