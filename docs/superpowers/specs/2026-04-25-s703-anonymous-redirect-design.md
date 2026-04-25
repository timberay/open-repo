# S-703 — Anonymous user redirect produces 404

**Date:** 2026-04-25
**Severity:** HIGH (UX-breaking, also affects production)
**Source:** `/e2e-testing` 전수검사 2026-04-25
**Evidence:** `docs/screenshots/20260425-120952/error/s703-anon-settings-redirect.png`, `docs/e2e-test-report.md` (S-703)

## Problem

Anonymous users hitting protected pages (`/settings/tokens`, `DELETE /repositories/:name`, etc.) get a 404 instead of a sign-in page.

Reproduction:

```bash
USE_MOCK_REGISTRY=true bin/rails server -p 3000 -b 127.0.0.1 &
curl -sI http://127.0.0.1:3000/settings/tokens
# HTTP/1.1 302 Found
# Location: http://127.0.0.1:3000/auth/google_oauth2
curl -sI http://127.0.0.1:3000/auth/google_oauth2
# HTTP/1.1 404 Not Found
```

Root cause:

1. `app/controllers/application_controller.rb:9` rescues `Auth::Unauthenticated` with `redirect_to "/auth/google_oauth2"`.
2. The browser follows the 302 with a `GET`.
3. `config/initializers/omniauth.rb:14` pins `OmniAuth.config.allowed_request_methods = [:post]`, so OmniAuth's middleware does **not** intercept the GET.
4. There is no Rails route for `GET /auth/google_oauth2`, so it falls through to `public/404.html`.

The same chain occurs in `app/controllers/settings/tokens_controller.rb:40`. The GNB sign-in button (`app/views/shared/_auth_nav.html.erb:11`) is correct because it uses `button_to ... method: :post`.

## Goal

Anonymous users hitting any protected page land on a sign-in page that renders a working `POST /auth/google_oauth2` button. After successful sign-in, they return to the page they originally tried to reach.

Non-goals:

- Replacing or modifying OmniAuth configuration. POST-only `allowed_request_methods` stays.
- Changing the GNB sign-in button. It already works.
- Multi-provider sign-in. Stage 0 is Google-only and remains so.

## Approach

Add a server-rendered `/sign_in` page hosting the existing POST `button_to`. Persist the originally requested path in `session[:return_to]` (only for safe `GET` requests) and consume it on successful OAuth callback. Validate the persisted path against the routing table to prevent open-redirect.

This is the standard Rails+OmniAuth pattern (Devise/Sorcery use the same shape).

## Design

### 1. Route (`config/routes.rb`)

Add immediately under the existing OmniAuth block:

```ruby
get "/sign_in", to: "auth/sessions#new", as: :sign_in
```

### 2. Controller (`app/controllers/auth/sessions_controller.rb`)

Add a `new` action — render the sign-in page; bounce already-signed-in users to root:

```ruby
def new
  redirect_to(root_path) and return if signed_in?
end
```

Modify `create` to consume `session[:return_to]` before `reset_session` zeros it out:

```ruby
def create
  auth_hash = request.env["omniauth.auth"] or
    raise Auth::InvalidProfile, "missing omniauth.auth env (middleware not engaged)"
  profile = adapter_for(provider_param).to_profile(auth_hash)
  user = Auth::SessionCreator.new.call(profile)

  return_to = session[:return_to]
  reset_session
  session[:user_id] = user.id
  destination = safe_return_to(return_to) || root_path
  redirect_to destination, notice: "Signed in as #{user.email}"
rescue Auth::EmailMismatch => e
  # ... unchanged ...
end
```

The three failure rescues are unchanged.

### 3. Concern (`app/controllers/concerns/auth/safe_return.rb`, new)

Extract path validation into a focused concern so it has clear inputs/outputs and a unit test:

```ruby
module Auth
  module SafeReturn
    extend ActiveSupport::Concern

    private

    def safe_return_to(path)
      return nil unless path.is_a?(String)
      return nil unless path.start_with?("/") && !path.start_with?("//")
      uri = URI.parse(path)
      Rails.application.routes.recognize_path(uri.path)
      path
    rescue URI::InvalidURIError, ActionController::RoutingError
      nil
    end
  end
end
```

