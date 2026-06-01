FactoryBot.define do
  factory :host_invitation do
    sequence(:code) { |n| "HOST#{n.to_s.rjust(4, '0')}" }
    email { nil }
    notes { "Invite a local host" }
    association :invited_by, factory: [:user, :admin]
    expires_at { 30.days.from_now }
  end
end
