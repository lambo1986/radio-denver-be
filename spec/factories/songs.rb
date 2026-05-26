FactoryBot.define do
  factory :song do
    playlist
    name { "Station Intro" }
    artist { "Poole and the Gang" }
    album { "Host Breaks" }
    duration { 30 }
    position { 1 }
  end
end