`URI.parse(path).path` strips the query string before passing to `recognize_path` (which only matches routes, not querystrings). The original `path` is what gets returned, so query strings round-trip back to the user.

### 4. ApplicationController helpers (`app/controllers/application_controller.rb`)

Include the concern, replace the lambda-form `rescue_from` with a method, extract a shared `redirect_to_sign_in!` helper:

```ruby
include Auth::SafeReturn

rescue_from Auth::Unauthenticated, with: :handle_unauthenticated

private

def handle_unauthenticated
  redirect_to_sign_in!
end

def redirect_to_sign_in!
  session[:return_to] = request.fullpath if request.get?
  redirect_to sign_in_path
end
```

`request.get?` guard: never persist `return_to` for non-idempotent verbs (POST/PATCH/PUT/DELETE). Replaying them after sign-in is dangerous and almost never what the user wanted.

### 5. settings/tokens_controller.rb

Use the shared helper:

```ruby
def ensure_current_user
  return if signed_in?
  redirect_to_sign_in!
end
```

### 6. View (`app/views/auth/sessions/new.html.erb`, new)

Minimal sign-in page reusing the existing `_auth_nav.html.erb:11` button pattern. Single `<h1>` plus the button — no return_to indicator (keeps the page clean; the post-sign-in redirect is the indicator).

```erb
<% content_for :title, "Sign in" %>
<div class="max-w-md mx-auto py-16 px-4 text-center">
  <h1 class="text-2xl font-semibold text-slate-100 mb-6">Sign in to continue</h1>
  <%= button_to "Sign in with Google", "/auth/google_oauth2", method: :post,
                class: "inline-flex items-center justify-center min-h-11 px-4 py-2 rounded-md bg-indigo-600 text-white hover:bg-indigo-700 transition-colors duration-150",
                data: { turbo: false } %>
</div>
```

The container styles match the project's existing centered-content pattern. Tailwind classes are taken from `_auth_nav.html.erb` for consistency.

## Tidy First — Commit Plan

The PR is **two commits** on a single branch:

**Commit 1 — structural (no behavior change yet):**

- Add `get "/sign_in"` route
- Add `Auth::SessionsController#new`
- Add `app/views/auth/sessions/new.html.erb`
- Add `app/controllers/concerns/auth/safe_return.rb` concern + `test/controllers/concerns/auth/safe_return_test.rb`
- Include `Auth::SafeReturn` in `ApplicationController`; extract `redirect_to_sign_in!` private helper (callers still use the old `redirect_to "/auth/google_oauth2"`)

After commit 1: full test suite green. The new page is reachable but no caller routes to it. `redirect_to "/auth/google_oauth2"` still 404s for anon users — bug not yet fixed, but no regression.

**Commit 2 — behavioral:**

- Switch `application_controller.rb` `rescue_from` to `handle_unauthenticated`
- Switch `settings/tokens_controller.rb#ensure_current_user` to `redirect_to_sign_in!`
- Add `return_to` consumption in `Auth::SessionsController#create`
- Update existing assertions in `test/controllers/settings/tokens_controller_test.rb` and `test/controllers/repositories_controller_test.rb`
- Add new `test/integration/anonymous_redirect_test.rb`

After commit 2: bug fixed, all tests green.

## Test Plan (TDD — write first)

### New: `test/integration/anonymous_redirect_test.rb`

1. **anon GET protected page → sign-in renders**
   `get "/settings/tokens"` → 302 → `follow_redirect!` → 200 with `form[action='/auth/google_oauth2'][method='post'] button`.
2. **anon direct GET /sign_in → renders**
   `get "/sign_in"` → 200 with the same button assertion.
3. **signed-in GET /sign_in → root**
   After `post "/testing/sign_in"`, `get "/sign_in"` → redirect to root.
4. **return_to round-trip via OAuth mock**
   Set `OmniAuth.config.test_mode = true` + `mock_auth[:google_oauth2]`, then:
   `get "/settings/tokens"` → follow → `get "/auth/google_oauth2/callback"` → final redirect Location ends with `/settings/tokens`.
