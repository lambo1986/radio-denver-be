require 'rails_helper'

RSpec.describe 'Multiple-show station workflow', type: :request do
  let(:admin) { create(:user, :admin) }
  let(:host_one) { create(:user, host_name: 'Deep Cuts Dana') }
  let(:host_two) { create(:user, host_name: 'Midnight Miles') }
  let(:admin_headers) { auth_headers(admin) }

  def auth_headers(user)
    { 'Authorization' => "Bearer #{JsonWebTokenService.encode(user_id: user.id)}" }
  end

  def confirmations
    {
      audio_authorized: true,
      metadata_confirmed: true,
      explicit_content_confirmed: true,
      contains_explicit_content: false
    }
  end

  it 'handles different hosts, reused audio, edits, adjacent slots, and overlap rejection' do
    shared_track = create(
      :audio_file,
      user: host_one,
      title: 'Community Groove',
      artist: 'The Local Players',
      visibility: 'shared',
      duration: 600
    )

    post '/api/v1/playlists',
         params: {
           playlist: confirmations.merge(
             name: 'Deep Cuts',
             description: 'Rare soul and jazz selections.',
             host_name: host_one.host_name,
             status: 'submitted',
             songs: [
               {
                 name: shared_track.title,
                 artist: shared_track.artist,
                 album: 'Station Library',
                 duration: 600,
                 audio_file_id: shared_track.id
               },
               {
                 name: 'Dana Host Break',
                 artist: host_one.host_name,
                 album: 'Host Break',
                 duration: 120,
                 file_url: 'https://example.com/dana-break.mp3'
               }
             ]
           )
         },
         headers: auth_headers(host_one)

    expect(response).to have_http_status(:created)
    assembled_show = Playlist.find(JSON.parse(response.body)['id'])
    expect(assembled_show.duration_seconds).to eq(720)
    expect(assembled_show.songs.first.audio_file_id).to eq(shared_track.id)

    patch "/api/v1/playlists/#{assembled_show.id}/request_changes",
          params: { review: { review_notes: 'Add a stronger opening note.' } },
          headers: admin_headers

    expect(response).to have_http_status(:ok)
    expect(assembled_show.reload.status).to eq('needs_edits')

    patch "/api/v1/playlists/#{assembled_show.id}",
          params: {
            playlist: confirmations.merge(
              name: assembled_show.name,
              description: 'Rare soul and jazz selections with a new opening.',
              host_name: assembled_show.host_name,
              status: 'submitted'
            )
          },
          headers: auth_headers(host_one)

    expect(response).to have_http_status(:ok)

    patch "/api/v1/playlists/#{assembled_show.id}/mark_ready", headers: admin_headers
    expect(response).to have_http_status(:ok)

    patch "/api/v1/playlists/#{assembled_show.id}/schedule",
          params: { playlist: { scheduled_at: '2026-07-11T20:00:00Z' } },
          headers: admin_headers

    expect(response).to have_http_status(:ok)

    upload = {
      key: 'full_shows/test/midnight-miles.mp3',
      url: 'https://example.com/midnight-miles.mp3'
    }
    service = instance_double(AwsS3Service, upload_uploaded_file: upload, get_file_url: upload[:url])
    allow(AwsS3Service).to receive(:new).and_return(service)
    file = fixture_file_upload(Rails.root.join('spec', 'fixtures', 'files', 'test_file.mp3'), 'audio/mp3')

    post '/api/v1/playlists',
         params: {
           playlist: confirmations.merge(
             name: 'Midnight Miles',
             description: 'A complete mixed show.',
             host_name: host_two.host_name,
             status: 'submitted',
             full_show_file: file,
             full_show_duration: 900
           )
         },
         headers: auth_headers(host_two)

    expect(response).to have_http_status(:created)
    full_show = Playlist.find(JSON.parse(response.body)['id'])
    expect(full_show.duration_seconds).to eq(900)

    patch "/api/v1/playlists/#{full_show.id}/mark_ready", headers: admin_headers
    expect(response).to have_http_status(:ok)

    patch "/api/v1/playlists/#{full_show.id}/schedule",
          params: { playlist: { scheduled_at: '2026-07-11T20:12:00Z' } },
          headers: admin_headers

    expect(response).to have_http_status(:ok)

    conflicting_show = create(
      :playlist,
      user: host_two,
      status: 'ready',
      audio_authorized: true,
      metadata_confirmed: true,
      explicit_content_confirmed: true
    )
    create(:song, playlist: conflicting_show, duration: 300, file_url: 'https://example.com/conflict.mp3')

    patch "/api/v1/playlists/#{conflicting_show.id}/schedule",
          params: { playlist: { scheduled_at: '2026-07-11T20:20:00Z' } },
          headers: admin_headers

    expect(response).to have_http_status(:unprocessable_entity)
    expect(JSON.parse(response.body)['errors'].join).to include(full_show.name)
    expect(conflicting_show.reload.status).to eq('ready')
  end
end
