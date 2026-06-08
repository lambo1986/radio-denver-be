require 'rails_helper'

RSpec.describe User, type: :model do
  describe 'validations' do
    it { should validate_presence_of(:first_name) }
    it { should validate_presence_of(:last_name) }
    it { should validate_presence_of(:email) }
    it { should validate_uniqueness_of(:email).case_insensitive }
    it { should validate_presence_of(:password_digest) }
    it { should validate_inclusion_of(:role).in_array(%w[host admin]) }
  end

  describe 'associations' do
    it { should have_many(:playlists) }
  end

  describe 'user creation' do
    it "should be able to create a new user" do
      user1 = User.create!(first_name: "John", last_name: "Doe", email: "lame@gmail.com", password: "1234password", password_confirmation: "1234password")
      user2 = User.create!(first_name: "Jane", last_name: "Doe", email: "lamby@gmail.com", password: "1265password", password_confirmation: "1265password")
      user3 = User.create!(first_name: "Bill", last_name: "Dot", email: "larre@gmail.com", password: "12345pass", password_confirmation: "12345pass")

      expect(user1.first_name).to eq("John")
      expect(user1.last_name).to eq("Doe")
      expect(user1.email).to eq("lame@gmail.com")
      expect(user1.password).to be_a(String)
      expect(user1.role).to eq("host")
      expect(user2.first_name).to eq("Jane")
      expect(user3.last_name).to eq("Dot")
      expect(User.count).to eq(3)
    end

    it "cannot create a user with an existing email" do
      user1 = User.create!(first_name: "John", last_name: "Doe", email: "lame@gmail.com", password: "1234password", password_confirmation: "1234password")
      user2 = User.new(first_name: "Jane", last_name: "Doe", email: "lame@gmail.com", password: "1265password", password_confirmation: "1265password")

      expect(user1.email).to eq("lame@gmail.com")
      expect { user2.save! }.to raise_error(ActiveRecord::RecordInvalid)
      expect(user2.save).to eq(false)
      expect(User.count).to eq(1)
    end

    it "normalizes email casing and whitespace" do
      user = create(:user, email: "  Host@Example.COM ")

      expect(user.email).to eq("host@example.com")
      expect(User.find_by_email("HOST@example.com")).to eq(user)
    end

    it "rejects an existing email with different casing" do
      create(:user, email: "host@example.com")
      duplicate = build(:user, email: "HOST@EXAMPLE.COM")

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:email]).to include("has already been taken")
    end
  end
end
