require 'rails_helper'

RSpec.describe Tag, type: :model do
  let(:repository) { Repository.create!(name: 'test-repo') }
  let(:manifest) { Manifest.create!(repository: repository, digest: 'sha256:abc', media_type: 'application/vnd.docker.distribution.manifest.v2+json', payload: '{}', size: 100) }

  describe 'validations' do
    it 'requires name' do
      tag = Tag.new(repository: repository, manifest: manifest, name: nil)
      expect(tag).not_to be_valid
    end

    it 'requires unique name per repository' do
      Tag.create!(repository: repository, manifest: manifest, name: 'latest')
      t2 = Tag.new(repository: repository, manifest: manifest, name: 'latest')
      expect(t2).not_to be_valid
    end
  end
end
