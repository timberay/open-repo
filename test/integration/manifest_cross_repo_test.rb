require "test_helper"

# G1 — manifest digests are content-addressed, so the SAME image content
# yields the SAME digest in every repository. The digest uniqueness constraint
# must therefore be scoped per repository: a global unique index made the
# second repository's push of an already-seen digest raise RecordNotUnique
# (500). Pushing the same digest to two repos must succeed and both copies
# must be independently servable.
class ManifestCrossRepoTest < ActionDispatch::IntegrationTest
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

    @payload = {
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

    @headers = { "CONTENT_TYPE" => "application/vnd.docker.distribution.manifest.v2+json" }
               .merge(basic_auth_for(pat_raw: TONNY_CLI_RAW, email: "tonny@timberay.com"))
  end

  teardown do
    FileUtils.rm_rf(@storage_dir)
    Rails.configuration.storage_path = @original_storage_path
  end

  test "the same manifest digest can be pushed to two different repositories" do
    suffix = SecureRandom.hex(4)
    repo_a = "teama-#{suffix}/app"
    repo_b = "teamb-#{suffix}/app"

    put "/v2/#{repo_a}/manifests/v1.0.0", params: @payload, headers: @headers
    assert_response 201, "first repo push should succeed; got #{response.status}: #{response.body}"
    digest_a = response.headers["Docker-Content-Digest"]

    put "/v2/#{repo_b}/manifests/v1.0.0", params: @payload, headers: @headers
    assert_response 201, "same digest to a second repo should succeed; got #{response.status}: #{response.body}"
    digest_b = response.headers["Docker-Content-Digest"]

    assert_equal digest_a, digest_b, "identical content must yield an identical digest"

    # Both copies are independently servable.
    get "/v2/#{repo_a}/manifests/v1.0.0", headers: @headers
    assert_response :ok
    get "/v2/#{repo_b}/manifests/v1.0.0", headers: @headers
    assert_response :ok
  end
end
