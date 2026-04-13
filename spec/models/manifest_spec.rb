require 'rails_helper'

RSpec.describe Manifest, type: :model do
  let(:repository) { Repository.create!(name: 'test-repo') }

  describe 'validations' do
    it 'requires digest, media_type, payload, size' do
      manifest = Manifest.new(repository: repository)
      expect(manifest).not_to be_valid
      expect(manifest.errors[:digest]).to include("can't be blank")
      expect(manifest.errors[:media_type]).to include("can't be blank")
      expect(manifest.errors[:payload]).to include("can't be blank")
      expect(manifest.errors[:size]).to include("can't be blank")
    end

    it 'requires unique digest' do
      Manifest.create!(repository: repository, digest: 'sha256:abc', media_type: 'application/vnd.docker.distribution.manifest.v2+json', payload: '{}', size: 100)
      m2 = Manifest.new(repository: repository, digest: 'sha256:abc', media_type: 'application/vnd.docker.distribution.manifest.v2+json', payload: '{}', size: 100)
      expect(m2).not_to be_valid
    end
  end

  describe 'associations' do
    it 'has many tags' do
      expect(Manifest.reflect_on_association(:tags).macro).to eq(:has_many)
    end

    it 'has many layers' do
      expect(Manifest.reflect_on_association(:layers).macro).to eq(:has_many)
    end

    it 'has many pull_events' do
      expect(Manifest.reflect_on_association(:pull_events).macro).to eq(:has_many)
    end
  end
end
