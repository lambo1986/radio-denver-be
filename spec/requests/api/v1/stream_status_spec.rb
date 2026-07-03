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
end
