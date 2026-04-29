require "test_helper"

class AuthGoogleOauthFlowTest < ActionDispatch::IntegrationTest
  setup do
    OmniAuth.config.test_mode = true
    @original_admin_email = Rails.configuration.x.registry.admin_email
  end

  teardown do
    OmniAuth.config.mock_auth[:google_oauth2] = nil
    OmniAuth.config.test_mode = false
    Rails.configuration.x.registry.admin_email = @original_admin_email
  end

  def mock_google(email:, uid:, verified: true)
    OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
      provider: "google_oauth2", uid: uid,
      info: { email: email, name: "Test" },
      extra: { raw_info: { email_verified: verified } }
    )
  end

  test "new user full OAuth round-trip: login → home shows email → sign out" do
    mock_google(email: "fresh@timberay.com", uid: "fresh-uid")
    assert_difference -> { User.count }, +1 do
      get "/auth/google_oauth2/callback"
      assert_redirected_to root_path
      follow_redirect!
    end
    assert_match "fresh@timberay.com", response.body

    delete sign_out_path
    assert_redirected_to root_path
    follow_redirect!
    assert_match "Sign in with Google", response.body
  end

  test "returning user: existing identity reused, primary_identity updated" do
    existing = identities(:tonny_google)
    mock_google(email: existing.email, uid: existing.uid)

    assert_no_difference -> { User.count } do
      get "/auth/google_oauth2/callback"
    end
    existing.reload
    assert_in_delta Time.current, existing.last_login_at, 5.seconds

    user = existing.user.reload
    assert_equal existing.id, user.primary_identity_id
  end

  test "admin bootstrap: REGISTRY_ADMIN_EMAIL gets admin=true on first login" do
    Rails.configuration.x.registry.admin_email = "boss@timberay.com"
    mock_google(email: "boss@timberay.com", uid: "boss-uid")
    get "/auth/google_oauth2/callback"
    assert User.find_by!(email: "boss@timberay.com").admin?
  end

  # E-22: OAuth state CSRF protection.
  # OmniAuth's google_oauth2 strategy validates the `state` param to defend
  # against login-CSRF. When test_mode is on, that validation is bypassed —
  # so we route the failure path explicitly: assigning a Symbol to mock_auth
  # makes OmniAuth deliver an error to its failure endpoint, which our
  # Auth::SessionsController#failure handler converts to a redirect to root
  # with an alert flash. The contract this test pins:
  #   - no session is created (no session[:user_id])
  #   - user lands back on the unauthenticated UI with an alert flash
  #   - no User row is created from a forged callback
  test "callback with state CSRF failure does NOT create a session and surfaces error flash" do
    OmniAuth.config.mock_auth[:google_oauth2] = :csrf_detected

    assert_no_difference -> { User.count } do
      get "/auth/google_oauth2/callback"
    end

    # OmniAuth's on_failure proc is wired in config/initializers/omniauth.rb to
    # invoke Auth::SessionsController#failure directly, so the callback response
    # IS the failure handler's redirect (not an intermediate /auth/failure hop).
    assert_redirected_to root_path
    # Failure handler whitelists messages (csrf_detected is not in the list,
    # so it normalizes to "failed") — we just assert the user-visible alert
    # surfaces the failure rather than the specific OmniAuth error name.
    assert_match(/sign-in failed/i, flash[:alert].to_s)

    # Critical security assertion: no session was established.
    assert_nil session[:user_id]
  end
end
