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

  # E-32: GC must preserve a blob that is shared across repositories.
  # Two repos each have a manifest referencing blob B (references_count = 2).
  # After deleting the manifest in repoA (which decrements references_count to 1),
  # the GC job MUST NOT delete B because it is still referenced by repoB.
  test "perform preserves blob shared across repos when one reference is removed" do
    content = "shared blob bytes"
    digest = DigestCalculator.compute(content)
    @blob_store.put(digest, StringIO.new(content))
    blob = Blob.create!(digest: digest, size: content.bytesize, references_count: 2)

    owner = identities(:tonny_google)
    repo_a = Repository.create!(name: "shared-blob-repo-a-#{SecureRandom.hex(4)}", owner_identity: owner)
    repo_b = Repository.create!(name: "shared-blob-repo-b-#{SecureRandom.hex(4)}", owner_identity: owner)

    manifest_a = repo_a.manifests.create!(
      digest: "sha256:shared-a-#{SecureRandom.hex(8)}",
      media_type: "application/vnd.docker.distribution.manifest.v2+json",
      payload: "{}", size: 2
    )
    manifest_b = repo_b.manifests.create!(
      digest: "sha256:shared-b-#{SecureRandom.hex(8)}",
      media_type: "application/vnd.docker.distribution.manifest.v2+json",
      payload: "{}", size: 2
    )
    Layer.create!(manifest: manifest_a, blob: blob, position: 0)
    Layer.create!(manifest: manifest_b, blob: blob, position: 0)
    # Tag both manifests so the orphan-manifest sweep does not destroy them.
    repo_a.tags.create!(name: "v1", manifest: manifest_a)
    repo_b.tags.create!(name: "v1", manifest: manifest_b)

    # Simulate the V2 destroy path on repoA: drop tags, decrement once
    # (references_count: 2 -> 1), then destroy the manifest in repoA.
    manifest_a.tags.destroy_all
    blob.decrement!(:references_count)
    manifest_a.destroy!

    CleanupOrphanedBlobsJob.perform_now

    assert Blob.exists?(digest: digest), "shared blob row must survive GC"
    assert_equal true, @blob_store.exists?(digest), "shared blob file must survive GC"
    assert_equal 1, blob.reload.references_count
    # Sanity: manifest in repoB still alive and still referencing the blob.
    assert Manifest.exists?(id: manifest_b.id)
  end

  # E-33: GC must remove orphan manifests (no tag pointing to them) and
  # decrement the references_count of every blob the manifest used. Blobs
  # whose only reference was the orphan manifest reach 0 and are deleted
  # on the next sweep.
  test "perform removes orphan manifests and decrements (then GCs) their blobs" do
    content = "orphan manifest blob"
    digest = DigestCalculator.compute(content)
    @blob_store.put(digest, StringIO.new(content))
    blob = Blob.create!(digest: digest, size: content.bytesize, references_count: 1)

    repo = Repository.create!(
      name: "orphan-mfst-repo-#{SecureRandom.hex(4)}",
      owner_identity: identities(:tonny_google)
    )
    orphan_manifest = repo.manifests.create!(
      digest: "sha256:orphan-#{SecureRandom.hex(8)}",
      media_type: "application/vnd.docker.distribution.manifest.v2+json",
      payload: "{}", size: 2
    )
    Layer.create!(manifest: orphan_manifest, blob: blob, position: 0)
    # Intentionally NO tag: this manifest is orphaned.

    assert_nil Tag.find_by(manifest_id: orphan_manifest.id), "precondition: no tag on orphan manifest"

    CleanupOrphanedBlobsJob.perform_now

    # Manifest is destroyed; its blob's references_count is decremented to 0.
    assert_nil Manifest.find_by(id: orphan_manifest.id), "orphan manifest must be destroyed"
    assert_equal 0, blob.reload.references_count, "blob references_count must be decremented"

    # Blob is still on disk because cleanup_orphaned_blobs ran BEFORE
    # cleanup_orphaned_manifests in this same pass — that's expected.
    # A second GC pass picks up the now-zero-ref blob.
    CleanupOrphanedBlobsJob.perform_now

    assert_nil Blob.find_by(digest: digest), "blob row must be GC'd on the next pass"
    assert_equal false, @blob_store.exists?(digest), "blob file must be GC'd on the next pass"
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
