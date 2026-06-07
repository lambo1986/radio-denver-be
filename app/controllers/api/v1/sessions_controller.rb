class Api::V1::SessionsController < ApplicationController
  skip_before_action :verify_authenticity_token, only: [:create, :destroy]
  before_action :authenticate_request, only: :show

  def show
    render json: UserSerializer.new(@current_user), status: :ok
  end

  def create
    user = User.find_by(email: session_params[:email])
    if user && user.authenticate(session_params[:password]) && !user.active?
      render json: { error: 'This host account is paused. Contact the station admin for help.' }, status: :forbidden
    elsif user && user.authenticate(session_params[:password])
      session[:user_id] = user.id
      render json: UserSerializer.new(user), status: :ok
    else
      render json: { error: 'Invalid email or password' }, status: :unauthorized
    end
  end

  def destroy
    reset_session  
    render json: { message: 'Logged out successfully' }, status: :ok
  end

  private

  def session_params
    params.require(:session).permit(:email, :password)
  end
end
