# S-703 Anonymous Redirect Fix — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Spec:** `docs/superpowers/specs/2026-04-25-s703-anonymous-redirect-design.md` (committed `e2a3d84`)

**Goal:** Anonymous users hitting protected pages land on a working `/sign_in` page (not a 404), and after OAuth sign-in return to the page they originally requested.

**Architecture:** Add a server-rendered `/sign_in` page that hosts the existing `POST /auth/google_oauth2` `button_to`. Persist `request.fullpath` in `session[:return_to]` for safe `GET` requests at the moment of `Auth::Unauthenticated` rescue, then consume + validate it on successful OAuth callback. Open-redirect defense lives in a `Auth::SafeReturn` concern with a focused unit test.

**Tech Stack:** Rails 8, Ruby, OmniAuth (google_oauth2), Tailwind CSS, ERB, Minitest.

**Commit Plan (Tidy First):**
- **Commit 1 (structural)** — Tasks 2-5. Adds new files and helpers. No production behavior change. Full suite green.
- **Commit 2 (behavioral)** — Tasks 6-12. Wires the new helpers into existing rescue paths and adds the integration tests. Full suite green.

---

## File Structure

**New files:**
- `app/controllers/concerns/auth/safe_return.rb` — open-redirect-safe path validation concern
- `app/views/auth/sessions/new.html.erb` — sign-in page rendering the POST button
- `test/controllers/concerns/auth/safe_return_test.rb` — unit test for the concern
- `test/integration/anonymous_redirect_test.rb` — end-to-end coverage of the redirect flow

**Modified files:**
- `config/routes.rb` — add `get "/sign_in", to: "auth/sessions#new", as: :sign_in`
- `app/controllers/application_controller.rb` — `include Auth::SafeReturn`, swap `rescue_from` to a method, add `redirect_to_sign_in!` helper
- `app/controllers/auth/sessions_controller.rb` — add `new` action; have `create` consume `session[:return_to]` before `reset_session`
- `app/controllers/settings/tokens_controller.rb` — `ensure_current_user` calls `redirect_to_sign_in!`
- `test/controllers/settings/tokens_controller_test.rb` — first test asserts `assert_redirected_to sign_in_path`
- `test/controllers/repositories_controller_test.rb` — anonymous DELETE test asserts `%r{/sign_in}`

---

## Task 1: Create feature branch

**Files:**
- (none — git only)

- [ ] **Step 1: Verify clean working tree**

```bash
git status
```

Expected: `nothing to commit, working tree clean` (the spec from `e2a3d84` is already committed). If anything is dirty, stop and surface it to the user before proceeding.

- [ ] **Step 2: Create + checkout the feature branch from `main`**

```bash
git checkout -b fix/s703-anonymous-redirect
```

Expected: `Switched to a new branch 'fix/s703-anonymous-redirect'`.

---

## Task 2: `Auth::SafeReturn` concern (TDD — write the failing test first)

**Files:**
- Create: `test/controllers/concerns/auth/safe_return_test.rb`
- Create: `app/controllers/concerns/auth/safe_return.rb`

- [ ] **Step 1: Write the failing unit test**

Create `test/controllers/concerns/auth/safe_return_test.rb` with this exact content:

```ruby
require "test_helper"

class Auth::SafeReturnTest < ActiveSupport::TestCase
  # We exercise the concern via a throwaway host class so the test does not
  # depend on ApplicationController (and so it can call the private method
  # without going through controller machinery).
  class Host
    include Auth::SafeReturn
    public :safe_return_to
  end

  setup { @host = Host.new }

  test "returns the path for an existing relative route" do
    assert_equal "/repositories/foo", @host.safe_return_to("/repositories/foo")
  end

  test "preserves the query string when the path resolves to a route" do
    assert_equal "/settings/tokens?x=1", @host.safe_return_to("/settings/tokens?x=1")
  end

  test "blocks protocol-relative URLs" do
    assert_nil @host.safe_return_to("//evil.com/x")
  end

  test "blocks absolute URLs" do
    assert_nil @host.safe_return_to("https://evil.com/x")
  end

  test "blocks paths that do not match any route" do
    assert_nil @host.safe_return_to("/no/such/path-#{SecureRandom.hex(2)}")
  end

  test "returns nil for nil input" do
    assert_nil @host.safe_return_to(nil)
  end

  test "returns nil for empty string" do
    assert_nil @host.safe_return_to("")
  end

  test "returns nil for paths without a leading slash" do
    assert_nil @host.safe_return_to("not-a-path")
  end

  test "swallows URI::InvalidURIError and returns nil" do
    assert_nil @host.safe_return_to("/%")
  end
end
```

