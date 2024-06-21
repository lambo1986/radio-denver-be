class Api::V1::SessionsController < ApplicationController
  skip_before_action :verify_authenticity_token, only: [:create, :destroy]

  def create
    user = User.find_by(email: session_params[:email])
    if user && user.authenticate(session_params[:password])
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
