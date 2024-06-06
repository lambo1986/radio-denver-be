require 'rails_helper'

RSpec.describe "Files requests", vcr: true, type: :request do
  describe "POST /users/:user_id/audio_files" do
    it "creates a new file" do
      user = User.create!(first_name: "John", last_name: "Doe", email: "lamb@gmail.com", password: "1234password", password_confirmation: "1234password")
      file = fixture_file_upload(Rails.root.join('spec', 'fixtures', 'files', 'test_file.mp3'), 'audio/mp3')
      file_params = { name: "new_file", size: 300, file: file }
      token = JsonWebTokenService.encode(user_id: user.id)
      headers = { 'Authorization' => "Bearer #{token}" }

      expect {
        post "/api/v1/users/#{user.id}/audio_files", params: { audio_file: file_params }, headers: headers
      }.to change(AudioFile, :count).by(1)

      json_response = JSON.parse(response.body)

      expect(json_response["name"]).to eq("new_file")
      expect(json_response["size"]).to eq(300)
      expect(response).to have_http_status(:created)
      expect(assigns(:audio_file)).to be_a(AudioFile)
      expect(assigns(:audio_file)).to be_persisted
    end

  end

  describe "GET /users/:user_id/audio_files", type: :request do
    it "returns a list of files belonging to a user" do
      user = User.create!(first_name: "John", last_name: "Doe", email: "lamb@gmail.com", password: "1234password", password_confirmation: "1234password")
      audio_file1 = user.audio_files.create!(name: "file1", size: 100, s3_key: "key1")
      audio_file2 = user.audio_files.create!(name: "file2", size: 200, s3_key: "key2")
      headers = { 'Authorization' => "Bearer #{JsonWebTokenService.encode(user_id: user.id)}" }

      get "/api/v1/users/#{user.id}/audio_files", headers: headers

      expect(response).to have_http_status(:ok)

      json_response = JSON.parse(response.body)

      expect(json_response[0]["name"]).to eq("file1")
      expect(json_response[1]["name"]).to eq("file2")
      expect(json_response.count).to eq(2)
      expect(assigns(:audio_files)).to eq([audio_file1, audio_file2])
    end
  end

  describe "GET /users/:user_id/audio_files/:id", type: :request do
    it "returns a single file belonging to a user" do
      user = User.create!(first_name: "John", last_name: "Doe", email: "lamb@gmail.com", password: "1234password", password_confirmation: "1234password")
      audio_file1 = user.audio_files.create!(name: "file1", size: 100, s3_key: "key1")
      headers = { 'Authorization' => "Bearer #{JsonWebTokenService.encode(user_id: user.id)}" }

      get "/api/v1/users/#{user.id}/audio_files/#{audio_file1.id}", headers: headers

      expect(response).to have_http_status(:ok)

      json_response = JSON.parse(response.body)

      expect(json_response["name"]).to eq("file1")
      expect(json_response["size"]).to eq(100)
      expect(json_response["s3_key"]).to eq("key1")
      expect(assigns(:audio_file)).to eq(audio_file1)
      expect(assigns(:audio_file)).to be_a(AudioFile)
      expect(assigns(:audio_file)).to be_persisted
      expect(assigns(:audio_file).id).to eq(audio_file1.id)
    end
  end

  describe "PUT /users/:user_id/audio_files/:id", type: :request do
    it "updates a file belonging to a user" do
      user = User.create!(first_name: "John", last_name: "Doe", email: "lamb@gmail.com", password: "1234password", password_confirmation: "1234password")
      audio_file1 = user.audio_files.create!(name: "file1", size: 100, s3_key: "key1")
      file = fixture_file_upload(Rails.root.join('spec', 'fixtures', 'files', 'new_test_file.mp3'), 'audio/mp3')
      headers = { 'Authorization' => "Bearer #{JsonWebTokenService.encode(user_id: user.id)}" }

      put "/api/v1/users/#{user.id}/audio_files/#{audio_file1.id}", params: { audio_file: { name: "new_name", size: 333, file: file } }, headers: headers

      expect(response).to have_http_status(:ok)

      json_response = JSON.parse(response.body)

      expect(json_response["name"]).to eq("new_name")
      expect(json_response["size"]).to eq(333)
      expect(json_response["s3_key"]).not_to eq("key1")
      expect(assigns(:audio_file)).to eq(audio_file1)
    end
  end

  describe "DELETE /users/:user_id/audio_files/:id", type: :request do
    it "deletes a file belonging to a user" do
      user = User.create!(first_name: "John", last_name: "Doe", email: "lamb@gmail.com", password: "1234password", password_confirmation: "1234password")
      audio_file1 = user.audio_files.create!(name: "file1", size: 100, s3_key: "key1")
      audio_file2 = user.audio_files.create!(name: "file2", size: 200, s3_key: "key2")
      headers = { 'Authorization' => "Bearer #{JsonWebTokenService.encode(user_id: user.id)}" }

      delete "/api/v1/users/#{user.id}/audio_files/#{audio_file1.id}", headers: headers

      expect(response).to have_http_status(:no_content)

      get "/api/v1/users/#{user.id}/audio_files", headers: headers

      expect(response).to have_http_status(:ok)

      json_response = JSON.parse(response.body)

      expect(json_response[0]["name"]).to eq("file2")
      expect(json_response[0]["size"]).to eq(audio_file2.size)
      expect(json_response.count).to eq(1)
    end
  end
end
