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

  describe 'PATCH /repositories/:name with tag protection fields' do
    let!(:protection_repo) { Repository.create!(name: 'example') }

    it 'persists tag_protection_policy when set to semver' do
      patch "/repositories/#{protection_repo.name}",
        params: { repository: { tag_protection_policy: 'semver' } }
      expect(protection_repo.reload.tag_protection_policy).to eq('semver')
    end

    it 'persists tag_protection_pattern when policy is custom_regex' do
      patch "/repositories/#{protection_repo.name}",
        params: { repository: { tag_protection_policy: 'custom_regex', tag_protection_pattern: '^release-\d+$' } }
      expect(protection_repo.reload.tag_protection_policy).to eq('custom_regex')
      expect(protection_repo.reload.tag_protection_pattern).to eq('^release-\d+$')
    end

    it 'clears pattern when policy reverts from custom_regex' do
      protection_repo.update!(tag_protection_policy: 'custom_regex', tag_protection_pattern: '^v.+$')
      patch "/repositories/#{protection_repo.name}",
        params: { repository: { tag_protection_policy: 'semver', tag_protection_pattern: '^v.+$' } }
      expect(protection_repo.reload.tag_protection_pattern).to be_nil
    end

    it 'rejects invalid regex' do
      patch "/repositories/#{protection_repo.name}",
        params: { repository: { tag_protection_policy: 'custom_regex', tag_protection_pattern: '[unclosed' } }
      expect(protection_repo.reload.tag_protection_policy).to eq('none')
    end
  end
end
