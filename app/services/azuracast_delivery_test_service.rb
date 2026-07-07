class AzuracastDeliveryTestService
  DeliveryTestError = Class.new(StandardError) do
    attr_reader :report

    def initialize(message, report)
      @report = report
      super(message)
    end
  end

  STEP_LABELS = {
    render_master: 'Render broadcast master',
    queue_package: 'Queue AzuraCast package',
    upload_master: 'Upload master to AzuraCast',
    verify_assignment: 'Confirm playlist assignment',
    now_playing: 'Check now-playing visibility'
  }.freeze

  def initialize(playlist, actor: nil, renderer: nil, delivery_service: nil, azuracast_client: nil)
    @playlist = playlist
    @actor = actor
    @renderer = renderer
    @delivery_service = delivery_service
    @azuracast_client = azuracast_client || AzuracastClient.new
    @report = base_report
  end

  def run
    validate_show!
    render_master
    queue_package
    upload_master
    verify_assignment
    check_now_playing
    persist_report!
    playlist.record_timeline_event!(
      'delivery_test',
      actor: actor,
      message: 'AzuraCast delivery test completed.',
      metadata: { status: report[:status], reference: report[:reference] },
      system_generated: false
    )
    report.deep_stringify_keys
  rescue DeliveryTestError
    persist_report!
    raise
  rescue StandardError => error
    fail_step(current_step || :upload_master, error.message)
    persist_report!
    raise DeliveryTestError.new(error.message, report.deep_stringify_keys)
  end

  private

  attr_reader :playlist, :actor, :azuracast_client, :report

  def validate_show!
    raise_error(:queue_package, 'Only scheduled shows can run an AzuraCast delivery test.') unless playlist.status == 'scheduled'
    raise_error(:queue_package, 'Schedule the show before running an AzuraCast delivery test.') if playlist.scheduled_at.blank?
    raise_error(:queue_package, playlist.readiness_issues.join(' ')) if playlist.readiness_issues.any?
    unless azuracast_client.api_key_configured?
      needs_configuration(:upload_master, 'AZURACAST_API_KEY is not configured.')
      raise DeliveryTestError.new('AzuraCast API key is not configured.', report.deep_stringify_keys)
    end
  end

  def render_master
    start_step(:render_master)
    if playlist.render_status == 'ready' && playlist.rendered_master_audio_file&.s3_key.present?
      succeed_step(:render_master, 'Existing rendered master is ready.', master_details)
      return
    end

    renderer.render
    playlist.reload
    succeed_step(:render_master, 'Broadcast master rendered.', master_details)
  rescue StandardError => error
    fail_step(:render_master, error.message)
    raise DeliveryTestError.new(error.message, report.deep_stringify_keys)
  end

  def queue_package
    start_step(:queue_package)
    if playlist.delivery_status == 'queued' && playlist.delivery_target == 'azuracast' && playlist.delivery_manifest.dig('show', 'package_mode') == 'single_master'
      succeed_step(:queue_package, 'Existing AzuraCast single-master package is ready.', package_details)
      return
    end

    delivery_service.deliver
    playlist.reload
    succeed_step(:queue_package, 'AzuraCast stream package queued.', package_details)
  rescue StandardError => error
    fail_step(:queue_package, error.message)
    raise DeliveryTestError.new(error.message, report.deep_stringify_keys)
  end

  def upload_master
    start_step(:upload_master)
    AzuracastMasterDeliveryService.deliver_broadcast_master_to_azuracast(playlist.id)
    playlist.reload
    succeed_step(:upload_master, 'Broadcast master uploaded to AzuraCast.', upload_details)
  rescue AzuracastMasterDeliveryService::DeliveryError => error
    fail_step(:upload_master, error.message)
    raise DeliveryTestError.new(error.message, report.deep_stringify_keys)
  end

  def verify_assignment
    start_step(:verify_assignment)
    azuracast = playlist.delivery_manifest['azuracast'] || {}
    if playlist.delivery_status == 'sent' && azuracast['media_id'].present? && (azuracast['playlist_id'].present? || azuracast['playlist_name'].present?)
      succeed_step(:verify_assignment, 'AzuraCast confirmed upload and playlist assignment.', upload_details)
    else
      raise_error(:verify_assignment, 'AzuraCast assignment is missing from the delivery manifest.')
    end
  end

  def check_now_playing
    start_step(:now_playing)
    payload = azuracast_client.now_playing
    details = {
      ok: payload[:ok],
      fetched_at: payload[:fetched_at],
      current_title: payload.dig(:nowPlaying, :title),
      current_artist: payload.dig(:nowPlaying, :artist),
      current_playlist: payload.dig(:nowPlaying, :playlist),
      listeners: payload[:listeners]
    }.compact

    if payload[:ok]
      if now_playing_matches_show?(payload)
        succeed_step(:now_playing, 'Now-playing currently matches this show.', details)
      else
        skip_step(:now_playing, 'AzuraCast now-playing is reachable, but this uploaded show is not currently playing yet.', details)
      end
    else
      fail_step(:now_playing, payload[:error].presence || 'AzuraCast now-playing could not be reached.', details)
      raise DeliveryTestError.new('AzuraCast now-playing could not be reached.', report.deep_stringify_keys)
    end
  end

  def now_playing_matches_show?(payload)
    current_title = payload.dig(:nowPlaying, :title).to_s.downcase
    current_text = payload.dig(:nowPlaying, :text).to_s.downcase
    show_name = playlist.name.to_s.downcase
    current_title.include?(show_name) || current_text.include?(show_name)
  end

  def renderer
    @renderer ||= @renderer || BroadcastMasterRenderer.new(playlist)
  end

  def delivery_service
    @delivery_service ||= @delivery_service || StreamDeliveryService.new(playlist, target: 'azuracast')
  end

  def start_step(key)
    @current_step = key
    step(key)[:status] = 'running'
    step(key)[:started_at] = Time.current.iso8601
  end

  def succeed_step(key, message, details = {})
    finish_step(key, 'succeeded', message, details)
  end

  def skip_step(key, message, details = {})
    finish_step(key, 'skipped', message, details)
  end

  def needs_configuration(key, message, details = {})
    finish_step(key, 'needs_configuration', message, details)
  end

  def fail_step(key, message, details = {})
    finish_step(key, 'failed', message, details)
  end

  def finish_step(key, status, message, details)
    report[:status] = 'failed' if status == 'failed'
    step(key).merge!(
      status: status,
      message: sanitize(message),
      details: sanitize_payload(details),
      finished_at: Time.current.iso8601
    )
  end

  def raise_error(key, message)
    fail_step(key, message)
    raise DeliveryTestError.new(message, report.deep_stringify_keys)
  end

  def step(key)
    report[:steps].find { |item| item[:key] == key.to_s }
  end

  def current_step
    @current_step
  end

  def master_details
    audio_file = playlist.rendered_master_audio_file
    {
      audio_file_id: audio_file&.id,
      name: audio_file&.name,
      s3_key: audio_file&.s3_key,
      render_status: playlist.render_status,
      rendered_at: playlist.rendered_at&.iso8601
    }.compact
  end

  def package_details
    {
      delivery_status: playlist.delivery_status,
      delivery_target: playlist.delivery_target,
      delivery_reference: playlist.delivery_reference,
      package_mode: playlist.delivery_manifest.dig('show', 'package_mode'),
      manifest_generated_at: playlist.delivery_manifest['generated_at']
    }.compact
  end

  def upload_details
    azuracast = playlist.delivery_manifest['azuracast'] || {}
    {
      delivery_status: playlist.delivery_status,
      delivery_reference: playlist.delivery_reference,
      media_id: azuracast['media_id'],
      playlist_id: azuracast['playlist_id'],
      playlist_name: azuracast['playlist_name'],
      remote_path: azuracast['remote_path'],
      uploaded_at: azuracast['uploaded_at'],
      assigned_at: azuracast['assigned_at']
    }.compact
  end

  def persist_report!
    report[:finished_at] = Time.current.iso8601
    report[:status] = if report[:steps].any? { |item| item[:status] == 'failed' }
                        'failed'
                      elsif report[:steps].any? { |item| item[:status] == 'needs_configuration' }
                        'needs_configuration'
                      else
                        'completed'
                      end
    manifest = playlist.delivery_manifest.to_h.deep_merge('azuracast_delivery_test' => report.deep_stringify_keys)
    playlist.update_columns(delivery_manifest: manifest)
  end

  def base_report
    {
      reference: "hf-azuracast-test-#{playlist.id}-#{Time.current.to_i}",
      status: 'running',
      show: {
        id: playlist.id,
        title: playlist.name,
        status: playlist.status,
        scheduled_at: playlist.scheduled_at&.iso8601
      },
      started_at: Time.current.iso8601,
      finished_at: nil,
      steps: STEP_LABELS.map do |key, label|
        {
          key: key.to_s,
          label: label,
          status: 'pending',
          message: nil,
          details: {},
          started_at: nil,
          finished_at: nil
        }
      end
    }
  end

  def sanitize_payload(value)
    case value
    when Hash
      value.transform_values { |item| sanitize_payload(item) }
    when Array
      value.map { |item| sanitize_payload(item) }
    when String
      sanitize(value)
    else
      value
    end
  end

  def sanitize(value)
    sanitized = value.to_s
    sanitized = sanitized.gsub(ENV['AZURACAST_API_KEY'].to_s, '[redacted]') if ENV['AZURACAST_API_KEY'].present?
    sanitized.gsub(/https:\/\/[^\s?]+[^\s]*X-Amz-[^\s]*/i, '[redacted-s3-url]')
  end
end
