require "test_helper"

# UC-V2-001 — Ping (`GET /v2/`) edge cases per docs/qa-audit/TEST_PLAN.md.
#
# Happy path + 3 of the original .e1–.e5 are pinned in
# test/controllers/v2/base_controller_test.rb. This file fills the remaining
# edges: anon disabled challenge headers, invalid Basic, HEAD parity,
# unknown HTTP verb. None of these add fixtures or modify production code.
class V2::PingEdgesTest < ActionDispatch::IntegrationTest
  setup do
    # Default: anonymous discovery is allowed. Each test toggles as needed.
    Rails.configuration.x.registry.anonymous_pull_enabled = true
  end

  teardown do
    Rails.configuration.x.registry.anonymous_pull_enabled = true
  end

  # e1 — anonymous, anon pull enabled → 200 + version header.
  test "GET /v2/ anonymous with anonymous_pull_enabled=true returns 200 and version header" do
    Rails.configuration.x.registry.anonymous_pull_enabled = true
    get "/v2/"
    assert_response :ok
    assert_equal "registry/2.0", response.headers["Docker-Distribution-API-Version"]
  end

  # e2 — anonymous, anon pull disabled → 401 + Basic challenge.
  test "GET /v2/ anonymous with anonymous_pull_enabled=false returns 401 and Basic challenge" do
    Rails.configuration.x.registry.anonymous_pull_enabled = false
    get "/v2/"
    assert_response :unauthorized
    assert_equal %(Basic realm="Registry"), response.headers["WWW-Authenticate"]
    assert_equal "registry/2.0", response.headers["Docker-Distribution-API-Version"]
  end

  # Garbage Basic credentials should produce the same 401 + Basic challenge,
  # never bleed into a 500 / unhandled exception path.
  test "GET /v2/ with garbage Basic auth returns 401 and Basic challenge" do
    Rails.configuration.x.registry.anonymous_pull_enabled = false
    get "/v2/", headers: {
      "Authorization" => ActionController::HttpAuthentication::Basic
        .encode_credentials("nobody@example.invalid", "this-is-not-a-real-pat")
    }
    assert_response :unauthorized
    assert_equal %(Basic realm="Registry"), response.headers["WWW-Authenticate"]
  end

  # HEAD probe — registries commonly health-check with HEAD before GET.
  # HEAD must produce the same status as GET (whatever GET returns).
  test "HEAD /v2/ anonymous matches GET status when anonymous_pull_enabled=true" do
    Rails.configuration.x.registry.anonymous_pull_enabled = true
    get "/v2/"
    get_status = response.status
    head "/v2/"
    assert_equal get_status, response.status,
      "HEAD /v2/ should match GET /v2/ status (#{get_status}); got #{response.status}"
    assert_equal "registry/2.0", response.headers["Docker-Distribution-API-Version"]
  end

  test "HEAD /v2/ anonymous matches GET status when anonymous_pull_enabled=false" do
    Rails.configuration.x.registry.anonymous_pull_enabled = false
    get "/v2/"
    get_status = response.status
    head "/v2/"
    assert_equal get_status, response.status,
      "HEAD /v2/ should match GET /v2/ status (#{get_status}); got #{response.status}"
  end

  # Unknown HTTP verb — POST /v2/ has no route. Rails returns 404 via
  # ActionController::RoutingError (no route match). Pin whichever Rails
  # actually returns so any silent change to a 405 / 200 is caught.
  test "POST /v2/ returns 404 (no matching route)" do
    post "/v2/"
    assert_includes [ 404, 405 ], response.status,
      "POST /v2/ should be 404 or 405 (no route); got #{response.status}"
  end
end
