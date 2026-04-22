require 'rails_helper'

RSpec.describe 'V2 Base API', type: :request do
  describe 'GET /v2/' do
    it 'returns 200 with empty JSON body' do
      get '/v2/'
      expect(response).to have_http_status(200)
      expect(JSON.parse(response.body)).to eq({})
    end

    it 'includes Docker-Distribution-API-Version header' do
      get '/v2/'
      expect(response.headers['Docker-Distribution-API-Version']).to eq('registry/2.0')
    end
  end
end

RSpec.describe V2::BaseController, type: :controller do
  controller(V2::BaseController) do
    def trigger
      raise Registry::TagProtected.new(tag: 'v1.0.0', policy: 'semver')
    end
  end

  before { routes.draw { get 'trigger' => 'v2/base#trigger' } }

  it 'returns 409 Conflict' do
    get :trigger
    expect(response).to have_http_status(:conflict)
  end

  it 'renders Docker Registry error envelope with DENIED code' do
    get :trigger
    body = JSON.parse(response.body)
    expect(body['errors'].first).to include(
      'code' => 'DENIED',
      'message' => "tag 'v1.0.0' is protected by immutability policy 'semver'",
      'detail' => { 'tag' => 'v1.0.0', 'policy' => 'semver' }
    )
  end

  it 'includes Docker-Distribution-API-Version header on 409' do
    get :trigger
    expect(response.headers['Docker-Distribution-API-Version']).to eq('registry/2.0')
  end
end
