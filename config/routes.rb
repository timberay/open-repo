Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  root "repositories#index"

  get "repositories", to: "repositories#index", as: "repositories"
  get "repositories/*id", to: "repositories#show", as: "repository", format: false

  resources :registries do
    member do
      post :switch
      post :test_connection
    end
    collection do
      post :switch_to_env
    end
  end
end
