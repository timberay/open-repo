require 'rails_helper'

RSpec.describe Layer, type: :model do
  let(:repository) { Repository.create!(name: 'test-repo') }
  let(:manifest) { Manifest.create!(repository: repository, digest: 'sha256:abc', media_type: 'application/vnd.docker.distribution.manifest.v2+json', payload: '{}', size: 100) }
  let(:blob) { Blob.create!(digest: 'sha256:layer1', size: 2048) }

  describe 'validations' do
    it 'requires position' do
      layer = Layer.new(manifest: manifest, blob: blob, position: nil)
      expect(layer).not_to be_valid
    end

    it 'requires unique position per manifest' do
      Layer.create!(manifest: manifest, blob: blob, position: 0)
      l2 = Layer.new(manifest: manifest, blob: blob, position: 0)
      expect(l2).not_to be_valid
    end
  end
end
