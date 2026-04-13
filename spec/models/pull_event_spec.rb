require 'rails_helper'

RSpec.describe PullEvent, type: :model do
  let(:repository) { Repository.create!(name: 'test-repo') }
  let(:manifest) { Manifest.create!(repository: repository, digest: 'sha256:abc', media_type: 'application/vnd.docker.distribution.manifest.v2+json', payload: '{}', size: 100) }

  describe 'validations' do
    it 'requires occurred_at' do
      event = PullEvent.new(manifest: manifest, repository: repository)
      expect(event).not_to be_valid
      expect(event.errors[:occurred_at]).to include("can't be blank")
    end
  end
end
