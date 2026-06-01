require "rails_helper"

RSpec.describe "create a new user endpoint", type: :request do
  describe "POST /api/v1/users" do
    it "creates a new user in the database" do
      invitation = create(:host_invitation, code: "MUSIC123")

      post "/api/v1/users", params: {
        user: {
          first_name: "Jerry",
          last_name: "Seinfeld",
          email: "pinebreeze@millionz.cloudflare.com",
          password: "shy_guy_23",
          password_confirmation: "shy_guy_23",
          invite_code: invitation.code
        }
      }.to_json, headers: { "Content-Type" => "application/json", "Accept" => "application/json" }

      json_response = JSON.parse(response.body)

      expect(response.status).to eq(201)
      expect(json_response["data"]["attributes"]["first_name"]).to eq("Jerry")
      expect(invitation.reload.used_at).to be_present
    end

    it "requires an invite code" do
      post "/api/v1/users", params: {
        user: {
          first_name: "Elaine",
          last_name: "Benes",
          email: "elaine@example.com",
          password: "shy_guy_23",
          password_confirmation: "shy_guy_23"
        }
      }.to_json, headers: { "Content-Type" => "application/json", "Accept" => "application/json" }

      json_response = JSON.parse(response.body)

      expect(response.status).to eq(403)
      expect(json_response["error"]).to eq("A valid host invite code is required.")
    end

    it "sends back a 422 if invited user data is invalid" do
      invitation = create(:host_invitation)

      post "/api/v1/users", params: {
        user: {
          first_name: "",
          last_name: "",
          email: "",
          password: "",
          password_confirmation: "",
          invite_code: invitation.code
        }
      }.to_json, headers: { "Content-Type" => "application/json", "Accept" => "application/json" }

      json_response = JSON.parse(response.body)

      expect(response.status).to eq(422)
      expect(json_response["errors"]).to include("First name can't be blank")
    end
  end
end