- [ ] **Step 2: Run the test and verify it fails**

```bash
bin/rails test test/controllers/concerns/auth/safe_return_test.rb
```

Expected: ERROR — `NameError: uninitialized constant Auth::SafeReturn` (or equivalent).

- [ ] **Step 3: Implement the concern**

Create `app/controllers/concerns/auth/safe_return.rb`:

```ruby
module Auth
  module SafeReturn
    extend ActiveSupport::Concern

    private

    # Returns +path+ unchanged when it is a same-origin relative URL that
    # resolves to a real route in this application; otherwise returns nil.
    # Defends against open redirects (protocol-relative, absolute, unknown
    # routes, malformed URIs).
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

- [ ] **Step 4: Run the test and verify it passes**

```bash
bin/rails test test/controllers/concerns/auth/safe_return_test.rb
```

Expected: `9 runs, 9 assertions, 0 failures, 0 errors, 0 skips`.

- [ ] **Step 5: Run the full controller test slice to confirm no incidental regression**

```bash
bin/rails test test/controllers
```

Expected: all green. (No existing controller test references `Auth::SafeReturn` yet — this should be a no-op for the rest.)

(No commit yet — this lands as part of commit 1.)

---

## Task 3: Add `/sign_in` route

**Files:**
- Modify: `config/routes.rb` (around lines 1-5, the OmniAuth block)

- [ ] **Step 1: Add the route**

In `config/routes.rb`, change the OmniAuth block from:

```ruby
  # OmniAuth (Stage 0 — Google only)
  get    "/auth/:provider/callback", to: "auth/sessions#create",  as: :auth_callback
  get    "/auth/failure",            to: "auth/sessions#failure", as: :auth_failure
  delete "/auth/sign_out",           to: "auth/sessions#destroy", as: :sign_out
```

…to:

```ruby
  # OmniAuth (Stage 0 — Google only)
  get    "/sign_in",                 to: "auth/sessions#new",     as: :sign_in
  get    "/auth/:provider/callback", to: "auth/sessions#create",  as: :auth_callback
  get    "/auth/failure",            to: "auth/sessions#failure", as: :auth_failure
  delete "/auth/sign_out",           to: "auth/sessions#destroy", as: :sign_out
```

- [ ] **Step 2: Verify the route exists**

```bash
bin/rails routes -g sign_in
```

Expected output includes a line like:

```
sign_in GET    /sign_in(.:format)  auth/sessions#new
```

(No commit — part of commit 1.)

---

## Task 4: `Auth::SessionsController#new` + sign-in view (TDD)

**Files:**
- Modify: `app/controllers/auth/sessions_controller.rb` (add `new` action)
- Create: `app/views/auth/sessions/new.html.erb`
- Modify: `test/controllers/auth/sessions_controller_test.rb` (add `new` coverage)

- [ ] **Step 1: Write the failing controller test**

Append to `test/controllers/auth/sessions_controller_test.rb` (just before the final `end`):

```ruby
  # --- new (sign-in page) ---

  test "GET /sign_in renders the sign-in page with the Google POST button" do
    get "/sign_in"
    assert_response :ok
    assert_select "form[action='/auth/google_oauth2'][method='post'] button",
                  text: /Sign in with Google/i
  end

  test "GET /sign_in redirects signed-in users to root" do
    post "/testing/sign_in", params: { user_id: users(:tonny).id }
    get "/sign_in"
    assert_redirected_to root_path
  end
```

