class AudioFile < ApplicationRecord
  belongs_to :user

  VISIBILITIES = %w[private shared pending_review].freeze
  KINDS = %w[track full_show host_break].freeze

  validates :name, presence: true
  validates :size, presence: true
  validates :s3_key, presence: true
  validates :visibility, inclusion: { in: VISIBILITIES }, allow_nil: true
  validates :kind, inclusion: { in: KINDS }, allow_nil: true

  scope :library_visible, -> { where(visibility: 'shared') }
  scope :owned_by, ->(user) { where(user: user) }

  before_validation :set_defaults

  def public_url
    url.presence || s3_key
  end

  private

  def set_defaults
    self.visibility ||= 'private'
    self.kind ||= 'track'
  end
end
