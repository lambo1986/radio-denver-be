require 'rails_helper'

RSpec.describe StreamStatusService, type: :service do
  around do |example|
    keys = %w[
      STREAM_STATION_NAME
      AZURACAST_STREAM_URL
      STREAM_URL
      AZURACAST_BASE_URL
      AZURACAST_STATION_ID
      AZURACAST_STATION_SHORTCODE
      AZURACAST_API_KEY
    ]
    previous_values = keys.to_h { |key| [key, ENV[key]] }
    keys.each { |key| ENV.delete(key) }
    ENV['STREAM_STATION_NAME'] = 'Human Frequency'
    example.run
  ensure
    previous_values.each do |key, value|
      value.nil? ? ENV.delete(key) : ENV[key] = value
    end
  end

  it 'reports setup_needed before a stream URL is configured' do
    status = described_class.new.status

    expect(status[:status]).to eq('setup_needed')
    expect(status[:configured]).to be(false)
    expect(status[:stream_reachable]).to be(false)
    expect(status[:stream_detail]).to include('not configured')
  end

  it 'reports online when the stream responds successfully' do
    response = instance_double(Net::HTTPResponse, code: '200')
    http = instance_double(Net::HTTP, request: response)
    allow(Net::HTTP).to receive(:start).and_yield(http)

    ENV['AZURACAST_STREAM_URL'] = 'https://radio.example.com/listen/hf/radio.mp3'
    status = described_class.new.status

    expect(status[:status]).to eq('online')
    expect(status[:stream_reachable]).to be(true)
    expect(status[:stream_url]).to eq('https://radio.example.com/listen/hf/radio.mp3')
  end

  it 'reports offline when the stream check fails' do
    allow(Net::HTTP).to receive(:start).and_raise(SocketError, 'connection refused')

    ENV['AZURACAST_STREAM_URL'] = 'https://radio.example.com/listen/hf/radio.mp3'
    status = described_class.new.status

    expect(status[:status]).to eq('offline')
    expect(status[:stream_reachable]).to be(false)
    expect(status[:stream_detail]).to include('connection refused')
  end

  it 'reports AzuraCast readiness without exposing the API key' do
    ENV['AZURACAST_BASE_URL'] = 'https://radio.example.com'
    ENV['AZURACAST_STATION_ID'] = '1'
    ENV['AZURACAST_STATION_SHORTCODE'] = 'human_frequency'
    ENV['AZURACAST_API_KEY'] = 'secret'
    ENV['AZURACAST_STREAM_URL'] = 'ftp://bad-url'
    status = described_class.new.status

    expect(status[:azuracast]).to include(
      configured: true,
      base_url: 'https://radio.example.com',
      station_id: '1',
      station_shortcode: 'human_frequency',
      public_player_url: nil,
      api_key_configured: true,
      now_playing_url: 'https://radio.example.com/api/nowplaying_static/human_frequency.json'
    )
    expect(status.to_s).not_to include('secret')
  end
end
