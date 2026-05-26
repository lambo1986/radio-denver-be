class Playlist < ApplicationRecord
  belongs_to :user
  belongs_to :full_show_audio_file, class_name: 'AudioFile', optional: true
  has_many :songs, -> { order(:position, :created_at) }, dependent: :destroy
  accepts_nested_attributes_for :songs, allow_destroy: true

  validates :name, presence: true
  validates :description, presence: true
  validates :host_name, presence: true
  validates :status, inclusion: { in: %w[draft ready scheduled submitted aired] }, allow_nil: true

  before_validation :set_default_status

  private

  def set_default_status
    self.status ||= 'draft'
  end
end
