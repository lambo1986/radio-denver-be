class AudioFile < ApplicationRecord
  MAX_UPLOAD_SIZE = 500.megabytes
  SUPPORTED_CONTENT_TYPES = %w[
    audio/mpeg
    audio/mp3
    audio/wav
    audio/x-wav
    audio/flac
    audio/x-flac
    audio/mp4
    audio/x-m4a
    audio/aac
    audio/ogg
    audio/webm
  ].freeze
  belongs_to :user

  VISIBILITIES = %w[private shared pending_review].freeze
  KINDS = %w[track full_show host_break].freeze

  validates :name, presence: true
  validates :size, presence: true
  validates :s3_key, presence: true
  validates :visibility, inclusion: { in: VISIBILITIES }, allow_nil: true
  validates :kind, inclusion: { in: KINDS }, allow_nil: true
  validates :duration, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :size, numericality: { less_than_or_equal_to: MAX_UPLOAD_SIZE }
  validates :content_type, inclusion: { in: SUPPORTED_CONTENT_TYPES }, allow_blank: true

  scope :library_visible, -> { where(visibility: 'shared') }
  scope :owned_by, ->(user) { where(user: user) }

  before_validation :set_defaults

  def public_url
    return if s3_key.blank?

    AwsS3Service.new(ENV.fetch('AWS_BUCKET_NAME', 'radio-denver')).get_file_url(s3_key)
  rescue StandardError
    url.presence || s3_key
  end

  private

  def set_defaults
    self.visibility ||= 'private'
    self.kind ||= 'track'
  end
end
