Rails.application.routes.draw do
  root "repositories#index"

  resources :repositories, only: [:index]

  # Docker Registry V2 API
  scope '/v2', defaults: { format: :json } do
    get '/', to: 'v2/base#index'
    get '/_catalog', to: 'v2/catalog#index'

    get '/*name/tags/list', to: 'v2/tags#index', format: false
    match '/*name/manifests/:reference', to: 'v2/manifests#show', via: [:get, :head], format: false
    put '/*name/manifests/:reference', to: 'v2/manifests#update', format: false
    delete '/*name/manifests/:reference', to: 'v2/manifests#destroy', format: false

    match '/*name/blobs/:digest', to: 'v2/blobs#show', via: [:get, :head], format: false
    delete '/*name/blobs/:digest', to: 'v2/blobs#destroy', format: false

    post '/*name/blobs/uploads', to: 'v2/blob_uploads#create', format: false
    patch '/*name/blobs/uploads/:uuid', to: 'v2/blob_uploads#update', format: false
    put '/*name/blobs/uploads/:uuid', to: 'v2/blob_uploads#complete', format: false
    delete '/*name/blobs/uploads/:uuid', to: 'v2/blob_uploads#destroy', format: false
  end

  get "up" => "rails/health#show", as: :rails_health_check
end
