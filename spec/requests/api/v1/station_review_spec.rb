require 'rails_helper'

RSpec.describe 'Station review workflow', type: :request do
  let(:admin) { create(:user, :admin) }
  let(:headers) { { 'Authorization' => "Bearer #{JsonWebTokenService.encode(user_id: admin.id)}" } }

  describe 'GET /api/v1/playlists?scope=station' do
    it 'returns submitted and station-side shows' do
      submitted = create(:playlist, status: 'submitted')
      ready = create(:playlist, status: 'ready')
      needs_edits = create(:playlist, status: 'needs_edits')
      create(:playlist, status: 'draft')

      get '/api/v1/playlists?scope=station', headers: headers

      expect(response).to have_http_status(:ok)
      names = JSON.parse(response.body).map { |playlist| playlist['name'] }
      expect(names).to include(submitted.name)
      expect(names).to include(ready.name)
      expect(names).to include(needs_edits.name)
      expect(names.count).to eq(3)
    end

    it 'does not return the station queue to hosts' do
      host = create(:user)
      create(:playlist, status: 'submitted')

      get '/api/v1/playlists?scope=station',
          headers: { 'Authorization' => "Bearer #{JsonWebTokenService.encode(user_id: host.id)}" }

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to eq([])
    end
  end

  describe 'GET /api/v1/station/schedule' do
    it 'returns scheduled public shows without authentication' do
      scheduled = create(:playlist, status: 'scheduled', scheduled_at: 1.hour.from_now)
      create(:playlist, status: 'submitted')

      get '/api/v1/station/schedule'

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body.length).to eq(1)
      expect(body.first['name']).to eq(scheduled.name)
      expect(body.first).not_to have_key('review_notes')
    end
  end

  describe 'PATCH /api/v1/playlists/:id/mark_ready' do
    it 'marks a submitted show ready' do
      playlist = create(:playlist, status: 'submitted')

      patch "/api/v1/playlists/#{playlist.id}/mark_ready", headers: headers

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)['status']).to eq('ready')
    end

    it 'rejects hosts' do
      host = create(:user)
      playlist = create(:playlist, status: 'submitted')

      patch "/api/v1/playlists/#{playlist.id}/mark_ready",
            headers: { 'Authorization' => "Bearer #{JsonWebTokenService.encode(user_id: host.id)}" }

      expect(response).to have_http_status(:forbidden)
      expect(JSON.parse(response.body)['error']).to eq('Admin access required')
    end
  end

  describe 'PATCH /api/v1/playlists/:id/request_changes' do
    it 'returns a submitted show to the host with notes' do
      playlist = create(:playlist, status: 'submitted')

      patch "/api/v1/playlists/#{playlist.id}/request_changes",
            params: { review: { review_notes: 'Please add a voice intro.' } },
            headers: headers

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body['status']).to eq('needs_edits')
      expect(body['review_notes']).to eq('Please add a voice intro.')
      expect(body['reviewed_at']).to be_present
    end
  end

  describe 'PATCH /api/v1/playlists/:id/reopen_for_edits' do
    it 'clears scheduling and delivery fields so a queued show can be edited again' do
      playlist = create(
        :playlist,
        status: 'scheduled',
        scheduled_at: 1.hour.from_now,
        delivery_status: 'queued',
        delivery_target: 'azuracast',
        delivery_reference: 'mmn-show-1-test',
        delivery_manifest: { provider: { name: 'AzuraCast' } },
        delivered_at: Time.current
      )

      patch "/api/v1/playlists/#{playlist.id}/reopen_for_edits",
            params: { review: { review_notes: 'Fix durations before scheduling.' } },
            headers: headers

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body['status']).to eq('needs_edits')
      expect(body['delivery_status']).to eq('not_sent')
      expect(body['delivery_target']).to be_nil
      expect(body['delivery_reference']).to be_nil
      expect(body['delivery_manifest']).to eq({})
      expect(body['scheduled_at']).to be_nil
      expect(body['review_notes']).to eq('Fix durations before scheduling.')
    end
  end

  describe 'PATCH /api/v1/playlists/:id/reject' do
    it 'rejects a submitted show with notes' do
      playlist = create(:playlist, status: 'submitted')

      patch "/api/v1/playlists/#{playlist.id}/reject",
            params: { review: { review_notes: 'This does not fit the station right now.' } },
            headers: headers

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body['status']).to eq('rejected')
      expect(body['review_notes']).to eq('This does not fit the station right now.')
    end
  end

  describe 'PATCH /api/v1/playlists/:id/schedule' do
    it 'schedules a ready show' do
      playlist = create(:playlist, status: 'ready')

      patch "/api/v1/playlists/#{playlist.id}/schedule",
            params: { playlist: { scheduled_at: '2026-05-27T20:00:00Z' } },
            headers: headers

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body['status']).to eq('scheduled')
      expect(body['scheduled_at']).to be_present
    end
  end

  describe 'POST /api/v1/playlists/:id/deliver' do
    it 'queues a scheduled show for stream delivery' do
      playlist = create(:playlist, status: 'scheduled')

      post "/api/v1/playlists/#{playlist.id}/deliver",
           params: { delivery: { target: 'local_stream' } },
           headers: headers

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body['delivery_status']).to eq('queued')
      expect(body['delivery_target']).to eq('local_stream')
      expect(body['delivery_reference']).to start_with("mmn-show-#{playlist.id}-")
      expect(body['delivery_manifest']['station']).to eq('Alpine Groove Guide')
      expect(body['delivery_manifest']['show']['id']).to eq(playlist.id)
      expect(body['delivery_manifest']['assets']).to be_an(Array)
      expect(body['delivered_at']).to be_present
    end

    it 'adds AzuraCast handoff metadata when queued for AzuraCast' do
      playlist = create(:playlist, status: 'scheduled')

      post "/api/v1/playlists/#{playlist.id}/deliver",
           params: { delivery: { target: 'azuracast' } },
           headers: headers

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      provider = body['delivery_manifest']['provider']

      expect(body['delivery_target']).to eq('azuracast')
      expect(provider['name']).to eq('AzuraCast')
      expect(provider['mode']).to eq('manual_export')
      expect(provider['recommended_playlist']).to eq('Alpine Groove Guide Shows')
      expect(provider['recommended_media_folder']).to include("melody-mixer/#{playlist.id}-")
    end
  end
end
