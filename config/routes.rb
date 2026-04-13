Rails.application.routes.draw do
  root "repositories#index"

  resources :repositories, only: [:index]

  get "up" => "rails/health#show", as: :rails_health_check
end
