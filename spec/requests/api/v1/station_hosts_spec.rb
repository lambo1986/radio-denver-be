require 'rails_helper'

RSpec.describe 'Station host administration', type: :request do
  let(:admin) { create(:user, :admin) }
  let(:headers) { { 'Authorization' => "Bearer #{JsonWebTokenService.encode(user_id: admin.id)}" } }

  it 'lists station hosts with useful counts' do
    host = create(:user, host_name: 'Deep Cuts Dana')
    create(:playlist, user: host)
    create(:audio_file, user: host)

    get '/api/v1/station_hosts', headers: headers

    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body).find { |item| item['id'] == host.id }
    expect(body['host_name']).to eq('Deep Cuts Dana')
    expect(body['shows_count']).to eq(1)
    expect(body['audio_count']).to eq(1)
  end

  it 'suspends and reactivates a host' do
    host = create(:user)

    patch "/api/v1/station_hosts/#{host.id}/suspend", headers: headers
    expect(response).to have_http_status(:ok)
    expect(host.reload.account_status).to eq('suspended')

    patch "/api/v1/station_hosts/#{host.id}/reactivate", headers: headers
    expect(response).to have_http_status(:ok)
    expect(host.reload.account_status).to eq('active')
  end

  it 'blocks a suspended host from authenticated endpoints' do
    host = create(:user, account_status: 'suspended')
    host_headers = { 'Authorization' => "Bearer #{JsonWebTokenService.encode(user_id: host.id)}" }

    get '/api/v1/audio_files', headers: host_headers

    expect(response).to have_http_status(:forbidden)
  end
end
