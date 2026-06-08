class Api::V1::AudioFilesController < ApplicationController
  before_action :authenticate_request
  before_action :set_visible_audio_file, only: :show
  before_action :set_owned_audio_file, only: [:update, :destroy]

  def index
    nested_user_scope = params[:user_id].present? || params[:scope] == 'mine'
    @audio_files = if nested_user_scope
                     @current_user.audio_files.includes(:user).order(created_at: :asc)
                   else
                     AudioFile.library_visible.or(AudioFile.owned_by(@current_user)).includes(:user).order(created_at: :desc)
                   end

    render json: @audio_files.map { |audio_file| serialize_audio_file(audio_file) }
  end

  def show
    render json: serialize_audio_file(@audio_file)
  end

  def create
    @audio_file = @current_user.audio_files.build(audio_file_params.except(:file))
    @audio_file.visibility = default_visibility_for(@audio_file.kind) unless audio_file_params.key?(:visibility)
    apply_file_metadata(@audio_file, audio_file_params[:file])
    upload_errors = uploaded_file_errors(audio_file_params[:file])
    return render json: { errors: upload_errors }, status: :unprocessable_entity if upload_errors.any?

    upload = apply_uploaded_file(@audio_file, audio_file_params[:file])

    if @audio_file.save
      render json: serialize_audio_file(@audio_file), status: :created
    else
      delete_from_s3(upload[:key]) if upload
      render json: { errors: @audio_file.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def update
    previous_s3_key = @audio_file.s3_key
    @audio_file.assign_attributes(audio_file_params.except(:file))
    upload = apply_uploaded_file(@audio_file, audio_file_params[:file])

    if @audio_file.save
      delete_from_s3(previous_s3_key) if upload && previous_s3_key.present? && previous_s3_key != upload[:key]
      render json: serialize_audio_file(@audio_file)
    else
      delete_from_s3(upload[:key]) if upload
      render json: { errors: @audio_file.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def destroy
    delete_from_s3(@audio_file.s3_key)
    @audio_file.destroy
    head :no_content
  end

  private

  def set_visible_audio_file
    @audio_file = AudioFile.library_visible.or(AudioFile.owned_by(@current_user)).find(params[:id])
  end

  def set_owned_audio_file
    @audio_file = @current_user.audio_files.find_by(id: params[:id])
    return if @audio_file.present?

    render json: { error: 'Audio file not found' }, status: :not_found
  end

  def default_visibility_for(kind)
    kind == 'full_show' ? 'private' : 'shared'
  end

  def audio_file_params
    params.require(:audio_file).permit(
      :name,
      :title,
      :artist,
      :album,
      :genre,
      :duration,
      :size,
      :file,
      :kind,
      :visibility,
      :content_type,
      :explicit,
      :notes
    )
  end

  def apply_uploaded_file(audio_file, uploaded_file)
    return unless uploaded_file.present?

    upload = s3_service.upload_uploaded_file(uploaded_file, prefix: audio_file.kind.presence || 'audio_files')
    audio_file.s3_key = upload[:key]
    audio_file.url = upload[:url]
    audio_file.name = uploaded_file.original_filename if audio_file.name.blank?
    audio_file.title = File.basename(uploaded_file.original_filename, '.*') if audio_file.title.blank?
    audio_file.size = uploaded_file.size if audio_file.size.blank?
    audio_file.content_type = uploaded_file.content_type
    upload
  end

  def apply_file_metadata(audio_file, uploaded_file)
    return unless uploaded_file.present?

    audio_file.name = uploaded_file.original_filename if audio_file.name.blank?
    audio_file.title = File.basename(uploaded_file.original_filename, '.*') if audio_file.title.blank?
    audio_file.size = uploaded_file.size if audio_file.size.blank?
    audio_file.content_type = uploaded_file.content_type
  end

  def uploaded_file_errors(uploaded_file)
    return ['Choose an audio file to upload.'] if uploaded_file.blank?

    errors = []
    errors << 'Audio file is too large. Maximum size is 500 MB.' if uploaded_file.size > AudioFile::MAX_UPLOAD_SIZE
    unless AudioFile::SUPPORTED_CONTENT_TYPES.include?(uploaded_file.content_type)
      errors << 'Choose an MP3, WAV, FLAC, M4A, AAC, OGG, or WebM audio file.'
    end
    errors
  end

  def delete_from_s3(object_key)
    return if object_key.blank?

    s3_service.delete_file(object_key)
  end

  def s3_service
    @s3_service ||= AwsS3Service.new(ENV.fetch('AWS_BUCKET_NAME', 'radio-denver'))
  end

  def serialize_audio_file(audio_file)
    {
      id: audio_file.id,
      user_id: audio_file.user_id,
      name: audio_file.name,
      title: audio_file.title,
      artist: audio_file.artist,
      album: audio_file.album,
      genre: audio_file.genre,
      duration: audio_file.duration,
      size: audio_file.size,
      s3_key: audio_file.s3_key,
      url: audio_file.public_url,
      content_type: audio_file.content_type,
      kind: audio_file.kind,
      visibility: audio_file.visibility,
      explicit: audio_file.explicit,
      notes: audio_file.notes,
      owner_name: audio_file.user.host_name.presence || audio_file.user.full_name,
      owned_by_current_user: audio_file.user_id == @current_user.id,
      created_at: audio_file.created_at
    }
  end
end
