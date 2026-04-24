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
