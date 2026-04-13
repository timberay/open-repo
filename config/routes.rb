Rails.application.routes.draw do
  root "repositories#index"

  resources :repositories, only: [:index, :show, :update, :destroy], param: :name,
                           constraints: { name: /[^\/]+(?:\/[^\/]+)*/ } do
    resources :tags, only: [:show, :destroy], param: :name, constraints: { name: /[a-zA-Z0-9._:-]+/ } do
      member do
        get :history
      end
    end
  end

  get '/help', to: 'help#show'

  # Docker Registry V2 API
  ref_constraint = { reference: /[a-zA-Z0-9._:-]+/ }
  digest_constraint = { digest: /[a-zA-Z0-9._:-]+/ }
  name_constraint = { name: /[a-z0-9][a-z0-9._-]*/ }
  ns_constraint = { ns: /[a-z0-9][a-z0-9._-]*/, name: /[a-z0-9][a-z0-9._-]*/ }

  scope '/v2', defaults: { format: :json } do
    get '/', to: 'v2/base#index'
    get '/_catalog', to: 'v2/catalog#index'

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
