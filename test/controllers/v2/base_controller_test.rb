require "test_helper"

class V2::BaseControllerTest < ActionDispatch::IntegrationTest
  test "GET /v2/ returns 200 with empty JSON body" do
    get "/v2/"
    assert_response 200
    assert_equal({}, JSON.parse(response.body))
  end

  test "GET /v2/ includes Docker-Distribution-API-Version header" do
    get "/v2/"
    assert_equal "registry/2.0", response.headers["Docker-Distribution-API-Version"]
  end

  # TagProtected error handling — tested via a real endpoint that raises it.
  # The RSpec suite used an anonymous controller; here we use the manifests
  # destroy action, which goes through V2::BaseController's rescue_from clause.
  setup do
    @repo = Repository.create!(name: "example", tag_protection_policy: "semver")
    @manifest = @repo.manifests.create!(
      digest: "sha256:abc",
      media_type: "application/vnd.docker.distribution.manifest.v2+json",
      payload: "{}", size: 2
    )
    @repo.tags.create!(name: "v1.0.0", manifest: @manifest)
  end

  test "TagProtected raises returns 409 Conflict" do
    delete "/v2/#{@repo.name}/manifests/#{@manifest.digest}"
    assert_response :conflict
  end

  test "TagProtected renders Docker Registry error envelope with DENIED code" do
    delete "/v2/#{@repo.name}/manifests/#{@manifest.digest}"
    body = JSON.parse(response.body)
    assert_includes body["errors"].first["code"], "DENIED"
    assert_includes body["errors"].first["message"], "v1.0.0"
    assert_includes body["errors"].first["message"], "semver"
    assert_equal "v1.0.0", body["errors"].first["detail"]["tag"]
    assert_equal "semver", body["errors"].first["detail"]["policy"]
  end

  test "TagProtected includes Docker-Distribution-API-Version header on 409" do
    delete "/v2/#{@repo.name}/manifests/#{@manifest.digest}"
    assert_equal "registry/2.0", response.headers["Docker-Distribution-API-Version"]
  end
end
