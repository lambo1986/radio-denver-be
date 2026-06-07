require 'rails_helper'

RSpec.describe 'Audio library', type: :request do
  let(:user) { create(:user) }
  let(:headers) { { 'Authorization' => "Bearer #{JsonWebTokenService.encode(user_id: user.id)}" } }

  describe 'GET /api/v1/audio_files' do
    it 'returns shared tracks and the current users private tracks' do
      own_private = create(:audio_file, user: user, title: 'Private Demo', visibility: 'private')
      shared = create(:audio_file, title: 'Shared Track', visibility: 'shared')
      create(:audio_file, title: 'Other Private Track', visibility: 'private')

      get '/api/v1/audio_files', headers: headers

      expect(response).to have_http_status(:ok)
      titles = JSON.parse(response.body).map { |audio_file| audio_file['title'] }

      expect(titles).to include(own_private.title)
      expect(titles).to include(shared.title)
      expect(titles).not_to include('Other Private Track')
    end
  end

  describe 'POST /api/v1/audio_files' do
    it 'creates a Rails-owned audio library record' do
      upload = {
        key: 'audio_files/test/upload.mp3',
        url: 'https://example.com/upload.mp3'
      }
      service = instance_double(AwsS3Service, upload_uploaded_file: upload, get_file_url: upload[:url])
      allow(AwsS3Service).to receive(:new).and_return(service)

      file = fixture_file_upload(Rails.root.join('spec', 'fixtures', 'files', 'test_file.mp3'), 'audio/mp3')

      expect do
        post '/api/v1/audio_files',
             params: {
               audio_file: {
                 title: 'Library Track',
                 artist: 'Local Artist',
                 genre: 'Soul',
                 duration: 195,
                 visibility: 'shared',
                 file: file
               }
             },
             headers: headers
      end.to change(AudioFile, :count).by(1)

      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      expect(body['title']).to eq('Library Track')
      expect(body['artist']).to eq('Local Artist')
      expect(body['duration']).to eq(195)
      expect(body['visibility']).to eq('shared')
      expect(body['s3_key']).to eq(upload[:key])
      expect(body['url']).to eq(upload[:url])
    end

    it 'rejects unsupported files before uploading to storage' do
      service = instance_double(AwsS3Service)
      allow(service).to receive(:upload_uploaded_file)
      allow(AwsS3Service).to receive(:new).and_return(service)
      file = fixture_file_upload(Rails.root.join('spec', 'fixtures', 'files', 'test_file.mp3'), 'application/pdf')

      post '/api/v1/audio_files',
           params: { audio_file: { title: 'Not Audio', artist: 'Unknown', visibility: 'private', file: file } },
           headers: headers

      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)['errors'].join).to include('Choose an MP3')
      expect(service).not_to have_received(:upload_uploaded_file)
    end
  end

  describe 'PATCH /api/v1/audio_files/:id' do
    it 'updates editable metadata for a library track' do
      audio_file = create(:audio_file, user: user, title: 'Bad Title', artist: 'Unknown', duration: 0)

      patch "/api/v1/audio_files/#{audio_file.id}",
            params: {
              audio_file: {
                title: 'Fixed Title',
                artist: 'Local Band',
                album: 'Demo Tape',
                genre: 'Jazz',
                duration: 241,
                notes: 'Clean metadata'
              }
            },
            headers: headers

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body['title']).to eq('Fixed Title')
      expect(body['artist']).to eq('Local Band')
      expect(body['album']).to eq('Demo Tape')
      expect(body['genre']).to eq('Jazz')
      expect(body['duration']).to eq(241)
      expect(body['notes']).to eq('Clean metadata')
    end
  end
end
