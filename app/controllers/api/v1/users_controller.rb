class Api::V1::UsersController < ApplicationController
  skip_before_action :verify_authenticity_token, only: [:create, :update, :destroy, :profile_image]
  before_action :authenticate_request, except: :create
  before_action :require_admin, only: [:index, :destroy]
  before_action :set_user, only: [:show, :update, :destroy, :profile_image]
  before_action :authorize_user_access, only: [:show, :update, :profile_image]

  def index
    users = User.all
    render json: UserSerializer.new(users)
  end

   def show
    render json: UserSerializer.new(@user)
  end

   def create
    invitation = HostInvitation.find_usable(params.dig(:user, :invite_code), email: user_params[:email])
    unless invitation
      render json: { error: 'A valid host invite code is required.' }, status: :forbidden
      return
    end

    user = User.new(user_params)
    if user.save
      invitation.use!(user)
      session[:user_id] = user.id
      render json: UserSerializer.new(user).serializable_hash.merge(
        token: JsonWebTokenService.encode(user_id: user.id, exp: 30.days.from_now.to_i)
      ), status: :created
    else
      render json: { errors: user.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def update
    if @user.update(user_params)
      render json: UserSerializer.new(@user).serializable_hash.to_json, status: :ok
    else
      render json: { errors: @user.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def profile_image
    uploaded_file = params[:profile_image]
    errors = profile_image_errors(uploaded_file)
    return render json: { errors: errors }, status: :unprocessable_entity if errors.any?

    previous_key = stored_profile_image_key
    upload = s3_service.upload_uploaded_file(uploaded_file, prefix: "profile_images/#{@user.id}")

    if @user.update(profile_image: upload[:key])
      delete_profile_image(previous_key) if previous_key.present? && previous_key != upload[:key]
      render json: UserSerializer.new(@user).serializable_hash, status: :ok
    else
      delete_profile_image(upload[:key])
      render json: { errors: @user.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def destroy
    if @user.destroy
      render json: { message: 'User deleted' }, status: :ok
    end
  end

  private

   def user_params
    params.require(:user).permit(:host_name, :description, :first_name, :last_name, :email, :phone_number, :password, :password_confirmation)
  end

  def set_user
    @user = User.find_by(id: params[:id])
    render json: { error: 'User not found' }, status: :not_found unless @user
  end

  def authorize_user_access
    return if @current_user.admin? || @current_user.id == @user.id

    render json: { error: 'Not Authorized' }, status: :forbidden
  end

  def profile_image_errors(uploaded_file)
    return ['Choose a profile image to upload.'] if uploaded_file.blank?

    errors = []
    errors << 'Profile image is too large. Maximum size is 10 MB.' if uploaded_file.size > User::MAX_PROFILE_IMAGE_SIZE
    unless User::PROFILE_IMAGE_CONTENT_TYPES.include?(uploaded_file.content_type)
      errors << 'Choose a JPG, PNG, or WebP image.'
    end
    errors
  end

  def stored_profile_image_key
    value = @user.profile_image.to_s
    return if value.blank? || value.start_with?('http://', 'https://', '/')

    value
  end

  def delete_profile_image(key)
    return if key.blank?

    s3_service.delete_file(key)
  rescue StandardError
    nil
  end

  def s3_service
    @s3_service ||= AwsS3Service.new(ENV.fetch('AWS_BUCKET_NAME', 'radio-denver'))
  end
end
