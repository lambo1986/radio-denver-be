class NormalizeUserEmails < ActiveRecord::Migration[7.1]
  class MigrationUser < ActiveRecord::Base
    self.table_name = 'users'
  end

  def up
    duplicate_emails.each do |normalized_email|
      users = MigrationUser.where('LOWER(TRIM(email)) = ?', normalized_email).to_a
      survivor = users.max_by { |user| [user.role == 'admin' ? 1 : 0, user.id] }

      users.reject { |user| user.id == survivor.id }.each do |duplicate|
        execute "UPDATE playlists SET user_id = #{survivor.id} WHERE user_id = #{duplicate.id}"
        execute "UPDATE audio_files SET user_id = #{survivor.id} WHERE user_id = #{duplicate.id}"
        execute "UPDATE host_invitations SET invited_by_id = #{survivor.id} WHERE invited_by_id = #{duplicate.id}"
        execute "UPDATE host_invitations SET used_by_id = #{survivor.id} WHERE used_by_id = #{duplicate.id}"
        duplicate.delete
      end
    end

    execute "UPDATE users SET email = LOWER(TRIM(email))"
    add_index :users, 'LOWER(email)', unique: true, name: 'index_users_on_lower_email'
  end

  def down
    remove_index :users, name: 'index_users_on_lower_email'
  end

  private

  def duplicate_emails
    MigrationUser
      .where.not(email: nil)
      .group(Arel.sql('LOWER(TRIM(email))'))
      .having('COUNT(*) > 1')
      .pluck(Arel.sql('LOWER(TRIM(email))'))
  end
end
