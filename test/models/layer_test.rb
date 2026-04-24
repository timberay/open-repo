require "test_helper"

class LayerTest < ActiveSupport::TestCase
  def repository
    @repository ||= Repository.create!(name: "test-repo", owner_identity: identities(:tonny_google))
  end

  def manifest
    @manifest ||= Manifest.create!(
      repository: repository,
      digest: "sha256:abc",
      media_type: "application/vnd.docker.distribution.manifest.v2+json",
      payload: "{}",
      size: 100
    )
  end

  def blob
    @blob ||= Blob.create!(digest: "sha256:layer1", size: 2048)
  end

  test "validations requires position" do
    layer = Layer.new(manifest: manifest, blob: blob, position: nil)
    refute layer.valid?
  end

  test "validations requires unique position per manifest" do
    Layer.create!(manifest: manifest, blob: blob, position: 0)
    l2 = Layer.new(manifest: manifest, blob: blob, position: 0)
    refute l2.valid?
  end

  # UC-MODEL-004.e2 — Layer destroy and Blob#references_count.
  # IMPORTANT: As with Manifest destroy, Layer destroy itself does NOT
  # decrement the Blob#references_count. Decrement is performed explicitly by
  # `RepositoriesController#destroy`, `V2::ManifestsController#destroy`, and
  # `CleanupOrphanedBlobsJob` BEFORE calling destroy. These tests pin that
  # boundary so the contract is observable.
  test "destroying a single layer does not auto-decrement its blob references_count" do
    target_blob = Blob.create!(digest: "sha256:#{SecureRandom.hex(32)}", size: 1024, references_count: 1)
    layer = Layer.create!(manifest: manifest, blob: target_blob, position: 0)

    layer.destroy!
    target_blob.reload

    assert_equal 1, target_blob.references_count, "model destroy must not auto-decrement"
  end

  test "two layers pointing to the same blob: destroying one leaves blob row intact" do
    shared_blob = Blob.create!(digest: "sha256:#{SecureRandom.hex(32)}", size: 1024, references_count: 2)
    other_manifest = Manifest.create!(
      repository: repository,
      digest: "sha256:#{SecureRandom.hex(32)}",
      media_type: "application/vnd.docker.distribution.manifest.v2+json",
      payload: "{}",
      size: 100
    )
    l1 = Layer.create!(manifest: manifest,       blob: shared_blob, position: 0)
    Layer.create!(manifest: other_manifest, blob: shared_blob, position: 0)

    # Caller-driven decrement (mirrors controller / job behavior).
    shared_blob.decrement!(:references_count)
    l1.destroy!
    shared_blob.reload

    assert_equal 1, shared_blob.references_count
    assert Blob.exists?(shared_blob.id), "blob is NOT destroyed when one of its layers is destroyed"
    assert_equal 1, Layer.where(blob_id: shared_blob.id).count
  end

  test "blob is NOT destroyed when its layer is destroyed (only the layer row goes away)" do
    target_blob = Blob.create!(digest: "sha256:#{SecureRandom.hex(32)}", size: 1024, references_count: 1)
    layer = Layer.create!(manifest: manifest, blob: target_blob, position: 0)

    layer.destroy!

    assert Blob.exists?(target_blob.id), "blob row must survive layer destroy"
    refute Layer.exists?(layer.id)
  end
end