- [ ] **Step 2: Run the test and verify it fails**

```bash
bin/rails test test/controllers/auth/sessions_controller_test.rb -n "/sign_in/"
```

Expected: ERROR — `AbstractController::ActionNotFound: The action 'new' could not be found...` (or a routing error / view missing).

- [ ] **Step 3: Add the `new` action**

In `app/controllers/auth/sessions_controller.rb`, add this action immediately above `def create`:

```ruby
  def new
    redirect_to(root_path) and return if signed_in?
  end
```

- [ ] **Step 4: Create the view**

Create `app/views/auth/sessions/new.html.erb` with this exact content:

```erb
<% content_for :title, "Sign in" %>
<div class="max-w-md mx-auto py-16 px-4 text-center">
  <h1 class="text-2xl font-semibold text-slate-100 mb-6">Sign in to continue</h1>
  <%= button_to "Sign in with Google", "/auth/google_oauth2", method: :post,
                class: "inline-flex items-center justify-center min-h-11 px-4 py-2 rounded-md bg-indigo-600 text-white hover:bg-indigo-700 transition-colors duration-150",
                data: { turbo: false } %>
</div>
```

- [ ] **Step 5: Run the test and verify it passes**

```bash
bin/rails test test/controllers/auth/sessions_controller_test.rb -n "/sign_in/"
```

Expected: `2 runs, ... 0 failures, 0 errors`.

- [ ] **Step 6: Run the full sessions controller suite for regression**

```bash
bin/rails test test/controllers/auth/sessions_controller_test.rb
```

Expected: all green (the existing `create` / `failure` / `destroy` tests are unchanged and should still pass).

(No commit — part of commit 1.)

---

## Task 5: ApplicationController — include concern + `redirect_to_sign_in!` helper

**Files:**
- Modify: `app/controllers/application_controller.rb`

This task ONLY adds the helper. Callers continue to use the old `redirect_to "/auth/google_oauth2"` until commit 2. The helper is intentionally dead code at this point — that is what makes commit 1 a structural-only change.

- [ ] **Step 1: Edit `application_controller.rb`**

Replace the current file with:

```ruby
class ApplicationController < ActionController::Base
  include RepositoryAuthorization
  include Auth::SafeReturn

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  helper_method :current_user, :signed_in?

  rescue_from Auth::Unauthenticated, with: -> { redirect_to "/auth/google_oauth2" }
  rescue_from Auth::ForbiddenAction, with: ->(e) {
    redirect_to repository_path(e.repository.name),
                alert: "You don't have permission to #{e.action} in '#{e.repository.name}'."
  }

  private

  def current_user
    return @current_user if defined?(@current_user)
    @current_user =
      if session[:user_id]
        User.find_by(id: session[:user_id]).tap do |u|
          session.delete(:user_id) if u.nil?
        end
      end
  end

  def signed_in?
    current_user.present?
  end

  def redirect_to_sign_in!
    session[:return_to] = request.fullpath if request.get?
    redirect_to sign_in_path
  end
end
```

The two changes versus the original are:
1. `include Auth::SafeReturn` (line 3)
2. New private method `redirect_to_sign_in!` at the bottom

`rescue_from Auth::Unauthenticated` is intentionally NOT changed in this commit.

- [ ] **Step 2: Run the full test suite**

```bash
bin/rails test
```

Expected: all green. The new `include` should be a no-op for existing behavior, and the dead helper does not affect anything.

(No commit yet — combined into commit 1 in Task 6.)

---

## Task 6: Commit 1 (structural)

**Files:**
- (git only — bundle the work from Tasks 2-5 into one commit)

- [ ] **Step 1: Stage exactly the structural files**

```bash
git add \
  app/controllers/concerns/auth/safe_return.rb \
  app/controllers/application_controller.rb \
  app/controllers/auth/sessions_controller.rb \
  app/views/auth/sessions/new.html.erb \
  config/routes.rb \
  test/controllers/auth/sessions_controller_test.rb \
  test/controllers/concerns/auth/safe_return_test.rb
```

