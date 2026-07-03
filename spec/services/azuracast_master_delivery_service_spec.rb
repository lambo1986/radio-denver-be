require 'rails_helper'

RSpec.describe AzuracastMasterDeliveryService, type: :service do
  let(:playlist) { create(:playlist, status: 'scheduled', scheduled_at: 1.hour.from_now, delivery_manifest: stream_manifest) }
  let(:master) do
    create(
      :audio_file,
      user: playlist.user,
      kind: 'full_show',
      name: 'midnight-brass-broadcast-master.mp3',
      s3_key: 'broadcast_masters/master.mp3',
      duration: 1200
    )
  end
  let(:stream_manifest) do
    {
      'provider' => {
        'recommended_playlist' => 'test show',
        'recommended_media_folder' => 'shows'
      }
    }
  end
  let(:azuracast_client) do
    instance_double(
      AzuracastClient,
      find_playlist_by_name: { id: 6814, name: 'test show' },
      upload_media_file: { 'id' => 123, 'path' => 'shows/midnight-brass-broadcast-master.mp3', 'playlists' => [] },
      assign_media_to_playlist: { 'id' => 123, 'path' => 'shows/midnight-brass-broadcast-master.mp3', 'playlists' => [{ 'id' => 6814 }] }
    )
  end
  let(:s3_service) { instance_double(AwsS3Service) }

  before do
    playlist.update!(rendered_master_audio_file: master, render_status: 'ready')
    allow(s3_service).to receive(:download_file) do |_key, destination|
      File.binwrite(destination, 'rendered master')
    end
  end

  it 'uploads the rendered master, assigns the playlist, and records AzuraCast ids' do
    described_class.new(playlist, azuracast_client: azuracast_client, s3_service: s3_service).deliver

    expect(s3_service).to have_received(:download_file).with('broadcast_masters/master.mp3', anything)
    expect(azuracast_client).to have_received(:find_playlist_by_name).with('test show')
    expect(azuracast_client).to have_received(:upload_media_file).with(anything, remote_path: 'shows/midnight-brass-broadcast-master.mp3')
    expect(azuracast_client).to have_received(:assign_media_to_playlist).with(123, 6814, existing_playlist_ids: [])

    playlist.reload
    expect(playlist.delivery_status).to eq('sent')
    expect(playlist.delivery_target).to eq('azuracast')
    expect(playlist.delivery_reference).to eq('azuracast-media-123')
    expect(playlist.delivery_manifest['azuracast']).to include(
      'media_id' => 123,
      'playlist_id' => 6814,
      'playlist_name' => 'test show',
      'remote_path' => 'shows/midnight-brass-broadcast-master.mp3'
    )
  end

  it 'fails clearly when the configured AzuraCast playlist does not exist' do
    allow(azuracast_client).to receive(:find_playlist_by_name).and_return(nil)
    allow(azuracast_client).to receive(:get_playlists).and_return([{ 'name' => 'default' }])

    expect do
      described_class.new(playlist, azuracast_client: azuracast_client, s3_service: s3_service).deliver
    end.to raise_error(described_class::DeliveryError, /was not found/)

    expect(playlist.reload.delivery_status).to eq('failed')
  end

  it 'requires a scheduled show with a ready rendered master' do
    playlist.update!(render_status: 'not_rendered', rendered_master_audio_file: nil)

    expect do
      described_class.new(playlist, azuracast_client: azuracast_client, s3_service: s3_service).deliver
    end.to raise_error(described_class::DeliveryError, /Render the broadcast master/)
  end
end
