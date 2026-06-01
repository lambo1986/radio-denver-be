class User < ApplicationRecord
  has_secure_password

  ROLES = %w[host admin].freeze

  validates :first_name, presence: true
  validates :last_name, presence: true
  validates :phone_number, length: { minimum: 10, maximum: 15 }, allow_blank: true
  validates :email, presence: true, uniqueness: true
  validates :password_digest, presence: true
  validates :role, inclusion: { in: ROLES }

  has_many :playlists, dependent: :destroy
  has_many :audio_files, dependent: :destroy
  has_many :sent_host_invitations, class_name: 'HostInvitation', foreign_key: :invited_by_id, dependent: :nullify
  has_one :accepted_host_invitation, class_name: 'HostInvitation', foreign_key: :used_by_id, dependent: :nullify

  before_validation :set_default_role

  def admin?
    role == 'admin'
  end

  def generate_password_token!
    self.reset_password_token = SecureRandom.hex(10)
    self.reset_password_sent_at = Time.now.utc
    save!
  end

  def password_token_valid?
    (self.reset_password_sent_at + 4.hours) > Time.now.utc
  end

  def reset_password!(password, password_confirmation)
    if password_token_valid?
      self.reset_password_token = nil
      self.password = password
      self.password_confirmation = password_confirmation
      save
    else
      errors.add(:base, "Password reset token has expired")
      false
    end
  end

  private

  def set_default_role
    self.role ||= 'host'
  end
end