- [ ] **Step 2: Verify the staged diff is structural-only**

```bash
git diff --cached --stat
```

Expected file count: 7 files. No lines should change in `tokens_controller.rb`, `repositories_controller_test.rb:485`, or `tokens_controller_test.rb:10` — those land in commit 2.

```bash
git status
```

Expected: only the seven staged files, plus the still-untracked `docs/e2e-test-report-20260422-tag-immutability.md` (pre-existing, leave alone).

- [ ] **Step 3: Run the full suite once more before committing**

```bash
bin/rails test
```

Expected: all green.

- [ ] **Step 4: Commit**

```bash
git commit -m "$(cat <<'EOF'
fix(auth): scaffold /sign_in page + safe_return concern (S-703 part 1)

Structural-only: add the /sign_in route, the Auth::SessionsController#new
action, the new sign-in view, and the Auth::SafeReturn concern. The
ApplicationController gains a redirect_to_sign_in! private helper but
no caller uses it yet — the existing Auth::Unauthenticated rescue still
points at /auth/google_oauth2. Behavior change ships in part 2.

Refs: docs/superpowers/specs/2026-04-25-s703-anonymous-redirect-design.md
EOF
)"
```

Expected: pre-commit hooks pass, single commit recorded. (If pre-commit fails, see `docs/standards/QUALITY.md#pre-commit-failure-recovery` — fix and retry, do not `--no-verify`.)

- [ ] **Step 5: Confirm clean state**

```bash
git status
git log --oneline -3
```

Expected: working tree clean (except the untracked pre-existing doc), HEAD is the new commit, prior HEAD was `e2a3d84`.

---

## Task 7: Anonymous redirect integration test (TDD — RED)

**Files:**
- Create: `test/integration/anonymous_redirect_test.rb`

Write all five integration cases up front; they will all fail until Tasks 8-10 wire the new redirect path. This is a small, cohesive test file — write it once and watch it go from RED → GREEN through subsequent tasks.

- [ ] **Step 1: Create the test file**

Create `test/integration/anonymous_redirect_test.rb` with this exact content:

```ruby
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
```

- [ ] **Step 2: Run the test and confirm the expected RED state**

```bash
bin/rails test test/integration/anonymous_redirect_test.rb
```

Expected at this point:
- Cases 1 ("anon GET /settings/tokens redirects to /sign_in"), 2 ("successful OAuth round-trip"), and 3 ("anon DELETE on a protected resource") **FAIL** — current rescue paths still redirect to `/auth/google_oauth2` and `Auth::SessionsController#create` does not consume `return_to` yet.
- Case 4 ("GET /sign_in is accessible to anonymous users") **PASSES** — commit 1 already wired this. This is your green sentinel that proves Task 4 was correct.
- Case 5 ("GET /sign_in redirects signed-in users to root") **PASSES** — also from commit 1.

Record which tests fail; Tasks 8-10 will flip 1, 2, 3 green one path at a time.

(No commit — TDD red bar, code follows.)

---

## Task 8: Wire `tokens_controller` to `redirect_to_sign_in!` + update its existing test

**Files:**
- Modify: `app/controllers/settings/tokens_controller.rb` (line 39-41)
- Modify: `test/controllers/settings/tokens_controller_test.rb` (line 8-11)

- [ ] **Step 1: Update the existing token test FIRST (TDD red)**

In `test/controllers/settings/tokens_controller_test.rb`, change:

```ruby
  test "GET /settings/tokens 302 without signed-in user" do
    get settings_tokens_path
    assert_redirected_to "/auth/google_oauth2"
  end
```

…to:

```ruby
  test "GET /settings/tokens 302 without signed-in user" do
    get settings_tokens_path
    assert_redirected_to sign_in_path
  end
```

- [ ] **Step 2: Run that test and confirm it fails**

```bash
bin/rails test test/controllers/settings/tokens_controller_test.rb -n "302 without"
```

