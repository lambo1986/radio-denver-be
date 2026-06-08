class ShareStationAudioByDefault < ActiveRecord::Migration[7.1]
  def up
    change_column_default :audio_files, :visibility, from: 'private', to: 'shared'

    execute <<~SQL.squish
      UPDATE audio_files
      SET visibility = 'shared', updated_at = CURRENT_TIMESTAMP
      WHERE visibility = 'private'
        AND kind IN ('track', 'host_break')
    SQL
  end

  def down
    change_column_default :audio_files, :visibility, from: 'shared', to: 'private'
  end
end
