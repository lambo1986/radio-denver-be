class Api::V1::SessionsController < ApplicationController
  skip_before_action :verify_authenticity_token, only: [:create, :destroy]
  before_action :authenticate_request, only: :show

  def show
    render json: UserSerializer.new(@current_user), status: :ok
  end

  def create
    email = session_params[:email].to_s.strip.downcase
    return render_rate_limit if login_rate_limited?(email)

    user = User.find_by_email(email)
    if user && user.authenticate(session_params[:password]) && !user.active?
      render json: { error: 'This host account is paused. Contact the station admin for help.' }, status: :forbidden
    elsif user && user.authenticate(session_params[:password])
      session[:user_id] = user.id
      render json: authenticated_user_payload(user), status: :ok
    else
      record_failed_login(email)
      render json: { error: 'Invalid email or password' }, status: :unauthorized
    end
  end

  def destroy
    reset_session  
    render json: { message: 'Logged out successfully' }, status: :ok
  end

  private

  LOGIN_PERIOD = 15.minutes.to_i
  LOGIN_IP_LIMIT = 20
  LOGIN_EMAIL_LIMIT = 8

  def login_rate_limited?(email)
    RequestRateLimiter.blocked?(scope: 'login-ip', identifier: request.remote_ip, limit: LOGIN_IP_LIMIT, period: LOGIN_PERIOD) ||
      RequestRateLimiter.blocked?(scope: 'login-email', identifier: email, limit: LOGIN_EMAIL_LIMIT, period: LOGIN_PERIOD)
  end

  def record_failed_login(email)
    RequestRateLimiter.record!(scope: 'login-ip', identifier: request.remote_ip, period: LOGIN_PERIOD)
    RequestRateLimiter.record!(scope: 'login-email', identifier: email, period: LOGIN_PERIOD)
  end

  def render_rate_limit
    retry_after = RequestRateLimiter.retry_after(period: LOGIN_PERIOD)
    response.set_header('Retry-After', retry_after.to_s)
    render json: { error: 'Too many sign-in attempts. Wait a few minutes and try again.' }, status: :too_many_requests
  end

  def session_params
    params.require(:session).permit(:email, :password)
  end

  def authenticated_user_payload(user)
    UserSerializer.new(user).serializable_hash.merge(
      token: JsonWebTokenService.encode(user_id: user.id, exp: 30.days.from_now.to_i)
    )
  end
end