Expected: FAIL — `Expected response to be a redirect to <http://www.example.com/sign_in> but was a redirect to <http://www.example.com/auth/google_oauth2>`.

- [ ] **Step 3: Update `tokens_controller.rb`**

In `app/controllers/settings/tokens_controller.rb`, change:

```ruby
    def ensure_current_user
      redirect_to "/auth/google_oauth2" unless signed_in?
    end
```

…to:

```ruby
    def ensure_current_user
      return if signed_in?
      redirect_to_sign_in!
    end
```

- [ ] **Step 4: Run the updated test**

```bash
bin/rails test test/controllers/settings/tokens_controller_test.rb -n "302 without"
```

Expected: PASS.

- [ ] **Step 5: Run all tokens controller tests for regression**

```bash
bin/rails test test/controllers/settings/tokens_controller_test.rb
```

Expected: all green.

- [ ] **Step 6: Re-run the integration test — first case should now go GREEN**

```bash
bin/rails test test/integration/anonymous_redirect_test.rb -n "anon GET /settings/tokens"
```

Expected: PASS.

(No commit — part of commit 2.)

---

## Task 9: Update `ApplicationController#rescue_from` + the repositories regression test

**Files:**
- Modify: `app/controllers/application_controller.rb` (rescue_from + handle_unauthenticated)
- Modify: `test/controllers/repositories_controller_test.rb:485`

- [ ] **Step 1: Update the existing repositories test FIRST (TDD red)**

In `test/controllers/repositories_controller_test.rb`, change line 485:

```ruby
    assert_match %r{/auth/google_oauth2}, response.location
```

…to:

```ruby
    assert_match %r{/sign_in}, response.location
```

(Leave the surrounding test untouched — only that one assertion line changes.)

- [ ] **Step 2: Run that test and confirm it fails**

```bash
bin/rails test test/controllers/repositories_controller_test.rb -n "anonymous"
```

Expected: FAIL — the response location is still `/auth/google_oauth2`.

- [ ] **Step 3: Update `application_controller.rb` `rescue_from`**

Replace the lambda with a method-name symbol and add `handle_unauthenticated`. The full file should now read:

```ruby
class ApplicationController < ActionController::Base
  include RepositoryAuthorization
  include Auth::SafeReturn

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  helper_method :current_user, :signed_in?

  rescue_from Auth::Unauthenticated, with: :handle_unauthenticated
  rescue_from Auth::ForbiddenAction, with: ->(e) {
    redirect_to repository_path(e.repository.name),
                alert: "You don't have permission to #{e.action} in '#{e.repository.name}'."
  }

  private

  def current_user
    return @current_user if defined?(@current_user)
    @current_user =
      if session[:user_id]
        User.find_by(id: session[:user_id]).tap do |u|
          session.delete(:user_id) if u.nil?
        end
      end
  end

  def signed_in?
    current_user.present?
  end

  def handle_unauthenticated
    redirect_to_sign_in!
  end

  def redirect_to_sign_in!
    session[:return_to] = request.fullpath if request.get?
    redirect_to sign_in_path
  end
end
```

The two changes versus Task 5's version:
1. `rescue_from Auth::Unauthenticated, with: :handle_unauthenticated`
2. New private method `handle_unauthenticated`

- [ ] **Step 4: Run the repositories test**

```bash
bin/rails test test/controllers/repositories_controller_test.rb -n "anonymous"
```

Expected: PASS.

(No commit — part of commit 2.)

---

## Task 10: `Auth::SessionsController#create` consumes `return_to`

**Files:**
- Modify: `app/controllers/auth/sessions_controller.rb` (`create` action)

- [ ] **Step 1: Update the `create` action**

In `app/controllers/auth/sessions_controller.rb`, change the existing `create` from:

