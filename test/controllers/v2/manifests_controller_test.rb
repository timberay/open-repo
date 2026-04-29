require "test_helper"

class V2::ManifestsControllerTest < ActionDispatch::IntegrationTest
  def config_content
    @config_content ||= File.read(Rails.root.join("test/fixtures/configs/image_config.json"))
  end

  setup do
    @storage_dir = Dir.mktmpdir
    Rails.configuration.storage_path = @storage_dir

    @blob_store = BlobStore.new(@storage_dir)
    @repo_name = "test-repo"
    @repo = Repository.create!(name: @repo_name, owner_identity: identities(:tonny_google))

    @config_digest = DigestCalculator.compute(config_content)
    @layer_content = SecureRandom.random_bytes(1024)
    @layer_digest = DigestCalculator.compute(@layer_content)

    @manifest_payload = {
      schemaVersion: 2,
      mediaType: "application/vnd.docker.distribution.manifest.v2+json",
      config: { mediaType: "application/vnd.docker.container.image.v1+json", size: config_content.bytesize, digest: @config_digest },
      layers: [ { mediaType: "application/vnd.docker.image.rootfs.diff.tar.gzip", size: @layer_content.bytesize, digest: @layer_digest } ]
    }.to_json

    @blob_store.put(@config_digest, StringIO.new(config_content))
    @blob_store.put(@layer_digest, StringIO.new(@layer_content))
    Blob.create!(digest: @config_digest, size: config_content.bytesize)
    Blob.create!(digest: @layer_digest, size: @layer_content.bytesize)
  end

  teardown do
    FileUtils.rm_rf(@storage_dir)
  end

  test "PUT /v2/:name/manifests/:reference creates manifest and tag" do
    put "/v2/#{@repo_name}/manifests/v1.0.0",
        params: @manifest_payload,
        headers: { "CONTENT_TYPE" => "application/vnd.docker.distribution.manifest.v2+json" }.merge(basic_auth_for)

    assert_response 201
    assert_match(/\Asha256:/, response.headers["Docker-Content-Digest"])
  end

  test "PUT /v2/:name/manifests/:reference accepts OCI image manifest media type" do
    put "/v2/#{@repo_name}/manifests/v1.0.0",
        params: @manifest_payload,
        headers: { "CONTENT_TYPE" => "application/vnd.oci.image.manifest.v1+json" }.merge(basic_auth_for)

    assert_response 201
    assert_match(/\Asha256:/, response.headers["Docker-Content-Digest"])
    assert_equal "application/vnd.oci.image.manifest.v1+json", Manifest.last.media_type
  end

  test "GET /v2/:name/manifests/:reference returns OCI media type when stored as OCI and Accept matches" do
    put "/v2/#{@repo_name}/manifests/v1.0.0",
        params: @manifest_payload,
        headers: { "CONTENT_TYPE" => "application/vnd.oci.image.manifest.v1+json" }.merge(basic_auth_for)

    get "/v2/#{@repo_name}/manifests/v1.0.0",
        headers: { "HTTP_ACCEPT" => "application/vnd.oci.image.manifest.v1+json" }

    assert_response 200
    assert_equal "application/vnd.oci.image.manifest.v1+json", response.headers["Content-Type"]
  end

  test "GET /v2/:name/manifests/:reference returns Docker media type when stored as Docker and Accept matches" do
    put "/v2/#{@repo_name}/manifests/v1.0.0",
        params: @manifest_payload,
        headers: { "CONTENT_TYPE" => "application/vnd.docker.distribution.manifest.v2+json" }.merge(basic_auth_for)

    get "/v2/#{@repo_name}/manifests/v1.0.0",
        headers: { "HTTP_ACCEPT" => "application/vnd.docker.distribution.manifest.v2+json" }

    assert_response 200
    assert_equal "application/vnd.docker.distribution.manifest.v2+json", response.headers["Content-Type"]
  end

  test "GET /v2/:name/manifests/:reference returns 200 when Accept header is missing or */*" do
    put "/v2/#{@repo_name}/manifests/v1.0.0",
        params: @manifest_payload,
        headers: { "CONTENT_TYPE" => "application/vnd.oci.image.manifest.v1+json" }.merge(basic_auth_for)

    get "/v2/#{@repo_name}/manifests/v1.0.0", headers: { "HTTP_ACCEPT" => "*/*" }
    assert_response 200
    assert_equal "application/vnd.oci.image.manifest.v1+json", response.headers["Content-Type"]
  end

  test "GET /v2/:name/manifests/:reference returns 406 when Accept does not include the stored media type" do
    put "/v2/#{@repo_name}/manifests/v1.0.0",
        params: @manifest_payload,
        headers: { "CONTENT_TYPE" => "application/vnd.docker.distribution.manifest.v2+json" }.merge(basic_auth_for)

    get "/v2/#{@repo_name}/manifests/v1.0.0",
        headers: { "HTTP_ACCEPT" => "text/plain" }

    assert_response 406
  end

  test "PUT /v2/:name/manifests/:reference rejects unsupported media type" do
    put "/v2/#{@repo_name}/manifests/v1",
        params: "{}",
        headers: { "CONTENT_TYPE" => "application/vnd.docker.distribution.manifest.list.v2+json" }.merge(basic_auth_for)

    assert_response 415
    assert_equal "UNSUPPORTED", JSON.parse(response.body)["errors"][0]["code"]
  end

  test "GET /v2/:name/manifests/:reference returns manifest by tag" do
    put "/v2/#{@repo_name}/manifests/v1.0.0",
        params: @manifest_payload,
        headers: { "CONTENT_TYPE" => "application/vnd.docker.distribution.manifest.v2+json" }.merge(basic_auth_for)

    get "/v2/#{@repo_name}/manifests/v1.0.0"

    assert_response 200
    assert_match(/\Asha256:/, response.headers["Docker-Content-Digest"])
    assert_equal "application/vnd.docker.distribution.manifest.v2+json", response.headers["Content-Type"]
    assert_equal 2, JSON.parse(response.body)["schemaVersion"]
  end

  test "GET /v2/:name/manifests/:reference returns manifest by digest" do
    put "/v2/#{@repo_name}/manifests/v1.0.0",
        params: @manifest_payload,
        headers: { "CONTENT_TYPE" => "application/vnd.docker.distribution.manifest.v2+json" }.merge(basic_auth_for)
    digest = response.headers["Docker-Content-Digest"]

    get "/v2/#{@repo_name}/manifests/#{digest}"
    assert_response 200
  end

  test "GET /v2/:name/manifests/:reference increments pull_count on GET" do
    put "/v2/#{@repo_name}/manifests/v1.0.0",
        params: @manifest_payload,
        headers: { "CONTENT_TYPE" => "application/vnd.docker.distribution.manifest.v2+json" }.merge(basic_auth_for)

    get "/v2/#{@repo_name}/manifests/v1.0.0"
    assert_equal 1, Manifest.last.pull_count
  end

  test "GET /v2/:name/manifests/:reference creates a PullEvent on GET" do
    put "/v2/#{@repo_name}/manifests/v1.0.0",
        params: @manifest_payload,
        headers: { "CONTENT_TYPE" => "application/vnd.docker.distribution.manifest.v2+json" }.merge(basic_auth_for)

    get "/v2/#{@repo_name}/manifests/v1.0.0"
    assert_equal 1, PullEvent.count
    assert_equal "v1.0.0", PullEvent.last.tag_name
  end

  test "GET /v2/:name/manifests/:reference returns 404 for unknown tag" do
    get "/v2/#{@repo_name}/manifests/nonexistent"
    assert_response 404
  end

  test "HEAD /v2/:name/manifests/:reference returns headers without body" do
    put "/v2/#{@repo_name}/manifests/v1.0.0",
        params: @manifest_payload,
        headers: { "CONTENT_TYPE" => "application/vnd.docker.distribution.manifest.v2+json" }.merge(basic_auth_for)

    head "/v2/#{@repo_name}/manifests/v1.0.0"

    assert_response 200
    assert_match(/\Asha256:/, response.headers["Docker-Content-Digest"])
    assert_empty response.body
  end

  test "HEAD /v2/:name/manifests/:reference does NOT increment pull_count" do
    put "/v2/#{@repo_name}/manifests/v1.0.0",
        params: @manifest_payload,
        headers: { "CONTENT_TYPE" => "application/vnd.docker.distribution.manifest.v2+json" }.merge(basic_auth_for)

    head "/v2/#{@repo_name}/manifests/v1.0.0"
    assert_equal 0, Manifest.last.pull_count
  end

  test "DELETE /v2/:name/manifests/:digest deletes manifest and associated tags" do
    put "/v2/#{@repo_name}/manifests/v1.0.0",
        params: @manifest_payload,
        headers: { "CONTENT_TYPE" => "application/vnd.docker.distribution.manifest.v2+json" }.merge(basic_auth_for)

    digest = Manifest.last.digest
    repo = Repository.find_by!(name: @repo_name)
    delete "/v2/#{@repo_name}/manifests/#{digest}", headers: basic_auth_for

    assert_response 202
    assert_nil Manifest.find_by(digest: digest)
    assert_equal 0, repo.tags.count
  end

  # Tag protection tests — protected_repo and its tag set up inline in each test

  test "DELETE /v2/:name/manifests/:digest when connected tag is protected returns 409 Conflict with DENIED envelope" do
    repo = Repository.create!(name: "example", tag_protection_policy: "semver", owner_identity: identities(:tonny_google))
    manifest = repo.manifests.create!(digest: "sha256:#{"a" * 64}", media_type: "application/vnd.docker.distribution.manifest.v2+json", payload: "{}", size: 2)
    repo.tags.create!(name: "v1.0.0", manifest: manifest)

    delete "/v2/#{repo.name}/manifests/#{manifest.digest}", headers: basic_auth_for
    assert_response :conflict
    body = JSON.parse(response.body)
    assert_includes body["errors"].first["code"], "DENIED"
    assert_equal "v1.0.0", body["errors"].first["detail"]["tag"]
    assert_equal "semver", body["errors"].first["detail"]["policy"]
  end

  test "DELETE /v2/:name/manifests/:reference returns 409 even when called with tag reference" do
    repo = Repository.create!(name: "example", tag_protection_policy: "semver", owner_identity: identities(:tonny_google))
    manifest = repo.manifests.create!(digest: "sha256:#{"a" * 64}", media_type: "application/vnd.docker.distribution.manifest.v2+json", payload: "{}", size: 2)
    repo.tags.create!(name: "v1.0.0", manifest: manifest)

    delete "/v2/#{repo.name}/manifests/v1.0.0", headers: basic_auth_for
    assert_response :conflict
  end

  test "DELETE /v2/:name/manifests/:digest when connected tag is protected does NOT destroy the manifest" do
    repo = Repository.create!(name: "example", tag_protection_policy: "semver", owner_identity: identities(:tonny_google))
    manifest = repo.manifests.create!(digest: "sha256:#{"a" * 64}", media_type: "application/vnd.docker.distribution.manifest.v2+json", payload: "{}", size: 2)
    repo.tags.create!(name: "v1.0.0", manifest: manifest)

    delete "/v2/#{repo.name}/manifests/#{manifest.digest}", headers: basic_auth_for
    assert Manifest.find_by(id: manifest.id).present?
  end

  test "DELETE /v2/:name/manifests/:digest when no connected tag is protected returns 202 Accepted" do
    repo = Repository.create!(name: "open", owner_identity: identities(:tonny_google))
    manifest = repo.manifests.create!(
      digest: "sha256:#{"d" * 64}",
      media_type: "application/vnd.docker.distribution.manifest.v2+json",
      payload: "{}", size: 2
    )
    delete "/v2/#{repo.name}/manifests/#{manifest.digest}", headers: basic_auth_for
    assert_response :accepted
  end

  # --- Task 2.5: actor 실명화 (current_user.email) ---

  test "authenticated PUT records TagEvent.actor = current_user.email" do
    repo_name = "actor-realname-put-repo"
    Repository.create!(name: repo_name, owner_identity: identities(:tonny_google))
    headers = { "CONTENT_TYPE" => "application/vnd.docker.distribution.manifest.v2+json" }.merge(basic_auth_for)

    assert_difference -> { TagEvent.where(actor: "tonny@timberay.com").count }, +1 do
      put "/v2/#{repo_name}/manifests/v1", params: @manifest_payload, headers: headers
    end
    assert_response :created
  end

  test "authenticated DELETE records TagEvent.actor = current_user.email for each tag" do
    repo = Repository.create!(name: "actor-realname-delete-repo", owner_identity: identities(:tonny_google))
    manifest = repo.manifests.create!(
      digest: "sha256:#{SecureRandom.hex(32)}",
      media_type: "application/vnd.docker.distribution.manifest.v2+json",
      payload: "{}",
      size: 2
    )
    repo.tags.create!(name: "v1-realname", manifest: manifest)

    assert_difference -> { TagEvent.where(actor: "tonny@timberay.com", action: "delete").count }, +1 do
      delete "/v2/#{repo.name}/manifests/#{manifest.digest}", headers: basic_auth_for
    end
  end

  # ---------------------------------------------------------------------------
  # Stage 2: authorization
  # ---------------------------------------------------------------------------

  test "PUT /v2/:name/manifests/:ref by non-member returns 403" do
    # admin user is not owner/member of tonny's repo
    repo = Repository.create!(
      name: "authz-mfst-#{SecureRandom.hex(4)}",
      owner_identity: identities(:tonny_google)
    )
    put "/v2/#{repo.name}/manifests/v1",
        params: @manifest_payload,
        headers: { "CONTENT_TYPE" => "application/vnd.docker.distribution.manifest.v2+json" }
              .merge(basic_auth_for(pat_raw: ADMIN_CLI_RAW, email: "admin@timberay.com"))
    assert_response 403
    assert_equal "DENIED", JSON.parse(response.body)["errors"][0]["code"]
  end

  test "PUT /v2/:name/manifests/:ref by owner returns 201" do
    repo = Repository.create!(
      name: "authz-owner-push-#{SecureRandom.hex(4)}",
      owner_identity: identities(:tonny_google)
    )
    put "/v2/#{repo.name}/manifests/v1",
        params: @manifest_payload,
        headers: { "CONTENT_TYPE" => "application/vnd.docker.distribution.manifest.v2+json" }
              .merge(basic_auth_for)
    assert_response 201
  end

  test "DELETE /v2/:name/manifests/:ref by non-member returns 403" do
    repo = Repository.create!(
      name: "authz-del-#{SecureRandom.hex(4)}",
      owner_identity: identities(:tonny_google)
    )
    # seed a manifest
    put "/v2/#{repo.name}/manifests/v1",
        params: @manifest_payload,
        headers: { "CONTENT_TYPE" => "application/vnd.docker.distribution.manifest.v2+json" }
              .merge(basic_auth_for)
    digest = response.headers["Docker-Content-Digest"]

    delete "/v2/#{repo.name}/manifests/#{digest}",
           headers: basic_auth_for(pat_raw: ADMIN_CLI_RAW, email: "admin@timberay.com")
    assert_response 403
  end

  test "DELETE /v2/:name/manifests/:ref records actor_identity_id" do
    repo = Repository.create!(
      name: "authz-actid-#{SecureRandom.hex(4)}",
      owner_identity: identities(:tonny_google)
    )
    put "/v2/#{repo.name}/manifests/v1",
        params: @manifest_payload,
        headers: { "CONTENT_TYPE" => "application/vnd.docker.distribution.manifest.v2+json" }
              .merge(basic_auth_for)
    digest = response.headers["Docker-Content-Digest"]

    delete "/v2/#{repo.name}/manifests/#{digest}", headers: basic_auth_for
    assert_response 202

    event = TagEvent.order(:occurred_at).last
    assert_equal identities(:tonny_google).id, event.actor_identity_id
  end
end
