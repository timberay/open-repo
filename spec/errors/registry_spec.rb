require 'rails_helper'

RSpec.describe Registry do
  describe 'exception hierarchy' do
    it 'all exceptions inherit from Registry::Error' do
      expect(Registry::BlobUnknown.new).to be_a(Registry::Error)
      expect(Registry::BlobUploadUnknown.new).to be_a(Registry::Error)
      expect(Registry::ManifestUnknown.new).to be_a(Registry::Error)
      expect(Registry::ManifestInvalid.new).to be_a(Registry::Error)
      expect(Registry::NameUnknown.new).to be_a(Registry::Error)
      expect(Registry::DigestMismatch.new).to be_a(Registry::Error)
      expect(Registry::Unsupported.new).to be_a(Registry::Error)
    end

    it 'Registry::Error inherits from StandardError' do
      expect(Registry::Error.new).to be_a(StandardError)
    end

    it 'carries custom messages' do
      error = Registry::BlobUnknown.new('blob sha256:abc not found')
      expect(error.message).to eq('blob sha256:abc not found')
    end
  end
end
