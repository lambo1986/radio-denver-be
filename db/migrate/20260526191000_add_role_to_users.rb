class AddRoleToUsers < ActiveRecord::Migration[7.1]
  def change
    add_column :users, :role, :string, null: false, default: 'host'
    add_index :users, :role
  end
end
