require "test_helper"

class CleanupOrphanedBlobsJobTest < ActiveJob::TestCase
  def setup
    @store_dir = Dir.mktmpdir
    @original_storage_path = Rails.configuration.storage_path
    Rails.configuration.storage_path = @store_dir
    @blob_store = BlobStore.new(@store_dir)
  end

  def teardown
    Rails.configuration.storage_path = @original_storage_path
    FileUtils.rm_rf(@store_dir)
  end

  test "perform deletes blobs with references_count == 0" do
    content = "orphan blob"
    digest = DigestCalculator.compute(content)
    @blob_store.put(digest, StringIO.new(content))
    Blob.create!(digest: digest, size: content.bytesize, references_count: 0)

    CleanupOrphanedBlobsJob.perform_now

    assert_nil Blob.find_by(digest: digest)
    assert_equal false, @blob_store.exists?(digest)
  end

  test "perform does NOT delete blobs with references_count > 0" do
    content = "referenced blob"
    digest = DigestCalculator.compute(content)
    @blob_store.put(digest, StringIO.new(content))
    Blob.create!(digest: digest, size: content.bytesize, references_count: 1)

    CleanupOrphanedBlobsJob.perform_now

    assert Blob.find_by(digest: digest).present?
    assert_equal true, @blob_store.exists?(digest)
  end
end
