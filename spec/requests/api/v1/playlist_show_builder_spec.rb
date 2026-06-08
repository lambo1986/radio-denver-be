require 'rails_helper'

RSpec.describe 'Playlist show builder', type: :request do
  let(:user) { create(:user, host_name: 'Poole and the Gang') }
  let(:headers) { { 'Authorization' => "Bearer #{JsonWebTokenService.encode(user_id: user.id)}" } }

  describe 'POST /api/v1/playlists' do
    it 'creates a show with ordered song items' do
      library_track = create(:audio_file, user: user, visibility: 'private')

      expect do
        post '/api/v1/playlists',
             params: {
               playlist: {
                 name: 'Late Night Signal',
                 description: 'Show notes',
                 host_name: 'Poole and the Gang',
                 status: 'draft',
                 scheduled_at: '2026-05-22T20:00',
                 songs: [
                   {
                     name: 'Station Intro',
                     artist: 'Poole and the Gang',
                     album: 'Host Break',
                     duration: '00:30',
                     audio_file_id: library_track.id
                   },
                   {
                     name: 'Shared Song',
                     artist: 'Local Artist',
                     album: 'Single',
                     duration: '03:15'
                   }
                 ]
               }
             },
             headers: headers
      end.to change(Playlist, :count).by(1).and change(Song, :count).by(2)

      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      expect(body['name']).to eq('Late Night Signal')
      expect(body['status']).to eq('draft')
      expect(body['songs'].first['duration']).to eq(30)
      expect(body['songs'].second['duration']).to eq(195)
      expect(body['songs'].first['position']).to eq(1)
      expect(body['songs'].second['position']).to eq(2)
      expect(body['songs'].first['file_url']).to include(library_track.s3_key)
      expect(body['songs'].first['audio_file']['url']).to eq(body['songs'].first['file_url'])
    end

    it 'attaches a full show upload to the show' do
      upload = {
        key: 'full_shows/test/show.mp3',
        url: 'https://example.com/show.mp3'
      }
      service = instance_double(AwsS3Service, upload_uploaded_file: upload, get_file_url: upload[:url])
      allow(AwsS3Service).to receive(:new).and_return(service)

      file = fixture_file_upload(Rails.root.join('spec', 'fixtures', 'files', 'test_file.mp3'), 'audio/mp3')

      post '/api/v1/playlists',
           params: {
             playlist: {
               name: 'Uploaded Full Show',
               description: 'Complete show upload',
               host_name: 'Poole and the Gang',
               full_show_file: file
             }
           },
           headers: headers

      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      expect(body['full_show_audio_file']['name']).to eq('test_file.mp3')
      expect(body['full_show_audio_file']['url']).to eq(upload[:url])
      expect(AudioFile.last.kind).to eq('full_show')
    end

    it 'rejects an unsupported full-show file before uploading to storage' do
      service = instance_double(AwsS3Service)
      allow(service).to receive(:upload_uploaded_file)
      allow(AwsS3Service).to receive(:new).and_return(service)
      file = fixture_file_upload(Rails.root.join('spec', 'fixtures', 'files', 'test_file.mp3'), 'application/pdf')

      post '/api/v1/playlists',
           params: {
             playlist: {
               name: 'Invalid Full Show',
               description: 'Wrong file type',
               host_name: user.host_name,
               full_show_file: file
             }
           },
           headers: headers

      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)['errors'].join).to include('Full show must be')
      expect(service).not_to have_received(:upload_uploaded_file)
    end

    it 'cleans up a full-show upload when submission validation fails' do
      upload = { key: 'full_shows/test/rejected.mp3', url: 'https://example.com/rejected.mp3' }
      service = instance_double(AwsS3Service, upload_uploaded_file: upload, delete_file: true)
      allow(AwsS3Service).to receive(:new).and_return(service)
      file = fixture_file_upload(Rails.root.join('spec', 'fixtures', 'files', 'test_file.mp3'), 'audio/mp3')

      expect do
        post '/api/v1/playlists',
             params: {
               playlist: {
                 name: 'Unconfirmed Show',
                 description: 'Missing confirmations',
                 host_name: user.host_name,
                 status: 'submitted',
                 full_show_file: file,
                 full_show_duration: 1800
               }
             },
             headers: headers
      end.not_to change(AudioFile, :count)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(service).to have_received(:delete_file).with(upload[:key])
    end
  end

  describe 'PATCH /api/v1/playlists/:id' do
    it 'keeps the existing lineup when a replacement submission is invalid' do
      playlist = create(:playlist, user: user, status: 'needs_edits')
      original_song = create(
        :song,
        playlist: playlist,
        name: 'Original Broadcast Track',
        file_url: 'https://example.com/original.mp3'
      )

      patch "/api/v1/playlists/#{playlist.id}",
            params: {
              playlist: {
                name: playlist.name,
                description: playlist.description,
                host_name: playlist.host_name,
                status: 'submitted',
                audio_authorized: true,
                metadata_confirmed: true,
                explicit_content_confirmed: true,
                contains_explicit_content: false,
                songs: [
                  {
                    name: 'Replacement Without Audio',
                    artist: 'Local Artist',
                    album: 'Single',
                    duration: '03:15'
                  }
                ]
              }
            },
            headers: headers

      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)['errors'].join).to include('missing audio')
      expect(playlist.reload.status).to eq('needs_edits')
      expect(playlist.songs.reload.pluck(:id, :name)).to eq([[original_song.id, 'Original Broadcast Track']])
    end
  end
end
