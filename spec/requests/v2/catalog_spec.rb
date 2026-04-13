require 'rails_helper'

RSpec.describe 'V2 Catalog API', type: :request do
  before do
    %w[alpha bravo charlie].each { |n| Repository.create!(name: n) }
  end

  describe 'GET /v2/_catalog' do
    it 'returns all repositories' do
      get '/v2/_catalog'
      expect(response).to have_http_status(200)
      body = JSON.parse(response.body)
      expect(body['repositories']).to eq(%w[alpha bravo charlie])
    end

    it 'paginates with n and last' do
      get '/v2/_catalog?n=2'
      body = JSON.parse(response.body)
      expect(body['repositories']).to eq(%w[alpha bravo])
      expect(response.headers['Link']).to include('rel="next"')

      get '/v2/_catalog?n=2&last=bravo'
      body = JSON.parse(response.body)
      expect(body['repositories']).to eq(%w[charlie])
      expect(response.headers['Link']).to be_nil
    end
  end
end
