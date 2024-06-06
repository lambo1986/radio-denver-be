class Api::V1::UsersController < ApplicationController
  skip_before_action :verify_authenticity_token, only: [:create, :update, :destroy]

  def index
    users = User.all
    render json: UserSerializer.new(users)
  end

   def show
    user = User.find_by(id: params[:id])
    if user
      render json: UserSerializer.new(user)
    else
      render json: { error: 'User not found' }, status: :not_found
    end
  end

   def create
    user = User.new(user_params)
    if user.save
      render json: UserSerializer.new(user).serializable_hash.to_json, status: :created
    else
      render json: { errors: user.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def update
    user = User.find_by(id: params[:id])

    if user.nil?
      render json: { error: 'User not found' }, status: :not_found
      return
    end

    if user.update(user_params)
      render json: UserSerializer.new(user).serializable_hash.to_json, status: :ok
    else
      render json: { errors: user.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def destroy
    user = User.find_by(id: params[:id])

    if user.nil?
      render json: { error: 'User not found' }, status: :not_found
      return
    end

    if user.destroy
      render json: { message: 'User deleted' }, status: :ok
    end
  end

  private

   def user_params
    params.require(:user).permit(:host_name, :description, :first_name, :last_name, :email, :phone_number, :password, :password_confirmation)
  end
end
