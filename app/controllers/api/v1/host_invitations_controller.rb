class Api::V1::HostInvitationsController < ApplicationController
  before_action :authenticate_request
  before_action :require_admin

  def index
    invitations = HostInvitation.includes(:invited_by, :used_by).order(created_at: :desc)
    render json: invitations.map { |invitation| serialize_invitation(invitation) }
  end

  def create
    invitation = HostInvitation.new(invitation_params.merge(invited_by: @current_user))

    if invitation.save
      render json: serialize_invitation(invitation), status: :created
    else
      render json: { errors: invitation.errors.full_messages }, status: :unprocessable_entity
    end
  end

  private

  def invitation_params
    params.fetch(:host_invitation, {}).permit(:email, :notes, :expires_at)
  end

  def serialize_invitation(invitation)
    {
      id: invitation.id,
      code: invitation.code,
      email: invitation.email,
      notes: invitation.notes,
      status: invitation.status,
      expires_at: invitation.expires_at,
      used_at: invitation.used_at,
      invited_by: invitation.invited_by&.email,
      used_by: invitation.used_by&.email,
      created_at: invitation.created_at
    }
  end
end
