class ApplicationController < ActionController::Base
  protect_from_forgery with: :exception
  skip_before_action :verify_authenticity_token, if: :api_request?

  private

  def authenticate_request
    @current_user = User.find_by(id: session[:user_id]) if session[:user_id].present?
    @current_user ||= AuthorizeApiRequestService.new(request.headers).result
    unless @current_user&.active?
      reset_session if session[:user_id].present?
      render json: { error: 'This host account is paused. Contact the station admin for help.' }, status: :forbidden
    end
  rescue RuntimeError
    render json: { error: 'Not Authorized' }, status: :unauthorized
  end

  def require_admin
    return if @current_user&.admin?

    render json: { error: 'Admin access required' }, status: :forbidden
  end

  def api_request?
    request.format.json? || request.path.start_with?('/api/')
  end
end
