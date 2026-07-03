require 'rails_helper'

RSpec.describe 'Station review workflow', type: :request do
  let(:admin) { create(:user, :admin) }
  let(:headers) { { 'Authorization' => "Bearer #{JsonWebTokenService.encode(user_id: admin.id)}" } }

  def add_valid_track(playlist, duration: 1800)
    create(:song, playlist: playlist, duration: duration, file_url: 'https://example.com/show-track.mp3')
  end

  def confirm_submission(playlist)
    playlist.update!(
      audio_authorized: true,
      metadata_confirmed: true,
      explicit_content_confirmed: true
    )
  end

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
      full_show = create(:audio_file, user: scheduled.user, kind: 'full_show', duration: 1800)
      scheduled.update!(full_show_audio_file: full_show, delivery_reference: 'private-package-reference')
      create(:playlist, status: 'submitted')

      get '/api/v1/station/schedule'

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body.length).to eq(1)
      expect(body.first['name']).to eq(scheduled.name)
      expect(body.first).not_to have_key('review_notes')
      expect(body.first).not_to have_key('delivery_reference')
      expect(body.first['full_show_audio_file']).to eq('duration' => 1800)
    end
  end

  describe 'PATCH /api/v1/playlists/:id/mark_ready' do
    it 'marks a submitted show ready' do
      playlist = create(:playlist, status: 'submitted')
      add_valid_track(playlist)
      confirm_submission(playlist)

      patch "/api/v1/playlists/#{playlist.id}/mark_ready", headers: headers

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)['status']).to eq('ready')
    end

    it 'rejects an empty submitted show' do
      playlist = create(:playlist, status: 'submitted')

      patch "/api/v1/playlists/#{playlist.id}/mark_ready", headers: headers

      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)['errors']).to include('Add a full-show file or at least one lineup track.')
      expect(playlist.reload.status).to eq('submitted')
    end

    it 'rejects a submitted show with a zero-duration item' do
      playlist = create(:playlist, status: 'submitted')
      create(:song, playlist: playlist, duration: 0, file_url: 'https://example.com/silent.mp3')
      confirm_submission(playlist)

      patch "/api/v1/playlists/#{playlist.id}/mark_ready", headers: headers

      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)['errors'].join).to include('missing duration')
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

  describe 'DELETE /api/v1/playlists/:id' do
    it 'lets an admin delete a station queue show and cleans generated show audio' do
      host = create(:user)
      playlist = create(:playlist, user: host, status: 'scheduled')
      full_show = create(:audio_file, user: host, kind: 'full_show', visibility: 'private', s3_key: 'full_shows/old-show.mp3')
      master = create(:audio_file, user: host, kind: 'full_show', visibility: 'private', s3_key: 'broadcast_masters/old-master.mp3')
      playlist.update!(full_show_audio_file: full_show, rendered_master_audio_file: master, render_status: 'ready')
      service = instance_double(AwsS3Service, delete_file: true)
      allow(AwsS3Service).to receive(:new).and_return(service)

      expect do
        delete "/api/v1/playlists/#{playlist.id}", headers: headers
      end.to change(Playlist, :count).by(-1)

      expect(response).to have_http_status(:no_content)
      expect(AudioFile.exists?(full_show.id)).to be(false)
      expect(AudioFile.exists?(master.id)).to be(false)
      expect(service).to have_received(:delete_file).with('full_shows/old-show.mp3')
      expect(service).to have_received(:delete_file).with('broadcast_masters/old-master.mp3')
    end

    it 'still keeps hosts from deleting another hosts show' do
      owner = create(:user)
      other_host = create(:user)
      playlist = create(:playlist, user: owner, status: 'submitted')

      delete "/api/v1/playlists/#{playlist.id}",
             headers: { 'Authorization' => "Bearer #{JsonWebTokenService.encode(user_id: other_host.id)}" }

      expect(response).to have_http_status(:not_found)
      expect(Playlist.exists?(playlist.id)).to be(true)
    end
  end

  describe 'host submission confirmations' do
    it 'rejects submission without all confirmations' do
      playlist = create(:playlist, status: 'draft')
      add_valid_track(playlist)
      host_headers = { 'Authorization' => "Bearer #{JsonWebTokenService.encode(user_id: playlist.user_id)}" }

      patch "/api/v1/playlists/#{playlist.id}",
            params: {
              playlist: {
                name: playlist.name,
                description: playlist.description,
                host_name: playlist.host_name,
                status: 'submitted',
                audio_authorized: true,
                metadata_confirmed: false,
                explicit_content_confirmed: true
              }
            },
            headers: host_headers

      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)['errors'].join).to include('Confirm audio permission')
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
        delivery_reference: 'hf-show-1-test',
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

    it 'removes a stale rendered master when reopening a show' do
      playlist = create(:playlist, status: 'ready')
      master = create(:audio_file, user: playlist.user, kind: 'full_show', s3_key: 'broadcast_masters/old.mp3')
      playlist.update!(rendered_master_audio_file: master, render_status: 'ready', rendered_at: Time.current)
      service = instance_double(AwsS3Service, delete_file: true)
      allow(AwsS3Service).to receive(:new).and_return(service)

      patch "/api/v1/playlists/#{playlist.id}/reopen_for_edits", headers: headers

      expect(response).to have_http_status(:ok)
      expect(playlist.reload.render_status).to eq('not_rendered')
      expect(playlist.rendered_master_audio_file).to be_nil
      expect(service).to have_received(:delete_file).with('broadcast_masters/old.mp3')
      expect(AudioFile.exists?(master.id)).to be(false)
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
      add_valid_track(playlist)

      patch "/api/v1/playlists/#{playlist.id}/schedule",
            params: { playlist: { scheduled_at: '2026-06-27T20:00:00Z' } },
            headers: headers

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body['status']).to eq('scheduled')
      expect(body['scheduled_at']).to be_present
    end

    it 'allows a show to start exactly when another show ends' do
      existing = create(:playlist, status: 'scheduled', scheduled_at: '2026-06-27T20:00:00Z')
      add_valid_track(existing, duration: 1800)
      playlist = create(:playlist, status: 'ready')
      add_valid_track(playlist, duration: 900)

      patch "/api/v1/playlists/#{playlist.id}/schedule",
            params: { playlist: { scheduled_at: '2026-06-27T20:30:00Z' } },
            headers: headers

      expect(response).to have_http_status(:ok)
    end

    it 'rejects a schedule that overlaps an existing show' do
      existing = create(:playlist, status: 'scheduled', scheduled_at: '2026-06-27T20:00:00Z')
      add_valid_track(existing, duration: 1800)
      playlist = create(:playlist, status: 'ready')
      add_valid_track(playlist, duration: 900)

      patch "/api/v1/playlists/#{playlist.id}/schedule",
            params: { playlist: { scheduled_at: '2026-06-27T20:15:00Z' } },
            headers: headers

      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)['errors'].join).to include(existing.name)
      expect(playlist.reload.status).to eq('ready')
    end

    it 'rejects a show that has no playable audio' do
      playlist = create(:playlist, status: 'ready')
      create(:song, playlist: playlist, duration: 900, file_url: nil)

      patch "/api/v1/playlists/#{playlist.id}/schedule",
            params: { playlist: { scheduled_at: '2026-06-27T20:00:00Z' } },
            headers: headers

      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)['errors'].join).to include('missing audio')
    end

    it 'rejects scheduling a submitted show that has not been approved' do
      playlist = create(:playlist, status: 'submitted')
      add_valid_track(playlist)
      confirm_submission(playlist)

      patch "/api/v1/playlists/#{playlist.id}/schedule",
            params: { playlist: { scheduled_at: '2026-06-27T20:00:00Z' } },
            headers: headers

      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)['errors']).to include('Only ready or scheduled shows can be scheduled.')
    end
  end

  describe 'POST /api/v1/playlists/:id/deliver' do
    it 'queues a scheduled show for stream delivery' do
      playlist = create(:playlist, status: 'scheduled', scheduled_at: 1.hour.from_now)
      add_valid_track(playlist)

      post "/api/v1/playlists/#{playlist.id}/deliver",
           params: { delivery: { target: 'local_stream' } },
           headers: headers

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body['delivery_status']).to eq('queued')
      expect(body['delivery_target']).to eq('local_stream')
      expect(body['delivery_reference']).to start_with("hf-show-#{playlist.id}-")
      expect(body['delivery_manifest']['station']).to eq('Human Frequency')
      expect(body['delivery_manifest']['version']).to eq(2)
      expect(body['delivery_manifest']['show']['id']).to eq(playlist.id)
      expect(body['delivery_manifest']['show']['package_mode']).to eq('ordered_assets')
      expect(body['delivery_manifest']['assets']).to be_an(Array)
      expect(body['delivery_manifest']['playout'].first).to include(
        'start_offset_seconds' => 0,
        'end_offset_seconds' => body['delivery_manifest']['playout'].first['duration_seconds']
      )
      expect(body['delivered_at']).to be_present
    end

    it 'adds AzuraCast handoff metadata when queued for AzuraCast' do
      playlist = create(:playlist, status: 'scheduled', scheduled_at: 1.hour.from_now)
      add_valid_track(playlist)

      post "/api/v1/playlists/#{playlist.id}/deliver",
           params: { delivery: { target: 'azuracast' } },
           headers: headers

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      provider = body['delivery_manifest']['provider']

      expect(body['delivery_target']).to eq('azuracast')
      expect(provider['name']).to eq('AzuraCast')
      expect(provider['mode']).to eq('manual_export')
      expect(provider['recommended_playlist']).to eq('Human Frequency Shows')
      expect(provider['recommended_media_folder']).to include("human-frequency/#{playlist.id}-")
    end

    it 'uses a ready rendered master as the single AzuraCast playout asset' do
      playlist = create(:playlist, status: 'scheduled', scheduled_at: 1.hour.from_now)
      add_valid_track(playlist)
      master = create(
        :audio_file,
        user: playlist.user,
        kind: 'full_show',
        duration: playlist.duration_seconds,
        s3_key: 'broadcast_masters/show.mp3'
      )
      playlist.update!(rendered_master_audio_file: master, render_status: 'ready', rendered_at: Time.current)

      post "/api/v1/playlists/#{playlist.id}/deliver",
           params: { delivery: { target: 'azuracast' } },
           headers: headers

      body = JSON.parse(response.body)
      expect(body['delivery_manifest']['show']['package_mode']).to eq('single_master')
      expect(body['delivery_manifest']['assets'].length).to eq(1)
      expect(body['delivery_manifest']['assets'].first['role']).to eq('broadcast_master')
      expect(body['delivery_manifest']['playout'].first['s3_key']).to eq('broadcast_masters/show.mp3')
    end

    it 'rejects delivery for an unscheduled show' do
      playlist = create(:playlist, status: 'ready')
      add_valid_track(playlist)

      post "/api/v1/playlists/#{playlist.id}/deliver",
           params: { delivery: { target: 'azuracast' } },
           headers: headers

      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)['errors']).to include('Only scheduled shows can be queued for delivery.')
    end

    it 'rejects delivery when a scheduled show no longer has playable audio' do
      playlist = create(:playlist, status: 'scheduled', scheduled_at: 1.hour.from_now)
      create(:song, playlist: playlist, duration: 300)

      post "/api/v1/playlists/#{playlist.id}/deliver",
           params: { delivery: { target: 'azuracast' } },
           headers: headers

      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)['errors'].join).to include('missing audio')
    end
  end

  describe 'POST /api/v1/playlists/:id/render_master' do
    it 'queues rendering for an approved show and returns immediately' do
      playlist = create(:playlist, status: 'ready')
      add_valid_track(playlist)
      allow(RenderBroadcastMasterJob).to receive(:perform_later)

      post "/api/v1/playlists/#{playlist.id}/render_master", headers: headers

      expect(response).to have_http_status(:accepted)
      body = JSON.parse(response.body)
      expect(body['render_status']).to eq('rendering')
      expect(RenderBroadcastMasterJob).to have_received(:perform_later).with(playlist.id)
    end

    it 'prevents hosts from rendering station masters' do
      host = create(:user)
      playlist = create(:playlist, status: 'ready')
      add_valid_track(playlist)

      post "/api/v1/playlists/#{playlist.id}/render_master",
           headers: { 'Authorization' => "Bearer #{JsonWebTokenService.encode(user_id: host.id)}" }

      expect(response).to have_http_status(:forbidden)
    end

    it 'rejects rendering a show before approval' do
      playlist = create(:playlist, status: 'submitted')
      add_valid_track(playlist)

      post "/api/v1/playlists/#{playlist.id}/render_master", headers: headers

      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)['errors']).to include('Only ready or scheduled shows can be rendered.')
    end
  end

  describe 'POST /api/v1/playlists/:id/deliver_to_azuracast' do
    it 'lets an admin upload a rendered master to AzuraCast' do
      playlist = create(:playlist, status: 'scheduled', scheduled_at: 1.hour.from_now, delivery_status: 'queued')
      master = create(:audio_file, user: playlist.user, kind: 'full_show', s3_key: 'broadcast_masters/master.mp3')
      playlist.update!(rendered_master_audio_file: master, render_status: 'ready')
      delivered_playlist = playlist.tap { |item| item.delivery_status = 'sent' }
      service = instance_double(AzuracastMasterDeliveryService, deliver: delivered_playlist)
      allow(AzuracastMasterDeliveryService).to receive(:new).with(playlist).and_return(service)

      post "/api/v1/playlists/#{playlist.id}/deliver_to_azuracast", headers: headers

      expect(response).to have_http_status(:ok)
      expect(AzuracastMasterDeliveryService).to have_received(:new).with(playlist)
      expect(JSON.parse(response.body)['delivery_status']).to eq('sent')
    end

    it 'does not let a host upload a show to AzuraCast' do
      host = create(:user)
      playlist = create(:playlist, status: 'scheduled', scheduled_at: 1.hour.from_now)

      post "/api/v1/playlists/#{playlist.id}/deliver_to_azuracast",
           headers: { 'Authorization' => "Bearer #{JsonWebTokenService.encode(user_id: host.id)}" }

      expect(response).to have_http_status(:forbidden)
    end
  end
end
