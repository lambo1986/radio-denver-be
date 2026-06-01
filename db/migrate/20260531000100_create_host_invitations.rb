class CreateHostInvitations < ActiveRecord::Migration[7.1]
  def change
    create_table :host_invitations do |t|
      t.string :code, null: false
      t.string :email
      t.text :notes
      t.references :invited_by, foreign_key: { to_table: :users }
      t.references :used_by, foreign_key: { to_table: :users }
      t.datetime :used_at
      t.datetime :expires_at

      t.timestamps
    end

    add_index :host_invitations, :code, unique: true
    add_index :host_invitations, :email
    add_index :host_invitations, :used_at
  end
end
