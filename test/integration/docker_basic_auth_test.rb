require "test_helper"

# Tech design §6.5 — Docker V2 Basic-scheme auth integration scenarios.
#
# Scenario coverage:
#   1. PUT without Authorization → 401 + exact Basic realm="Registry" challenge
#   2. PUT with valid PAT Basic auth → 201 + TagEvent.actor = user email + pat.last_used_at updated
#   3. PUT with revoked PAT → 401
#   4. Anonymous GET manifest (anonymous_pull_enabled=true) → 200 without Authorization
class DockerBasicAuthTest < ActionDispatch::IntegrationTest
  def config_content
    @config_content ||= File.read(Rails.root.join("test/fixtures/configs/image_config.json"))
  end

  setup do
    @suffix = SecureRandom.hex(4)
    @repo_name = "basic-auth-test-#{@suffix}"

    @storage_dir = Dir.mktmpdir
    @original_storage_path = Rails.configuration.storage_path
    Rails.configuration.storage_path = @storage_dir

    @blob_store = BlobStore.new(@storage_dir)

    @config_digest = DigestCalculator.compute(config_content)
    @layer_content = SecureRandom.random_bytes(1024)
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
    @blob_store.put(@layer_digest, StringIO.new(@layer_content))
    Blob.create!(digest: @config_digest, size: config_content.bytesize)
    Blob.create!(digest: @layer_digest, size: @layer_content.bytesize)
  end

  teardown do
    FileUtils.rm_rf(@storage_dir)
    Rails.configuration.storage_path = @original_storage_path
  end

  # Scenario 1: no Authorization header → 401 + exact Basic challenge
  test "PUT without Authorization returns 401 with exact Basic realm challenge" do
    put "/v2/#{@repo_name}/manifests/v1.0.0",
        params: "{}",
        headers: { "CONTENT_TYPE" => "application/vnd.docker.distribution.manifest.v2+json" }

    assert_response :unauthorized
    assert_equal %(Basic realm="Registry"), response.headers["WWW-Authenticate"]
  end

  # Scenario 2: valid PAT Basic auth → 201 + TagEvent.actor = user email + pat.last_used_at updated
  test "PUT with valid PAT returns 201 and records TagEvent actor as user email" do
    pat = personal_access_tokens(:tonny_cli_active)
    before_time = Time.current

    assert_difference -> { TagEvent.count }, +1 do
      put "/v2/#{@repo_name}/manifests/v1.0.0",
          params: @manifest_payload,
          headers: {
            "CONTENT_TYPE" => "application/vnd.docker.distribution.manifest.v2+json"
          }.merge(basic_auth_for(pat_raw: TONNY_CLI_RAW, email: "tonny@timberay.com"))
    end

    assert_response 201

    event = TagEvent.order(:occurred_at).last
    assert_equal "tonny@timberay.com", event.actor

    pat.reload
    assert_in_delta before_time.to_i, pat.last_used_at.to_i, 5
  end

  # Scenario 3: revoked PAT → 401
  test "PUT with revoked PAT returns 401" do
    put "/v2/#{@repo_name}/manifests/v1.0.0",
        params: "{}",
        headers: {
          "CONTENT_TYPE" => "application/vnd.docker.distribution.manifest.v2+json"
        }.merge(basic_auth_for(pat_raw: TONNY_REVOKED_RAW, email: "tonny@timberay.com"))

    assert_response :unauthorized
  end

  # Scenario 4: anonymous pull (flag=true) → 200 without Authorization
  test "GET manifest without Authorization returns 200 when anonymous_pull_enabled" do
    Rails.configuration.x.registry.anonymous_pull_enabled = true

    anon_repo = Repository.create!(name: "anon-basic-#{@suffix}")
    anon_manifest = anon_repo.manifests.create!(
      digest: "sha256:anon#{SecureRandom.hex(8)}",
      media_type: "application/vnd.docker.distribution.manifest.v2+json",
      payload: "{}",
      size: 2
    )
    anon_repo.tags.create!(name: "latest", manifest: anon_manifest)

    get "/v2/#{anon_repo.name}/manifests/latest"

    assert_response :ok
  end
end
