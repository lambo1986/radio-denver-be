require 'fileutils'
require 'tmpdir'

class AzuracastMasterDeliveryService
  DeliveryError = Class.new(StandardError)
  DEFAULT_PLAYLIST_NAME = 'Human Frequency Shows'
  DEFAULT_MEDIA_FOLDER = 'human-frequency-shows'

  def initialize(playlist, azuracast_client: nil, s3_service: nil)
    @playlist = playlist
    @azuracast_client = azuracast_client || AzuracastClient.new
    @s3_service = s3_service || AwsS3Service.new(ENV.fetch('AWS_BUCKET_NAME', 'radio-denver'))
  end

  def deliver
    validate_playlist!

    target_playlist = resolve_target_playlist
    remote_path = build_remote_path

    Dir.mktmpdir("azuracast-master-#{playlist.id}-") do |directory|
      local_path = File.join(directory, playlist.rendered_master_audio_file.name)
      s3_service.download_file(playlist.rendered_master_audio_file.s3_key, local_path)
      uploaded_media = azuracast_client.upload_media_file(local_path, remote_path: remote_path)
      media = normalize_uploaded_media(uploaded_media)
      media_id = media.fetch(:id)
      playlist_ids = existing_playlist_ids(media)
      assignment = azuracast_client.assign_media_to_playlist(media_id, target_playlist.fetch(:id), existing_playlist_ids: playlist_ids)

      update_playlist!(media, target_playlist, assignment, remote_path)
    end

    playlist
  rescue DeliveryError
    mark_failed!
    raise
  rescue StandardError => error
    mark_failed!
    Rails.logger.error("AzuraCast master delivery failed for playlist #{playlist.id}: #{error.class}: #{error.message}")
    raise DeliveryError, "AzuraCast delivery failed: #{error.message}"
  end

  private

  attr_reader :playlist, :azuracast_client, :s3_service

  def validate_playlist!
    raise DeliveryError, 'Only scheduled shows can be uploaded to AzuraCast.' unless playlist.status == 'scheduled'
    raise DeliveryError, 'Render the broadcast master before uploading to AzuraCast.' unless playlist.render_status == 'ready'
    raise DeliveryError, 'Rendered broadcast master is missing.' unless playlist.rendered_master_audio_file&.s3_key.present?
    raise DeliveryError, 'Schedule the show before uploading to AzuraCast.' if playlist.scheduled_at.blank?
  end

  def resolve_target_playlist
    playlist_name = configured_playlist_name
    playlist = azuracast_client.find_playlist_by_name(playlist_name)
    return playlist if playlist.present?

    available = azuracast_client.get_playlists
    names = Array(available).map { |item| item['name'] || item[:name] }.compact
    raise DeliveryError, "AzuraCast playlist \"#{playlist_name}\" was not found. Available playlists: #{names.join(', ')}."
  end

  def configured_playlist_name
    ENV['AZURACAST_PLAYLIST_NAME'].presence ||
      playlist.delivery_manifest.dig('provider', 'recommended_playlist').presence ||
      DEFAULT_PLAYLIST_NAME
  end

  def configured_media_folder
    ENV['AZURACAST_MEDIA_FOLDER'].presence ||
      playlist.delivery_manifest.dig('provider', 'recommended_media_folder').presence ||
      DEFAULT_MEDIA_FOLDER
  end

  def build_remote_path
    folder = configured_media_folder.to_s.gsub(%r{\A/+|/+\z}, '')
    filename = playlist.rendered_master_audio_file.name.to_s.presence || "#{playlist.name.parameterize}-broadcast-master.mp3"
    [folder, filename].compact_blank.join('/')
  end

  def normalize_uploaded_media(payload)
    record = payload.is_a?(Array) ? payload.first : payload
    record = record['media'] || record[:media] if record.respond_to?(:[]) && (record['media'] || record[:media]).present?
    raise DeliveryError, 'AzuraCast upload did not return media details.' unless record.respond_to?(:[])

    id = record['id'] || record[:id]
    raise DeliveryError, 'AzuraCast upload did not return a media id.' if id.blank?

    {
      id: id,
      path: record['path'] || record[:path],
      title: record['title'] || record[:title],
      artist: record['artist'] || record[:artist],
      playlists: record['playlists'] || record[:playlists] || []
    }
  end

  def existing_playlist_ids(media)
    Array(media[:playlists]).filter_map do |item|
      item.is_a?(Hash) ? item['id'] || item[:id] : item
    end
  end

  def update_playlist!(media, target_playlist, assignment, remote_path)
    now = Time.current
    manifest = playlist.delivery_manifest.deep_dup
    manifest['azuracast'] = {
      'media_id' => media[:id],
      'playlist_id' => target_playlist.fetch(:id),
      'playlist_name' => target_playlist[:name] || target_playlist['name'],
      'remote_path' => remote_path,
      'uploaded_at' => now.iso8601,
      'assigned_at' => now.iso8601,
      'assignment_response' => safe_assignment_summary(assignment)
    }

    playlist.update!(
      delivery_status: 'sent',
      delivery_target: 'azuracast',
      delivery_reference: "azuracast-media-#{media[:id]}",
      delivery_manifest: manifest,
      delivered_at: now
    )
  end

  def safe_assignment_summary(assignment)
    return {} unless assignment.respond_to?(:[])

    {
      'id' => assignment['id'] || assignment[:id],
      'path' => assignment['path'] || assignment[:path],
      'playlists' => assignment['playlists'] || assignment[:playlists]
    }.compact
  end

  def mark_failed!
    playlist.update_columns(delivery_status: 'failed') if playlist.persisted?
  end
end
