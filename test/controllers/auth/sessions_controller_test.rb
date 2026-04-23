require "test_helper"

class Auth::SessionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    OmniAuth.config.test_mode = true
  end

  teardown do
    OmniAuth.config.mock_auth[:google_oauth2] = nil
    OmniAuth.config.test_mode = false
  end

  def mock_google(email:, uid:, verified: true)
    OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
      provider: "google_oauth2",
      uid: uid,
      info: { email: email, name: "Test User" },
      extra: { raw_info: { email_verified: verified } }
    )
  end

  test "GET /auth/google_oauth2/callback with valid auth → session created, redirect to root" do
    mock_google(email: "tonny@timberay.com", uid: identities(:tonny_google).uid)
    get "/auth/google_oauth2/callback"
    assert_redirected_to root_path
    assert_equal users(:tonny).id, session[:user_id]
  end

  test "new email → user created, signed in" do
    mock_google(email: "newbie@timberay.com", uid: "new-uid")
    assert_difference -> { User.count }, +1 do
      get "/auth/google_oauth2/callback"
    end
    assert_equal User.find_by!(email: "newbie@timberay.com").id, session[:user_id]
    assert_redirected_to root_path
  end

  test "email unverified Case B → redirect to failure with flash" do
    mock_google(email: users(:tonny).email, uid: "untrusted-uid", verified: false)
    get "/auth/google_oauth2/callback"
    assert_redirected_to auth_failure_path(strategy: "google_oauth2", message: "email_mismatch")
  end

  test "DELETE /auth/sign_out clears session" do
    post "/testing/sign_in", params: { user_id: users(:tonny).id }
    assert_equal users(:tonny).id, session[:user_id]

    delete sign_out_path
    assert_redirected_to root_path
    assert_nil session[:user_id]
  end

  # /auth/failure allowlist tests
  test "failure with unknown strategy and message → coerced to fallbacks" do
    get "/auth/failure", params: { strategy: "evil-strategy", message: "Your bank password is wrong" }
    assert_redirected_to root_path
    assert_equal "Sign-in failed (unknown: failed).", flash[:alert]
  end

  test "failure with allowed strategy and message → passed through unchanged" do
    get "/auth/failure", params: { strategy: "google_oauth2", message: "email_mismatch" }
    assert_redirected_to root_path
    assert_equal "Sign-in failed (google_oauth2: email_mismatch).", flash[:alert]
  end

  test "failure with no params → coerced to fallbacks" do
    get "/auth/failure"
    assert_redirected_to root_path
    assert_equal "Sign-in failed (unknown: failed).", flash[:alert]
  end
end
