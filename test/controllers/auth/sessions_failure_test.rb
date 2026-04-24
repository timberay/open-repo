require "test_helper"

# UC-AUTH-003 — `/auth/failure` strategy + message validation.
#
# Auth::SessionsController#failure (app/controllers/auth/sessions_controller.rb)
# allowlists strategy ∈ ALLOWED_STRATEGIES and message ∈ ALLOWED_FAILURE_MESSAGES.
# Two existing cases at test/controllers/auth/sessions_controller_test.rb pin
# (a) unknown strategy + unknown message → "unknown: failed", and
# (b) allowed strategy + allowed message → echoed verbatim.
# This file fills the remaining .e1/.e2 spec rows: each allowed message renders
# its corresponding flash, unknown strategy alone defaults to "unknown",
# unknown message alone defaults to "failed", and HTML-injection in ?message=
# does not bypass the allowlist (raw injection string never appears in the
# response body — Rails ERB escapes by default for the flash that does land).
class Auth::SessionsFailureTest < ActionDispatch::IntegrationTest
  # Each allowed message renders the corresponding flash text.
  Auth::SessionsController::ALLOWED_FAILURE_MESSAGES.each do |msg|
    test "failure with allowed message #{msg.inspect} echoes message in flash" do
      get "/auth/failure", params: { strategy: "google_oauth2", message: msg }
      assert_redirected_to root_path
      assert_equal "Sign-in failed (google_oauth2: #{msg}).", flash[:alert]
    end
  end

  # Unknown message defaults to "failed" — never echoed verbatim.
  test "failure with unknown message defaults to failed" do
    get "/auth/failure", params: { strategy: "google_oauth2", message: "totally-not-allowed" }
    assert_redirected_to root_path
    assert_equal "Sign-in failed (google_oauth2: failed).", flash[:alert]
    refute_match(/totally-not-allowed/, flash[:alert].to_s)
  end

  # Unknown strategy alone defaults to "unknown" (allowed message preserved).
  test "failure with unknown strategy defaults to unknown" do
    get "/auth/failure", params: { strategy: "rogue-provider", message: "email_mismatch" }
    assert_redirected_to root_path
    assert_equal "Sign-in failed (unknown: email_mismatch).", flash[:alert]
    refute_match(/rogue-provider/, flash[:alert].to_s)
  end

  # XSS attempt in ?message= is not echoed at all because the controller
  # allowlist coerces unknown values to "failed". Follow the redirect to the
  # rendered HTML and assert the raw injection string never appears in the
  # response body. (Rails ERB also escapes flash values by default; the
  # allowlist is the primary defense and is what we pin here.)
  test "failure with XSS attempt in message is not echoed in response body" do
    injection = '<script>alert("xss")</script>'
    get "/auth/failure", params: { strategy: "google_oauth2", message: injection }
    assert_redirected_to root_path
    assert_equal "Sign-in failed (google_oauth2: failed).", flash[:alert]

    follow_redirect!
    assert_response :ok
    refute_includes response.body, injection,
      "raw injection string must never reach the rendered HTML"
    refute_includes response.body, "<script>alert",
      "raw <script> tag must not appear in response body"
  end

  # Same XSS check on the strategy parameter.
  test "failure with XSS attempt in strategy is not echoed in response body" do
    injection = '"><img src=x onerror=alert(1)>'
    get "/auth/failure", params: { strategy: injection, message: "failed" }
    assert_redirected_to root_path
    assert_equal "Sign-in failed (unknown: failed).", flash[:alert]

    follow_redirect!
    assert_response :ok
    refute_includes response.body, injection,
      "raw injection string in strategy must never reach the rendered HTML"
    refute_includes response.body, "onerror=alert",
      "raw onerror= attribute must not appear in response body"
  end
end
