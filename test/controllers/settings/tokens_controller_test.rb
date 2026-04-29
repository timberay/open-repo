require "test_helper"

class Settings::TokensControllerTest < ActionDispatch::IntegrationTest
  include TokenFixtures

  # --- index ---

  test "GET /settings/tokens 302 without signed-in user" do
    get settings_tokens_path
    assert_redirected_to sign_in_path
  end

  test "GET /settings/tokens lists active + revoked tokens for current identity" do
    post "/testing/sign_in", params: { user_id: users(:tonny).id }
    get settings_tokens_path
    assert_response :ok
    assert_select "td", text: "laptop"
  end

  # B-40: /settings/tokens must explain that oprk_ identifies open-repo PATs.
  test "GET /settings/tokens explains the oprk_ token prefix" do
    post "/testing/sign_in", params: { user_id: users(:tonny).id }
    get settings_tokens_path
    assert_response :ok
    assert_includes response.body, "oprk_",
      "expected /settings/tokens to mention the oprk_ prefix"
    assert_match(/personal access token/i, response.body,
      "expected /settings/tokens to describe oprk_ as a personal access token prefix")
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

  # B-25: raw-token flash banner must include a copy-to-clipboard affordance
  # using the existing clipboard Stimulus controller.
  test "POST /settings/tokens raw-token flash includes a clipboard copy button" do
    post "/testing/sign_in", params: { user_id: users(:tonny).id }
    post settings_tokens_path, params: {
      personal_access_token: { name: "copy-test", kind: "cli", expires_in_days: "30" }
    }
    follow_redirect!
    raw = flash[:raw_token].to_s
    assert_match(/\Aoprk_/, raw)

    # Stimulus controller binding present.
    assert_match(/data-controller="clipboard"/, response.body,
      "expected a data-controller=\"clipboard\" element on the raw-token flash")
    # The clipboard target value carries the raw token.
    assert_includes response.body, %(data-clipboard-text-value="#{raw}"),
      "expected clipboard-text-value to carry the raw token"
    # A click action wired to clipboard#copy is present.
    assert_match(/data-action="click->clipboard#copy"/, response.body,
      "expected click->clipboard#copy action on a copy button")
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

  # ---------------------------------------------------------------------------
  # UC-UI-012: PAT create — kind / expires / name validation edges (Wave 6 — pin)
  # ---------------------------------------------------------------------------

  test "UC-UI-012 POST with kind=registry is rejected — model only allows cli/ci" do
    post "/testing/sign_in", params: { user_id: users(:tonny).id }
    assert_no_difference -> { PersonalAccessToken.count } do
      post settings_tokens_path, params: {
        personal_access_token: { name: "registry-style", kind: "registry", expires_in_days: "30" }
      }
    end
    assert_response :unprocessable_entity
    assert_match(/Kind/i, response.body)
  end

  test "UC-UI-012 POST with expires_in_days=30 stores expires_at ~30 days in the future" do
    post "/testing/sign_in", params: { user_id: users(:tonny).id }
    freeze_time do
      assert_difference -> { PersonalAccessToken.count }, +1 do
        post settings_tokens_path, params: {
          personal_access_token: { name: "future-30d", kind: "cli", expires_in_days: "30" }
        }
      end
      pat = PersonalAccessToken.order(created_at: :desc).first
      assert_equal "future-30d", pat.name
      assert_in_delta 30.days.from_now, pat.expires_at, 1.second
      assert pat.expires_at > Time.current, "expires_at should be in the future"
    end
  end

  test "UC-UI-012 POST with expires_in_days=-1 (past-style) stores nil expires_at — controller treats non-positive as never-expires" do
    # Pin current behavior: parse_expires_in returns nil for days <= 0, so a "past expiry" intent
    # via the form ends up as a never-expires PAT (NOT a validation error, NOT an immediately-expired row).
    post "/testing/sign_in", params: { user_id: users(:tonny).id }
    assert_difference -> { PersonalAccessToken.count }, +1 do
      post settings_tokens_path, params: {
        personal_access_token: { name: "past-attempt", kind: "cli", expires_in_days: "-1" }
      }
    end
    pat = PersonalAccessToken.order(created_at: :desc).first
    assert_equal "past-attempt", pat.name
    assert_nil pat.expires_at, "non-positive expires_in_days should collapse to nil (never-expires)"
  end

  test "UC-UI-012 POST with blank expires_in_days creates row with nil expires_at (never-expires)" do
    post "/testing/sign_in", params: { user_id: users(:tonny).id }
    assert_difference -> { PersonalAccessToken.count }, +1 do
      post settings_tokens_path, params: {
        personal_access_token: { name: "never-dies", kind: "cli", expires_in_days: "" }
      }
    end
    pat = PersonalAccessToken.order(created_at: :desc).first
    assert_equal "never-dies", pat.name
    assert_nil pat.expires_at
  end

  test "UC-UI-012 POST with blank name is rejected with validation error and creates no row" do
    post "/testing/sign_in", params: { user_id: users(:tonny).id }
    assert_no_difference -> { PersonalAccessToken.count } do
      post settings_tokens_path, params: {
        personal_access_token: { name: "", kind: "cli", expires_in_days: "30" }
      }
    end
    assert_response :unprocessable_entity
    assert_match(/Name/i, response.body)
  end

  test "UC-UI-012 PAT name uniqueness is per-identity, not global — same name on a DIFFERENT user's identity is allowed" do
    # tonny already owns a PAT named "laptop" via fixtures (personal_access_tokens(:tonny_cli_active)).
    # Confirm admin (different user → different identity) can create another PAT with name "laptop".
    post "/testing/sign_in", params: { user_id: users(:admin).id }
    assert_difference -> { PersonalAccessToken.count }, +1 do
      post settings_tokens_path, params: {
        personal_access_token: { name: "laptop", kind: "cli", expires_in_days: "30" }
      }
    end
    assert_redirected_to settings_tokens_path

    pat = PersonalAccessToken.order(created_at: :desc).first
    assert_equal "laptop", pat.name
    assert_equal users(:admin).primary_identity, pat.identity
    # And tonny's original "laptop" PAT remains intact and distinct.
    tonny_pat = personal_access_tokens(:tonny_cli_active)
    assert_equal "laptop", tonny_pat.name
    assert_not_equal tonny_pat.id, pat.id
    assert_not_equal tonny_pat.identity_id, pat.identity_id
  end
end
