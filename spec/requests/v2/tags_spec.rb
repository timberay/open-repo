require 'rails_helper'

RSpec.describe 'V2 Tags API', type: :request do
  let(:repo) { Repository.create!(name: 'test-repo') }
  let(:manifest) { Manifest.create!(repository: repo, digest: 'sha256:abc', media_type: 'application/vnd.docker.distribution.manifest.v2+json', payload: '{}', size: 100) }

  before do
    %w[v1.0.0 v2.0.0 latest].each { |t| Tag.create!(repository: repo, manifest: manifest, name: t) }
  end

  describe 'GET /v2/:name/tags/list' do
    it 'returns all tags' do
      get "/v2/#{repo.name}/tags/list"
      body = JSON.parse(response.body)
      expect(body['name']).to eq('test-repo')
      expect(body['tags']).to eq(%w[latest v1.0.0 v2.0.0])
    end

    it 'paginates with n and last' do
      get "/v2/#{repo.name}/tags/list?n=2"
      body = JSON.parse(response.body)
      expect(body['tags'].length).to eq(2)
      expect(response.headers['Link']).to include('rel="next"')
    end

    it 'returns 404 for unknown repo' do
      get '/v2/nonexistent/tags/list'
      expect(response).to have_http_status(404)
    end
  end
end
