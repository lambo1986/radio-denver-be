class StreamDeliveryService
  MANIFEST_VERSION = 1

  def initialize(playlist, target: 'local_queue')
    @playlist = playlist
    @target = target.presence || 'local_queue'
  end

  def deliver
    reference = "mmn-show-#{playlist.id}-#{Time.current.to_i}"

    playlist.update!(
      delivery_status: 'queued',
      delivery_target: target,
      delivery_reference: reference,
      delivery_manifest: build_manifest(reference),
      delivered_at: Time.current
    )

    playlist
  end

  private

  attr_reader :playlist, :target

  def build_manifest(reference)
    {
      version: MANIFEST_VERSION,
      reference: reference,
      station: station_name,
      target: target,
      generated_at: Time.current.iso8601,
      show: {
        id: playlist.id,
        title: playlist.name,
        description: playlist.description,
        host_name: playlist.host_name,
        scheduled_at: playlist.scheduled_at&.iso8601,
        status: playlist.status,
        total_duration_seconds: total_duration_seconds
      },
      assets: audio_assets,
      playout: playout_items
    }
  end

  def station_name
    ENV.fetch('STREAM_STATION_NAME', 'Alpine Groove Guide')
  end

  def audio_assets
    assets = []

    if playlist.full_show_audio_file.present?
      assets << audio_asset(playlist.full_show_audio_file, role: 'full_show', position: 1)
    end

    playlist.songs.includes(:audio_file).each do |song|
      assets << song_asset(song)
    end

    assets.compact
  end

  def playout_items
    if playlist.full_show_audio_file.present?
      return [
        {
          position: 1,
          type: 'full_show',
          title: playlist.name,
          audio_url: playlist.full_show_audio_file.public_url
        }
      ]
    end

    playlist.songs.includes(:audio_file).map do |song|
      {
        position: song.position,
        type: song.audio_file&.kind || 'track',
        title: song.name,
        artist: song.artist,
        duration_seconds: song.duration,
        audio_url: song.audio_file&.public_url || song.file_url
      }
    end
  end

  def song_asset(song)
    return unless song.audio_file.present? || song.file_url.present?

    if song.audio_file.present?
      return audio_asset(song.audio_file, role: song.audio_file.kind, position: song.position, title: song.name, artist: song.artist)
    end

    {
      position: song.position,
      role: 'external_audio',
      title: song.name,
      artist: song.artist,
      url: song.file_url,
      file_name: song.file_name
    }
  end

  def audio_asset(audio_file, role:, position:, title: nil, artist: nil)
    {
      position: position,
      role: role,
      audio_file_id: audio_file.id,
      title: title.presence || audio_file.title,
      artist: artist.presence || audio_file.artist,
      file_name: audio_file.name,
      content_type: audio_file.content_type,
      url: audio_file.public_url,
      s3_key: audio_file.s3_key
    }
  end

  def total_duration_seconds
    playlist.songs.sum(:duration).to_i
  end
end
