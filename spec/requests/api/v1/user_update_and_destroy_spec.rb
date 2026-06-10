require "rails_helper"

RSpec.describe "update and destroy" do
  describe "update" do
    it "updates a user's data" do
      user1 = User.create!(first_name: "John", last_name: "Doe", email: "lame@gmail.com", password: "1234password", password_confirmation: "1234password")

      patch api_v1_user_path(user1), params: { user: { first_name: "Jack", last_name: "Smith", email: "doop@gmail.com" }}, headers: auth_headers(user1)

      json_response = JSON.parse(response.body)

      expect(response).to be_successful
      expect(json_response["data"]["attributes"]["first_name"]).to eq("Jack")
      expect(json_response["data"]["attributes"]["last_name"]).to eq("Smith")
      expect(json_response["data"]["attributes"]["email"]).to eq("doop@gmail.com")
    end

    it "does not update a user's password if it can't find the user" do
      user1 = User.create!(first_name: "John", last_name: "Doe", email: "lame@gmail.com", password: "1234password", password_confirmation: "1234password")

      patch '/api/v1/users/123456789', params: { user: { first_name: "Jack", last_name: "Smith", email: "doop@gmail.com" }}, headers: auth_headers(user1)

      json_response = JSON.parse(response.body)

      expect(response).to_not be_successful
      expect(json_response["error"]).to eq("User not found")
    end

    it "throws an error if the fields are missing" do
      user1 = User.create!(first_name: "John", last_name: "Doe", email: "lame@gmail.com", password: "1234password", password_confirmation: "1234password")

      patch api_v1_user_path(user1), params: { user: { first_name: "", last_name: "", email: "" }}, headers: auth_headers(user1)

      json_response = JSON.parse(response.body)

      expect(response).to_not be_successful
      expect(json_response["errors"]).to eq(["First name can't be blank", "Last name can't be blank", "Email can't be blank"])
    end
  end

  describe "profile image" do
    let(:user) { create(:user) }
    let(:file) { fixture_file_upload(Rails.root.join("spec/fixtures/files/profile.jpg"), "image/jpeg") }

    it "uploads and replaces the current user's profile image" do
      service = instance_double(AwsS3Service)
      allow(service).to receive(:upload_uploaded_file).and_return(
        key: "profile_images/#{user.id}/new/profile.jpg",
        url: "https://example.com/profile.jpg"
      )
      allow(service).to receive(:get_file_url).and_return("https://example.com/profile.jpg")
      allow(service).to receive(:delete_file)
      allow(AwsS3Service).to receive(:new).and_return(service)
      user.update!(profile_image: "profile_images/#{user.id}/old/profile.jpg")

      patch profile_image_api_v1_user_path(user),
            params: { profile_image: file },
            headers: auth_headers(user)

      expect(response).to have_http_status(:ok)
      expect(user.reload.profile_image).to eq("profile_images/#{user.id}/new/profile.jpg")
      expect(JSON.parse(response.body).dig("data", "attributes", "profile_image")).to eq("https://example.com/profile.jpg")
      expect(service).to have_received(:delete_file).with("profile_images/#{user.id}/old/profile.jpg")
    end

    it "rejects unsupported profile image types" do
      invalid_file = fixture_file_upload(Rails.root.join("spec/fixtures/files/test_file.mp3"), "audio/mpeg")

      patch profile_image_api_v1_user_path(user),
            params: { profile_image: invalid_file },
            headers: auth_headers(user)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)["errors"]).to include("Choose a JPG, PNG, or WebP image.")
    end

    it "prevents another host from changing the image" do
      other_user = create(:user)

      patch profile_image_api_v1_user_path(user),
            params: { profile_image: file },
            headers: auth_headers(other_user)

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "destroy" do
    it "destroys a user" do
      user1 = User.create!(first_name: "John", last_name: "Doe", email: "lame@gmail.com", password: "1234password", password_confirmation: "1234password", role: "admin")

      delete api_v1_user_path(user1), headers: auth_headers(user1)

      json_response = JSON.parse(response.body)

      expect(response).to be_successful
      expect(json_response["data"]).to eq(nil)
      expect(User.count).to eq(0)
      expect(json_response["message"]).to eq("User deleted")
    end

    it "throws an error if the user can't be found" do
      user1 = User.create!(first_name: "John", last_name: "Doe", email: "lame@gmail.com", password: "1234password", password_confirmation: "1234password", role: "admin")

      delete '/api/v1/users/123456789', headers: auth_headers(user1)

      json_response = JSON.parse(response.body)

      expect(status).to eq(404)
      expect(response).to_not be_successful
      expect(json_response["error"]).to eq("User not found")
    end
  end

  def auth_headers(user)
    { "Authorization" => "Bearer #{JsonWebTokenService.encode(user_id: user.id)}" }
  end
end
