Rails.application.routes.draw do
  # GraphQL endpoint
  post "/graphql", to: "graphql#execute"

  # Health check endpoint
  get "up" => "rails/health#show", as: :rails_health_check

  namespace :api do
    namespace :v1 do
      resources :audio_files, only: [:index, :show, :update, :create, :destroy]
      resources :host_invitations, only: [:index, :create] do
        member do
          patch :revoke
        end
      end
      resources :station_hosts, only: [:index] do
        member do
          patch :suspend
          patch :reactivate
        end
      end
      get 'station/schedule', to: 'playlists#public_schedule'
      get 'station/stream_status', to: 'station#stream_status'
      get 'station/now_playing', to: 'station#now_playing'
      resources :playlists, only: [:index, :show, :update, :create, :destroy] do
        member do
          patch :mark_ready
          patch :request_changes
          patch :reopen_for_edits
          patch :reject
          patch :schedule
          post :render_master
          post :deliver
        end
      end

      # User routes with nested audio_files routes
      resources :users, only: [:index, :show, :create, :update, :destroy] do
        patch :profile_image, on: :member
        resources :audio_files, only: [:index, :show, :update, :create, :destroy]
      end

      # Session routes for login, current user, and logout
      get 'sessions/current', to: 'sessions#show'
      delete 'sessions', to: 'sessions#destroy'
      resources :sessions, only: [:create, :destroy]

      # Password reset routes
      resources :password_resets, only: [:create] do
        patch ':token', to: 'password_resets#update', on: :collection, as: :update_with_token
      end
    end
  end
end
