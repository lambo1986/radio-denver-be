FactoryBot.define do
  factory :audio_file do
    user
    name { "station_intro.mp3" }
    title { "Station Intro" }
    artist { "Poole and the Gang" }
    album { "Host Breaks" }
    genre { "Radio" }
    size { 12345 }
    s3_key { "audio_files/test/station_intro.mp3" }
    url { "https://example.com/station_intro.mp3" }
    content_type { "audio/mpeg" }
    kind { "track" }
    visibility { "private" }
    explicit { false }
  end
end
