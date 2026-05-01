require "test_helper"

# B-42: Accidentally deleted a tag, then push the same digest+name back.
#
# Verifies the data model supports the "oh no, I deleted my tag" recovery
# path:
#   1. PUT  /v2/<name>/manifests/<tag>     -> 201 (initial push)
#   2. DELETE /v2/<name>/manifests/<tag>   -> 202 (tag + manifest gone)
#   3. GET  /v2/<name>/manifests/<tag>     -> 404 (truly gone)
#   4. PUT  /v2/<name>/manifests/<tag>     -> 201 (re-push same payload)
#   5. Re-push Docker-Content-Digest matches the original
#   6. GET  /v2/<name>/manifests/<tag>     -> 200 (recovered)
#
# Note: the V2 destroy action wipes ALL tags pointing at the manifest and
# destroys the manifest row, so the re-push creates a brand-new Manifest
# row + Tag row. The TagEvent action recorded is "create" (the assign_tag!
# branch where existing_tag is nil), NOT "pushed" — TagEvent.action is
# constrained to %w[create update delete ownership_transfer].
class TagRecoveryTest < ActionDispatch::IntegrationTest
  def config_content
    @config_content ||= File.read(Rails.root.join("test/fixtures/configs/image_config.json"))
  end

  setup do
    @suffix = SecureRandom.hex(4)
    @repo_name = "recover-#{@suffix}"
    @tag_name  = "v1"

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

    @blob_store.put(@config_digest, StringIO.new(config_content))
    @blob_store.put(@layer_digest,  StringIO.new(@layer_content))
    Blob.create!(digest: @config_digest, size: config_content.bytesize)
    Blob.create!(digest: @layer_digest,  size: @layer_content.bytesize)
    Repository.create!(name: @repo_name, owner_identity: identities(:tonny_google))

    @auth = basic_auth_for(pat_raw: TONNY_CLI_RAW, email: "tonny@timberay.com")
    @manifest_headers = {
      "CONTENT_TYPE" => "application/vnd.docker.distribution.manifest.v2+json"
    }.merge(@auth)
  end

  teardown do
    FileUtils.rm_rf(@storage_dir)
    Rails.configuration.storage_path = @original_storage_path
  end

  test "deleted tag can be re-pushed with the same digest and recovers" do
    # 1) Initial push.
    put "/v2/#{@repo_name}/manifests/#{@tag_name}",
        params: @manifest_payload, headers: @manifest_headers
    assert_response 201
    digest_after_push = response.headers["Docker-Content-Digest"]
    assert_not_nil digest_after_push,
                   "initial push must echo Docker-Content-Digest"

    # 2) Delete the tag (and its manifest).
    delete "/v2/#{@repo_name}/manifests/#{@tag_name}", headers: @auth
    assert_response 202

    # 3) GET should now 404.
    get "/v2/#{@repo_name}/manifests/#{@tag_name}", headers: @auth
    assert_response :not_found

    # 4) Re-push the SAME manifest payload — assign_tag! takes the
    #    existing_tag.nil? branch, so it logs a fresh `create` event.
    assert_difference -> { TagEvent.where(action: "create").count }, +1 do
      put "/v2/#{@repo_name}/manifests/#{@tag_name}",
          params: @manifest_payload, headers: @manifest_headers
      assert_response 201
    end

    # 5) Re-push digest is identical to original (content-addressable).
    assert_equal digest_after_push, response.headers["Docker-Content-Digest"]

    # 6) GET succeeds — tag recovered.
    get "/v2/#{@repo_name}/manifests/#{@tag_name}", headers: @auth
    assert_response :ok
  end
end
