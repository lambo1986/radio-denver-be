require 'fileutils'
require 'tmpdir'

class AzuracastMasterDeliveryService
  DeliveryError = Class.new(StandardError)
  DEFAULT_PLAYLIST_NAME = 'Human Frequency Shows'
  DEFAULT_MEDIA_FOLDER = 'human-frequency-shows'

  def self.deliver_broadcast_master_to_azuracast(show_id)
    playlist = Playlist.find_by(id: show_id)
    raise DeliveryError, 'Show was not found.' unless playlist

    new(playlist).deliver
  end

  def initialize(playlist, azuracast_client: nil, s3_service: nil)
    @playlist = playlist
    @azuracast_client = azuracast_client || AzuracastClient.new
    @s3_service = s3_service || AwsS3Service.new(ENV.fetch('AWS_BUCKET_NAME', 'radio-denver'))
  end

  def deliver
    validate_playlist!

    target_playlist = resolve_target_playlist
    remote_path = build_remote_path
    master_audio = playlist.rendered_master_audio_file

    Dir.mktmpdir("azuracast-master-#{playlist.id}-") do |directory|
      local_path = File.join(directory, master_audio.name)
      s3_service.download_file(master_audio.s3_key, local_path)
      validate_downloaded_master!(local_path)
      uploaded_media = azuracast_client.upload_media_file(local_path, remote_path: remote_path)
      media = normalize_uploaded_media(uploaded_media)
      media_id = media.fetch(:id)
      playlist_ids = existing_playlist_ids(media)
      assignment = azuracast_client.assign_media_to_playlist(media_id, target_playlist.fetch(:id), existing_playlist_ids: playlist_ids)
      verified_assignment = verify_playlist_assignment!(media_id, target_playlist.fetch(:id), assignment)

      update_playlist!(media, target_playlist, verified_assignment, remote_path)
    end

    playlist
  rescue DeliveryError => error
    record_failure!(error.message)
    raise
  rescue StandardError => error
    message = sanitize_error("AzuraCast delivery failed: #{error.message}")
    record_failure!(message)
    Rails.logger.error("AzuraCast master delivery failed for playlist #{playlist.id}: #{error.class}: #{message}")
    raise DeliveryError, message
  end

  private

  attr_reader :playlist, :azuracast_client, :s3_service

  def validate_playlist!
    raise DeliveryError, 'AZURACAST_API_KEY is not configured.' unless azuracast_client.api_key_configured?
    raise DeliveryError, 'Only scheduled shows can be uploaded to AzuraCast.' unless playlist.status == 'scheduled'
    raise DeliveryError, 'Queue an AzuraCast stream package before uploading to AzuraCast.' unless manifest.present?
    raise DeliveryError, 'AzuraCast delivery requires a single-master stream package.' unless manifest.dig('show', 'package_mode') == 'single_master'
    raise DeliveryError, 'AzuraCast stream package is missing the broadcast master asset.' unless broadcast_master_asset.present?
    raise DeliveryError, 'Render the broadcast master before uploading to AzuraCast.' unless playlist.render_status == 'ready'
    raise DeliveryError, 'Rendered broadcast master is missing.' unless playlist.rendered_master_audio_file&.s3_key.present?
    raise DeliveryError, 'Broadcast master asset is missing a durable S3 key.' if durable_master_s3_key.blank?
    raise DeliveryError, 'Schedule the show before uploading to AzuraCast.' if playlist.scheduled_at.blank?
  end

  def resolve_target_playlist
    playlist_id = configured_playlist_id
    return resolve_target_playlist_by_id(playlist_id) if playlist_id.present?

    playlist_name = configured_playlist_name
    playlist = azuracast_client.find_playlist_by_name(playlist_name)
    return playlist if playlist.present?

    available = azuracast_client.get_playlists
    names = Array(available).map { |item| item['name'] || item[:name] }.compact
    raise DeliveryError, "AzuraCast playlist \"#{playlist_name}\" was not found. Available playlists: #{names.join(', ')}."
  end

  def resolve_target_playlist_by_id(playlist_id)
    playlists = azuracast_client.get_playlists
    playlist = Array(playlists).find { |item| (item['id'] || item[:id]).to_s == playlist_id.to_s }
    return normalize_playlist_record(playlist) if playlist.present?

    names = Array(playlists).map { |item| "#{item['name'] || item[:name]} (#{item['id'] || item[:id]})" }.compact
    raise DeliveryError, "AzuraCast playlist id \"#{playlist_id}\" was not found. Available playlists: #{names.join(', ')}."
  end

  def normalize_playlist_record(record)
    {
      id: record['id'] || record[:id],
      name: record['name'] || record[:name]
    }.compact
  end

  def configured_playlist_id
    ENV['AZURACAST_PLAYLIST_ID'].presence ||
      manifest.dig('azuracast', 'playlist_id').presence ||
      manifest.dig('provider', 'playlist_id').presence
  end

  def configured_playlist_name
    ENV['AZURACAST_PLAYLIST_NAME'].presence ||
      manifest.dig('provider', 'recommended_playlist').presence ||
      DEFAULT_PLAYLIST_NAME
  end

  def configured_media_folder
    ENV['AZURACAST_MEDIA_FOLDER'].presence ||
      manifest.dig('provider', 'recommended_media_folder').presence ||
      DEFAULT_MEDIA_FOLDER
  end

  def build_remote_path
    folder = configured_media_folder.to_s.gsub(%r{\A/+|/+\z}, '')
    filename = playlist.rendered_master_audio_file.name.to_s.presence || "#{playlist.name.parameterize}-broadcast-master.mp3"
    [folder, filename].compact_blank.join('/')
  end

  def validate_downloaded_master!(local_path)
    raise DeliveryError, 'Broadcast master could not be downloaded server-side.' unless File.exist?(local_path)
    raise DeliveryError, 'Downloaded broadcast master is empty.' unless File.size(local_path).positive?
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

  def verify_playlist_assignment!(media_id, playlist_id, assignment)
    return assignment if playlist_assignment_present?(assignment, playlist_id)

    refreshed_media = azuracast_client.get_media_file(media_id)
    return refreshed_media if playlist_assignment_present?(refreshed_media, playlist_id)

    raise DeliveryError, 'AzuraCast did not confirm playlist assignment.'
  end

  def playlist_assignment_present?(payload, playlist_id)
    playlist_ids_from_payload(payload).map(&:to_s).include?(playlist_id.to_s)
  end

  def playlist_ids_from_payload(payload)
    return [] unless payload.respond_to?(:[])

    playlists = payload['playlists'] || payload[:playlists] || payload.dig('media', 'playlists') || payload.dig(:media, :playlists)
    Array(playlists).filter_map do |item|
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
    playlist.record_timeline_event!(
      'uploaded',
      message: 'Broadcast master uploaded to AzuraCast and assigned to the configured playlist.',
      metadata: {
        azuracast_media_id: media[:id],
        azuracast_playlist_id: target_playlist.fetch(:id),
        azuracast_playlist_name: target_playlist[:name] || target_playlist['name'],
        remote_path: remote_path
      },
      occurred_at: now
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

  def manifest
    @manifest ||= playlist.delivery_manifest.to_h
  end

  def broadcast_master_asset
    @broadcast_master_asset ||= Array(manifest['assets']).find { |asset| asset['role'] == 'broadcast_master' }
  end

  def durable_master_s3_key
    playlist.rendered_master_audio_file&.s3_key.presence || broadcast_master_asset&.dig('s3_key').presence
  end

  def record_failure!(message)
    return unless playlist.persisted?

    failed_manifest = manifest.deep_dup
    failed_manifest['azuracast_error'] = {
      'message' => sanitize_error(message),
      'failed_at' => Time.current.iso8601
    }
    playlist.update_columns(
      delivery_status: 'failed',
      delivery_manifest: failed_manifest
    )
    playlist.record_timeline_event!(
      'upload_failed',
      message: sanitize_error(message),
      metadata: { delivery_target: 'azuracast' }
    )
  end

  def sanitize_error(message)
    sanitized = message.to_s
    sanitized = sanitized.gsub(ENV['AZURACAST_API_KEY'].to_s, '[redacted]') if ENV['AZURACAST_API_KEY'].present?
    sanitized.gsub(/https:\/\/[^\s?]+[^\s]*X-Amz-[^\s]*/i, '[redacted-s3-url]')
  end
end
