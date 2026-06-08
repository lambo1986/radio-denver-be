class Api::V1::PasswordResetsController < ApplicationController
  skip_before_action :verify_authenticity_token

  def create
    email = params[:email].to_s.strip.downcase
    return render_rate_limit if password_reset_rate_limited?(email)

    record_password_reset_request(email)
    user = User.find_by_email(email)
    if user
      user.generate_password_token!
      UserMailer.reset_password_email(user).deliver_now
    end

    render json: { message: "If that address belongs to an account, password reset instructions have been sent." }, status: :ok
  end

  def update
    user = User.find_by(reset_password_token: params[:token], email: params[:email].to_s.strip.downcase)
    if user.present? && user.password_token_valid?
      if user.reset_password!(params[:password], params[:password_confirmation])
        render json: { message: "Password has been reset successfully." }, status: :ok
      else
        render json: { errors: user.errors.full_messages }, status: :unprocessable_entity
      end
    else
      render json: { error: "Password token is invalid or has expired" }, status: :not_found
    end
  end

  private

  PASSWORD_RESET_PERIOD = 1.hour.to_i
  PASSWORD_RESET_IP_LIMIT = 10
  PASSWORD_RESET_EMAIL_LIMIT = 3

  def password_reset_rate_limited?(email)
    RequestRateLimiter.blocked?(scope: 'password-reset-ip', identifier: request.remote_ip, limit: PASSWORD_RESET_IP_LIMIT, period: PASSWORD_RESET_PERIOD) ||
      RequestRateLimiter.blocked?(scope: 'password-reset-email', identifier: email, limit: PASSWORD_RESET_EMAIL_LIMIT, period: PASSWORD_RESET_PERIOD)
  end

  def record_password_reset_request(email)
    RequestRateLimiter.record!(scope: 'password-reset-ip', identifier: request.remote_ip, period: PASSWORD_RESET_PERIOD)
    RequestRateLimiter.record!(scope: 'password-reset-email', identifier: email, period: PASSWORD_RESET_PERIOD)
  end

  def render_rate_limit
    retry_after = RequestRateLimiter.retry_after(period: PASSWORD_RESET_PERIOD)
    response.set_header('Retry-After', retry_after.to_s)
    render json: { error: 'Too many password reset requests. Wait before trying again.' }, status: :too_many_requests
  end
end
