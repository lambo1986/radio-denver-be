require 'rails_helper'

RSpec.describe AzuracastClient, type: :service do
  around do |example|
    keys = %w[
      STREAM_STATION_NAME
      AZURACAST_BASE_URL
      AZURACAST_STATION_ID
      AZURACAST_STATION_SHORTCODE
      AZURACAST_PUBLIC_PLAYER_URL
      AZURACAST_STREAM_URL
      AZURACAST_NOW_PLAYING_URL
      AZURACAST_API_KEY
    ]
    previous_values = keys.to_h { |key| [key, ENV[key]] }
    keys.each { |key| ENV.delete(key) }
    ENV['STREAM_STATION_NAME'] = 'Human Frequency'
    ENV['AZURACAST_BASE_URL'] = 'https://a5.asurahosting.com'
    ENV['AZURACAST_STATION_ID'] = '720'
    ENV['AZURACAST_STATION_SHORTCODE'] = 'human_frequency'
    ENV['AZURACAST_PUBLIC_PLAYER_URL'] = 'https://a5.asurahosting.com/public/human_frequency'
    ENV['AZURACAST_STREAM_URL'] = 'https://a5.asurahosting.com:7390/radio.mp3'
    ENV['AZURACAST_NOW_PLAYING_URL'] = 'https://a5.asurahosting.com/api/nowplaying_static/human_frequency.json'
    example.run
  ensure
    previous_values.each do |key, value|
      value.nil? ? ENV.delete(key) : ENV[key] = value
    end
  end

  it 'normalizes AzuraCast now-playing data without exposing the API key' do
    ENV['AZURACAST_API_KEY'] = 'super-secret-key'
    response = instance_double(Net::HTTPResponse, code: '200', body: azuracast_payload.to_json)
    http = instance_double(Net::HTTP, request: response)
    allow(Net::HTTP).to receive(:start).and_yield(http)

    now_playing = described_class.new.now_playing

    expect(now_playing).to include(
      ok: true,
      stationName: 'Human Frequency',
      stationShortcode: 'human_frequency',
      isPublic: true,
      streamUrl: 'https://a5.asurahosting.com:7390/radio.mp3',
      publicPlayerUrl: 'https://a5.asurahosting.com/public/human_frequency'
    )
    expect(now_playing[:nowPlaying]).to include(
      title: 'Dardanella',
      artist: 'Dinosaurchestra',
      album: 'New Orleans Run pre release',
      text: 'Dinosaurchestra - New Orleans Run pre release - Dardanella',
      playlist: 'test show',
      elapsed: 149,
      duration: 290
    )
    expect(now_playing[:playingNext]).to include(title: 'Turn', artist: 'Leonie Evans & Gina Leslie')
    expect(now_playing[:listeners]).to eq(total: 1, unique: 1, current: 1)
    expect(now_playing[:live]).to eq(isLive: false, streamerName: nil)
    expect(now_playing[:azuracast]).to include(apiKeyConfigured: true)
    expect(now_playing.to_s).not_to include('super-secret-key')
  end

  it 'returns a safe offline shape when AzuraCast is unavailable' do
    allow(Net::HTTP).to receive(:start).and_raise(SocketError, 'connection refused')

    now_playing = described_class.new.now_playing

    expect(now_playing[:ok]).to be(false)
    expect(now_playing[:error]).to include('connection refused')
    expect(now_playing[:streamUrl]).to eq('https://a5.asurahosting.com:7390/radio.mp3')
    expect(now_playing[:nowPlaying]).to include(title: nil, artist: nil)
  end

  def azuracast_payload
    {
      'station' => {
        'id' => 720,
        'name' => 'Human Frequency',
        'shortcode' => 'human_frequency',
        'listen_url' => 'https://a5.asurahosting.com:7390/radio.mp3',
        'public_player_url' => 'https://a5.asurahosting.com/public/human_frequency',
        'is_public' => true
      },
      'listeners' => { 'total' => 1, 'unique' => 1, 'current' => 1 },
      'live' => { 'is_live' => false, 'streamer_name' => '' },
      'now_playing' => {
        'duration' => 290,
        'playlist' => 'test show',
        'elapsed' => 149,
        'song' => {
          'art' => 'https://a5.asurahosting.com/api/station/human_frequency/art/current',
          'text' => 'Dinosaurchestra - New Orleans Run pre release - Dardanella',
          'artist' => 'Dinosaurchestra',
          'title' => 'Dardanella',
          'album' => 'New Orleans Run pre release'
        }
      },
      'playing_next' => {
        'duration' => 219,
        'playlist' => 'test show',
        'song' => {
          'art' => 'https://a5.asurahosting.com/api/station/human_frequency/art/next',
          'text' => 'Leonie Evans & Gina Leslie - Live From The Levee - Turn',
          'artist' => 'Leonie Evans & Gina Leslie',
          'title' => 'Turn',
          'album' => 'Live From The Levee'
        }
      }
    }
  end
end
