class HostInvitation < ApplicationRecord
  belongs_to :invited_by, class_name: 'User', optional: true
  belongs_to :used_by, class_name: 'User', optional: true

  before_validation :set_code

  validates :code, presence: true, uniqueness: true

  scope :unused, -> { where(used_at: nil, used_by_id: nil) }
  scope :active, -> { unused.where('expires_at IS NULL OR expires_at > ?', Time.current) }

  def self.find_usable(code, email: nil)
    invitation = active.find_by(code: normalize_code(code))
    return unless invitation
    return invitation if invitation.email.blank?
    return invitation if email.to_s.casecmp?(invitation.email)
  end

  def use!(user)
    update!(used_by: user, used_at: Time.current)
  end

  def used?
    used_at.present? || used_by_id.present?
  end

  def expired?
    expires_at.present? && expires_at <= Time.current
  end

  def status
    return 'used' if used?
    return 'expired' if expired?

    'active'
  end

  def self.normalize_code(code)
    code.to_s.strip.upcase
  end

  private

  def set_code
    self.code = self.class.normalize_code(code.presence || SecureRandom.alphanumeric(10))
  end
end
