require 'rails_helper'

RSpec.describe "regular old user endpoints", type: :request do
  describe "GET /api/v1/users" do
    it "retuns an index of all users" do
      user1 = User.create!(first_name: "John", last_name: "Doe", email: "lame@gmail.com", password: "1234password", password_confirmation: "1234password", role: "admin")
      user2 = User.create!(first_name: "Jane", last_name: "Doe", email: "lamby@gmail.com", password: "1265password", password_confirmation: "1265password")
      user3 = User.create!(first_name: "Bill", last_name: "Dot", email: "larre@gmail.com", password: "12345pass", password_confirmation: "12345pass")

      get "/api/v1/users", headers: auth_headers(user1)

      json_response = JSON.parse(response.body)

      expect(response).to have_http_status(:success)
      expect(json_response["data"].length).to eq(3)
      expect(json_response["data"][0]["attributes"]["first_name"]).to eq(user1.first_name)
      expect(json_response["data"][1]["attributes"]["first_name"]).to eq(user2.first_name)
      expect(json_response["data"][2]["attributes"]["first_name"]).to eq(user3.first_name)
    end
  end

  describe "GET /api/v1/users/:id" do
    it "returns a single user" do
      user1 = User.create!(first_name: "John", last_name: "Doe", email: "lame@gmail.com", password: "1234password", password_confirmation: "1234password")

      get "/api/v1/users/#{user1.id}", headers: auth_headers(user1)

      json_response = JSON.parse(response.body)

      expect(response).to have_http_status(:success)
      expect(json_response["data"]["attributes"]["first_name"]).to eq("John")
    end
  end

  def auth_headers(user)
    {
      "Content-Type" => "application/json",
      "Accept" => "application/json",
      "Authorization" => "Bearer #{JsonWebTokenService.encode(user_id: user.id)}"
    }
  end
end
