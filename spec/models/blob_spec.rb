require 'rails_helper'

RSpec.describe Blob, type: :model do
  describe 'validations' do
    it 'requires digest and size' do
      blob = Blob.new
      expect(blob).not_to be_valid
      expect(blob.errors[:digest]).to include("can't be blank")
      expect(blob.errors[:size]).to include("can't be blank")
    end

    it 'requires unique digest' do
      Blob.create!(digest: 'sha256:abc', size: 1024)
      b2 = Blob.new(digest: 'sha256:abc', size: 1024)
      expect(b2).not_to be_valid
    end
  end

  describe 'defaults' do
    it 'has references_count defaulting to 0' do
      blob = Blob.create!(digest: 'sha256:abc', size: 1024)
      expect(blob.references_count).to eq(0)
    end
  end
end
