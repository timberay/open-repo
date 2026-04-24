require "test_helper"

# UC-AUTH-016 — Session cookie hygiene.
#
# Pins the attributes Rails 8 emits for our session cookie, plus the
# session-fixation/sign-out invariants enforced by `Auth::SessionsController`'s
# `reset_session` calls (controller at app/controllers/auth/sessions_controller.rb).
#
# We do NOT add an initializer or change `config.session_options` — these tests
# assert what the Rails 8 cookie store currently emits with the project's
# default configuration. If any assertion ever flips, that is a real change in
# session security posture and should be reviewed, not silently relaxed.
class SessionCookieHygieneTest < ActionDispatch::IntegrationTest
  # Discover the configured session cookie name (Rails default is
  # "_<app_name>_session"; for this app it's "_repo_vista_session").
  SESSION_KEY = Rails.application.config.session_options[:key].freeze

  # Returns the raw Set-Cookie line for the session cookie, or nil if absent.
  # `response.headers["Set-Cookie"]` may be a String (single cookie) or
  # Array (multiple cookies) depending on the Rack version, so handle both.
  def session_set_cookie
    Array(response.headers["Set-Cookie"]).find { |c| c.start_with?("#{SESSION_KEY}=") }
  end

  # Splits a Set-Cookie line into attribute tokens after the name=value pair.
  # Lower-cased to make `HttpOnly` / `httponly` comparisons case-insensitive,
  # matching how browsers treat cookie attributes (RFC 6265 §5.2).
  def cookie_attributes(set_cookie_line)
    set_cookie_line.split("; ")[1..].to_a.map(&:downcase)
  end

  # (1) HttpOnly — protects the session cookie from being read by document.cookie
  # in JavaScript, blunting XSS-driven session theft.
  test "session cookie is marked HttpOnly" do
    post "/testing/sign_in", params: { user_id: users(:tonny).id }

    raw = session_set_cookie
    assert raw, "expected a Set-Cookie line for #{SESSION_KEY}, got: #{response.headers['Set-Cookie'].inspect}"
    attrs = cookie_attributes(raw)
    assert_includes attrs, "httponly",
      "session cookie should carry HttpOnly; saw attributes: #{attrs.inspect}"
  end

  # (2) SameSite — Rails 8's cookie store defaults to SameSite=Lax via a Proc.
  # Lax (or Strict) blocks CSRF via cross-site top-level POST/iframe loads.
  # `None` would only be acceptable paired with Secure, and is NOT what we
  # want for a first-party app — assert we never accidentally end up there.
  test "session cookie carries SameSite=Lax (or Strict), never None" do
    post "/testing/sign_in", params: { user_id: users(:tonny).id }

    raw = session_set_cookie
    assert raw, "expected a Set-Cookie line for #{SESSION_KEY}"
    attrs = cookie_attributes(raw)
    samesite = attrs.find { |a| a.start_with?("samesite=") }
    assert samesite, "session cookie missing SameSite attribute; saw: #{attrs.inspect}"

    value = samesite.split("=", 2).last
    assert_includes %w[lax strict], value,
      "session cookie SameSite must be Lax or Strict (saw #{value.inspect}); " \
      "SameSite=None without Secure is a CSRF/leak hazard"
  end

  # (3) Session id rotates on sign-in — `reset_session` in
  # Auth::SessionsController#create defends against session fixation by
  # issuing a fresh cookie value when an authenticated session begins.
  #
  # We exercise the *real* controller (not /testing/sign_in, which does not
  # call reset_session) by driving the OAuth callback in OmniAuth test mode.
  # First we plant a pre-auth session cookie via /testing/sign_in (acting as
  # an attacker-supplied fixation cookie), then trigger the OAuth callback
  # and assert the cookie value changed.
  test "Auth::SessionsController#create rotates the session cookie value" do
    # Plant an initial session cookie (simulating a fixated/pre-existing session).
    post "/testing/sign_in", params: { user_id: users(:tonny).id }
    initial = session_set_cookie
    assert initial, "expected an initial session cookie after priming"

    OmniAuth.config.test_mode = true
    OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
      provider: "google_oauth2",
      uid:      identities(:tonny_google).uid,
      info:     { email: users(:tonny).email, name: "Tonny" },
      extra:    { raw_info: { email_verified: true } }
    )

    get "/auth/google_oauth2/callback"
    rotated = session_set_cookie
    assert rotated, "expected a rotated session cookie after OAuth callback"

    initial_value = initial.split(";", 2).first.split("=", 2).last
    rotated_value = rotated.split(";", 2).first.split("=", 2).last

    refute_equal initial_value, rotated_value,
      "session cookie value must change on sign-in (session-fixation defense)"
  ensure
    OmniAuth.config.mock_auth[:google_oauth2] = nil
    OmniAuth.config.test_mode = false
  end

  # (4) Sign-out clears session[:user_id] — Auth::SessionsController#destroy
  # calls `reset_session`, so the next request must behave as anonymous
  # (sign-in CTA is back, signed-in user's email is gone).
  test "DELETE /auth/sign_out invalidates the authenticated session" do
    post "/testing/sign_in", params: { user_id: users(:tonny).id }

    get "/"
    assert_response :ok
    assert_match users(:tonny).email, response.body,
      "sanity: after sign-in, root should display signed-in user's email"

    delete "/auth/sign_out"

    get "/"
    assert_response :ok
    assert_no_match Regexp.new(Regexp.escape(users(:tonny).email)), response.body,
      "after sign-out, signed-in user's email should not appear on root"
    # Mirrors auth_session_restore_test.rb:7 — anonymous-state CTA reappears.
    assert_select "form[action='/auth/google_oauth2'] button", text: /Sign in with Google/i
  end

  # (5) Secure attribute under force_ssl — production sets `force_ssl = true`
  # which inserts `ActionDispatch::SSL` middleware that rewrites Set-Cookie
  # headers to append `; secure`. `force_ssl` is currently commented out in
  # config/environments/production.rb, but if/when it is enabled, the SSL
  # middleware is the mechanism that makes the session cookie Secure.
  #
  # Skipped: flipping `force_ssl` mid-process does not insert the SSL
  # middleware (the stack is built at boot), and stubbing
  # `Rails.application.config.force_ssl` does not retroactively rewrite
  # response cookies. Verifying this would require either a dedicated
  # production-like environment boot or rewriting the middleware stack,
  # neither of which is appropriate for an integration test. The contract
  # is exercised in production by `ActionDispatch::SSL#flag_cookies_as_secure!`
  # (actionpack/lib/action_dispatch/middleware/ssl.rb) and is independently
  # tested by Rails itself.
  test "session cookie is marked Secure when force_ssl is on" do
    skip "force_ssl toggle requires app reboot — middleware stack is built once at boot, " \
         "and stubbing config.force_ssl does not retroactively insert ActionDispatch::SSL. " \
         "Coverage of the rewrite itself lives in Rails' own test suite."
  end
end
