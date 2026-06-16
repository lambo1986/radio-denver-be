require 'rails_helper'

RSpec.describe 'Station stream status', type: :request do
  it 'returns public stream readiness without authentication' do
    service = instance_double(StreamStatusService, status: { station: 'Human Frequency', status: 'setup_needed' })
    allow(StreamStatusService).to receive(:new).and_return(service)

    get '/api/v1/station/stream_status'

    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body)).to eq('station' => 'Human Frequency', 'status' => 'setup_needed')
  end
end
