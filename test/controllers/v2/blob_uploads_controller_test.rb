require "test_helper"

class V2::BlobUploadsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @storage_dir = Dir.mktmpdir
    Rails.configuration.storage_path = @storage_dir
    @repo_name = "test-repo"
  end

  teardown do
    FileUtils.rm_rf(@storage_dir)
  end

  test "POST /v2/:name/blobs/uploads returns 202 with Location and upload UUID" do
    post "/v2/#{@repo_name}/blobs/uploads", headers: basic_auth_for

    assert_response 202
    assert_match %r{/v2/#{@repo_name}/blobs/uploads/.+}, response.headers["Location"]
    assert response.headers["Docker-Upload-UUID"].present?
    assert_equal "0-0", response.headers["Range"]
  end

  test "POST /v2/:name/blobs/uploads creates repository if not exists" do
    post "/v2/#{@repo_name}/blobs/uploads", headers: basic_auth_for
    assert Repository.find_by(name: @repo_name).present?
  end

  test "POST /v2/:name/blobs/uploads?digest= stores blob in single request" do
    content = "monolithic blob data"
    digest = DigestCalculator.compute(content)

    post "/v2/#{@repo_name}/blobs/uploads?digest=#{digest}",
         params: content,
         headers: { "CONTENT_TYPE" => "application/octet-stream" }.merge(basic_auth_for)

    assert_response 201
    assert_equal digest, response.headers["Docker-Content-Digest"]
  end

  test "PATCH /v2/:name/blobs/uploads/:uuid appends data and returns updated range" do
    post "/v2/#{@repo_name}/blobs/uploads", headers: basic_auth_for
    uuid = response.headers["Docker-Upload-UUID"]

    patch "/v2/#{@repo_name}/blobs/uploads/#{uuid}",
          params: "chunk data",
          headers: { "CONTENT_TYPE" => "application/octet-stream" }.merge(basic_auth_for)

    assert_response 202
    assert_equal "0-9", response.headers["Range"]
    assert_equal uuid, response.headers["Docker-Upload-UUID"]
  end

  test "PUT /v2/:name/blobs/uploads/:uuid?digest= finalizes upload and creates blob record" do
    content = "final blob content"
    digest = DigestCalculator.compute(content)

    post "/v2/#{@repo_name}/blobs/uploads", headers: basic_auth_for
    uuid = response.headers["Docker-Upload-UUID"]

    patch "/v2/#{@repo_name}/blobs/uploads/#{uuid}",
          params: content,
          headers: { "CONTENT_TYPE" => "application/octet-stream" }.merge(basic_auth_for)

    put "/v2/#{@repo_name}/blobs/uploads/#{uuid}?digest=#{digest}", headers: basic_auth_for

    assert_response 201
    assert_equal digest, response.headers["Docker-Content-Digest"]
    assert Blob.find_by(digest: digest).present?
  end

  test "PUT /v2/:name/blobs/uploads/:uuid?digest= rejects wrong digest" do
    post "/v2/#{@repo_name}/blobs/uploads", headers: basic_auth_for
    uuid = response.headers["Docker-Upload-UUID"]

    patch "/v2/#{@repo_name}/blobs/uploads/#{uuid}",
          params: "some data",
          headers: { "CONTENT_TYPE" => "application/octet-stream" }.merge(basic_auth_for)

    put "/v2/#{@repo_name}/blobs/uploads/#{uuid}?digest=sha256:wrong", headers: basic_auth_for

    assert_response 400
    assert_equal "DIGEST_INVALID", JSON.parse(response.body)["errors"][0]["code"]
  end

  test "POST /v2/:name/blobs/uploads?mount=&from= mounts existing blob from another repo" do
    content = "shared layer"
    digest = DigestCalculator.compute(content)
    source = Repository.create!(name: "source-repo", owner_identity: identities(:tonny_google))
    blob = Blob.create!(digest: digest, size: content.bytesize, references_count: 1)
    # The source repo must actually reference the blob (manifest -> layer -> blob).
    manifest = source.manifests.create!(
      digest: "sha256:src-#{SecureRandom.hex(8)}",
      media_type: "application/vnd.docker.distribution.manifest.v2+json",
      payload: "{}", size: 2
    )
    Layer.create!(manifest: manifest, blob: blob, position: 0)
    BlobStore.new(@storage_dir).put(digest, StringIO.new(content))

    post "/v2/#{@repo_name}/blobs/uploads?mount=#{digest}&from=source-repo", headers: basic_auth_for

    assert_response 201
    assert_equal digest, response.headers["Docker-Content-Digest"]
    # Mount does NOT bump references_count; the manifest PUT that references the
    # blob is what counts it (avoids double-count / abandoned-mount leak).
    assert_equal 1, blob.reload.references_count
  end

  test "POST mount falls back to 202 when the from-repo does not reference the digest" do
    content = "unowned layer"
    digest = DigestCalculator.compute(content)
    # source-repo exists but has no manifest/layer referencing the blob.
    Repository.create!(name: "source-repo", owner_identity: identities(:tonny_google))
    blob = Blob.create!(digest: digest, size: content.bytesize, references_count: 0)
    BlobStore.new(@storage_dir).put(digest, StringIO.new(content))

    post "/v2/#{@repo_name}/blobs/uploads?mount=#{digest}&from=source-repo", headers: basic_auth_for

    assert_response 202
    assert response.headers["Docker-Upload-UUID"].present?
    assert_equal 0, blob.reload.references_count, "ref count must not move on a failed mount"
  end

  test "POST mount falls back to 202 when the from-repo does not exist" do
    content = "no source layer"
    digest = DigestCalculator.compute(content)
    blob = Blob.create!(digest: digest, size: content.bytesize, references_count: 0)
    BlobStore.new(@storage_dir).put(digest, StringIO.new(content))

    post "/v2/#{@repo_name}/blobs/uploads?mount=#{digest}&from=ghost-repo", headers: basic_auth_for

    assert_response 202
    assert_equal 0, blob.reload.references_count
  end

  test "POST /v2/:name/blobs/uploads?mount=&from= falls back to regular upload if blob not found" do
    post "/v2/#{@repo_name}/blobs/uploads?mount=sha256:nonexistent&from=other-repo", headers: basic_auth_for

    assert_response 202
    assert response.headers["Docker-Upload-UUID"].present?
  end

  test "GET /v2/:name/blobs/uploads/:uuid returns 204 with current Range and Docker-Upload-UUID" do
    post "/v2/#{@repo_name}/blobs/uploads", headers: basic_auth_for
    uuid = response.headers["Docker-Upload-UUID"]

    patch "/v2/#{@repo_name}/blobs/uploads/#{uuid}",
          params: "chunk data", # 10 bytes
          headers: { "CONTENT_TYPE" => "application/octet-stream" }.merge(basic_auth_for)

    get "/v2/#{@repo_name}/blobs/uploads/#{uuid}", headers: basic_auth_for

    assert_response 204
    assert_equal "0-9", response.headers["Range"]
    assert_equal uuid, response.headers["Docker-Upload-UUID"]
  end

  test "GET /v2/:name/blobs/uploads/:uuid returns 0-0 for upload with no bytes received" do
    post "/v2/#{@repo_name}/blobs/uploads", headers: basic_auth_for
    uuid = response.headers["Docker-Upload-UUID"]

    get "/v2/#{@repo_name}/blobs/uploads/#{uuid}", headers: basic_auth_for

    assert_response 204
    assert_equal "0-0", response.headers["Range"]
    assert_equal uuid, response.headers["Docker-Upload-UUID"]
  end

  test "GET /v2/:name/blobs/uploads/:uuid returns 404 BLOB_UPLOAD_UNKNOWN for missing upload" do
    Repository.create!(name: @repo_name, owner_identity: identities(:tonny_google))
    get "/v2/#{@repo_name}/blobs/uploads/does-not-exist", headers: basic_auth_for
    assert_response 404
    assert_equal "BLOB_UPLOAD_UNKNOWN", JSON.parse(response.body)["errors"][0]["code"]
  end

  test "DELETE /v2/:name/blobs/uploads/:uuid cancels upload" do
    post "/v2/#{@repo_name}/blobs/uploads", headers: basic_auth_for
    uuid = response.headers["Docker-Upload-UUID"]

    delete "/v2/#{@repo_name}/blobs/uploads/#{uuid}", headers: basic_auth_for
    assert_response 204
    assert_nil BlobUpload.find_by(uuid: uuid)
  end

  # ---------------------------------------------------------------------------
  # Stage 2: first-pusher-owner + write authz
  # ---------------------------------------------------------------------------

  test "POST /v2/:name/blobs/uploads creates repo with current_user as owner" do
    repo_name = "fp-owner-#{SecureRandom.hex(4)}"
    refute Repository.exists?(name: repo_name)

    post "/v2/#{repo_name}/blobs/uploads", headers: basic_auth_for
    assert_response 202

    repo = Repository.find_by!(name: repo_name)
    assert_equal identities(:tonny_google).id, repo.owner_identity_id
  end

  test "POST /v2/:name/blobs/uploads by non-member of existing repo returns 403" do
    owner_identity = identities(:tonny_google)
    repo = Repository.create!(
      name: "fp-nonmember-#{SecureRandom.hex(4)}",
      owner_identity: owner_identity
    )

    post "/v2/#{repo.name}/blobs/uploads",
         headers: basic_auth_for(pat_raw: ADMIN_CLI_RAW, email: "admin@timberay.com")
    assert_response 403
    assert_equal "DENIED", JSON.parse(response.body)["errors"][0]["code"]
  end

  test "POST /v2/:name/blobs/uploads by writer member of existing repo returns 202" do
    owner_identity = identities(:tonny_google)
    repo = Repository.create!(
      name: "fp-writer-#{SecureRandom.hex(4)}",
      owner_identity: owner_identity
    )
    RepositoryMember.create!(
      repository: repo,
      identity: identities(:admin_google),
      role: "writer"
    )

    post "/v2/#{repo.name}/blobs/uploads",
         headers: basic_auth_for(pat_raw: ADMIN_CLI_RAW, email: "admin@timberay.com")
    assert_response 202
  end

  # ---------------------------------------------------------------------------
  # P1: upload UUIDs must be repo-scoped, and chunk/finalize/cancel must be
  # write-authorized (parity with `create`).
  # ---------------------------------------------------------------------------

  test "an upload UUID cannot be driven under a different repository path" do
    # Upload session is created under repo-a (owned by tonny).
    post "/v2/repo-a/blobs/uploads", headers: basic_auth_for
    uuid = response.headers["Docker-Upload-UUID"]

    # repo-b exists and is also owned by tonny (so write authz passes), but the
    # upload does not belong to it: the lookup must be scoped per-repository.
    Repository.create!(name: "repo-b", owner_identity: identities(:tonny_google))

    patch "/v2/repo-b/blobs/uploads/#{uuid}",
          params: "x",
          headers: { "CONTENT_TYPE" => "application/octet-stream" }.merge(basic_auth_for)
    assert_response 404
    assert_equal "BLOB_UPLOAD_UNKNOWN", JSON.parse(response.body)["errors"][0]["code"]

    delete "/v2/repo-b/blobs/uploads/#{uuid}", headers: basic_auth_for
    assert_response 404
    assert_equal "BLOB_UPLOAD_UNKNOWN", JSON.parse(response.body)["errors"][0]["code"]
  end

  test "PATCH/PUT/DELETE on an upload by a non-writer returns 403" do
    owner_identity = identities(:tonny_google)
    repo = Repository.create!(
      name: "authz-upload-#{SecureRandom.hex(4)}",
      owner_identity: owner_identity
    )
    upload = repo.blob_uploads.create!(uuid: SecureRandom.uuid)
    BlobStore.new(@storage_dir).create_upload(upload.uuid)

    non_member = basic_auth_for(pat_raw: ADMIN_CLI_RAW, email: "admin@timberay.com")

    patch "/v2/#{repo.name}/blobs/uploads/#{upload.uuid}",
          params: "x",
          headers: { "CONTENT_TYPE" => "application/octet-stream" }.merge(non_member)
    assert_response 403

    put "/v2/#{repo.name}/blobs/uploads/#{upload.uuid}?digest=sha256:#{'a' * 64}",
        headers: non_member
    assert_response 403

    delete "/v2/#{repo.name}/blobs/uploads/#{upload.uuid}", headers: non_member
    assert_response 403
  end

  test "create still authorizes write after a find_or_create race (RecordNotUnique)" do
    repo = Repository.create!(
      name: "race-repo-#{SecureRandom.hex(4)}",
      owner_identity: identities(:tonny_google)
    )

    # Simulate losing the create race: find_or_create_by! raises RecordNotUnique
    # even though the repo already exists and is owned by someone else.
    Repository.define_singleton_method(:find_or_create_by!) do |*, &_blk|
      raise ActiveRecord::RecordNotUnique, "race"
    end
    begin
      post "/v2/#{repo.name}/blobs/uploads",
           headers: basic_auth_for(pat_raw: ADMIN_CLI_RAW, email: "admin@timberay.com")
    ensure
      Repository.singleton_class.send(:remove_method, :find_or_create_by!)
    end

    assert_response 403
    assert_equal "DENIED", JSON.parse(response.body)["errors"][0]["code"]
  end
end
