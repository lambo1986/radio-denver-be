class Song < ApplicationRecord
  belongs_to :playlist
  belongs_to :audio_file, optional: true

  validates :name, presence: true
  validates :artist, presence: true
  validates :album, presence: true
  validates :duration, presence: true
end
