require "test_helper"

class LoginButtonVisibilityTest < ActionDispatch::IntegrationTest
  test "unauthenticated home shows 'Sign in with Google' button" do
    get "/"
    assert_response :ok
    assert_select "form[action='/auth/google_oauth2'][method='post'] button",
                  text: /Sign in with Google/i
  end

  test "signed-in home shows user email and sign-out" do
    post "/testing/sign_in", params: { user_id: users(:tonny).id }
    get "/"
    assert_response :ok
    assert_match users(:tonny).email, response.body
    assert_select "form[action='/auth/sign_out'][method='post']"
  end

  test "signed-in home shows 'Tokens' link to /settings/tokens" do
    post "/testing/sign_in", params: { user_id: users(:tonny).id }
    get "/"
    assert_response :ok
    assert_select "a[href='/settings/tokens']", text: "Tokens"
  end

  test "unauthenticated home does not show 'Tokens' link" do
    get "/"
    assert_response :ok
    assert_select "a[href='/settings/tokens']", count: 0
  end
end
