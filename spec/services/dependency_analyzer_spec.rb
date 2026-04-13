require 'rails_helper'

RSpec.describe DependencyAnalyzer do
  let(:shared_blob) { Blob.create!(digest: 'sha256:shared', size: 1024) }
  let(:unique_blob) { Blob.create!(digest: 'sha256:unique', size: 512) }

  let(:repo_a) { Repository.create!(name: 'repo-a') }
  let(:repo_b) { Repository.create!(name: 'repo-b') }

  before do
    ma = Manifest.create!(repository: repo_a, digest: 'sha256:ma', media_type: 'application/vnd.docker.distribution.manifest.v2+json', payload: '{}', size: 100)
    Layer.create!(manifest: ma, blob: shared_blob, position: 0)
    Layer.create!(manifest: ma, blob: unique_blob, position: 1)

    mb = Manifest.create!(repository: repo_b, digest: 'sha256:mb', media_type: 'application/vnd.docker.distribution.manifest.v2+json', payload: '{}', size: 100)
    Layer.create!(manifest: mb, blob: shared_blob, position: 0)
  end

  describe '#call' do
    it 'identifies repositories sharing layers' do
      result = DependencyAnalyzer.new.call(repo_a)
      expect(result.length).to eq(1)
      expect(result[0][:repository]).to eq('repo-b')
      expect(result[0][:shared_layers]).to eq(1)
    end
  end
end
