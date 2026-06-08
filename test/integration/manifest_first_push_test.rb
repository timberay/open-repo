require "test_helper"

# G4 — first push to a brand-new repository must succeed and assign ownership
# to the authenticated pusher, even on a fresh deploy where the configured
# admin User has not been seeded yet.
#
# Scenario: docker has already pushed/mounted every referenced blob, so the
# manifest PUT is the first write that reaches a not-yet-existing repository.
# This pins that the manifest write path:
#   - does NOT 500 on an unseeded admin (no admin User lookup), and
#   - does NOT 404 a legitimate first push, and
#   - creates the repository owned by the pusher (not the admin).
class ManifestFirstPushTest < ActionDispatch::IntegrationTest
  def config_content
    @config_content ||= File.read(Rails.root.join("test/fixtures/configs/image_config.json"))
  end

  setup do
    @storage_dir = Dir.mktmpdir
    @original_storage_path = Rails.configuration.storage_path
    Rails.configuration.storage_path = @storage_dir
    @blob_store = BlobStore.new(@storage_dir)

    @config_digest = DigestCalculator.compute(config_content)
    @layer_content = SecureRandom.random_bytes(512)
    @layer_digest  = DigestCalculator.compute(@layer_content)

    @manifest_payload = {
      schemaVersion: 2,
      mediaType: "application/vnd.docker.distribution.manifest.v2+json",
      config: {
        mediaType: "application/vnd.docker.container.image.v1+json",
        size: config_content.bytesize,
        digest: @config_digest
      },
      layers: [
        {
          mediaType: "application/vnd.docker.image.rootfs.diff.tar.gzip",
          size: @layer_content.bytesize,
          digest: @layer_digest
        }
      ]
    }.to_json

    # Pre-seed the referenced blobs (simulates docker having already pushed /
    # mounted every layer, so the manifest PUT is the first write to the repo).
    @blob_store.put(@config_digest, StringIO.new(config_content))
    @blob_store.put(@layer_digest,  StringIO.new(@layer_content))

    @manifest_headers = {
      "CONTENT_TYPE" => "application/vnd.docker.distribution.manifest.v2+json"
    }.merge(basic_auth_for(pat_raw: TONNY_CLI_RAW, email: "tonny@timberay.com"))
  end

  teardown do
    FileUtils.rm_rf(@storage_dir)
    Rails.configuration.storage_path = @original_storage_path
  end

  test "first manifest push to a new repo by a non-admin succeeds and owns the repo when admin is unseeded" do
    # Fresh deploy: the configured admin has never signed in, so no admin User row exists.
    Rails.configuration.x.registry.admin_email = "unseeded-admin-#{SecureRandom.hex(4)}@nowhere.invalid"
    repo_name = "first-push-#{SecureRandom.hex(4)}"

    put "/v2/#{repo_name}/manifests/v1.0.0",
        params: @manifest_payload, headers: @manifest_headers

    assert_response 201,
                    "first push to a new repo should succeed; got #{response.status}: #{response.body}"

    repo = Repository.find_by!(name: repo_name)
    assert_equal identities(:tonny_google).id, repo.owner_identity_id,
                 "first pusher (not the admin) must own the new repository"
  end
end
