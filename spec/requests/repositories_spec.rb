require 'rails_helper'

RSpec.describe 'Repositories', type: :request do
  let!(:repo) { Repository.create!(name: 'test-repo', description: 'Test', maintainer: 'Team A') }
  let!(:manifest) { Manifest.create!(repository: repo, digest: 'sha256:abc', media_type: 'application/vnd.docker.distribution.manifest.v2+json', payload: '{}', size: 100) }
  let!(:tag) { Tag.create!(repository: repo, manifest: manifest, name: 'v1.0.0') }

  describe 'GET /' do
    it 'lists repositories' do
      get root_path
      expect(response).to have_http_status(200)
      expect(response.body).to include('test-repo')
    end

    it 'searches by name' do
      get root_path, params: { q: 'test' }
      expect(response.body).to include('test-repo')
    end
  end

  describe 'GET /repositories/:name' do
    it 'shows repository details' do
      get repository_path('test-repo')
      expect(response).to have_http_status(200)
      expect(response.body).to include('v1.0.0')
    end
  end

  describe 'PATCH /repositories/:name' do
    it 'updates description' do
      patch repository_path('test-repo'), params: { repository: { description: 'Updated' } }
      expect(response).to redirect_to(repository_path('test-repo'))
      expect(repo.reload.description).to eq('Updated')
    end
  end

  describe 'DELETE /repositories/:name' do
    it 'destroys repository' do
      delete repository_path('test-repo')
      expect(response).to redirect_to(root_path)
      expect(Repository.find_by(name: 'test-repo')).to be_nil
    end
  end
end
