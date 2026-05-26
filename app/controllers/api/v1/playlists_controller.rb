class Api::V1::PlaylistsController < ApplicationController
  before_action :authenticate_request
  before_action :set_playlist, only: [:show, :update, :destroy]

  def index
    playlists = @current_user.playlists.includes(:songs, :full_show_audio_file).order(created_at: :desc)
    render json: playlists.map { |playlist| serialize_playlist(playlist) }
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

  private

  def set_playlist
    @playlist = @current_user.playlists.find(params[:id])
  end

  def playlist_params
    params.require(:playlist).permit(
      :name,
      :description,
      :host_name,
      :status,
      :scheduled_at,
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
    playlist_params.except(:songs, :full_show_file)
  end

  def build_songs(playlist)
    Array(playlist_params[:songs]).each_with_index do |song_params, index|
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
      full_show_audio_file: playlist.full_show_audio_file && {
        id: playlist.full_show_audio_file.id,
        name: playlist.full_show_audio_file.name,
        url: playlist.full_show_audio_file.public_url
      },
      songs: playlist.songs.map do |song|
        {
          id: song.id,
          name: song.name,
          artist: song.artist,
          album: song.album,
          duration: song.duration,
          position: song.position,
          file_url: song.file_url,
          file_name: song.file_name,
          audio_file_id: song.audio_file_id
        }
      end,
      created_at: playlist.created_at
    }
  end
end
