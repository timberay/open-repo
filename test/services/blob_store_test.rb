require "test_helper"

class BlobStoreTest < ActiveSupport::TestCase
  def storage_dir
    @storage_dir ||= Dir.mktmpdir
  end

  def store
    @store ||= BlobStore.new(storage_dir)
  end

  teardown do
    FileUtils.rm_rf(storage_dir)
  end

  test "put and get stores and retrieves a blob by digest" do
    content = "hello blob"
    digest = DigestCalculator.compute(content)

    store.put(digest, StringIO.new(content))
    io = store.get(digest)
    assert_equal content, io.read
  end

  test "put skips write if blob already exists" do
    content = "hello blob"
    digest = DigestCalculator.compute(content)

    store.put(digest, StringIO.new(content))
    path = store.path_for(digest)
    mtime_before = File.mtime(path)

    sleep 0.01
    store.put(digest, StringIO.new(content))
    assert_equal mtime_before, File.mtime(path)
  end

  test "exists? returns false for non-existent blob" do
    assert_equal false, store.exists?("sha256:nonexistent")
  end

  test "exists? returns true after storing" do
    content = "test"
    digest = DigestCalculator.compute(content)
    store.put(digest, StringIO.new(content))
    assert_equal true, store.exists?(digest)
  end

  test "delete removes blob from disk" do
    content = "test"
    digest = DigestCalculator.compute(content)
    store.put(digest, StringIO.new(content))
    store.delete(digest)
    assert_equal false, store.exists?(digest)
  end

  test "path_for uses sharded directory structure" do
    path = store.path_for("sha256:aabbccdd1234")
    assert_includes path, "/blobs/sha256/aa/aabbccdd1234"
  end

  test "size returns file size" do
    content = "hello blob"
    digest = DigestCalculator.compute(content)
    store.put(digest, StringIO.new(content))
    assert_equal content.bytesize, store.size(digest)
  end

  test "upload lifecycle creates, appends, and finalizes an upload" do
    uuid = SecureRandom.uuid

    store.create_upload(uuid)
    assert_equal 0, store.upload_size(uuid)

    chunk1 = "hello "
    chunk2 = "world"
    store.append_upload(uuid, StringIO.new(chunk1))
    assert_equal 6, store.upload_size(uuid)

    store.append_upload(uuid, StringIO.new(chunk2))
    assert_equal 11, store.upload_size(uuid)

    content = chunk1 + chunk2
    digest = DigestCalculator.compute(content)
    store.finalize_upload(uuid, digest)

    assert_equal true, store.exists?(digest)
    assert_equal content, store.get(digest).read
  end

  test "upload lifecycle raises DigestMismatch on finalize with wrong digest" do
    uuid = SecureRandom.uuid
    store.create_upload(uuid)
    store.append_upload(uuid, StringIO.new("hello"))

    assert_raises(Registry::DigestMismatch) do
      store.finalize_upload(uuid, "sha256:wrong")
    end
  end

  test "upload lifecycle cancels an upload and cleans up" do
    uuid = SecureRandom.uuid
    store.create_upload(uuid)
    store.append_upload(uuid, StringIO.new("data"))
    store.cancel_upload(uuid)

    assert_raises(Errno::ENOENT) { store.upload_size(uuid) }
  end

  test "cleanup_stale_uploads removes uploads older than max_age" do
    uuid = SecureRandom.uuid
    store.create_upload(uuid)
    store.append_upload(uuid, StringIO.new("data"))

    # Backdate the startedat file
    startedat_path = File.join(storage_dir, "uploads", uuid, "startedat")
    File.write(startedat_path, 2.hours.ago.iso8601)

    store.cleanup_stale_uploads(max_age: 1.hour)
    assert_equal false, Dir.exist?(File.join(storage_dir, "uploads", uuid))
  end
end
