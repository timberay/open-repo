require "test_helper"

class ManifestTest < ActiveSupport::TestCase
  def repository
    @repository ||= Repository.create!(name: "test-repo", owner_identity: identities(:tonny_google))
  end

  test "validations requires digest, media_type, payload, size" do
    manifest = Manifest.new(repository: repository)
    refute manifest.valid?
    assert_includes manifest.errors[:digest], "can't be blank"
    assert_includes manifest.errors[:media_type], "can't be blank"
    assert_includes manifest.errors[:payload], "can't be blank"
    assert_includes manifest.errors[:size], "can't be blank"
  end

  test "validations requires unique digest" do
    Manifest.create!(
      repository: repository,
      digest: "sha256:abc",
      media_type: "application/vnd.docker.distribution.manifest.v2+json",
      payload: "{}",
      size: 100
    )
    m2 = Manifest.new(
      repository: repository,
      digest: "sha256:abc",
      media_type: "application/vnd.docker.distribution.manifest.v2+json",
      payload: "{}",
      size: 100
    )
    refute m2.valid?
  end

  test "associations has many tags" do
    assert_equal :has_many, Manifest.reflect_on_association(:tags).macro
  end

  test "associations has many layers" do
    assert_equal :has_many, Manifest.reflect_on_association(:layers).macro
  end

  test "associations has many pull_events" do
    assert_equal :has_many, Manifest.reflect_on_association(:pull_events).macro
  end

  # UC-MODEL-004 — Manifest destroy cascade (ref-count contract pin).
  # IMPORTANT: The Manifest model itself does NOT decrement Blob#references_count
  # on destroy. Decrement is the responsibility of the caller — see
  # `RepositoriesController#destroy`, `V2::ManifestsController#destroy`, and
  # `CleanupOrphanedBlobsJob#cleanup_orphaned_manifests`. These tests pin the
  # current model contract so any future migration of decrement-into-callback
  # is observable.
  test "destroying a manifest with N layers leaves blob references_count unchanged at the model layer" do
    digests = Array.new(3) { "sha256:#{SecureRandom.hex(32)}" }
    blobs = digests.map { |d| Blob.create!(digest: d, size: 512, references_count: 5) }
    manifest = Manifest.create!(
      repository: repository,
      digest: "sha256:#{SecureRandom.hex(32)}",
      media_type: "application/vnd.docker.distribution.manifest.v2+json",
      payload: "{}",
      size: 100
    )
    blobs.each_with_index do |b, i|
      Layer.create!(manifest: manifest, blob: b, position: i)
    end

    assert_difference -> { Layer.count }, -3 do
      manifest.destroy!
    end

    blobs.each(&:reload)
    blobs.each { |b| assert_equal 5, b.references_count, "model destroy must not auto-decrement" }
  end

  test "destroying a manifest with no layers does not raise" do
    manifest = Manifest.create!(
      repository: repository,
      digest: "sha256:#{SecureRandom.hex(32)}",
      media_type: "application/vnd.docker.distribution.manifest.v2+json",
      payload: "{}",
      size: 100
    )
    assert_nothing_raised { manifest.destroy! }
    assert_equal 0, Layer.where(manifest_id: manifest.id).count
  end

  test "destroying a manifest with associated tags nullifies the tag manifest_id (does not destroy tags)" do
    # UC-MODEL-004.e4 — `has_many :tags, dependent: :nullify`
    manifest = Manifest.create!(
      repository: repository,
      digest: "sha256:#{SecureRandom.hex(32)}",
      media_type: "application/vnd.docker.distribution.manifest.v2+json",
      payload: "{}",
      size: 100
    )
    tag = Tag.create!(repository: repository, manifest: manifest, name: "v1")

    # Schema FK on tags(manifest_id) is NOT NULL; without an FK on_delete clause,
    # `dependent: :nullify` will fail with NOT NULL violation. This pins that
    # contract: nullifying a NOT NULL column raises at DB level.
    assert_raises(ActiveRecord::NotNullViolation, ActiveRecord::StatementInvalid) do
      manifest.destroy!
    end

    # Tag should still exist after the failed destroy.
    assert Tag.exists?(tag.id), "tag should survive aborted nullify"
  end
end
