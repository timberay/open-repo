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
  end

  test "admin bootstrap: REGISTRY_ADMIN_EMAIL gets admin=true on first login" do
    Rails.configuration.x.registry.admin_email = "boss@timberay.com"
    mock_google(email: "boss@timberay.com", uid: "boss-uid")
    get "/auth/google_oauth2/callback"
    assert User.find_by!(email: "boss@timberay.com").admin?
  end
end
