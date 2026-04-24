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

  # e1: simulate a concurrent ManifestProcessor incrementing references_count
  # between find_each yielding the row (count == 0) and the in-loop reload.
  # The `next if blob.references_count > 0` guard MUST prevent destruction.
  test "perform skips blob when references_count is incremented mid-loop" do
    content = "racy blob"
    digest = DigestCalculator.compute(content)
    @blob_store.put(digest, StringIO.new(content))
    Blob.create!(digest: digest, size: content.bytesize, references_count: 0)

    # Stub Blob#reload globally to flip the in-memory references_count to 1
    # for any blob with this digest (we can't target a specific instance because
    # find_each materializes a fresh AR object inside the job).
    target_digest = digest
    Blob.class_eval do
      alias_method :__orig_reload_for_e1, :reload
      define_method(:reload) do |*args|
        result = __orig_reload_for_e1(*args)
        self.references_count = 1 if self.digest == target_digest
        result
      end
    end

    begin
      CleanupOrphanedBlobsJob.perform_now

      assert Blob.find_by(digest: digest).present?, "blob row should still exist (guard fired)"
      assert_equal true, @blob_store.exists?(digest), "blob file should still exist (guard fired)"
    ensure
      Blob.class_eval do
        alias_method :reload, :__orig_reload_for_e1
        remove_method :__orig_reload_for_e1
      end
    end
  end

  # e3: Blob row exists with references_count == 0 but the file is missing on disk.
  # FileUtils.rm_f is silent on missing files, so the job should destroy the row
  # without raising.
  test "perform deletes orphaned blob row even when file is missing on disk" do
    content = "ghost blob"
    digest = DigestCalculator.compute(content)
    Blob.create!(digest: digest, size: content.bytesize, references_count: 0)
    assert_equal false, @blob_store.exists?(digest), "precondition: file should not exist"

    assert_nothing_raised do
      CleanupOrphanedBlobsJob.perform_now
    end

    assert_nil Blob.find_by(digest: digest)
    assert_equal false, @blob_store.exists?(digest)
  end

  # cleanup_stale_uploads happy-path companion (older than max_age -> deleted)
  test "perform removes upload dirs older than 1 hour" do
    uuid = SecureRandom.uuid
    upload_dir = File.join(@store_dir, "uploads", uuid)
    FileUtils.mkdir_p(upload_dir)
    File.write(File.join(upload_dir, "startedat"), 2.hours.ago.iso8601)

    CleanupOrphanedBlobsJob.perform_now

    assert_equal false, Dir.exist?(upload_dir), "stale upload dir should be removed"
  end

  # cleanup_stale_uploads negative companion (younger than max_age -> kept)
  test "perform keeps upload dirs younger than 1 hour" do
    uuid = SecureRandom.uuid
    upload_dir = File.join(@store_dir, "uploads", uuid)
    FileUtils.mkdir_p(upload_dir)
    File.write(File.join(upload_dir, "startedat"), 5.minutes.ago.iso8601)

    CleanupOrphanedBlobsJob.perform_now

    assert Dir.exist?(upload_dir), "fresh upload dir should be preserved"
  end

  # e5: an unparseable startedat file. Per docs/qa-audit/TEST_PLAN.md (UC-JOB-001)
  # the spec expectation is that the dir is "skipped silently" and left in place.
  # NOTE: BlobStore#cleanup_stale_uploads (app/services/blob_store.rb:99) calls
  # Time.parse with no rescue, so this test asserts the spec — if it fails, that
  # signals a production-code gap to surface back to the caller.
  test "perform does not raise on unparseable startedat and leaves dir in place" do
    uuid = SecureRandom.uuid
    upload_dir = File.join(@store_dir, "uploads", uuid)
    FileUtils.mkdir_p(upload_dir)
    File.write(File.join(upload_dir, "startedat"), "not-a-timestamp")

    assert_nothing_raised do
      CleanupOrphanedBlobsJob.perform_now
    end

    assert Dir.exist?(upload_dir), "unparseable upload dir should be left in place"
  end
end
