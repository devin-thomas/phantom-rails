Rails.application.routes.draw do
  # Standard Rails internal health check
  get "up" => "rails/health#show", as: :rails_health_check

  # Public Read API v1
  namespace :api do
    namespace :v1 do
      get "health", to: "health#show"
    end
  end
end