```ruby
  def create
    auth_hash = request.env["omniauth.auth"] or
      raise Auth::InvalidProfile, "missing omniauth.auth env (middleware not engaged)"
    profile = adapter_for(provider_param).to_profile(auth_hash)
    user = Auth::SessionCreator.new.call(profile)
    reset_session
    session[:user_id] = user.id
    # Signed-in user sees their own email — intentional UX, not PII exposure.
    redirect_to root_path, notice: "Signed in as #{user.email}"
  rescue Auth::EmailMismatch => e
    Rails.logger.warn("auth: email mismatch (#{e.message})")
    redirect_to auth_failure_path(strategy: provider_param, message: "email_mismatch")
  rescue Auth::InvalidProfile => e
    Rails.logger.warn("auth: invalid profile (#{e.message})")
    redirect_to auth_failure_path(strategy: provider_param, message: "invalid_profile")
  rescue Auth::ProviderOutage => e
    Rails.logger.warn("auth: provider outage (#{e.message})")
    redirect_to auth_failure_path(strategy: provider_param, message: "provider_outage")
  end
```

…to:

```ruby
  def create
    auth_hash = request.env["omniauth.auth"] or
      raise Auth::InvalidProfile, "missing omniauth.auth env (middleware not engaged)"
    profile = adapter_for(provider_param).to_profile(auth_hash)
    user = Auth::SessionCreator.new.call(profile)

    # Pull return_to BEFORE reset_session wipes it; validate before trusting it.
    return_to = session[:return_to]
    reset_session
    session[:user_id] = user.id
    destination = safe_return_to(return_to) || root_path
    # Signed-in user sees their own email — intentional UX, not PII exposure.
    redirect_to destination, notice: "Signed in as #{user.email}"
  rescue Auth::EmailMismatch => e
    Rails.logger.warn("auth: email mismatch (#{e.message})")
    redirect_to auth_failure_path(strategy: provider_param, message: "email_mismatch")
  rescue Auth::InvalidProfile => e
    Rails.logger.warn("auth: invalid profile (#{e.message})")
    redirect_to auth_failure_path(strategy: provider_param, message: "invalid_profile")
  rescue Auth::ProviderOutage => e
    Rails.logger.warn("auth: provider outage (#{e.message})")
    redirect_to auth_failure_path(strategy: provider_param, message: "provider_outage")
  end
```

(The three `rescue` clauses are unchanged. Only the body before them changes.)

- [ ] **Step 2: `safe_return_to` is on the controller via inheritance**

`Auth::SessionsController < ApplicationController`, and Task 9's `ApplicationController` includes `Auth::SafeReturn`. So `safe_return_to` is available as a private method on this controller — no extra include needed.

- [ ] **Step 3: Run the integration test — round-trip case should go GREEN**

```bash
bin/rails test test/integration/anonymous_redirect_test.rb -n "round-trip"
```

Expected: PASS.

- [ ] **Step 4: Run the full integration test file**

```bash
bin/rails test test/integration/anonymous_redirect_test.rb
```

Expected: all 5 tests PASS.

- [ ] **Step 5: Run the existing OAuth callback regression**

```bash
bin/rails test test/controllers/auth/sessions_controller_test.rb \
            test/integration/auth_google_oauth_flow_test.rb \
            test/integration/csrf_test.rb \
            test/integration/session_cookie_hygiene_test.rb
```

Expected: all green. (When `session[:return_to]` is nil — which it is for these tests — the `safe_return_to(nil)` call returns nil and we fall through to `root_path`, matching the prior behavior.)

(No commit — part of commit 2.)

---

## Task 11: Full suite + commit 2 (behavioral)

**Files:**
- (git only — bundle Tasks 7-10 into one commit)

- [ ] **Step 1: Run the full test suite**

```bash
bin/rails test
```

Expected: all green. If anything fails, fix it and re-run before staging.

- [ ] **Step 2: Stage exactly the behavioral files**

```bash
git add \
  app/controllers/application_controller.rb \
  app/controllers/auth/sessions_controller.rb \
  app/controllers/settings/tokens_controller.rb \
  test/controllers/repositories_controller_test.rb \
  test/controllers/settings/tokens_controller_test.rb \
  test/integration/anonymous_redirect_test.rb
```

- [ ] **Step 3: Verify the staged diff is behavioral-only**

