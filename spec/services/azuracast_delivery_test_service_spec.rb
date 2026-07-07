require 'rails_helper'

RSpec.describe AzuracastDeliveryTestService, type: :service do
  let(:playlist) { create(:playlist, status: 'scheduled', scheduled_at: 1.hour.from_now) }
  let(:master) do
    create(
      :audio_file,
      user: playlist.user,
      kind: 'full_show',
      name: 'test-show-broadcast-master.mp3',
      s3_key: 'broadcast_masters/test-show.mp3',
      duration: 600
    )
  end
  let(:renderer) { instance_double(BroadcastMasterRenderer, render: playlist) }
  let(:delivery_service) { instance_double(StreamDeliveryService, deliver: playlist) }
  let(:azuracast_client) do
    instance_double(
      AzuracastClient,
      api_key_configured?: true,
      now_playing: {
        ok: true,
        fetched_at: Time.current.iso8601,
        nowPlaying: { title: 'Different show', artist: 'Station', playlist: 'Human Frequency Shows' },
        listeners: { current: 0 }
      }
    )
  end

  before do
    create(:song, playlist: playlist, duration: 600, file_url: 'https://example.com/audio.mp3')
    playlist.update!(
      rendered_master_audio_file: master,
      render_status: 'ready',
      delivery_status: 'queued',
      delivery_target: 'azuracast',
      delivery_reference: 'hf-show-test',
      delivery_manifest: {
        'show' => { 'package_mode' => 'single_master' },
        'azuracast' => {
          'media_id' => 99,
          'playlist_id' => 88,
          'playlist_name' => 'Human Frequency Shows',
          'remote_path' => 'human-frequency-shows/test.mp3'
        }
      }
    )
    allow(AzuracastMasterDeliveryService).to receive(:deliver_broadcast_master_to_azuracast) do
      playlist.update!(delivery_status: 'sent', delivery_reference: 'azuracast-media-99')
      playlist
    end
  end

  it 'walks through render, package, upload, assignment, and now-playing check without faking playback' do
    report = described_class.new(
      playlist,
      renderer: renderer,
      delivery_service: delivery_service,
      azuracast_client: azuracast_client
    ).run

    expect(report['steps'].map { |step| step['status'] }).to include('succeeded', 'skipped')
    expect(report['steps'].find { |step| step['key'] == 'now_playing' }['status']).to eq('skipped')
    expect(AzuracastMasterDeliveryService).to have_received(:deliver_broadcast_master_to_azuracast).with(playlist.id)
    expect(playlist.reload.delivery_manifest['azuracast_delivery_test']['status']).to eq('completed')
    expect(playlist.timeline_events.where(event_type: 'delivery_test')).to exist
  end

  it 'reports missing AzuraCast configuration without running upload' do
    allow(azuracast_client).to receive(:api_key_configured?).and_return(false)

    expect do
      described_class.new(playlist, azuracast_client: azuracast_client).run
    end.to raise_error(described_class::DeliveryTestError, /API key/)

    report = playlist.reload.delivery_manifest['azuracast_delivery_test']
    expect(report['status']).to eq('needs_configuration')
    expect(report['steps'].find { |step| step['key'] == 'upload_master' }['status']).to eq('needs_configuration')
  end
end
