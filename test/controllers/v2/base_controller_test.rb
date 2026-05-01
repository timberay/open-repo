require "test_helper"

class V2::BaseControllerTest < ActionDispatch::IntegrationTest
  include TokenFixtures
  include ActiveSupport::Testing::TimeHelpers

  test "GET /v2/ returns 200 with empty JSON body" do
    Rails.configuration.x.registry.anonymous_pull_enabled = true
    get "/v2/"
    assert_response 200
    assert_equal({}, JSON.parse(response.body))
  end

  test "GET /v2/ includes Docker-Distribution-API-Version header" do
    Rails.configuration.x.registry.anonymous_pull_enabled = true
    get "/v2/"
    assert_equal "registry/2.0", response.headers["Docker-Distribution-API-Version"]
  end

  # TagProtected error handling — tested via a real endpoint that raises it.
  # The RSpec suite used an anonymous controller; here we use the manifests
  # destroy action, which goes through V2::BaseController's rescue_from clause.
  setup do
    @repo = Repository.create!(name: "example", tag_protection_policy: "semver", owner_identity: identities(:tonny_google))
    @manifest = @repo.manifests.create!(
      digest: "sha256:#{"a" * 64}",
      media_type: "application/vnd.docker.distribution.manifest.v2+json",
      payload: "{}", size: 2
    )
    @repo.tags.create!(name: "v1.0.0", manifest: @manifest)

    # B-38: most of the auth-gate assertions below require the anonymous-pull
    # gate to be CLOSED so unauthenticated GETs receive 401 instead of being
    # waved through. Save the prior value to restore in teardown.
    @prev_anon = Rails.configuration.x.registry.anonymous_pull_enabled
    Rails.configuration.x.registry.anonymous_pull_enabled = false
  end

  teardown do
    Rails.configuration.x.registry.anonymous_pull_enabled = @prev_anon
  end

  test "TagProtected raises returns 409 Conflict" do
    delete "/v2/#{@repo.name}/manifests/#{@manifest.digest}", headers: basic_auth_for
    assert_response :conflict
  end

  test "TagProtected renders Docker Registry error envelope with DENIED code" do
    delete "/v2/#{@repo.name}/manifests/#{@manifest.digest}", headers: basic_auth_for
    body = JSON.parse(response.body)
    assert_includes body["errors"].first["code"], "DENIED"
    assert_includes body["errors"].first["message"], "v1.0.0"
    assert_includes body["errors"].first["message"], "semver"
    assert_equal "v1.0.0", body["errors"].first["detail"]["tag"]
    assert_equal "semver", body["errors"].first["detail"]["policy"]
  end

  test "TagProtected includes Docker-Distribution-API-Version header on 409" do
    delete "/v2/#{@repo.name}/manifests/#{@manifest.digest}", headers: basic_auth_for
    assert_equal "registry/2.0", response.headers["Docker-Distribution-API-Version"]
  end

  # --- Challenge on protected endpoints ---

  test "POST /v2/<name>/blobs/uploads without Authorization → 401 + Basic challenge" do
    post "/v2/myimage/blobs/uploads"
    assert_response :unauthorized
    assert_equal %(Basic realm="Registry"), response.headers["WWW-Authenticate"]
    assert_equal "registry/2.0", response.headers["Docker-Distribution-API-Version"]
  end

  test "PUT /v2/<name>/manifests/<ref> with malformed Authorization → 401 + challenge" do
    put "/v2/myimage/manifests/v1",
        headers: { "Authorization" => "Basic not-base64!" }
    assert_response :unauthorized
    assert_match %r{\ABasic realm=}, response.headers["WWW-Authenticate"]
  end

  # E-20: Bearer scheme is not honored on Basic-only V2 endpoints. The auth
  # gate uses `HttpAuthentication::Basic.user_name_and_password`, which silently
  # ignores non-Basic schemes — so a Bearer header looks like "no credentials"
  # and we must respond with the same exact challenge as anonymous, including
  # the canonical Docker error envelope (UNAUTHORIZED).
  test "POST /v2/<name>/blobs/uploads with Bearer scheme → 401 + Basic realm challenge + UNAUTHORIZED envelope" do
    post "/v2/myimage/blobs/uploads",
         headers: { "Authorization" => "Bearer oprk_validlookingvalue" }

    assert_response :unauthorized
    assert_equal %(Basic realm="Registry"), response.headers["WWW-Authenticate"]
    assert_equal "registry/2.0", response.headers["Docker-Distribution-API-Version"]

    body = JSON.parse(response.body)
    assert_equal "UNAUTHORIZED", body.dig("errors", 0, "code")
  end

  # --- Basic auth success ---

  test "with valid PAT Basic auth → current_user set and request proceeds" do
    headers = {
      "Authorization" => ActionController::HttpAuthentication::Basic.encode_credentials(
        "tonny@timberay.com", TONNY_CLI_RAW)
    }
    post "/v2/myimage/blobs/uploads", headers: headers
    # blob upload actual logic: not 401 is enough (we're only testing the auth gate here)
    assert_not_equal 401, response.status
  end

  test "updates pat.last_used_at on successful auth" do
    pat = personal_access_tokens(:tonny_cli_active)
    headers = {
      "Authorization" => ActionController::HttpAuthentication::Basic.encode_credentials(
        "tonny@timberay.com", TONNY_CLI_RAW)
    }
    freeze_time do
      post "/v2/myimage/blobs/uploads", headers: headers
      assert_in_delta Time.current, pat.reload.last_used_at, 2.seconds
    end
  end

  # --- PAT errors ---

  test "with revoked PAT → 401" do
    headers = {
      "Authorization" => ActionController::HttpAuthentication::Basic.encode_credentials(
        "tonny@timberay.com", TONNY_REVOKED_RAW)
    }
    post "/v2/myimage/blobs/uploads", headers: headers
    assert_response :unauthorized
  end

  test "with mismatched email → 401" do
    headers = {
      "Authorization" => ActionController::HttpAuthentication::Basic.encode_credentials(
        "admin@timberay.com", TONNY_CLI_RAW)
    }
    post "/v2/myimage/blobs/uploads", headers: headers
    assert_response :unauthorized
  end

  # --- Anonymous pull gate (D5 / tech design §7.3) ---

  test "GET /v2/ without Authorization → 200 (anonymous discovery)" do
    Rails.configuration.x.registry.anonymous_pull_enabled = true
    get "/v2/"
    assert_response :ok
  end

  test "GET /v2/ with anonymous_pull_enabled=false → 401" do
    Rails.configuration.x.registry.anonymous_pull_enabled = false
    get "/v2/"
    assert_response :unauthorized
    assert_match %r{\ABasic realm=}, response.headers["WWW-Authenticate"]
  end

  test "Auth::ForbiddenAction renders 403 JSON with DENIED code" do
    # 직접 raise 를 시뮬레이션 — 아직 실제 before_action 없으나 rescue_from 동작 확인
    repo = Repository.create!(
      name: "v2-base-forbidden-#{SecureRandom.hex(4)}",
      owner_identity: identities(:tonny_google)
    )
    # anonymous (no auth) → 401 은 이미 있음. 403 은 별도 케이스
    # 이 테스트는 concern + rescue_from 이 연결되면 통과
    skip "rescue_from wired in this task — tested via ManifestsController in Task 2.2"
  end

  # B-38: docker CLI surfaces the body of 401 responses to the user. Point
  # them at /help and /settings/tokens so they can recover without rummaging
  # through server logs.
  test "401 response body includes a /help URL pointer" do
    get "/v2/some-repo/manifests/latest"
    assert_response :unauthorized
    body = JSON.parse(response.body)
    detail = body["errors"].first["detail"]
    assert_kind_of Hash, detail
    assert_match %r{/help}, detail["help_url"]
    assert_match %r{/help}, body["errors"].first["message"]
    assert_match %r{/settings/tokens}, body["errors"].first["message"]
  end
end
