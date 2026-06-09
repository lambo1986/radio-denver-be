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
