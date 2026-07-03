class Api::V1::StationController < ApplicationController
  skip_before_action :verify_authenticity_token, only: [:stream_status, :now_playing]
  before_action :authenticate_request, only: [:azuracast_discovery]
  before_action :require_admin, only: [:azuracast_discovery]

  def stream_status
    render json: StreamStatusService.new.status
  end

  def now_playing
    expires_in 15.seconds, public: true
    render json: AzuracastClient.new.now_playing
  end

  def azuracast_discovery
    render json: AzuracastClient.new.discovery(
      recommended_playlist: params[:recommended_playlist],
      recommended_media_folder: params[:recommended_media_folder]
    )
  end
end
