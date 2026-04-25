require "test_helper"

class AnonymousRedirectTest < ActionDispatch::IntegrationTest
  setup do
    OmniAuth.config.test_mode = true
  end

  teardown do
    OmniAuth.config.mock_auth[:google_oauth2] = nil
    OmniAuth.config.test_mode = false
  end

  def mock_google_for(user)
    identity = user.primary_identity
    OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
      provider: "google_oauth2", uid: identity.uid,
      info: { email: identity.email, name: "Test" },
      extra: { raw_info: { email_verified: true } }
    )
  end

  test "anon GET /settings/tokens redirects to /sign_in and renders the Google button" do
    get "/settings/tokens"
    assert_redirected_to sign_in_path
    follow_redirect!
    assert_response :ok
    assert_select "form[action='/auth/google_oauth2'][method='post'] button",
                  text: /Sign in with Google/i
  end

  test "successful OAuth round-trip returns the user to the originally requested protected page" do
    mock_google_for(users(:tonny))

    get "/settings/tokens"
    assert_redirected_to sign_in_path
    follow_redirect!
    assert_response :ok

    get "/auth/google_oauth2/callback"
    assert_redirected_to "/settings/tokens"
  end

  test "anon DELETE on a protected resource redirects to /sign_in but does NOT save return_to" do
    repo = Repository.create!(
      name: "anon-delete-#{SecureRandom.hex(4)}",
      owner_identity: identities(:tonny_google)
    )

    delete "/repositories/#{repo.name}"
    assert_redirected_to sign_in_path

    mock_google_for(users(:tonny))
    get "/auth/google_oauth2/callback"
    # DELETE is non-idempotent — we never replay it after sign-in.
    assert_redirected_to root_path
  ensure
    repo&.destroy
  end

  test "anon HEAD on a protected GET-able resource saves return_to (HEAD is safe)" do
    mock_google_for(users(:tonny))

    head "/settings/tokens"
    assert_redirected_to sign_in_path

    get "/auth/google_oauth2/callback"
    assert_redirected_to "/settings/tokens"
  end

  test "GET /sign_in is accessible to anonymous users (no auth required)" do
    get "/sign_in"
    assert_response :ok
    assert_select "form[action='/auth/google_oauth2'][method='post'] button",
                  text: /Sign in with Google/i
  end

  test "GET /sign_in redirects already-signed-in users to root" do
    post "/testing/sign_in", params: { user_id: users(:tonny).id }
    get "/sign_in"
    assert_redirected_to root_path
  end
end
