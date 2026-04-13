Rails.application.routes.draw do
  root "repositories#index"

  resources :repositories, only: [:index]

  # Docker Registry V2 API
  # reference: tag name (v1.0.0) or digest (sha256:abc...)
  # digest: sha256:abc...
  ref_constraint = { reference: /[a-zA-Z0-9._:-]+/ }
  digest_constraint = { digest: /[a-zA-Z0-9._:-]+/ }
  name_constraint = { name: /[a-z0-9][a-z0-9._-]*/ }
  ns_constraint = { ns: /[a-z0-9][a-z0-9._-]*/, name: /[a-z0-9][a-z0-9._-]*/ }

  scope '/v2', defaults: { format: :json } do
    get '/', to: 'v2/base#index'
    get '/_catalog', to: 'v2/catalog#index'

    # Single-segment repository names (e.g., "myapp")
    scope ':name', constraints: name_constraint do
      get 'tags/list', to: 'v2/tags#index'
      match 'manifests/:reference', to: 'v2/manifests#show', via: [:get, :head], constraints: ref_constraint
      put 'manifests/:reference', to: 'v2/manifests#update', constraints: ref_constraint
      delete 'manifests/:reference', to: 'v2/manifests#destroy', constraints: ref_constraint

      match 'blobs/:digest', to: 'v2/blobs#show', via: [:get, :head], constraints: digest_constraint
      delete 'blobs/:digest', to: 'v2/blobs#destroy', constraints: digest_constraint

      post 'blobs/uploads', to: 'v2/blob_uploads#create'
      patch 'blobs/uploads/:uuid', to: 'v2/blob_uploads#update'
      put 'blobs/uploads/:uuid', to: 'v2/blob_uploads#complete'
      delete 'blobs/uploads/:uuid', to: 'v2/blob_uploads#destroy'
    end

    # Namespaced repository names (e.g., "library/nginx")
    scope ':ns/:name', constraints: ns_constraint do
      get 'tags/list', to: 'v2/tags#index'
      match 'manifests/:reference', to: 'v2/manifests#show', via: [:get, :head], constraints: ref_constraint
      put 'manifests/:reference', to: 'v2/manifests#update', constraints: ref_constraint
      delete 'manifests/:reference', to: 'v2/manifests#destroy', constraints: ref_constraint

      match 'blobs/:digest', to: 'v2/blobs#show', via: [:get, :head], constraints: digest_constraint
      delete 'blobs/:digest', to: 'v2/blobs#destroy', constraints: digest_constraint

      post 'blobs/uploads', to: 'v2/blob_uploads#create'
      patch 'blobs/uploads/:uuid', to: 'v2/blob_uploads#update'
      put 'blobs/uploads/:uuid', to: 'v2/blob_uploads#complete'
      delete 'blobs/uploads/:uuid', to: 'v2/blob_uploads#destroy'
    end
  end

  get "up" => "rails/health#show", as: :rails_health_check
end
