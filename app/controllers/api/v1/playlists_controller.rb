class Api::V1::PlaylistsController < ApplicationController
  skip_before_action :verify_authenticity_token, only: :public_schedule
  before_action :authenticate_request, except: :public_schedule
  before_action :set_playlist, only: [:show, :update, :destroy]
  before_action :require_admin, only: [:mark_ready, :request_changes, :reopen_for_edits, :reject, :schedule, :render_master, :deliver]
  before_action :set_station_playlist, only: [:mark_ready, :request_changes, :reopen_for_edits, :reject, :schedule, :render_master, :deliver]

  def index
    playlists = playlist_scope.includes(:full_show_audio_file, songs: :audio_file).order(created_at: :desc)
    render json: playlists.map { |playlist| serialize_playlist(playlist) }
  end

  def public_schedule
    playlists = Playlist
                .where(status: %w[scheduled aired])
                .where.not(scheduled_at: nil)
                .includes(:full_show_audio_file, songs: :audio_file)
                .order(:scheduled_at)

    render json: playlists.map { |playlist| serialize_public_playlist(playlist) }
  end

  def show
    render json: serialize_playlist(@playlist)
  end

  def create
    playlist = @current_user.playlists.build(playlist_attributes)
    return render_full_show_upload_errors if full_show_upload_errors.any?

    uploaded_full_show = attach_full_show_file(playlist)
    build_songs(playlist)
    if playlist.status == 'submitted' && submission_errors(playlist).any?
      cleanup_full_show_upload(uploaded_full_show)
      return render_submission_errors(playlist)
    end

    if playlist.save
      render json: serialize_playlist(playlist), status: :created
    else
      cleanup_full_show_upload(uploaded_full_show)
      render json: { errors: playlist.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def update
    return render_full_show_upload_errors if full_show_upload_errors.any?

    update_errors = nil
    updated = false
    previous_full_show = @playlist.full_show_audio_file
    previous_rendered_master = @playlist.rendered_master_audio_file
    uploaded_full_show = nil

    ActiveRecord::Base.transaction do
      @playlist.assign_attributes(playlist_attributes)
      uploaded_full_show = attach_full_show_file(@playlist)

      if playlist_params[:songs].present?
        @playlist.songs.destroy_all
        build_songs(@playlist)
      end

      update_errors = submission_errors(@playlist) if @playlist.status == 'submitted'
      update_errors = @playlist.errors.full_messages unless update_errors.present? || @playlist.save

      if update_errors.present?
        raise ActiveRecord::Rollback
      else
        updated = true
      end
    end

    if updated
      cleanup_replaced_full_show(previous_full_show, uploaded_full_show)
      invalidate_rendered_master(previous_rendered_master)
      render json: serialize_playlist(@playlist)
    else
      cleanup_full_show_upload(uploaded_full_show, destroy_record: false)
      @playlist.reload
      render json: { errors: update_errors }, status: :unprocessable_entity
    end
  rescue StandardError
    cleanup_full_show_upload(uploaded_full_show, destroy_record: false)
    raise
  end

  def destroy
    @playlist.destroy
    head :no_content
  end

  def mark_ready
    return render_transition_error('Only submitted shows can be marked ready.') unless @playlist.status == 'submitted'
    return render_readiness_errors if @playlist.readiness_issues.any?
    return render_confirmation_errors if @playlist.confirmation_issues.any?

    if @playlist.update(status: 'ready', review_notes: review_params[:review_notes], reviewed_at: Time.current)
      render json: serialize_playlist(@playlist)
    else
      render json: { errors: @playlist.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def request_changes
    if @playlist.update(status: 'needs_edits', review_notes: review_params[:review_notes], reviewed_at: Time.current)
      render json: serialize_playlist(@playlist)
    else
      render json: { errors: @playlist.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def reopen_for_edits
    previous_rendered_master = @playlist.rendered_master_audio_file
    if @playlist.update(
      status: 'needs_edits',
      scheduled_at: nil,
      delivery_status: 'not_sent',
      delivery_target: nil,
      delivery_reference: nil,
      delivery_manifest: {},
      delivered_at: nil,
      rendered_master_audio_file: nil,
      render_status: 'not_rendered',
      render_error: nil,
      rendered_at: nil,
      review_notes: review_params[:review_notes],
      reviewed_at: Time.current
    )
      cleanup_audio_file(previous_rendered_master)
      render json: serialize_playlist(@playlist)
    else
      render json: { errors: @playlist.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def reject
    if @playlist.update(status: 'rejected', review_notes: review_params[:review_notes], reviewed_at: Time.current)
      render json: serialize_playlist(@playlist)
    else
      render json: { errors: @playlist.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def schedule
    return render_transition_error('Only ready or scheduled shows can be scheduled.') unless %w[ready scheduled].include?(@playlist.status)
    return render_readiness_errors if @playlist.readiness_issues.any?

    scheduled_at = parse_scheduled_at
    return render_transition_error('Choose a valid scheduled date and time.') if scheduled_at.blank?

    conflicts = @playlist.scheduling_conflicts(scheduled_at)
    if conflicts.any?
      names = conflicts.map { |playlist| "#{playlist.name} at #{playlist.scheduled_at.iso8601}" }
      return render_transition_error("Schedule overlaps with #{names.join(', ')}.")
    end

    if @playlist.update(status: 'scheduled', scheduled_at: scheduled_at)
      render json: serialize_playlist(@playlist)
    else
      render json: { errors: @playlist.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def deliver
    return render_transition_error('Only scheduled shows can be queued for delivery.') unless @playlist.status == 'scheduled'
    return render_transition_error('Schedule the show before queueing it for delivery.') if @playlist.scheduled_at.blank?
    return render_readiness_errors if @playlist.readiness_issues.any?

    delivered_playlist = StreamDeliveryService.new(@playlist, target: delivery_params[:target]).deliver
    render json: serialize_playlist(delivered_playlist)
  end

  def render_master
    return render_transition_error('Only ready or scheduled shows can be rendered.') unless %w[ready scheduled].include?(@playlist.status)
    return render_readiness_errors if @playlist.readiness_issues.any?

    @playlist.update!(render_status: 'rendering', render_error: nil)
    RenderBroadcastMasterJob.perform_later(@playlist.id)
    render json: serialize_playlist(@playlist), status: :accepted
  end

  private

  def playlist_scope
    if params[:scope] == 'station'
      return Playlist.none unless @current_user.admin?

      return Playlist.where(status: %w[submitted needs_edits rejected ready scheduled aired])
    end

    @current_user.playlists
  end

  def set_playlist
    @playlist = @current_user.playlists.find(params[:id])
  end

  def set_station_playlist
    @playlist = Playlist.where(status: %w[submitted needs_edits rejected ready scheduled aired]).find(params[:id])
  end

  def playlist_params
    params.require(:playlist).permit(
      :name,
      :description,
      :host_name,
      :status,
      :scheduled_at,
      :delivery_target,
      :full_show_file,
      :full_show_duration,
      :audio_authorized,
      :metadata_confirmed,
      :explicit_content_confirmed,
      :contains_explicit_content,
      songs: [
        :name,
        :artist,
        :album,
        :duration,
        :file_url,
        :file_name,
        :audio_file_id
      ]
    )
  end

  def playlist_attributes
    attributes = playlist_params.except(:songs, :full_show_file, :full_show_duration, :delivery_target)
    attributes[:confirmations_recorded_at] = Time.current if attributes[:status] == 'submitted'
    attributes
  end

  def schedule_params
    params.require(:playlist).permit(:scheduled_at)
  end

  def review_params
    params.fetch(:review, {}).permit(:review_notes)
  end

  def delivery_params
    params.fetch(:delivery, {}).permit(:target)
  end

  def parse_scheduled_at
    Time.zone.parse(schedule_params[:scheduled_at].to_s)
  rescue ArgumentError
    nil
  end

  def render_readiness_errors
    render json: { errors: @playlist.readiness_issues }, status: :unprocessable_entity
  end

  def render_transition_error(message)
    render json: { errors: [message] }, status: :unprocessable_entity
  end

  def render_confirmation_errors
    render json: { errors: @playlist.confirmation_issues }, status: :unprocessable_entity
  end

  def render_submission_errors(playlist)
    render json: { errors: submission_errors(playlist) }, status: :unprocessable_entity
  end

  def submission_errors(playlist)
    playlist.readiness_issues + playlist.confirmation_issues
  end

  def build_songs(playlist)
    song_inputs.each_with_index do |song_params, index|
      playlist.songs.build(
        name: song_params[:name],
        artist: song_params[:artist],
        album: song_params[:album].presence || 'Single',
        duration: normalize_duration(song_params[:duration]),
        file_url: song_params[:file_url],
        file_name: song_params[:file_name],
        audio_file_id: owned_or_shared_audio_file_id(song_params[:audio_file_id]),
        position: index + 1
      )
    end
  end

  def song_inputs
    songs = playlist_params[:songs]
    return [] if songs.blank?

    songs.respond_to?(:values) ? songs.values : Array(songs)
  end

  def attach_full_show_file(playlist)
    uploaded_file = playlist_params[:full_show_file]
    return unless uploaded_file.present?

    audio_file = @current_user.audio_files.build(
      name: uploaded_file.original_filename,
      title: playlist.name,
      artist: playlist.host_name,
      kind: 'full_show',
      visibility: 'private',
      size: uploaded_file.size,
      content_type: uploaded_file.content_type,
      duration: playlist_params[:full_show_duration]
    )

    upload = s3_service.upload_uploaded_file(uploaded_file, prefix: 'full_shows')
    audio_file.s3_key = upload[:key]
    audio_file.url = upload[:url]
    audio_file.save!
    playlist.full_show_audio_file = audio_file
    audio_file
  rescue StandardError
    s3_service.delete_file(upload[:key]) if upload&.dig(:key)
    raise
  end

  def cleanup_full_show_upload(audio_file, destroy_record: true)
    return unless audio_file

    begin
      s3_service.delete_file(audio_file.s3_key) if audio_file.s3_key.present?
    rescue StandardError => error
      Rails.logger.error("Full-show S3 cleanup failed for #{audio_file.s3_key}: #{error.message}")
    ensure
      audio_file.destroy if destroy_record && audio_file.persisted?
    end
  end

  def cleanup_replaced_full_show(previous_audio_file, new_audio_file)
    return unless previous_audio_file && new_audio_file
    return if previous_audio_file.id == new_audio_file.id
    return if Playlist.where(full_show_audio_file_id: previous_audio_file.id).exists?

    cleanup_full_show_upload(previous_audio_file)
  end

  def invalidate_rendered_master(audio_file)
    return unless audio_file

    @playlist.update_columns(
      rendered_master_audio_file_id: nil,
      render_status: 'not_rendered',
      render_error: nil,
      rendered_at: nil
    )
    cleanup_audio_file(audio_file)
  end

  def cleanup_audio_file(audio_file)
    return unless audio_file

    s3_service.delete_file(audio_file.s3_key) if audio_file.s3_key.present?
    audio_file.destroy!
  rescue StandardError => error
    Rails.logger.error("Audio cleanup failed for #{audio_file&.s3_key}: #{error.message}")
  end

  def owned_or_shared_audio_file_id(audio_file_id)
    return if audio_file_id.blank?

    AudioFile.library_visible.or(AudioFile.owned_by(@current_user)).find(audio_file_id).id
  end

  def normalize_duration(duration)
    return duration if duration.is_a?(Integer)
    return 0 if duration.blank?

    parts = duration.to_s.split(':').map(&:to_i)
    return parts[0] if parts.one?

    parts.reverse.each_with_index.sum { |value, index| value * (60**index) }
  end

  def full_show_upload_errors
    uploaded_file = playlist_params[:full_show_file]
    return [] if uploaded_file.blank?

    errors = []
    errors << 'Full-show audio is too large. Maximum size is 500 MB.' if uploaded_file.size > AudioFile::MAX_UPLOAD_SIZE
    unless AudioFile::SUPPORTED_CONTENT_TYPES.include?(uploaded_file.content_type)
      errors << 'Full show must be an MP3, WAV, FLAC, M4A, AAC, OGG, or WebM audio file.'
    end
    errors
  end

  def render_full_show_upload_errors
    render json: { errors: full_show_upload_errors }, status: :unprocessable_entity
  end

  def s3_service
    @s3_service ||= AwsS3Service.new(ENV.fetch('AWS_BUCKET_NAME', 'radio-denver'))
  end

  def serialize_playlist(playlist)
    {
      id: playlist.id,
      user_id: playlist.user_id,
      name: playlist.name,
      description: playlist.description,
      host_name: playlist.host_name,
      status: playlist.status,
      scheduled_at: playlist.scheduled_at,
      review_notes: playlist.review_notes,
      reviewed_at: playlist.reviewed_at,
      audio_authorized: playlist.audio_authorized,
      metadata_confirmed: playlist.metadata_confirmed,
      explicit_content_confirmed: playlist.explicit_content_confirmed,
      contains_explicit_content: playlist.contains_explicit_content,
      confirmations_recorded_at: playlist.confirmations_recorded_at,
      delivery_status: playlist.delivery_status,
      delivery_target: playlist.delivery_target,
      delivery_reference: playlist.delivery_reference,
      delivery_manifest: playlist.delivery_manifest,
      delivered_at: playlist.delivered_at,
      render_status: playlist.render_status,
      render_error: playlist.render_error,
      rendered_at: playlist.rendered_at,
      rendered_master_audio_file: serialize_master_audio_file(playlist.rendered_master_audio_file),
      full_show_audio_file: playlist.full_show_audio_file && {
        id: playlist.full_show_audio_file.id,
        name: playlist.full_show_audio_file.name,
        url: playlist.full_show_audio_file.public_url,
        duration: playlist.full_show_audio_file.duration
      },
      songs: playlist.songs.map do |song|
        {
          id: song.id,
          name: song.name,
          artist: song.artist,
          album: song.album,
          duration: song.duration,
          position: song.position,
          file_url: song.audio_file&.public_url || song.file_url,
          file_name: song.file_name,
          audio_file_id: song.audio_file_id,
          audio_file: song.audio_file && {
            id: song.audio_file.id,
            name: song.audio_file.name,
            title: song.audio_file.title,
            artist: song.audio_file.artist,
            url: song.audio_file.public_url,
            kind: song.audio_file.kind,
            visibility: song.audio_file.visibility,
            duration: song.audio_file.duration
          }
        }
      end,
      created_at: playlist.created_at
    }
  end

  def serialize_master_audio_file(audio_file)
    return unless audio_file

    {
      id: audio_file.id,
      name: audio_file.name,
      url: audio_file.public_url,
      duration: audio_file.duration,
      content_type: audio_file.content_type,
      size: audio_file.size
    }
  end

  def serialize_public_playlist(playlist)
    {
      id: playlist.id,
      name: playlist.name,
      description: playlist.description,
      host_name: playlist.host_name,
      status: playlist.status,
      scheduled_at: playlist.scheduled_at,
      delivery_status: playlist.delivery_status,
      full_show_audio_file: playlist.full_show_audio_file && {
        duration: playlist.full_show_audio_file.duration
      },
      songs: playlist.songs.map do |song|
        {
          id: song.id,
          name: song.name,
          artist: song.artist,
          album: song.album,
          duration: song.duration,
          position: song.position
        }
      end
    }
  end
end