5. **non-GET requests do NOT save return_to**
   anon `delete "/repositories/<existing>"` (with CSRF token) → 302 to `/sign_in`. Then mock callback → final redirect to `root_path` (not back to the DELETE).

### New: `test/controllers/concerns/auth/safe_return_test.rb`

Open-redirect defense lives here as a unit test of the concern (where the input is directly controllable). Use a throwaway test class that includes `Auth::SafeReturn`:

1. `safe_return_to("/repositories/foo")` → `"/repositories/foo"`
2. `safe_return_to("/settings/tokens?x=1")` → `"/settings/tokens?x=1"` (query preserved)
3. `safe_return_to("//evil.com/x")` → `nil` (protocol-relative blocked)
4. `safe_return_to("https://evil.com/x")` → `nil` (absolute blocked)
5. `safe_return_to("/no/such/path-#{SecureRandom.hex(2)}")` → `nil` (unknown route)
6. `safe_return_to(nil)` → `nil`
7. `safe_return_to("")` → `nil`
8. `safe_return_to("not-a-path")` → `nil` (no leading slash)
9. `safe_return_to("/%")` → `nil` (URI::InvalidURIError swallowed)

### Modified

- `test/controllers/settings/tokens_controller_test.rb:10` — `assert_redirected_to sign_in_path`
- `test/controllers/repositories_controller_test.rb:485` — `assert_match %r{/sign_in}, response.location`

### Regression-safe (no change expected)

- `test/integration/auth_session_restore_test.rb` — root path GNB button assertion still passes
- `test/integration/login_button_visibility_test.rb` — same
- `test/controllers/auth/sessions_controller_test.rb` — callback tests run with no `session[:return_to]` and should still redirect to root
- `test/integration/csrf_test.rb` — POST /auth/google_oauth2/callback path unchanged
- `test/integration/rack_attack_auth_throttle_test.rb` — `POST /auth/google_oauth2` throttle unchanged
- `test/integration/session_cookie_hygiene_test.rb` — sign-in cookie behavior unchanged

## E2E Verification

After commit 2:

```bash
USE_MOCK_REGISTRY=true bin/rails server -p 3000 -b 127.0.0.1 &
curl -sI http://127.0.0.1:3000/settings/tokens
# expect: HTTP/1.1 302 Found, Location ending /sign_in
curl -sIL http://127.0.0.1:3000/settings/tokens
# expect: final HTTP/1.1 200 OK
```

Then re-run `/e2e-testing` and confirm the S-703 case in `docs/e2e-test-report.md` flips to PASS.

## Security Considerations

- **Open redirect:** `safe_return_to` enforces relative paths and routing-table membership. Protocol-relative (`//host`), absolute (`https://host`), and unknown paths all fall through to `root_path`.
- **CSRF:** unchanged. The new `new` action is a plain GET with no state mutation; `create` keeps `skip_forgery_protection only: [:create]` for the OAuth callback.
- **Side-effect replay:** `return_to` is only persisted for `GET`. POST/PATCH/PUT/DELETE never round-trip through sign-in.
- **Throttling:** `Rack::Attack` already throttles `POST /auth/google_oauth2`; the new `/sign_in` page is a static GET and does not need its own throttle.
- **Session reset:** `reset_session` runs **after** reading `return_to` and **before** setting `:user_id` — pre-sign-in session state (including `return_to`) is discarded, the new session contains only `:user_id`, no fixation risk.

## Out of scope

- Multi-provider sign-in UI (Stage 0 is Google-only).
- Returning the user to a `POST` action after sign-in. They get root — acceptable for the rare case of a signed-out user submitting a form.
- Localizing the sign-in page (project-wide i18n is a separate effort per `docs/standards/STACK.md`).

## Standards alignment

- **TDD** (`docs/standards/RULES.md`): every test in the test plan above is written before the code it covers.
- **Tidy First** (`docs/standards/RULES.md`): commit 1 is purely structural; commit 2 is purely behavioral.
- **Small commits**: two commits, each independently green.
- **Korean for conversation, English for code/commits/markdown** (`CLAUDE.md`): this spec follows that rule.
