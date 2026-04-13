require 'rails_helper'

RSpec.describe CleanupOrphanedBlobsJob do
  let(:store_dir) { Dir.mktmpdir }
  let(:blob_store) { BlobStore.new(store_dir) }

  before { allow(BlobStore).to receive(:new).and_return(blob_store) }
  after { FileUtils.rm_rf(store_dir) }

  describe '#perform' do
    it 'deletes blobs with references_count == 0' do
      content = 'orphan blob'
      digest = DigestCalculator.compute(content)
      blob_store.put(digest, StringIO.new(content))
      Blob.create!(digest: digest, size: content.bytesize, references_count: 0)

      CleanupOrphanedBlobsJob.perform_now

      expect(Blob.find_by(digest: digest)).to be_nil
      expect(blob_store.exists?(digest)).to be false
    end

    it 'does NOT delete blobs with references_count > 0' do
      content = 'referenced blob'
      digest = DigestCalculator.compute(content)
      blob_store.put(digest, StringIO.new(content))
      Blob.create!(digest: digest, size: content.bytesize, references_count: 1)

      CleanupOrphanedBlobsJob.perform_now

      expect(Blob.find_by(digest: digest)).to be_present
      expect(blob_store.exists?(digest)).to be true
    end
  end
end
