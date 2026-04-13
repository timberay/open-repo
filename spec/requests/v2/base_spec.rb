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
