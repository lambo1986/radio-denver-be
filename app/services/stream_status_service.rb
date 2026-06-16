require 'net/http'

class StreamStatusService
  CHECK_TIMEOUT_SECONDS = 5

  def status
    stream_url = configured_stream_url
    stream_check = stream_url.present? ? check_stream(stream_url) : { reachable: false, detail: 'Stream URL is not configured.' }
    azuracast = azuracast_status

    {
      station: ENV.fetch('STREAM_STATION_NAME', 'Human Frequency'),
      checked_at: Time.current.iso8601,
      configured: stream_url.present?,
      status: stream_status(stream_url, stream_check),
      stream_url: stream_url,
      stream_reachable: stream_check[:reachable],
      stream_detail: stream_check[:detail],
      azuracast: azuracast
    }
  end

  private

  def configured_stream_url
    ENV['AZURACAST_STREAM_URL'].presence || ENV['STREAM_URL'].presence
  end

  def stream_status(stream_url, stream_check)
    return 'setup_needed' if stream_url.blank?
    return 'online' if stream_check[:reachable]

    'offline'
  end

  def check_stream(stream_url)
    uri = URI.parse(stream_url)
    return { reachable: false, detail: 'Stream URL must use HTTP or HTTPS.' } unless uri.is_a?(URI::HTTP)

    response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.is_a?(URI::HTTPS), open_timeout: CHECK_TIMEOUT_SECONDS, read_timeout: CHECK_TIMEOUT_SECONDS) do |http|
      request = Net::HTTP::Head.new(uri.request_uri)
      request['Icy-MetaData'] = '1'
      http.request(request)
    end

    if response.code.to_i.between?(200, 399)
      { reachable: true, detail: "Stream responded with HTTP #{response.code}." }
    else
      { reachable: false, detail: "Stream responded with HTTP #{response.code}." }
    end
  rescue URI::InvalidURIError, SocketError, SystemCallError, Timeout::Error => error
    { reachable: false, detail: "Stream check failed: #{error.message}" }
  end

  def azuracast_status
    base_url = ENV['AZURACAST_BASE_URL'].presence
    station_id = ENV['AZURACAST_STATION_ID'].presence
    shortcode = ENV['AZURACAST_STATION_SHORTCODE'].presence

    {
      configured: base_url.present? && station_id.present? && ENV['AZURACAST_API_KEY'].present?,
      base_url: base_url,
      station_id: station_id,
      station_shortcode: shortcode,
      api_key_configured: ENV['AZURACAST_API_KEY'].present?,
      now_playing_url: now_playing_url(base_url, station_id, shortcode)
    }
  end

  def now_playing_url(base_url, station_id, shortcode)
    return if base_url.blank?

    identifier = shortcode.presence || station_id
    return if identifier.blank?

    "#{base_url.to_s.chomp('/').presence}/api/nowplaying/#{identifier}"
  end
end
