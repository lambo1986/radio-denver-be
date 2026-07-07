require 'net/http'
require 'base64'

class AzuracastClient
  CHECK_TIMEOUT_SECONDS = 5
  DEFAULT_BASE_URL = 'https://a5.asurahosting.com'
  DEFAULT_STATION_ID = '720'
  DEFAULT_STATION_SHORTCODE = 'human_frequency'
  DEFAULT_STREAM_URL = 'https://a5.asurahosting.com:7390/radio.mp3'
  DEFAULT_PUBLIC_PLAYER_URL = 'https://a5.asurahosting.com/public/human_frequency'
  DEFAULT_NOW_PLAYING_URL = 'https://a5.asurahosting.com/api/nowplaying_static/human_frequency.json'

  def now_playing
    response = get_json(now_playing_url)
    normalized_now_playing(response).merge(
      ok: true,
      fetched_at: Time.current.iso8601,
      error: nil
    )
  rescue StandardError => error
    fallback_now_playing(
      ok: false,
      error: "Could not reach AzuraCast now-playing data: #{error.message}",
      fetched_at: Time.current.iso8601
    )
  end

  def api_key_configured?
    ENV['AZURACAST_API_KEY'].present?
  end

  def station_configured?
    base_url.present? && station_id.present? && station_shortcode.present?
  end

  def get_station_status
    authenticated_get_json("/api/station/#{station_id}")
  end

  def get_playlists
    authenticated_get_json("/api/station/#{station_id}/playlists")
  end

  def get_media_files
    authenticated_get_json("/api/station/#{station_id}/files")
  end

  def get_media_file(media_id)
    authenticated_get_json("/api/station/#{station_id}/file/#{media_id}")
  end

  def get_media_folders
    authenticated_get_json("/api/station/#{station_id}/files/list")
  end

  def find_playlist_by_name(name)
    return nil if name.blank?

    normalized_playlists(get_playlists).find do |playlist|
      playlist[:name].to_s.casecmp(name.to_s).zero?
    end
  end

  def find_or_resolve_recommended_playlist(manifest_or_name)
    name = recommended_playlist_name(manifest_or_name)
    playlist = find_playlist_by_name(name)

    {
      name: name,
      found: playlist.present?,
      playlist: playlist
    }
  rescue StandardError => error
    {
      name: name,
      found: false,
      playlist: nil,
      error: safe_error_message(error)
    }
  end

  def discovery(recommended_playlist: nil, recommended_media_folder: nil, manifest: nil)
    errors = []
    fetched_at = Time.current.iso8601
    station_payload = fetch_discovery_value(errors, 'station') { get_station_status }
    playlist_payload = fetch_discovery_value(errors, 'playlists') { get_playlists }
    media_payload = fetch_discovery_value(errors, 'media') { get_media_files }
    folder_payload = fetch_discovery_value(errors, 'media_folders') { get_media_folders }

    playlists = normalized_playlists(playlist_payload)
    media_files = normalized_media_files(media_payload).first(10)
    media_folders = normalized_media_folders(folder_payload)
    requested_playlist_name = recommended_playlist.presence || recommended_playlist_name(manifest)
    requested_folder_name = recommended_media_folder.presence || recommended_media_folder_name(manifest)
    recommended_playlist_match = match_by_name(playlists, requested_playlist_name)
    recommended_folder_match = match_by_name(media_folders, requested_folder_name)

    {
      ok: errors.empty?,
      connected: station_payload.present? || playlist_payload.present? || media_payload.present? || folder_payload.present?,
      lastDiscoveryAt: fetched_at,
      stationId: station_id,
      stationShortcode: station_shortcode,
      baseUrl: base_url,
      streamUrl: stream_url,
      publicPlayerUrl: public_player_url,
      apiKeyConfigured: api_key_configured?,
      station: normalized_station(station_payload),
      playlists: playlists,
      mediaFolders: media_folders,
      recentMedia: media_files,
      recommendedPlaylist: {
        name: requested_playlist_name,
        found: recommended_playlist_match.present?,
        playlist: recommended_playlist_match
      },
      recommendedMediaFolder: {
        name: requested_folder_name,
        found: recommended_folder_match.present?,
        folder: recommended_folder_match
      },
      errors: errors
    }
  end

  def upload_media_file(path, remote_path: nil)
    raise 'Audio file does not exist for AzuraCast upload.' unless File.exist?(path)

    authenticated_request(
      Net::HTTP::Post,
      "/api/station/#{station_id}/files",
      json: {
        path: remote_path.presence || File.basename(path),
        file: Base64.strict_encode64(File.binread(path))
      }
    )
  end

  def update_media_file(media_id, attributes)
    authenticated_request(
      Net::HTTP::Put,
      "/api/station/#{station_id}/file/#{media_id}",
      json: attributes
    )
  end

  def assign_media_to_playlist(media_id, playlist_id, existing_playlist_ids: [])
    playlist_ids = (Array(existing_playlist_ids) + [playlist_id]).compact.map(&:to_i).uniq
    update_media_file(media_id, playlists: playlist_ids)
  rescue StandardError => first_error
    begin
      update_media_file(media_id, playlists: playlist_ids.map { |id| { id: id } })
    rescue StandardError => second_error
      raise "Could not assign AzuraCast media to playlist. #{safe_error_message(first_error)}; fallback failed: #{safe_error_message(second_error)}"
    end
  end

  def create_playlist(_attributes)
    raise NotImplementedError, 'TODO: create AzuraCast playlists from Human Frequency admin tools.'
  end

  def update_playlist(_playlist_id, _attributes)
    raise NotImplementedError, 'TODO: update AzuraCast playlist settings from Human Frequency.'
  end

  def restart_station
    raise NotImplementedError, 'TODO: restart station only after admin confirmation and API endpoint verification.'
  end

  def start_station
    raise NotImplementedError, 'TODO: start station only after admin confirmation and API endpoint verification.'
  end

  def stop_station
    raise NotImplementedError, 'TODO: stop station only after admin confirmation and API endpoint verification.'
  end

  private

  def normalized_now_playing(payload)
    station = payload.fetch('station', {})
    now_playing = payload.fetch('now_playing', {})
    playing_next = payload.fetch('playing_next', {})

    {
      stationName: station['name'].presence || ENV.fetch('STREAM_STATION_NAME', 'Human Frequency'),
      stationShortcode: station['shortcode'].presence || station_shortcode,
      isPublic: station.fetch('is_public', true),
      streamUrl: station['listen_url'].presence || stream_url,
      publicPlayerUrl: station['public_player_url'].presence || public_player_url,
      nowPlaying: song_payload(now_playing),
      playingNext: song_payload(playing_next),
      listeners: listeners_payload(payload['listeners']),
      live: live_payload(payload['live']),
      azuracast: {
        configured: station_configured?,
        baseUrl: base_url,
        stationId: station_id,
        stationShortcode: station_shortcode,
        nowPlayingUrl: now_playing_url,
        apiKeyConfigured: api_key_configured?
      }
    }
  end

  def fallback_now_playing(ok:, error:, fetched_at:)
    {
      ok: ok,
      fetched_at: fetched_at,
      error: error,
      stationName: ENV.fetch('STREAM_STATION_NAME', 'Human Frequency'),
      stationShortcode: station_shortcode,
      isPublic: true,
      streamUrl: stream_url,
      publicPlayerUrl: public_player_url,
      nowPlaying: empty_song_payload,
      playingNext: empty_song_payload,
      listeners: listeners_payload(nil),
      live: live_payload(nil),
      azuracast: {
        configured: station_configured?,
        baseUrl: base_url,
        stationId: station_id,
        stationShortcode: station_shortcode,
        nowPlayingUrl: now_playing_url,
        apiKeyConfigured: api_key_configured?
      }
    }
  end

  def song_payload(playback)
    song = playback&.fetch('song', {}) || {}
    {
      title: song['title'].presence,
      artist: song['artist'].presence,
      album: song['album'].presence,
      text: song['text'].presence,
      art: song['art'].presence,
      playlist: playback&.dig('playlist').presence,
      elapsed: playback&.dig('elapsed'),
      duration: playback&.dig('duration')
    }
  end

  def empty_song_payload
    {
      title: nil,
      artist: nil,
      album: nil,
      text: nil,
      art: nil,
      playlist: nil,
      elapsed: nil,
      duration: nil
    }
  end

  def listeners_payload(listeners)
    {
      total: listeners&.dig('total').to_i,
      unique: listeners&.dig('unique').to_i,
      current: listeners&.dig('current').to_i
    }
  end

  def live_payload(live)
    {
      isLive: live&.dig('is_live') == true,
      streamerName: live&.dig('streamer_name').presence
    }
  end

  def get_json(url)
    uri = URI.parse(url)
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.is_a?(URI::HTTPS), open_timeout: CHECK_TIMEOUT_SECONDS, read_timeout: CHECK_TIMEOUT_SECONDS) do |http|
      http.request(Net::HTTP::Get.new(uri.request_uri))
    end
    raise "HTTP #{response.code}" unless response.code.to_i.between?(200, 299)

    JSON.parse(response.body)
  rescue URI::InvalidURIError => error
    raise "invalid URL: #{error.message}"
  end

  def authenticated_get_json(path)
    raise 'AZURACAST_API_KEY is not configured.' unless api_key_configured?

    authenticated_request(Net::HTTP::Get, path)
  end

  def authenticated_request(request_class, path, json: nil, form: nil, form_encoding: nil)
    raise 'AZURACAST_API_KEY is not configured.' unless api_key_configured?

    uri = URI.join("#{base_url}/", path.sub(%r{\A/}, ''))
    request = request_class.new(uri.request_uri)
    request['Authorization'] = "Bearer #{ENV.fetch('AZURACAST_API_KEY')}"
    if json
      request['Content-Type'] = 'application/json'
      request.body = JSON.generate(json)
    elsif form
      request.set_form(form, form_encoding)
    end

    response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.is_a?(URI::HTTPS), open_timeout: CHECK_TIMEOUT_SECONDS, read_timeout: 120) do |http|
      http.request(request)
    end
    raise "AzuraCast API returned HTTP #{response.code}: #{response.body.to_s.truncate(200)}" unless response.code.to_i.between?(200, 299)

    response.body.present? ? JSON.parse(response.body) : {}
  end

  def fetch_discovery_value(errors, label)
    yield
  rescue StandardError => error
    errors << { source: label, message: safe_error_message(error) }
    nil
  end

  def normalized_station(payload)
    data = first_record(payload)
    return nil unless data

    {
      id: value_at(data, 'id'),
      name: value_at(data, 'name'),
      shortcode: value_at(data, 'shortcode'),
      listenUrl: value_at(data, 'listen_url') || value_at(data, 'listenUrl') || stream_url,
      publicPlayerUrl: value_at(data, 'public_player_url') || value_at(data, 'publicPlayerUrl') || public_player_url
    }.compact
  end

  def normalized_playlists(payload)
    records(payload).map do |playlist|
      {
        id: value_at(playlist, 'id'),
        name: value_at(playlist, 'name'),
        type: value_at(playlist, 'type'),
        source: value_at(playlist, 'source'),
        enabled: value_at(playlist, 'is_enabled') || value_at(playlist, 'isEnabled'),
        numSongs: value_at(playlist, 'num_songs') || value_at(playlist, 'numSongs')
      }.compact
    end
  end

  def normalized_media_files(payload)
    records(payload).map do |media|
      {
        id: value_at(media, 'id'),
        name: value_at(media, 'name') || value_at(media, 'basename'),
        path: value_at(media, 'path'),
        title: value_at(media, 'title'),
        artist: value_at(media, 'artist'),
        album: value_at(media, 'album'),
        length: value_at(media, 'length') || value_at(media, 'duration'),
        playlist: value_at(media, 'playlist'),
        updatedAt: value_at(media, 'mtime') || value_at(media, 'updated_at') || value_at(media, 'updatedAt')
      }.compact
    end
  end

  def normalized_media_folders(payload)
    folders = records(payload).select { |record| folder_record?(record) }

    folders.map do |folder|
      {
        id: value_at(folder, 'id') || value_at(folder, 'path'),
        name: value_at(folder, 'name') || value_at(folder, 'path'),
        path: value_at(folder, 'path')
      }.compact
    end
  end

  def records(payload)
    case payload
    when Array
      payload
    when Hash
      candidates = payload['records'] || payload[:records] || payload['rows'] || payload[:rows] || payload['items'] || payload[:items] || payload['data'] || payload[:data]
      candidates.is_a?(Array) ? candidates : [payload]
    else
      []
    end
  end

  def first_record(payload)
    records(payload).first
  end

  def value_at(record, key)
    return unless record.respond_to?(:[])

    record[key] || record[key.to_sym]
  end

  def folder_record?(record)
    value_at(record, 'type').to_s.casecmp('directory').zero? ||
      value_at(record, 'is_dir') == true ||
      value_at(record, 'isDir') == true ||
      value_at(record, 'is_folder') == true ||
      value_at(record, 'isFolder') == true
  end

  def match_by_name(records, name)
    return nil if name.blank?

    records.find do |record|
      [record[:name], record[:path], record['name'], record['path']].compact.any? { |value| value.to_s.casecmp(name.to_s).zero? }
    end
  end

  def recommended_playlist_name(manifest_or_name)
    return manifest_or_name if manifest_or_name.is_a?(String)
    return if manifest_or_name.blank?

    value_at(value_at(manifest_or_name, 'provider') || {}, 'recommended_playlist')
  end

  def recommended_media_folder_name(manifest)
    return if manifest.blank?

    value_at(value_at(manifest, 'provider') || {}, 'recommended_media_folder')
  end

  def safe_error_message(error)
    message = error.message.to_s
    secret = ENV['AZURACAST_API_KEY'].presence
    secret ? message.gsub(secret, '[redacted]') : message
  end

  def base_url
    ENV.fetch('AZURACAST_BASE_URL', DEFAULT_BASE_URL).to_s.chomp('/')
  end

  def station_id
    ENV.fetch('AZURACAST_STATION_ID', DEFAULT_STATION_ID)
  end

  def station_shortcode
    ENV.fetch('AZURACAST_STATION_SHORTCODE', DEFAULT_STATION_SHORTCODE)
  end

  def stream_url
    ENV.fetch('AZURACAST_STREAM_URL', DEFAULT_STREAM_URL)
  end

  def public_player_url
    ENV.fetch('AZURACAST_PUBLIC_PLAYER_URL', DEFAULT_PUBLIC_PLAYER_URL)
  end

  def now_playing_url
    ENV.fetch('AZURACAST_NOW_PLAYING_URL', DEFAULT_NOW_PLAYING_URL)
  end
end
