require "test_helper"

class AuthSessionRestoreTest < ActionDispatch::IntegrationTest
  test "current_user is nil when not signed in" do
    get "/"
    assert_response :ok
    assert_nil controller.send(:current_user)
  end

  test "session[:user_id] restores current_user" do
    post "/testing/sign_in", params: { user_id: users(:tonny).id }
    get "/"
    assert_response :ok
    assert_equal users(:tonny), controller.send(:current_user)
  end

  test "stale session[:user_id] (user deleted) silently resets" do
    deleted_id = 999_999
    post "/testing/sign_in", params: { user_id: deleted_id }
    get "/"
    assert_response :ok
    assert_nil controller.send(:current_user)
  end
end
