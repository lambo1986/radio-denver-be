Rails.application.routes.draw do
  # GraphQL endpoint
  post "/graphql", to: "graphql#execute"

  # Health check endpoint
  get "up" => "rails/health#show", as: :rails_health_check

  namespace :api do
    namespace :v1 do
      # User routes with nested audio_files routes
      resources :users, only: [:index, :show, :create, :update, :destroy] do
        resources :audio_files, only: [:index, :show, :update, :create, :destroy]
      end

      # Session routes for login and logout
      resources :sessions, only: [:create, :destroy]

      # Password reset routes
      resources :password_resets, only: [:create] do
        patch ':token', to: 'password_resets#update', on: :collection, as: :update_with_token
      end
    end
  end
end
