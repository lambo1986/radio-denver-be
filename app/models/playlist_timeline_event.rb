class PlaylistTimelineEvent < ApplicationRecord
  EVENT_TYPES = %w[
    draft_saved
    submitted
    reviewed
    needs_edits
    approved
    rejected
    scheduled
    render_requested
    stream_package_queued
    rendered
    render_failed
    uploaded
    upload_failed
    delivery_test
    aired
  ].freeze

  belongs_to :playlist
  belongs_to :actor, class_name: 'User', optional: true

  validates :event_type, presence: true, inclusion: { in: EVENT_TYPES }
  validates :occurred_at, presence: true

  before_validation :set_defaults

  private

  def set_defaults
    self.occurred_at ||= Time.current
    self.system_generated = true if system_generated.nil?
  end
end
