require "test_helper"

class V2::TagsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @repo = Repository.create!(name: "test-repo", owner_identity: identities(:tonny_google))
    @manifest = Manifest.create!(repository: @repo, digest: "sha256:abc", media_type: "application/vnd.docker.distribution.manifest.v2+json", payload: "{}", size: 100)
    %w[v1.0.0 v2.0.0 latest].each { |t| Tag.create!(repository: @repo, manifest: @manifest, name: t) }
  end

  test "GET /v2/:name/tags/list returns all tags" do
    get "/v2/#{@repo.name}/tags/list"
    body = JSON.parse(response.body)
    assert_equal "test-repo", body["name"]
    assert_equal %w[latest v1.0.0 v2.0.0], body["tags"]
  end

  test "GET /v2/:name/tags/list paginates with n and last" do
    get "/v2/#{@repo.name}/tags/list?n=2"
    body = JSON.parse(response.body)
    assert_equal 2, body["tags"].length
    assert_includes response.headers["Link"], "rel=\"next\""
  end

  test "GET /v2/:name/tags/list returns 404 for unknown repo" do
    get "/v2/nonexistent/tags/list"
    assert_response 404
  end
end