```bash
git diff --cached --stat
```

Expected: 6 files. No new helpers, no new view files (those were in commit 1).

```bash
git status
```

Expected: only the six staged files, plus the still-untracked pre-existing doc.

- [ ] **Step 4: Commit**

```bash
git commit -m "$(cat <<'EOF'
fix(auth): redirect anon users to /sign_in instead of GET /auth/google_oauth2 (S-703 part 2)

Anonymous users hitting protected pages were redirected to
GET /auth/google_oauth2, which 404'd because OmniAuth is configured
POST-only (omniauth.rb:14). They now land on the /sign_in page
introduced in part 1, and after a successful OAuth round-trip return
to the page they originally requested.

Behavior changes:
- ApplicationController rescue_from Auth::Unauthenticated now calls
  redirect_to_sign_in!, which persists request.fullpath in
  session[:return_to] for safe GETs (idempotent verbs only) and
  redirects to /sign_in.
- Settings::TokensController#ensure_current_user uses the same helper.
- Auth::SessionsController#create consumes session[:return_to] before
  reset_session and validates it via Auth::SafeReturn#safe_return_to,
  which blocks protocol-relative URLs, absolute URLs, and unknown
  routes.

Tests:
- New test/integration/anonymous_redirect_test.rb covers the full
  round-trip, the non-GET no-return_to invariant, and the unknown-route
  fall-back.
- Existing assertions in tokens_controller_test.rb and
  repositories_controller_test.rb updated to expect /sign_in.

Refs: docs/superpowers/specs/2026-04-25-s703-anonymous-redirect-design.md
EOF
)"
```

Expected: pre-commit hooks pass, single commit recorded.

- [ ] **Step 5: Confirm state**

```bash
git status
git log --oneline -5
```

Expected: working tree clean, two new commits on top of `e2a3d84` (the spec commit).

---

## Task 12: Manual E2E verification

**Files:**
- (none — server smoke test)

This task validates the fix against the original reproduction from the spec.

- [ ] **Step 1: Start the dev server with the mock registry**

```bash
USE_MOCK_REGISTRY=true bin/rails server -p 3000 -b 127.0.0.1 &
```

Wait ~3 seconds for the server to come up. Note the PID printed by `&` so you can stop it later (or use `pkill -f "rails server"`).

- [ ] **Step 2: Reproduce the original spec command and verify the redirect chain**

```bash
curl -sI http://127.0.0.1:3000/settings/tokens
```

Expected:

```
HTTP/1.1 302 Found
Location: http://127.0.0.1:3000/sign_in
```

(The `Location` header must end with `/sign_in`, not `/auth/google_oauth2`.)

- [ ] **Step 3: Follow the redirect and verify it lands on a 200**

```bash
curl -sIL http://127.0.0.1:3000/settings/tokens
```

Expected: the final response in the chain is `HTTP/1.1 200 OK` (the sign-in page). No 404 anywhere in the chain.

- [ ] **Step 4: Confirm the page contains the working POST button**

```bash
curl -sL http://127.0.0.1:3000/settings/tokens | grep -E 'action="/auth/google_oauth2"|Sign in with Google'
```

Expected: at least one match showing the `<form action="/auth/google_oauth2" ...>` and the button label.

- [ ] **Step 5: Stop the dev server**

```bash
pkill -f "rails server" || true
```

- [ ] **Step 6: (optional) Re-run `/e2e-testing` and confirm S-703 flips to PASS**

If you have time and the user wants the full evidence pack, run `/e2e-testing` and verify `docs/e2e-test-report.md` no longer lists S-703 as HIGH severity. This is optional; the curl chain above is the minimum gate.

---

## Done

Both commits are on `fix/s703-anonymous-redirect`. The bug is fixed, the test suite is green, and the curl reproduction shows a 200 instead of a 404.

The user has previously asked for two commits in one PR. Whether to push + open the PR is a separate, user-confirmed step (covered by the project's `push2gh` / `ship` skills) — do NOT push autonomously.
