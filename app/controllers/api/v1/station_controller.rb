class Api::V1::StationController < ApplicationController
  skip_before_action :verify_authenticity_token, only: [:stream_status, :now_playing]

  def stream_status
    render json: StreamStatusService.new.status
  end

  def now_playing
    expires_in 15.seconds, public: true
    render json: AzuracastClient.new.now_playing
  end
end
