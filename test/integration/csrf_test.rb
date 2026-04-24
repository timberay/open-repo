require "test_helper"

# UC-AUTH-013 — CSRF protection integration coverage.
#
# Scope (test plan §499):
#   (a) Web UI state-changing request without a valid CSRF token is rejected.
#   (b) Same request WITH a valid token succeeds.
#   (c) V2 API mutating endpoints DO NOT require a CSRF token
#       (Docker clients don't send one — failure must come from auth, not CSRF).
#   (d) OAuth callback (GET) is not subject to CSRF (GET is exempt; pin expected behavior).
#
# Test env normally disables forgery protection
# (`config.action_controller.allow_forgery_protection = false` in config/environments/test.rb).
# Each test here flips the flag ON within a begin/ensure block so the assertions
# reflect production behavior without leaking state into other tests.
class CsrfTest < ActionDispatch::IntegrationTest
  # Route picked for case (a)/(b): `POST /settings/tokens` (settings_tokens_path).
  # Chosen because it is a real, non-trivial state-changing form a signed-in
  # user submits (PAT creation) and already exists with a straightforward
  # redirect-on-success contract.

  def with_forgery_protection
    original = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    yield
  ensure
    ActionController::Base.allow_forgery_protection = original
  end

  # (a) Web UI POST without a valid CSRF token is rejected.
  # ApplicationController inherits ActionController::Base and uses the default
  # `:exception` forgery-protection strategy, so a missing/invalid token raises
  # ActionController::InvalidAuthenticityToken. With `show_exceptions = :rescuable`
  # in the test env, the middleware renders it as 422 Unprocessable Content.
  test "(a) POST /settings/tokens without CSRF token is rejected (422)" do
    post "/testing/sign_in", params: { user_id: users(:tonny).id }

    with_forgery_protection do
      assert_no_difference -> { PersonalAccessToken.count } do
        post settings_tokens_path, params: {
          personal_access_token: { name: "no-csrf", kind: "cli", expires_in_days: "30" }
        }
      end
      assert_response :unprocessable_content
    end
  end

  # (b) Web UI POST WITH a valid CSRF token succeeds.
  # The authenticity_token is pulled from the rendered form on the index page.
  test "(b) POST /settings/tokens with valid CSRF token succeeds" do
    post "/testing/sign_in", params: { user_id: users(:tonny).id }

    with_forgery_protection do
      get settings_tokens_path
      assert_response :ok
      token = css_select("form[action='#{settings_tokens_path}'] input[name='authenticity_token']").first&.[]("value")
      assert token.present?, "expected authenticity_token in the PAT creation form"

      assert_difference -> { PersonalAccessToken.count }, +1 do
        post settings_tokens_path, params: {
          authenticity_token: token,
          personal_access_token: { name: "with-csrf", kind: "cli", expires_in_days: "30" }
        }
      end
      assert_redirected_to settings_tokens_path
    end
  end

  # (c) V2 mutating endpoints do NOT enforce CSRF.
  # V2::BaseController inherits ActionController::API which has no forgery
  # protection at all. A POST with no CSRF token must not raise
  # InvalidAuthenticityToken nor return 422-from-CSRF. Without Basic auth, the
  # controller must respond 401 per Docker V2 Basic-scheme challenge contract.
  test "(c) V2 POST /v2/:name/blobs/uploads does not require CSRF (auth-gated, not CSRF-gated)" do
    with_forgery_protection do
      post "/v2/some-repo/blobs/uploads"
      assert_response :unauthorized
      assert_equal %(Basic realm="Registry"), response.headers["WWW-Authenticate"]
    end
  end

  # (d) GET is exempt from CSRF by construction. Pin that the OAuth callback
  # (GET /auth/:provider/callback) is reachable with forgery protection enabled.
  # The callback itself also declares `skip_forgery_protection only: [:create]`,
  # but the verb is GET anyway — we assert no CSRF rejection happens.
  test "(d) GET /auth/google_oauth2/callback is not subject to CSRF" do
    OmniAuth.config.test_mode = true
    OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
      provider: "google_oauth2",
      uid: "csrf-test-uid",
      info: { email: "csrf-test@timberay.com", name: "CSRF Test" },
      extra: { raw_info: { email_verified: true } }
    )

    with_forgery_protection do
      get "/auth/google_oauth2/callback"
      assert_redirected_to root_path
    end
  ensure
    OmniAuth.config.mock_auth[:google_oauth2] = nil
    OmniAuth.config.test_mode = false
  end
end
