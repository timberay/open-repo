require 'rails_helper'

RSpec.describe BlobUpload, type: :model do
  let(:repository) { Repository.create!(name: 'test-repo') }

  describe 'validations' do
    it 'requires uuid' do
      upload = BlobUpload.new(repository: repository, uuid: nil)
      expect(upload).not_to be_valid
    end

    it 'requires unique uuid' do
      BlobUpload.create!(repository: repository, uuid: 'abc-123')
      u2 = BlobUpload.new(repository: repository, uuid: 'abc-123')
      expect(u2).not_to be_valid
    end
  end

  describe 'defaults' do
    it 'byte_offset defaults to 0' do
      upload = BlobUpload.create!(repository: repository, uuid: 'abc-123')
      expect(upload.byte_offset).to eq(0)
    end
  end
end
