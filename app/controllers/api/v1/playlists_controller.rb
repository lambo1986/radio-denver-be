class Api::V1::PlaylistsController < ApplicationController
  skip_before_action :verify_authenticity_token, only: :public_schedule
  before_action :authenticate_request, except: :public_schedule
  before_action :set_playlist, only: [:show, :update, :destroy]
  before_action :require_admin, only: [:mark_ready, :request_changes, :reopen_for_edits, :reject, :schedule, :deliver]
  before_action :set_station_playlist, only: [:mark_ready, :request_changes, :reopen_for_edits, :reject, :schedule, :deliver]

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
    attach_full_show_file(playlist)
    build_songs(playlist)

    if playlist.save
      render json: serialize_playlist(playlist), status: :created
    else
      render json: { errors: playlist.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def update
    @playlist.assign_attributes(playlist_attributes)
    attach_full_show_file(@playlist)

    if playlist_params[:songs].present?
      @playlist.songs.destroy_all
      build_songs(@playlist)
    end

    if @playlist.save
      render json: serialize_playlist(@playlist)
    else
      render json: { errors: @playlist.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def destroy
    @playlist.destroy
    head :no_content
  end

  def mark_ready
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
    if @playlist.update(
      status: 'needs_edits',
      scheduled_at: nil,
      delivery_status: 'not_sent',
      delivery_target: nil,
      delivery_reference: nil,
      delivery_manifest: {},
      delivered_at: nil,
      review_notes: review_params[:review_notes],
      reviewed_at: Time.current
    )
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
    if @playlist.update(status: 'scheduled', scheduled_at: schedule_params[:scheduled_at])
      render json: serialize_playlist(@playlist)
    else
      render json: { errors: @playlist.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def deliver
    delivered_playlist = StreamDeliveryService.new(@playlist, target: delivery_params[:target]).deliver
    render json: serialize_playlist(delivered_playlist)
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
    playlist_params.except(:songs, :full_show_file, :delivery_target)
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
      content_type: uploaded_file.content_type
    )

    upload = s3_service.upload_uploaded_file(uploaded_file, prefix: 'full_shows')
    audio_file.s3_key = upload[:key]
    audio_file.url = upload[:url]
    audio_file.save!
    playlist.full_show_audio_file = audio_file
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
      delivery_status: playlist.delivery_status,
      delivery_target: playlist.delivery_target,
      delivery_reference: playlist.delivery_reference,
      delivery_manifest: playlist.delivery_manifest,
      delivered_at: playlist.delivered_at,
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

  def serialize_public_playlist(playlist)
    {
      id: playlist.id,
      name: playlist.name,
      description: playlist.description,
      host_name: playlist.host_name,
      status: playlist.status,
      scheduled_at: playlist.scheduled_at,
      delivery_status: playlist.delivery_status,
      delivery_reference: playlist.delivery_reference,
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
          position: song.position
        }
      end
    }
  end
end
