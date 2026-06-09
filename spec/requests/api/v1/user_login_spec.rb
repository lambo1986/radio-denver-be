require "rails_helper"

RSpec.describe "user login", type: :request do
  describe "create session" do
    it "should create a session for an existing user" do
      user1 = User.create!(first_name: "John", last_name: "Doe", email: "lame@gmail.com", password: "1234password", password_confirmation: "1234password")

      post "/api/v1/sessions", params: {
        email: user1.email,
        password: "1234password"
      }.to_json, headers: { "Content-Type" => "application/json", "Accept" => "application/json" }

      json_response = JSON.parse(response.body)

      expect(response.status).to eq(200)
      expect(json_response["data"]["id"]).to eq(user1.id.to_s)
      expect(JsonWebTokenService.decode(json_response["token"])[:user_id]).to eq(user1.id)
    end

    it "matches email addresses case-insensitively" do
      user = create(:user, email: "host@example.com")

      post "/api/v1/sessions",
           params: { email: " HOST@EXAMPLE.COM ", password: "securepassword" }.to_json,
           headers: { "Content-Type" => "application/json", "Accept" => "application/json" }

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body).dig("data", "id")).to eq(user.id.to_s)
    end

    it "should not create a session for a non-existing user" do
      user1 = User.create!(first_name: "John", last_name: "Doe", email: "lame@gmail.com", password: "1234password", password_confirmation: "1234password")

      post "/api/v1/sessions", params: {
        email: "wrong@error.nope",
        password: "1234password"
      }.to_json, headers: { "Content-Type" => "application/json", "Accept" => "application/json" }

      json_response = JSON.parse(response.body)

      expect(response.status).to eq(401)
      expect(json_response["error"]).to eq("Invalid email or password")
    end

    it "should not create a session for a wrong password" do
      user1 = User.create!(first_name: "John", last_name: "Doe", email: "lame@gmail.com", password: "1234password", password_confirmation: "1234password")

      post "/api/v1/sessions", params: {
        email: user1.email,
        password: "wrong666"
      }.to_json, headers: { "Content-Type" => "application/json", "Accept" => "application/json" }

      json_response = JSON.parse(response.body)

      expect(response.status).to eq(401)
      expect(json_response["error"]).to eq("Invalid email or password")
    end

    it "rate limits repeated failed attempts for an email address" do
      8.times do
        post "/api/v1/sessions",
             params: { email: "target@example.com", password: "wrong" }.to_json,
             headers: { "Content-Type" => "application/json", "Accept" => "application/json" }
      end

      post "/api/v1/sessions",
           params: { email: "TARGET@example.com", password: "wrong" }.to_json,
           headers: { "Content-Type" => "application/json", "Accept" => "application/json" }

      expect(response).to have_http_status(:too_many_requests)
      expect(response.headers["Retry-After"]).to be_present
    end
  end

  describe "destroy session" do
    it "should destroy a session to logout a user" do
      user1 = User.create!(first_name: "John", last_name: "Doe", email: "lame@gmail.com", password: "1234password", password_confirmation: "1234password")

      post "/api/v1/sessions", params: {
        email: user1.email,
        password: "1234password"
      }.to_json, headers: { "Content-Type" => "application/json", "Accept" => "application/json" }

      json_response = JSON.parse(response.body)

      expect(response.status).to eq(200)
      expect(json_response["data"]["id"]).to eq(user1.id.to_s)
      
      delete "/api/v1/sessions/#{user1.id}"

      json_response = JSON.parse(response.body)

      expect(response.status).to eq(200)
      expect(json_response["message"]).to eq("Logged out successfully")
    end
  end
end
