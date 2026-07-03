require 'net/http'

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

  def upload_media_file(_path, _remote_path: nil)
    raise NotImplementedError, 'TODO: upload rendered broadcast masters to AzuraCast station media.'
  end

  def assign_media_to_playlist(_media_id, _playlist_id)
    raise NotImplementedError, 'TODO: assign uploaded media to the Human Frequency AzuraCast playlist.'
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

    uri = URI.join("#{base_url}/", path.sub(%r{\A/}, ''))
    request = Net::HTTP::Get.new(uri.request_uri)
    request['Authorization'] = "Bearer #{ENV.fetch('AZURACAST_API_KEY')}"
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.is_a?(URI::HTTPS), open_timeout: CHECK_TIMEOUT_SECONDS, read_timeout: CHECK_TIMEOUT_SECONDS) do |http|
      http.request(request)
    end
    raise "AzuraCast API returned HTTP #{response.code}" unless response.code.to_i.between?(200, 299)

    JSON.parse(response.body)
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
