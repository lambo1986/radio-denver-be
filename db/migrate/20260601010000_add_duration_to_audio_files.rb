class AddDurationToAudioFiles < ActiveRecord::Migration[7.1]
  def change
    add_column :audio_files, :duration, :integer
  end
end
