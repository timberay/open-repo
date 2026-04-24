require "test_helper"

class V2::BlobsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @storage_dir = Dir.mktmpdir
    Rails.configuration.storage_path = @storage_dir

    @blob_store = BlobStore.new(@storage_dir)
    @repo_name = "test-repo"
    @content = "blob content data"
    @digest = DigestCalculator.compute(@content)

    Repository.create!(name: @repo_name, owner_identity: identities(:tonny_google))
    Blob.create!(digest: @digest, size: @content.bytesize)
    @blob_store.put(@digest, StringIO.new(@content))
  end

  teardown do
    FileUtils.rm_rf(@storage_dir)
  end

  test "GET /v2/:name/blobs/:digest returns blob content" do
    get "/v2/#{@repo_name}/blobs/#{@digest}"
    assert_response 200
    assert_equal @digest, response.headers["Docker-Content-Digest"]
    assert_equal @content.bytesize.to_s, response.headers["Content-Length"]
  end

  test "GET /v2/:name/blobs/:digest returns 404 for unknown digest" do
    get "/v2/#{@repo_name}/blobs/sha256:nonexistent"
    assert_response 404
  end

  test "HEAD /v2/:name/blobs/:digest returns headers without body" do
    head "/v2/#{@repo_name}/blobs/#{@digest}"
    assert_response 200
    assert_equal @digest, response.headers["Docker-Content-Digest"]
    assert_empty response.body
  end

  test "DELETE /v2/:name/blobs/:digest deletes blob" do
    delete "/v2/#{@repo_name}/blobs/#{@digest}", headers: basic_auth_for
    assert_response 202
  end

  # ---------------------------------------------------------------------------
  # Stage 2: destroy authz
  # ---------------------------------------------------------------------------

  test "DELETE /v2/:name/blobs/:digest by non-owner returns 403" do
    owner_identity = identities(:tonny_google)
    repo = Repository.create!(
      name: "blob-del-authz-#{SecureRandom.hex(4)}",
      owner_identity: owner_identity
    )
    # Upload a blob first using tonny
    blob_content = "blob for authz test"
    digest = DigestCalculator.compute(blob_content)
    BlobStore.new(@storage_dir).put(digest, StringIO.new(blob_content))
    Blob.create!(digest: digest, size: blob_content.bytesize)

    delete "/v2/#{repo.name}/blobs/#{digest}",
           headers: basic_auth_for(pat_raw: ADMIN_CLI_RAW, email: "admin@timberay.com")
    assert_response 403
    assert_equal "DENIED", JSON.parse(response.body)["errors"][0]["code"]
  end

  test "DELETE /v2/:name/blobs/:digest by owner returns 202" do
    owner_identity = identities(:tonny_google)
    repo = Repository.create!(
      name: "blob-del-owner-#{SecureRandom.hex(4)}",
      owner_identity: owner_identity
    )
    blob_content = "owner blob"
    digest = DigestCalculator.compute(blob_content)
    BlobStore.new(@storage_dir).put(digest, StringIO.new(blob_content))
    Blob.create!(digest: digest, size: blob_content.bytesize)

    delete "/v2/#{repo.name}/blobs/#{digest}", headers: basic_auth_for
    assert_response 202
  end
end
