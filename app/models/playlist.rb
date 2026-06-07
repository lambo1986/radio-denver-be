class Playlist < ApplicationRecord
  STATION_STATUSES = %w[scheduled aired].freeze

  belongs_to :user
  belongs_to :full_show_audio_file, class_name: 'AudioFile', optional: true
  has_many :songs, -> { order(:position, :created_at) }, dependent: :destroy
  accepts_nested_attributes_for :songs, allow_destroy: true

  validates :name, presence: true
  validates :description, presence: true
  validates :host_name, presence: true
  validates :status, inclusion: { in: %w[draft submitted needs_edits rejected ready scheduled aired] }, allow_nil: true
  validates :delivery_status, inclusion: { in: %w[not_sent queued sent failed] }, allow_nil: true

  before_validation :set_default_status

  def duration_seconds
    full_show_duration = full_show_audio_file&.duration.to_i
    return full_show_duration if full_show_duration.positive?

    songs.sum { |song| song.duration.to_i }
  end

  def readiness_issues
    if full_show_audio_file.present?
      return [] if full_show_audio_file.duration.to_i.positive?

      return ['Full-show audio must have a duration greater than zero.']
    end

    return ['Add a full-show file or at least one lineup track.'] if songs.empty?

    issues = []
    missing_audio_count = songs.count { |song| song.audio_file.blank? && song.file_url.blank? }
    missing_duration_count = songs.count { |song| song.duration.to_i <= 0 }

    issues << "#{missing_audio_count} lineup item(s) missing audio." if missing_audio_count.positive?
    issues << "#{missing_duration_count} lineup item(s) missing duration." if missing_duration_count.positive?
    issues
  end

  def confirmation_issues
    return [] if audio_authorized? && metadata_confirmed? && explicit_content_confirmed?

    ['Confirm audio permission, accurate metadata, and explicit-content information before submitting.']
  end

  def scheduling_conflicts(proposed_start)
    proposed_end = proposed_start + duration_seconds.seconds

    Playlist
      .where(status: STATION_STATUSES)
      .where.not(scheduled_at: nil)
      .where.not(id: id)
      .includes(:full_show_audio_file, :songs)
      .select do |other|
        other_end = other.scheduled_at + other.duration_seconds.seconds
        other.scheduled_at < proposed_end && other_end > proposed_start
      end
  end

  private

  def set_default_status
    self.status ||= 'draft'
    self.delivery_status ||= 'not_sent'
  end
end
