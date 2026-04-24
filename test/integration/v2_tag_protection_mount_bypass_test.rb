require "test_helper"

# UC-AUTH-014 — verify that a writer-level attacker cannot overwrite a
# protected tag by first mounting a donor blob into the victim repo.
#
# The defense lives at ManifestProcessor#call (inside a row lock) via
# Repository#enforce_tag_protection!. This is an end-to-end assertion at
# the HTTP boundary: even if the attacker staggers their operations
# (mount → PUT manifest), the final PUT must return 409 DENIED and the
# protected tag must remain pinned to the original manifest.
class V2TagProtectionMountBypassTest < ActionDispatch::IntegrationTest
  setup do
    @storage_dir = Dir.mktmpdir
    Rails.configuration.storage_path = @storage_dir
    @victim = "bypass-target-#{SecureRandom.hex(3)}"

    Repository.create!(name: @victim, owner_identity: identities(:tonny_google))

    @original_manifest = push_original_manifest(@victim, tag: "v1.0.0").reload
    @original_digest   = @original_manifest.digest

    Repository.find_by!(name: @victim).update!(tag_protection_policy: "semver")

    RepositoryMember.create!(
      repository: Repository.find_by!(name: @victim),
      identity: identities(:admin_google),
      role: "writer"
    )
  end

  teardown do
    FileUtils.rm_rf(@storage_dir)
  end

  test "attacker with write access cannot overwrite a protected tag after mounting a donor blob" do
    # Step 1: mount a blob into the victim repo. The mount itself is a blob-
    # level operation and is expected to succeed for any writer.
    mount_blob = @original_manifest.layers.first.blob
    post "/v2/#{@victim}/blobs/uploads?mount=#{mount_blob.digest}&from=donor",
         headers: attacker_headers
    assert_includes [ 201, 202 ], response.status,
      "mount should not error for a writer member (got #{response.status}: #{response.body})"

    # Step 2: attempt to overwrite v1.0.0 with a different digest.
    evil_payload = build_evil_manifest_payload
    put "/v2/#{@victim}/manifests/v1.0.0",
        params: evil_payload,
        headers: {
          "CONTENT_TYPE" => "application/vnd.docker.distribution.manifest.v2+json"
        }.merge(attacker_headers)

    assert_equal 409, response.status,
      "PUT on protected tag must be rejected; got #{response.status}: #{response.body}"
    body = JSON.parse(response.body)
    assert_equal "DENIED", body.dig("errors", 0, "code")
  end

  test "protected tag still points to the original manifest after a blocked bypass attempt" do
    mount_blob = @original_manifest.layers.first.blob
    post "/v2/#{@victim}/blobs/uploads?mount=#{mount_blob.digest}&from=donor",
         headers: attacker_headers

    evil_payload = build_evil_manifest_payload
    put "/v2/#{@victim}/manifests/v1.0.0",
        params: evil_payload,
        headers: {
          "CONTENT_TYPE" => "application/vnd.docker.distribution.manifest.v2+json"
        }.merge(attacker_headers)

    tag = Repository.find_by!(name: @victim).tags.find_by!(name: "v1.0.0")
    assert_equal @original_digest, tag.manifest.digest,
      "v1.0.0 must still point to the original manifest after a blocked bypass"
  end

  test "attacker without member role cannot even start the mount step (403)" do
    Repository.find_by!(name: @victim).repository_members
      .where(identity_id: identities(:admin_google).id).destroy_all

    mount_blob = @original_manifest.layers.first.blob
    post "/v2/#{@victim}/blobs/uploads?mount=#{mount_blob.digest}&from=donor",
         headers: attacker_headers

    assert_equal 403, response.status
    assert_equal "DENIED", JSON.parse(response.body).dig("errors", 0, "code")
  end

  private

  def attacker_headers
    basic_auth_for(pat_raw: ADMIN_CLI_RAW, email: "admin@timberay.com")
  end

  def blob_store
    @blob_store ||= BlobStore.new(@storage_dir)
  end

  def push_original_manifest(repo_name, tag:)
    config_content = File.read(Rails.root.join("test/fixtures/configs/image_config.json"))
    config_digest  = DigestCalculator.compute(config_content)
    layer_content  = "original-layer-#{SecureRandom.hex(6)}".b
    layer_digest   = DigestCalculator.compute(layer_content)

    blob_store.put(config_digest, StringIO.new(config_content))
    blob_store.put(layer_digest,  StringIO.new(layer_content))

    payload = {
      schemaVersion: 2,
      mediaType: "application/vnd.docker.distribution.manifest.v2+json",
      config: {
        mediaType: "application/vnd.docker.container.image.v1+json",
        size: config_content.bytesize,
        digest: config_digest
      },
      layers: [
        {
          mediaType: "application/vnd.docker.image.rootfs.diff.tar.gzip",
          size: layer_content.bytesize,
          digest: layer_digest
        }
      ]
    }.to_json

    ManifestProcessor.new(blob_store).call(
      repo_name, tag,
      "application/vnd.docker.distribution.manifest.v2+json",
      payload, actor: "tonny@timberay.com"
    )
  end

  def build_evil_manifest_payload
    config_content = File.read(Rails.root.join("test/fixtures/configs/image_config.json"))
    config_digest  = DigestCalculator.compute(config_content)
    evil_layer     = "evil-layer-#{SecureRandom.hex(6)}".b
    evil_digest    = DigestCalculator.compute(evil_layer)

    blob_store.put(config_digest, StringIO.new(config_content))
    blob_store.put(evil_digest,   StringIO.new(evil_layer))

    {
      schemaVersion: 2,
      mediaType: "application/vnd.docker.distribution.manifest.v2+json",
      config: {
        mediaType: "application/vnd.docker.container.image.v1+json",
        size: config_content.bytesize,
        digest: config_digest
      },
      layers: [
        {
          mediaType: "application/vnd.docker.image.rootfs.diff.tar.gzip",
          size: evil_layer.bytesize,
          digest: evil_digest
        }
      ]
    }.to_json
  end
end
