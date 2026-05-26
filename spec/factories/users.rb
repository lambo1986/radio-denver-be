FactoryBot.define do
  factory :user do
    first_name { "John" }
    last_name { "Doe" }
    sequence(:email) { |n| "john#{n}@example.com" }
    password { "securepassword" }
    password_confirmation { "securepassword" }
  end
end
