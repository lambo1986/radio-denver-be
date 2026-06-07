class AddAccountStatusToUsersAndRevokedAtToHostInvitations < ActiveRecord::Migration[7.1]
  def change
    add_column :users, :account_status, :string, null: false, default: 'active'
    add_index :users, :account_status
    add_column :host_invitations, :revoked_at, :datetime
  end
end
