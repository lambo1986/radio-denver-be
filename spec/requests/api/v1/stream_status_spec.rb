require 'rails_helper'

RSpec.describe 'Station stream status', type: :request do
  it 'returns public stream readiness without authentication' do
    service = instance_double(StreamStatusService, status: { station: 'Human Frequency', status: 'setup_needed' })
    allow(StreamStatusService).to receive(:new).and_return(service)

    get '/api/v1/station/stream_status'

    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body)).to eq('station' => 'Human Frequency', 'status' => 'setup_needed')
  end

  it 'returns public now-playing data without authentication' do
    service = instance_double(AzuracastClient, now_playing: { ok: true, stationName: 'Human Frequency' })
    allow(AzuracastClient).to receive(:new).and_return(service)

    get '/api/v1/station/now_playing'

    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body)).to eq('ok' => true, 'stationName' => 'Human Frequency')
    expect(response.headers['Cache-Control']).to include('max-age=15')
  end

  it 'returns admin-only AzuraCast discovery without exposing secrets' do
    admin = create(:user, :admin)
    service = instance_double(
      AzuracastClient,
      discovery: {
        ok: true,
        apiKeyConfigured: true,
        playlists: [{ id: 10, name: 'Human Frequency Shows' }]
      }
    )
    allow(AzuracastClient).to receive(:new).and_return(service)

    get '/api/v1/station/azuracast_discovery',
        params: { recommended_playlist: 'Human Frequency Shows', recommended_media_folder: 'shows' },
        headers: auth_headers(admin)

    expect(response).to have_http_status(:ok)
    expect(service).to have_received(:discovery).with(
      recommended_playlist: 'Human Frequency Shows',
      recommended_media_folder: 'shows'
    )
    expect(response.body).not_to include('AZURACAST_API_KEY')
  end

  it 'blocks hosts from AzuraCast discovery' do
    host = create(:user)

    get '/api/v1/station/azuracast_discovery', headers: auth_headers(host)

    expect(response).to have_http_status(:forbidden)
  end

  def auth_headers(user)
    { 'Authorization' => "Bearer #{JsonWebTokenService.encode(user_id: user.id)}" }
  end
end
