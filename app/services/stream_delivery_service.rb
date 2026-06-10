class StreamDeliveryService
  MANIFEST_VERSION = 2

  def initialize(playlist, target: 'local_queue')
    @playlist = playlist
    @target = target.presence || 'local_queue'
  end

  def deliver
    reference = "hf-show-#{playlist.id}-#{Time.current.to_i}"

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
      provider: provider_manifest,
      show: {
        id: playlist.id,
        title: playlist.name,
        description: playlist.description,
        host_name: playlist.host_name,
        scheduled_at: playlist.scheduled_at&.iso8601,
        status: playlist.status,
        total_duration_seconds: total_duration_seconds,
        package_mode: master_audio_file.present? ? 'single_master' : 'ordered_assets'
      },
      assets: audio_assets,
      playout: playout_items
    }
  end

  def station_name
    ENV.fetch('STREAM_STATION_NAME', 'Human Frequency')
  end

  def provider_manifest
    return azuracast_provider_manifest if azuracast_target?

    {
      name: target,
      mode: 'manual_export',
      next_steps: [
        'Use the assets and playout arrays to hand this show to the selected stream provider.'
      ]
    }
  end

  def azuracast_provider_manifest
    {
      name: 'AzuraCast',
      mode: azuracast_configured? ? 'api_ready' : 'manual_export',
      base_url: ENV['AZURACAST_BASE_URL'],
      station_id: ENV['AZURACAST_STATION_ID'],
      station_shortcode: ENV['AZURACAST_STATION_SHORTCODE'],
      stream_url: ENV['AZURACAST_STREAM_URL'],
      api_key_configured: ENV['AZURACAST_API_KEY'].present?,
      recommended_playlist: ENV.fetch('AZURACAST_PLAYLIST_NAME', 'Human Frequency Shows'),
      recommended_media_folder: "human-frequency/#{playlist.id}-#{playlist.name.parameterize}",
      next_steps: [
        'Upload the full-show audio or ordered show assets into AzuraCast media.',
        'Assign uploaded media to the recommended AutoDJ playlist.',
        'Use the stream URL on the Human Frequency listener page, presented by Alpine Groove Guide.'
      ],
      api_notes: 'AzuraCast exposes per-install API docs at /api. Configure AZURACAST_* env vars before automating uploads.'
    }
  end

  def azuracast_target?
    target.to_s == 'azuracast'
  end

  def azuracast_configured?
    ENV['AZURACAST_BASE_URL'].present? &&
      ENV['AZURACAST_STATION_ID'].present? &&
      ENV['AZURACAST_API_KEY'].present?
  end

  def audio_assets
    assets = []

    if master_audio_file.present?
      assets << audio_asset(master_audio_file, role: 'broadcast_master', position: 1)
      return assets
    end

    playlist.songs.includes(:audio_file).each do |song|
      assets << song_asset(song)
    end

    assets.compact
  end

  def playout_items
    if master_audio_file.present?
      return [
        {
          position: 1,
          type: playlist.rendered_master_audio_file.present? ? 'broadcast_master' : 'full_show',
          title: playlist.name,
          duration_seconds: master_audio_file.duration,
          start_offset_seconds: 0,
          end_offset_seconds: master_audio_file.duration,
          audio_url: master_audio_file.public_url,
          audio_file_id: master_audio_file.id,
          s3_key: master_audio_file.s3_key
        }
      ]
    end

    elapsed_seconds = 0
    playlist.songs.includes(:audio_file).map do |song|
      duration_seconds = song.duration.to_i
      item = {
        position: song.position,
        type: song.audio_file&.kind || 'track',
        title: song.name,
        artist: song.artist,
        duration_seconds: duration_seconds,
        start_offset_seconds: elapsed_seconds,
        end_offset_seconds: elapsed_seconds + duration_seconds,
        audio_url: song.audio_file&.public_url || song.file_url,
        audio_file_id: song.audio_file_id,
        s3_key: song.audio_file&.s3_key
      }
      elapsed_seconds = item[:end_offset_seconds]
      item
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
    playlist.duration_seconds
  end

  def master_audio_file
    return playlist.rendered_master_audio_file if playlist.render_status == 'ready'

    playlist.full_show_audio_file
  end
end
