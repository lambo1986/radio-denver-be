class Api::V1::StationHostsController < ApplicationController
  before_action :authenticate_request
  before_action :require_admin
  before_action :set_host, only: [:suspend, :reactivate]

  def index
    hosts = User.where(role: 'host').order(:first_name, :last_name, :email)
    render json: hosts.map { |host| serialize_host(host) }
  end

  def suspend
    update_status('suspended')
  end

  def reactivate
    update_status('active')
  end

  private

  def set_host
    @host = User.where(role: 'host').find(params[:id])
  end

  def update_status(status)
    if @host.update(account_status: status)
      render json: serialize_host(@host)
    else
      render json: { errors: @host.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def serialize_host(host)
    {
      id: host.id,
      first_name: host.first_name,
      last_name: host.last_name,
      host_name: host.host_name,
      email: host.email,
      account_status: host.account_status,
      shows_count: host.playlists.count,
      audio_count: host.audio_files.count,
      joined_at: host.created_at
    }
  end
end
