require "test_helper"

# Regression lock-in: Critical Gap #3 (Stage 1 PR-2).
# Codifies already-implemented behavior from the Task 2.4 auth gate so future
# changes cannot silently re-open write paths or break anonymous pull.
#
# Scenario coverage vs. tech design §7.3:
#   1. GET /v2/ discovery                          — covered
#   2. GET /v2/_catalog                            — covered
#   3. GET /v2/:name/tags/list                     — covered
#   4. GET /v2/:name/manifests/:ref (tag)          — covered
#   5. HEAD /v2/:name/manifests/:ref (digest)      — covered
#   6. GET /v2/:name/blobs/:digest                 — SKIPPED (see note below)
#   7. PUT /v2/:name/manifests/:ref                — covered
#   8. POST /v2/:name/blobs/uploads                — covered
#   9. DELETE /v2/:name/manifests/:ref             — covered
#  10. anonymous_pull_enabled=false gates pull     — covered
#  11. PullEvent remote_ip attribution             — covered (column verified)
#
# Scenario 6 is intentionally skipped: V2::BlobsController#show requires a real
# blob on disk (BlobStore#exists? is a filesystem check), Minitest 6.0.4 has no
# stub_any_instance, and the auth gate path for blobs/show is identical to
# manifests/show (same ANONYMOUS_PULL_ENDPOINTS entry). Skipping avoids cross-
# test filesystem side effects without sacrificing auth-gate coverage.
class AnonymousPullRegressionTest < ActionDispatch::IntegrationTest
  setup do
    Rails.configuration.x.registry.anonymous_pull_enabled = true
    @repo = Repository.create!(name: "anon-pull-regression-repo-#{SecureRandom.hex(4)}", owner_identity: identities(:tonny_google))
    @manifest = @repo.manifests.create!(
      digest: "sha256:#{SecureRandom.hex(32)}",
      media_type: "application/vnd.docker.distribution.manifest.v2+json",
      payload: "{}",
      size: 2
    )
    @tag = @repo.tags.create!(name: "anon-v1", manifest: @manifest)
  end

  # --- Anonymous pull: whitelisted GET/HEAD → 200 ---

  test "GET /v2/ (discovery) 200 without token" do
    get "/v2/"
    assert_response :ok
  end

  test "GET /v2/_catalog 200 without token" do
    get "/v2/_catalog"
    assert_response :ok
  end

  test "GET /v2/:name/tags/list 200 without token" do
    get "/v2/#{@repo.name}/tags/list"
    assert_response :ok
  end

  test "GET /v2/:name/manifests/:ref 200 without token (tag ref)" do
    get "/v2/#{@repo.name}/manifests/#{@tag.name}"
    assert_response :ok
    assert_equal @manifest.digest, response.headers["Docker-Content-Digest"]
  end

  test "HEAD /v2/:name/manifests/:ref 200 without token (digest ref)" do
    head "/v2/#{@repo.name}/manifests/#{@manifest.digest}"
    assert_response :ok
  end

  # --- Write paths require auth (401 + Basic challenge) ---

  test "PUT /v2/:name/manifests/:ref without token 401 + Basic challenge" do
    put "/v2/#{@repo.name}/manifests/newtag",
        params: "{}",
        headers: { "CONTENT_TYPE" => "application/vnd.docker.distribution.manifest.v2+json" }
    assert_response :unauthorized
    assert_match %r{\ABasic realm="[^"]+"}, response.headers["WWW-Authenticate"]
  end

  test "POST /v2/:name/blobs/uploads without token 401 + Basic challenge" do
    post "/v2/#{@repo.name}/blobs/uploads"
    assert_response :unauthorized
    assert_match %r{\ABasic realm="[^"]+"}, response.headers["WWW-Authenticate"]
  end

  test "DELETE /v2/:name/manifests/:ref without token 401" do
    delete "/v2/#{@repo.name}/manifests/#{@manifest.digest}"
    assert_response :unauthorized
    assert_match %r{\ABasic realm="[^"]+"}, response.headers["WWW-Authenticate"]
  end

  # --- Flag gating ---

  test "when anonymous_pull_enabled=false, GET manifests requires token" do
    Rails.configuration.x.registry.anonymous_pull_enabled = false
    get "/v2/#{@repo.name}/manifests/#{@tag.name}"
    assert_response :unauthorized
    assert_match %r{\ABasic realm="[^"]+"}, response.headers["WWW-Authenticate"]
  end

  # --- Pull event attribution (remote_ip column confirmed in schema) ---

  test "anonymous GET manifest records PullEvent with remote_ip" do
    assert_difference -> { PullEvent.count }, +1 do
      get "/v2/#{@repo.name}/manifests/#{@tag.name}",
          env: { "REMOTE_ADDR" => "10.0.0.42" }
    end
    event = PullEvent.order(:occurred_at).last
    assert_equal "10.0.0.42", event.remote_ip
  end
end
