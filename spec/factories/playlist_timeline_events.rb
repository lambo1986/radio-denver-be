FactoryBot.define do
  factory :playlist_timeline_event do
    playlist
    event_type { 'draft_saved' }
    message { 'Show draft saved.' }
    system_generated { false }
    occurred_at { Time.current }
    metadata { {} }
  end
end
