require 'rails_helper'

RSpec.describe 'Repositories search (turbo_stream)', type: :request do
  let!(:repo) { Repository.create!(name: 'searchable-repo', description: 'findable') }
  let!(:manifest) { Manifest.create!(repository: repo, digest: 'sha256:xyz', media_type: 'application/vnd.docker.distribution.manifest.v2+json', payload: '{}', size: 100) }
  let!(:tag) { Tag.create!(repository: repo, manifest: manifest, name: 'v1.0.0') }

  describe 'GET /repositories as turbo_stream' do
    it 'returns turbo_stream matching index.html.erb palette and structure' do
      get repositories_path, as: :turbo_stream
      expect(response).to be_successful
      expect(response.body).not_to include("gray-")             # No legacy gray palette
      expect(response.body).not_to include('stroke-width="2"')  # Heroicon stroke = 1.5
      expect(response.body).to include("slate-")                # Uses slate palette
    end

    it 'renders card grid when repositories exist' do
      get repositories_path, as: :turbo_stream
      expect(response.body).to include('searchable-repo')
      expect(response.body).to include('grid')
    end

    it 'renders empty state when no results match query' do
      get repositories_path(q: 'zzzznonexistentzzzz'), as: :turbo_stream
      expect(response.body).to include('No results found')
      expect(response.body).not_to include("gray-")
    end
  end
end
