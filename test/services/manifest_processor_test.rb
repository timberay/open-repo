require "test_helper"

class ManifestProcessorTest < ActiveSupport::TestCase
  def store_dir
    @store_dir ||= Dir.mktmpdir
  end

  def blob_store
    @blob_store ||= BlobStore.new(store_dir)
  end

  def processor
    @processor ||= ManifestProcessor.new(blob_store)
  end

  def config_content
    @config_content ||= File.read(Rails.root.join("test/fixtures/configs/image_config.json"))
  end

  def config_digest
    @config_digest ||= DigestCalculator.compute(config_content)
  end

  def layer1_content
    @layer1_content ||= SecureRandom.random_bytes(1024)
  end

  def layer1_digest
    @layer1_digest ||= DigestCalculator.compute(layer1_content)
  end

  def layer2_content
    @layer2_content ||= SecureRandom.random_bytes(2048)
  end

  def layer2_digest
    @layer2_digest ||= DigestCalculator.compute(layer2_content)
  end

  def manifest_json
    @manifest_json ||= {
      schemaVersion: 2,
      mediaType: "application/vnd.docker.distribution.manifest.v2+json",
      config: { mediaType: "application/vnd.docker.container.image.v1+json", size: config_content.bytesize, digest: config_digest },
      layers: [
        { mediaType: "application/vnd.docker.image.rootfs.diff.tar.gzip", size: layer1_content.bytesize, digest: layer1_digest },
        { mediaType: "application/vnd.docker.image.rootfs.diff.tar.gzip", size: layer2_content.bytesize, digest: layer2_digest }
      ]
    }.to_json
  end

  setup do
    blob_store.put(config_digest, StringIO.new(config_content))
    blob_store.put(layer1_digest, StringIO.new(layer1_content))
    blob_store.put(layer2_digest, StringIO.new(layer2_content))
  end

  teardown do
    FileUtils.rm_rf(store_dir)
  end

  test "call creates repository, manifest, tag, layers, and blobs" do
    result = processor.call("test-repo", "v1.0.0", "application/vnd.docker.distribution.manifest.v2+json", manifest_json, actor: "anonymous")

    assert_kind_of Manifest, result
    assert Repository.find_by(name: "test-repo").present?
    assert Tag.find_by(name: "v1.0.0").present?
    assert_equal 2, result.layers.count
    assert_equal "amd64", result.architecture
    assert_equal "linux", result.os
    assert_includes result.docker_config, "Cmd"
  end

  test "call creates a tag_event on new tag" do
    processor.call("test-repo", "v1.0.0", "application/vnd.docker.distribution.manifest.v2+json", manifest_json, actor: "anonymous")

    event = TagEvent.last
    assert_equal "create", event.action
    assert_equal "v1.0.0", event.tag_name
    assert_nil event.previous_digest
  end

  test "call creates an update tag_event when tag is reassigned" do
    result1 = processor.call("test-repo", "latest", "application/vnd.docker.distribution.manifest.v2+json", manifest_json, actor: "anonymous")
    old_digest = result1.digest

    # Push a different manifest to same tag
    new_layer = SecureRandom.random_bytes(512)
    new_layer_digest = DigestCalculator.compute(new_layer)
    blob_store.put(new_layer_digest, StringIO.new(new_layer))

    new_manifest_json = {
      schemaVersion: 2,
      mediaType: "application/vnd.docker.distribution.manifest.v2+json",
      config: { mediaType: "application/vnd.docker.container.image.v1+json", size: config_content.bytesize, digest: config_digest },
      layers: [
        { mediaType: "application/vnd.docker.image.rootfs.diff.tar.gzip", size: new_layer.bytesize, digest: new_layer_digest }
      ]
    }.to_json

    processor.call("test-repo", "latest", "application/vnd.docker.distribution.manifest.v2+json", new_manifest_json, actor: "anonymous")

    event = TagEvent.where(action: "update").last
    assert_equal old_digest, event.previous_digest
  end

  test "call raises ManifestInvalid for missing referenced blob" do
    bad_json = {
      schemaVersion: 2,
      mediaType: "application/vnd.docker.distribution.manifest.v2+json",
      config: { mediaType: "application/vnd.docker.container.image.v1+json", size: 100, digest: "sha256:nonexistent" },
      layers: []
    }.to_json

    err = assert_raises(Registry::ManifestInvalid) do
      processor.call("test-repo", "v1", "application/vnd.docker.distribution.manifest.v2+json", bad_json, actor: "anonymous")
    end
    assert_match(/config blob not found/, err.message)
  end

  test "call handles digest reference instead of tag name" do
    result = processor.call("test-repo", nil, "application/vnd.docker.distribution.manifest.v2+json", manifest_json, actor: "anonymous")
    assert_kind_of Manifest, result
    assert_equal 0, Tag.count
  end

  test "call increments blob references_count" do
    processor.call("test-repo", "v1", "application/vnd.docker.distribution.manifest.v2+json", manifest_json, actor: "anonymous")

    layer1_blob = Blob.find_by(digest: layer1_digest)
    assert_equal 1, layer1_blob.references_count
  end

  # Tag protection tests

  test "call with tag protection same digest re-push succeeds" do
    repo = Repository.create!(name: "test-repo", owner_identity: identities(:tonny_google))
    processor.call("test-repo", "v1.0.0", "application/vnd.docker.distribution.manifest.v2+json", manifest_json, actor: "anonymous")
    repo.update!(tag_protection_policy: "semver")
    repo.reload

    assert_nothing_raised do
      processor.call("test-repo", "v1.0.0", "application/vnd.docker.distribution.manifest.v2+json", manifest_json, actor: "anonymous")
    end
  end

  test "call with tag protection different digest push on protected tag raises Registry::TagProtected" do
    repo = Repository.create!(name: "test-repo", owner_identity: identities(:tonny_google))
    processor.call("test-repo", "v1.0.0", "application/vnd.docker.distribution.manifest.v2+json", manifest_json, actor: "anonymous")
    repo.update!(tag_protection_policy: "semver")
    repo.reload

    different_manifest_json = build_different_manifest_json

    assert_raises(Registry::TagProtected) do
      processor.call("test-repo", "v1.0.0", "application/vnd.docker.distribution.manifest.v2+json", different_manifest_json, actor: "anonymous")
    end
  end

  test "call with tag protection different digest push does NOT create a new manifest row" do
    repo = Repository.create!(name: "test-repo", owner_identity: identities(:tonny_google))
    processor.call("test-repo", "v1.0.0", "application/vnd.docker.distribution.manifest.v2+json", manifest_json, actor: "anonymous")
    repo.update!(tag_protection_policy: "semver")
    repo.reload

    different_manifest_json = build_different_manifest_json

    assert_no_difference -> { Manifest.count } do
      begin
        processor.call("test-repo", "v1.0.0", "application/vnd.docker.distribution.manifest.v2+json", different_manifest_json, actor: "anonymous")
      rescue Registry::TagProtected
      end
    end
  end

  test "call with tag protection different digest push does NOT increment layer blob references_count" do
    repo = Repository.create!(name: "test-repo", owner_identity: identities(:tonny_google))
    processor.call("test-repo", "v1.0.0", "application/vnd.docker.distribution.manifest.v2+json", manifest_json, actor: "anonymous")
    repo.update!(tag_protection_policy: "semver")
    repo.reload

    layer_blob = Blob.find_by(digest: layer1_digest)
    before_refs = layer_blob.references_count

    different_manifest_json = build_different_manifest_json

    begin
      processor.call("test-repo", "v1.0.0", "application/vnd.docker.distribution.manifest.v2+json", different_manifest_json, actor: "anonymous")
    rescue Registry::TagProtected
    end
    assert_equal before_refs, layer_blob.reload.references_count
  end

  test "call with tag protection unprotected tag (latest with semver policy) permits push" do
    repo = Repository.create!(name: "test-repo", owner_identity: identities(:tonny_google))
    processor.call("test-repo", "v1.0.0", "application/vnd.docker.distribution.manifest.v2+json", manifest_json, actor: "anonymous")
    repo.update!(tag_protection_policy: "semver")
    repo.reload

    assert_nothing_raised do
      processor.call("test-repo", "latest", "application/vnd.docker.distribution.manifest.v2+json", manifest_json, actor: "anonymous")
    end
  end

  test "call with tag protection digest reference bypasses protection check" do
    repo = Repository.create!(name: "test-repo", owner_identity: identities(:tonny_google))
    processor.call("test-repo", "v1.0.0", "application/vnd.docker.distribution.manifest.v2+json", manifest_json, actor: "anonymous")
    repo.update!(tag_protection_policy: "semver")
    repo.reload

    r = Repository.find_by!(name: "test-repo")
    r.update!(tag_protection_policy: "all_except_latest")

    assert_nothing_raised do
      processor.call("test-repo", "sha256:dummy-ignored-anyway", "application/vnd.docker.distribution.manifest.v2+json", manifest_json, actor: "anonymous")
    end
  end

  test "call without actor: raises ArgumentError" do
    err = assert_raises(ArgumentError) do
      ManifestProcessor.new.call(
        "repo-no-actor",
        "v1",
        "application/vnd.docker.distribution.manifest.v2+json",
        "{}"
      )
    end
    assert_match(/missing keyword: :actor/, err.message)
  end

  test "call with actor: 'anonymous' writes TagEvent.actor = 'anonymous'" do
    assert_difference -> { TagEvent.where(actor: "anonymous").count }, +1 do
      processor.call(
        "repo-actor-kwarg",
        "v1",
        "application/vnd.docker.distribution.manifest.v2+json",
        manifest_json,
        actor: "anonymous"
      )
    end
  end

  # ---------------------------------------------------------------------------
  # UC-MODEL-009 .e7 — malformed config JSON in the config blob.
  # ManifestProcessor#extract_config rescues JSON::ParserError and returns
  # {architecture: nil, os: nil, config_json: nil}; the call still succeeds
  # and the resulting Manifest row records the nil fallbacks.
  # ---------------------------------------------------------------------------
  test "call with malformed config JSON falls back to nil arch/os/docker_config and still succeeds" do
    bad_config = "this-is-not-json"
    bad_config_digest = DigestCalculator.compute(bad_config)
    blob_store.put(bad_config_digest, StringIO.new(bad_config))

    bad_layer = SecureRandom.random_bytes(256)
    bad_layer_digest = DigestCalculator.compute(bad_layer)
    blob_store.put(bad_layer_digest, StringIO.new(bad_layer))

    payload = {
      schemaVersion: 2,
      mediaType: "application/vnd.docker.distribution.manifest.v2+json",
      config: { mediaType: "application/vnd.docker.container.image.v1+json", size: bad_config.bytesize, digest: bad_config_digest },
      layers: [
        { mediaType: "application/vnd.docker.image.rootfs.diff.tar.gzip", size: bad_layer.bytesize, digest: bad_layer_digest }
      ]
    }.to_json

    result = processor.call("repo-bad-config", "v1.0.0", "application/vnd.docker.distribution.manifest.v2+json", payload, actor: "anonymous")

    assert_kind_of Manifest, result
    assert_nil result.architecture
    assert_nil result.os
    assert_nil result.docker_config
  end

  # ---------------------------------------------------------------------------
  # UC-MODEL-009 .e10 — admin email user missing on repo creation.
  # The processor delegates owner_identity to User.find_by!(email: admin_email).
  # When that user does not exist, find_by! raises ActiveRecord::RecordNotFound
  # and the error is intentionally NOT rescued (deployment misconfiguration
  # surface). Pin the current behavior so a silent rescue regression is caught.
  # ---------------------------------------------------------------------------
  test "call raises ActiveRecord::RecordNotFound when admin email user is missing" do
    Rails.configuration.x.registry.admin_email = "no-such-admin-#{SecureRandom.hex(4)}@example.invalid"

    assert_raises(ActiveRecord::RecordNotFound) do
      processor.call(
        "repo-no-admin-#{SecureRandom.hex(4)}",
        "v1.0.0",
        "application/vnd.docker.distribution.manifest.v2+json",
        manifest_json,
        actor: "anonymous"
      )
    end
  end

  # ---------------------------------------------------------------------------
  # UC-MODEL-009 .e12 — payload bytesize stored as Manifest#size.
  # ---------------------------------------------------------------------------
  test "call stores payload bytesize as manifest.size" do
    result = processor.call("repo-size-check", "v1.0.0", "application/vnd.docker.distribution.manifest.v2+json", manifest_json, actor: "anonymous")

    assert_equal manifest_json.bytesize, result.size
  end

  # ---------------------------------------------------------------------------
  # UC-MODEL-009 .e13 — tag retry idempotency.
  # CI re-pushes the SAME (manifest, tag) pair after a network glitch. The
  # second call must NOT create a duplicate Manifest row and must NOT emit a
  # spurious TagEvent (no digest change ⇒ no "update" event). Since the
  # repository starts without a protection policy and the push is idempotent
  # at the tag level (existing_tag.manifest.digest == new_digest), the second
  # call's assign_tag! short-circuits without creating a TagEvent.
  # ---------------------------------------------------------------------------
  test "call is idempotent on retry and does not emit a spurious TagEvent" do
    processor.call("repo-retry-idemp", "v1.0.0", "application/vnd.docker.distribution.manifest.v2+json", manifest_json, actor: "anonymous")

    manifest_count_before = Manifest.count
    tag_event_count_before = TagEvent.count

    processor.call("repo-retry-idemp", "v1.0.0", "application/vnd.docker.distribution.manifest.v2+json", manifest_json, actor: "anonymous")

    assert_equal manifest_count_before, Manifest.count,
      "second push of identical (tag, digest) should not create a new Manifest row"
    assert_equal tag_event_count_before, TagEvent.count,
      "second push of identical (tag, digest) should not emit a spurious TagEvent"
  end

  private

  def build_different_manifest_json
    new_layer = SecureRandom.random_bytes(512)
    new_layer_digest = DigestCalculator.compute(new_layer)
    blob_store.put(new_layer_digest, StringIO.new(new_layer))
    {
      schemaVersion: 2,
      mediaType: "application/vnd.docker.distribution.manifest.v2+json",
      config: { mediaType: "application/vnd.docker.container.image.v1+json", size: config_content.bytesize, digest: config_digest },
      layers: [
        { mediaType: "application/vnd.docker.image.rootfs.diff.tar.gzip", size: new_layer.bytesize, digest: new_layer_digest }
      ]
    }.to_json
  end
end
