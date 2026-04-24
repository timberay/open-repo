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
    Repository.create!(name: "source-repo", owner_identity: identities(:tonny_google))
    Blob.create!(digest: digest, size: content.bytesize)
    BlobStore.new(@storage_dir).put(digest, StringIO.new(content))

    post "/v2/#{@repo_name}/blobs/uploads?mount=#{digest}&from=source-repo", headers: basic_auth_for

    assert_response 201
    assert_equal digest, response.headers["Docker-Content-Digest"]
  end

  test "POST /v2/:name/blobs/uploads?mount=&from= falls back to regular upload if blob not found" do
    post "/v2/#{@repo_name}/blobs/uploads?mount=sha256:nonexistent&from=other-repo", headers: basic_auth_for

    assert_response 202
    assert response.headers["Docker-Upload-UUID"].present?
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
end
