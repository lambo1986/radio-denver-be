class Api::V1::UsersController < ApplicationController
  skip_before_action :verify_authenticity_token, only: [:create, :update, :destroy]
  before_action :authenticate_request, except: :create
  before_action :require_admin, only: [:index, :destroy]
  before_action :set_user, only: [:show, :update, :destroy]
  before_action :authorize_user_access, only: [:show, :update]

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
end
