FactoryBot.define do
  factory :playlist do
    user
    name { "Late Night Signal" }
    description { "A curated radio block." }
    host_name { "Poole and the Gang" }
    status { "draft" }
  end
end
