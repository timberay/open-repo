require "test_helper"

class Settings::TokensControllerTest < ActionDispatch::IntegrationTest
  include TokenFixtures

  # --- index ---

  test "GET /settings/tokens 302 without signed-in user" do
    get settings_tokens_path
    assert_redirected_to "/auth/google_oauth2"
  end

  test "GET /settings/tokens lists active + revoked tokens for current identity" do
    post "/testing/sign_in", params: { user_id: users(:tonny).id }
    get settings_tokens_path
    assert_response :ok
    assert_select "td", text: "laptop"
  end

  test "never leaks other users' tokens" do
    post "/testing/sign_in", params: { user_id: users(:admin).id }
    get settings_tokens_path
    assert_select "td", text: "laptop", count: 0
  end

  # --- create ---

  test "POST /settings/tokens creates PAT and flashes raw token once" do
    post "/testing/sign_in", params: { user_id: users(:tonny).id }
    assert_difference -> { PersonalAccessToken.count }, +1 do
      post settings_tokens_path, params: {
        personal_access_token: { name: "new-laptop", kind: "cli", expires_in_days: "30" }
      }
    end
    assert_redirected_to settings_tokens_path
    follow_redirect!
    assert_match(/\Aoprk_/, flash[:raw_token].to_s)
    pat = PersonalAccessToken.order(created_at: :desc).first
    assert_equal users(:tonny).primary_identity, pat.identity
    assert_equal "new-laptop", pat.name
    assert_equal "cli", pat.kind
    assert_in_delta 30.days.from_now, pat.expires_at, 1.minute
  end

  test "POST /settings/tokens with kind=ci + blank expires_in_days → never expires" do
    post "/testing/sign_in", params: { user_id: users(:tonny).id }
    post settings_tokens_path, params: {
      personal_access_token: { name: "ci-box", kind: "ci", expires_in_days: "" }
    }
    pat = PersonalAccessToken.order(created_at: :desc).first
    assert_nil pat.expires_at
    assert_equal "ci", pat.kind
  end

  test "POST /settings/tokens with duplicate name for same identity fails" do
    post "/testing/sign_in", params: { user_id: users(:tonny).id }
    assert_no_difference -> { PersonalAccessToken.count } do
      post settings_tokens_path, params: {
        personal_access_token: { name: "laptop", kind: "cli", expires_in_days: "30" }
      }
    end
    assert_response :unprocessable_entity
  end

  # --- destroy (revoke) ---

  test "DELETE /settings/tokens/:id revokes PAT of current user" do
    post "/testing/sign_in", params: { user_id: users(:tonny).id }
    pat = personal_access_tokens(:tonny_cli_active)
    assert_changes -> { pat.reload.revoked_at } do
      delete settings_token_path(pat)
    end
    assert_redirected_to settings_tokens_path
  end

  test "DELETE cannot revoke other user's token (404)" do
    post "/testing/sign_in", params: { user_id: users(:admin).id }
    pat = personal_access_tokens(:tonny_cli_active)
    assert_no_changes -> { pat.reload.revoked_at } do
      delete settings_token_path(pat)
    end
    assert_response :not_found
  end

  test "Revoked PAT can no longer push to V2 (end-to-end)" do
    post "/testing/sign_in", params: { user_id: users(:tonny).id }
    pat = personal_access_tokens(:tonny_cli_active)
    delete settings_token_path(pat)
    reset!

    headers = {
      "Authorization" => ActionController::HttpAuthentication::Basic.encode_credentials(
        "tonny@timberay.com", TONNY_CLI_RAW)
    }
    put "/v2/myimage/manifests/v1", params: "{}", headers: headers
    assert_response :unauthorized
  end
end
