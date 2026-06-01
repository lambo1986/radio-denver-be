require 'rails_helper'

RSpec.describe 'Host invitations', type: :request do
  let(:admin) { create(:user, :admin) }
  let(:admin_headers) { { 'Authorization' => "Bearer #{JsonWebTokenService.encode(user_id: admin.id)}" } }

  describe 'GET /api/v1/host_invitations' do
    it 'lists invitations for admins' do
      invitation = create(:host_invitation, invited_by: admin)

      get '/api/v1/host_invitations', headers: admin_headers

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body.first['code']).to eq(invitation.code)
      expect(body.first['status']).to eq('active')
    end

    it 'rejects hosts' do
      host = create(:user)

      get '/api/v1/host_invitations',
          headers: { 'Authorization' => "Bearer #{JsonWebTokenService.encode(user_id: host.id)}" }

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe 'POST /api/v1/host_invitations' do
    it 'creates an invitation for admins' do
      post '/api/v1/host_invitations',
           params: { host_invitation: { email: 'friend@example.com', notes: 'Local soul show' } },
           headers: admin_headers

      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      expect(body['code']).to be_present
      expect(body['email']).to eq('friend@example.com')
      expect(body['invited_by']).to eq(admin.email)
    end
  end
end
