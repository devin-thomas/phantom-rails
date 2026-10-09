Rails.application.routes.draw do
  # Standard Rails internal health check
  get "up" => "rails/health#show", as: :rails_health_check

  # Public Read API v1
  namespace :api do
    namespace :v1 do
      get "health", to: "health#show"
      get "meta", to: "meta#show"
      resources :postings, only: [:index, :show] do
        member do
          get :provenance
        end
      end

      match "*path", via: [:post, :put, :patch, :delete], to: "/application#method_not_allowed"
      match "", via: [:post, :put, :patch, :delete], to: "/application#method_not_allowed"
    end
  end

  match "*path", via: [:post, :put, :patch, :delete], to: "application#method_not_allowed"
end
