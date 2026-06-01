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
      expect(body['visibility']).to eq('shared')
      expect(body['s3_key']).to eq(upload[:key])
      expect(body['url']).to eq(upload[:url])
    end
  end
end
