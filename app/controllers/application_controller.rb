class ApplicationController < ActionController::Base
  protect_from_forgery with: :exception
  skip_before_action :verify_authenticity_token, if: :api_request?

  private

  def authenticate_request
    @current_user = User.find_by(id: session[:user_id]) if session[:user_id].present?
    @current_user ||= AuthorizeApiRequestService.new(request.headers).result
    render json: { error: 'Not Authorized' }, status: :unauthorized unless @current_user
  rescue RuntimeError
    render json: { error: 'Not Authorized' }, status: :unauthorized
  end

  def api_request?
    request.format.json?
  end
end
