require "test_helper"

class AuthSessionRestoreTest < ActionDispatch::IntegrationTest
  test "current_user is nil when not signed in" do
    get "/"
    assert_response :ok
    assert_select "form[action='/auth/google_oauth2'] button", text: /Sign in with Google/i
  end

  test "session[:user_id] restores current_user" do
    post "/testing/sign_in", params: { user_id: users(:tonny).id }
    get "/"
    assert_response :ok
    assert_match users(:tonny).email, response.body
  end

  test "stale session[:user_id] (user deleted) silently resets" do
    deleted_id = 999_999
    post "/testing/sign_in", params: { user_id: deleted_id }
    get "/"
    assert_response :ok
    assert_select "form[action='/auth/google_oauth2'] button", text: /Sign in with Google/i
  end
end
