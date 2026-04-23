require "test_helper"

class V2::BlobsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @storage_dir = Dir.mktmpdir
    Rails.configuration.storage_path = @storage_dir

    @blob_store = BlobStore.new(@storage_dir)
    @repo_name = "test-repo"
    @content = "blob content data"
    @digest = DigestCalculator.compute(@content)

    Repository.create!(name: @repo_name)
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
    delete "/v2/#{@repo_name}/blobs/#{@digest}"
    assert_response 202
  end
end
