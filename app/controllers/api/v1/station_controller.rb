class Api::V1::StationController < ApplicationController
  skip_before_action :verify_authenticity_token, only: [:stream_status]

  def stream_status
    render json: StreamStatusService.new.status
  end
end
