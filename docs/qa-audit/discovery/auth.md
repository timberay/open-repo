# Auth & Security Discovery

## Identity mechanisms

### User accounts
- **Creation**: OAuth-only (Google OAuth2 via OmniAuth).
- **Providers wired**: Google OAuth2 only.
- **Session lifecycle**:
  - Web UI: Rails HTTP-only session cookie (`session[:user_id]`), stored as session ID.
  - Docker V2 API: HTTP Basic auth using Personal Access Tokens (PAT) — no bearer tokens, no JWT.
- **Email verification required**: New users (Case C) and email-matching existing users (Case B) must have `email_verified=true` from Google before account creation; unverified raises `Auth::EmailMismatch`.
- **Admin flag**: Set at creation via `User.admin_email?(email)` comparison against `REGISTRY_ADMIN_EMAIL` env var.

### Personal Access Tokens (PATs)
- **Issuance**: Created via `/settings/tokens` POST by authenticated users (requires signed-in Web UI session).
- **Scopes**: **TODO:** PAT model lacks explicit scopes — all active PATs grant full write/delete per identity ownership. No fine-grained scope separation tested.
- **Storage**: **Hashed** — SHA256 digest stored in `PersonalAccessToken.token_digest`; raw token displayed once at creation (flash message), never retrievable.
- **Prefix**: `oprk_` + 32 bytes urlsafe Base64.
- **Expiration**: Optional `expires_at` timestamp; null means never expires.
- **Revocation**: Via `revoke!` sets `revoked_at`; `active` scope filters out.
- **Activation**: `authenticate_raw(raw_token)` hashes input, queries `active` scope, returns PAT or nil.
- **Binding**: Per `identity` (not user). One user can have multiple identities (Google + future providers); each identity can issue separate PATs.

### Session model

**Web UI:**
- Cookie-based Rails session; user ID stored as `session[:user_id]`.
- Authentication: `current_user` helper queries `User.find_by(id: session[:user_id])`.
- Sign-in: Google OAuth2 callback (`/auth/google_oauth2/callback`) → `Auth::SessionsController#create` → `reset_session` + `session[:user_id] = user.id`.
- Sign-out: DELETE `/auth/sign_out` → `reset_session` → redirect.
- **TODO:** Session cookie SameSite/Secure flags not explicitly reviewed; Rails 8.1 defaults should apply.

**Docker V2 API:**
- Stateless HTTP Basic per-request.
- Email + raw PAT in Authorization header.
- `V2::BaseController#authenticate_v2_basic!` extracts credentials, calls `Auth::PatAuthenticator`.
- Updates `last_used_at` on successful auth.

---

## Docker client auth flow

### Endpoint
No explicit token-issuing endpoint (e.g., `/v2/token`). Docker clients authenticate directly via HTTP Basic on each V2 API request.

### Flow (e.g., `docker login` + `docker push`)
1. **docker login**:
   - User enters email + raw PAT (not password).
   - Docker CLI stores credentials in `~/.docker/config.json`.

2. **docker push** request (e.g., PUT `/v2/myimage/manifests/tag`):
   - CLI sends `Authorization: Basic base64(email:raw_pat)`.
   - Registry validates via `V2::BaseController#authenticate_v2_basic!`:
     - Extracts email, raw_pat from header.
     - Calls `Auth::PatAuthenticator.new.call(email: email, raw_token: raw)`.
     - `PatAuthenticator`:
       - Raises `Auth::PatInvalid` if email or token blank.
       - Calls `PersonalAccessToken.authenticate_raw(raw_token)` → hashes token, queries DB.
       - Validates email matches PAT identity's user email (case-insensitive).
       - Returns `Result(user:, pat:)`.
   - Sets `@current_user`, `@current_pat`.
   - Updates `pat.last_used_at` via `update_column`.

3. **Authorization gate**:
   - Manifest PUT/DELETE calls `authorize_for!(:write)` or `authorize_for!(:delete)`.
   - Checks `@repository.writable_by?(current_user.primary_identity)` or `.deletable_by?()`.
   - Owner-identity check or membership with `writer`/`admin` role.

4. **Challenge on failure**:
   - 401 response + `WWW-Authenticate: Basic realm="Registry"` header.
   - Body: `{ errors: [{ code: "UNAUTHORIZED", message: "authentication required", detail: null }] }`.

### HTTP Basic as sole mechanism
- Yes, HTTP Basic is the only auth method for V2 API.
- No bearer tokens, no OAuth2 bearer flow.
- PAT = password substitute.

---

## Authorization rules

### Repository access

| Action | Rule | Code path |
|--------|------|-----------|
| **Anonymous pull** | GET `/v2/{name}/manifests/{ref}`, GET `/v2/{name}/blobs/{digest}`, GET `/v2/_catalog`, HEAD variants | `V2::BaseController#anonymous_pull_allowed?` checks `REGISTRY_ANONYMOUS_PULL_ENABLED` env var + GET/HEAD + whitelist of endpoints. If true, skips `authenticate_v2_basic!`. |
| **Authenticated pull** | Same endpoints, any authenticated user | `V2::BaseController#authenticate_v2_basic!` → all authenticated users can read (no repo-level check). |
| **Write (push)** | PUT `/v2/{name}/manifests/{ref}`, POST/PATCH/PUT blob uploads | `V2::ManifestsController#update` → `authorize_for!(:write)` → `@repository.writable_by?(identity)` → owner OR member with `writer`/`admin` role. |
| **Delete** | DELETE `/v2/{name}/manifests/{ref}`, DELETE `/v2/{name}/tags/{name}`, DELETE `/v2/{name}/blobs/{digest}` | `authorize_for!(:delete)` → `@repository.deletable_by?(identity)` → owner only OR member with `admin` role. |
| **Repository creation** | Implicit: first push to a new repo | `V2::BlobUploadsController#ensure_repository!` → `Repository.find_or_create_by!` → first pusher becomes owner (primary identity). |

### Web UI repository management

| Action | Rule | Code path |
|--------|------|-----------|
| **View repos** | List all public repos | `RepositoriesController#index` → no auth check (could enumerate all repos). **TODO:** No visibility gate; all repos visible to all authenticated users. |
| **View repo details** | Same as above | `RepositoriesController#show` → no auth check. |
| **Update repo settings** | Owner or admin member | `RepositoriesController#update` → **TODO:** No auth check! `repository_params` trusts form input; missing `authorize_for!(:write)`. |
| **Delete repo** | Owner only | `RepositoriesController#destroy` → `authorize_for!(:delete)` → owner-only. |

### PAT management

| Action | Rule | Code path |
|--------|------|-----------|
| **List PATs** | Own PATs only | `Settings::TokensController#index` → `current_identity.personal_access_tokens`. |
| **Create PAT** | Own identity only | `Settings::TokensController#create` → `current_identity.personal_access_tokens.new()`. |
| **Revoke PAT** | Own PAT only | `Settings::TokensController#destroy` → `current_identity.personal_access_tokens.find_by(id:)`. |

### Tag protection

- **Policy enforcement**: `Repository#tag_protected?()` checks policy (none, semver, all_except_latest, custom_regex).
- **Mutation gate**: `Repository#enforce_tag_protection!(tag_name, new_digest:)` raises `Registry::TagProtected` on protected tag PUT/DELETE.
- **Who enforces**: V2 and Web UI ManifestProcessors; no role-based exemption (all users blocked equally).

---

## Routes requiring auth

| Route | Public | Auth Required | Admin-only | Notes |
|-------|--------|---------------|------------|-------|
| `POST /auth/:provider/callback` | ✓ | (callback receiver) | N/A | OmniAuth callback handler. |
| `GET /auth/failure` | ✓ | (error page) | N/A | Failed OAuth redirect. |
| `DELETE /auth/sign_out` | ✓ (no-op if not signed in) | (sign-out action) | N/A | Rails session required, idempotent. |
| `GET /v2/` | ✓ (if anon pull enabled) | ✗ (if disabled) | N/A | Base endpoint check. |
| `GET /v2/_catalog` | ✓ (if anon pull enabled) | ✗ | N/A | List all repos. |
| `GET /v2/{name}/tags/list` | ✓ (if anon pull enabled) | ✗ | N/A | List tags in repo. |
| `GET /v2/{name}/manifests/{ref}` | ✓ (if anon pull enabled) | ✗ | N/A | Fetch manifest. |
| `HEAD /v2/{name}/manifests/{ref}` | ✓ (if anon pull enabled) | ✗ | N/A | Check manifest existence. |
| `GET /v2/{name}/blobs/{digest}` | ✓ (if anon pull enabled) | ✗ | N/A | Fetch blob. |
| `PUT /v2/{name}/manifests/{ref}` | ✗ | ✓ | ✗ | Push requires auth + write permission. |
| `DELETE /v2/{name}/manifests/{ref}` | ✗ | ✓ | ✗ | Delete requires auth + delete permission. |
| `POST /v2/{name}/blobs/uploads` | ✗ | ✓ | ✗ | Blob upload initiation. |
| `PATCH /v2/{name}/blobs/uploads/{uuid}` | ✗ | ✓ | ✗ | Blob upload chunk. |
| `PUT /v2/{name}/blobs/uploads/{uuid}` | ✗ | ✓ | ✗ | Blob upload completion. |
| `DELETE /v2/{name}/blobs/uploads/{uuid}` | ✗ | ✓ | ✗ | Blob upload cancellation. |
| `GET /repositories` | ✓ (no-op) | ✗ | N/A | Web UI list; returns all repos regardless. |
| `GET /repositories/{name}` | ✓ (no-op) | ✗ | N/A | Web UI show; no visibility gate. |
| `POST /repositories/{name}` | ✗ | ✓ | ✗ | **TODO:** Unprotected — missing auth check. |
| `DELETE /repositories/{name}` | ✗ | ✓ | ✗ | Delete requires delete permission. |
| `GET /settings/tokens` | ✗ | ✓ | ✗ | PAT list (own only). |
| `POST /settings/tokens` | ✗ | ✓ | ✗ | PAT creation (own identity). |
| `DELETE /settings/tokens/{id}` | ✗ | ✓ | ✗ | PAT revocation (own only). |
| `GET /help` | ✓ | N/A | N/A | Help page. |
| `GET /up` | ✓ | N/A | N/A | Rails health check. |

---

## Edge cases worth testing

### Authentication edge cases
- **Expired PAT**: `PersonalAccessToken.active` scope filters `expires_at <= Time.current` → `authenticate_raw` returns nil → 401 challenge.
- **Revoked PAT**: `active` scope filters `revoked_at IS NOT NULL` → returns nil → 401.
- **Malformed Bearer token**: No Bearer support; expected `Basic base64(...)`. If provided, `ActionController::HttpAuthentication::Basic.user_name_and_password` returns `(nil, nil)` → `Unauthenticated` raised → 401.
- **Missing Authorization header**: `user_name_and_password` returns `(nil, nil)` → raises `Unauthenticated` → 401 challenge.
- **Email in PAT mismatch**: `email.downcase != pat.identity.user.email.downcase` → `Auth::PatInvalid` → 401.
- **Case-insensitive email**: PAT validator lowercases email; sign-in also lowercases (GoogleAdapter). Consistency check needed.
- **PAT blank**: `authenticate_raw("")` → returns nil (early guard) → 401.

### Session & OAuth edge cases
- **Session cookie forgery / CSRF bypass**: 
  - OAuth callback (`POST /auth/:provider/callback`) has `skip_forgery_protection only: [:create]` (OmniAuth requirement, no CSRF token on callback).
  - `omniauth-rails_csrf_protection` gem should mitigate via state parameter validation.
  - **TODO:** Verify OmniAuth state parameter is validated; no explicit state check in `Auth::SessionsController#create`.
- **State parameter tampering**: `omniauth-rails_csrf_protection` should validate via Rails session; if mismatched, OmniAuth raises `FailureError` → routed to `#failure`.
- **Concurrent sign-in tabs**: No session-level conflict; new sign-in calls `reset_session` (clears old tab's session). Old tab loses auth.
- **OAuth callback race (double redirect)**: Not hardened; if same auth_hash processed twice, `Identity.find_or_create` can race. Should be atomic but SQLite constraints may cause brief duplication.
- **Sign-out Turbo bypass**: `DELETE /auth/sign_out` calls `reset_session` synchronously; Turbo frame bypass not tested. **TODO:** Verify DELETE is not intercepted by Turbo (likely OK since it's not a form).

### Authorization edge cases
- **Protected tag push with idempotent digest**: `enforce_tag_protection!(tag_name, new_digest: digest)` allows if existing tag has same digest. Retry-safe for CI.
- **Protected tag bypass via direct blob mount**: `V2::BlobUploadsController#handle_blob_mount` does not check tag protection; only manifest PUT does. **TODO:** Tag protection bypassed for blob-mount flow?
- **Repository ownership transfer**: `transfer_ownership_to!` is atomic (transaction). Previous owner added as admin member. No revocation of deleted members; **TODO:** Orphaned members after transfer?
- **PAT concurrent revocation**: `revoke!` is not atomic with auth check; PAT can be revoked mid-request. `update_column(:last_used_at)` happens after auth; if revoke() runs between, token is "live" but marked revoked in DB. Subsequent request sees revoked (401). Client retries with fresh PAT.
- **Repository write permission race**: `ensure_repository!` in blob uploads has `RecordNotUnique` catch; losing racer skips authz. **Design trade-off**: blob uploads are harmless orphans; manifest-level authz gates creation.

### Rate limiting & anti-abuse
- **Auth endpoint throttle**: `/auth/*` POST limited to 10 req/min per IP. Typical for OAuth.
- **V2 mutation throttle**: `/v2/*` non-GET/HEAD limited to 30 req/min per IP. Fairly permissive for concurrent pushes.
- **No per-PAT throttle**: Only IP-based. **TODO:** Compromised PAT can saturate endpoint within rate limits.

### CSRF & state
- **Forgery protection**: Enabled on ApplicationController (default). OmniAuth callback disabled via `skip_forgery_protection only: [:create]`.
- **PAT create/destroy via Web UI**: Forms use `params.expect()` (Rails 8+), CSRF token enforced by default. **TODO:** Verify Turbo forms include CSRF token.
- **Manifest/blob endpoints** (V2 API): No CSRF check (API context; status codes differ). Acceptable for stateless HTTP Basic.

---

## Security notes / concerns

### High-risk findings

1. **Missing auth on repository update endpoint** (`RepositoriesController#update`):
   - Route `POST /repositories/{name}` lacks `authorize_for!(:write)` check.
   - Any authenticated user can modify tag protection, description, maintainer.
   - **Severity: HIGH** — scope creep / data tampering.
   - **Fix location**: Add `before_action :set_repository_for_authz` with write check.

2. **OmniAuth state parameter validation unclear**:
   - `Auth::SessionsController#create` does not explicitly validate state.
   - `omniauth-rails_csrf_protection` gem should handle, but no integration test confirms state validation.
   - **Severity: MEDIUM** — relies on gem guarantee.
   - **Test**: Force state mismatch, verify rejection.

3. **No fine-grained PAT scopes**:
   - All active PATs grant full write/delete to owned repos.
   - No way to issue read-only or repo-specific tokens.
   - **Severity: MEDIUM** — compromised PAT is all-or-nothing.

4. **Session persistence across logout (Turbo concern)**:
   - `DELETE /auth/sign_out` is a non-GET link; Turbo may intercept and not send DELETE.
   - If UI frame doesn't update, user thinks signed out but session remains.
   - **Severity: MEDIUM** — UX risk; test with Turbo enabled.

### Medium-risk findings

5. **CSP not enabled**:
   - `content_security_policy.rb` is commented out.
   - No XSS hardening via CSP; relies on Rails auto-escaping.
   - **Severity: MEDIUM** — best practice gap.

6. **Repository visibility not gated**:
   - Web UI lists all repositories to all authenticated users.
   - No private/public distinction or access control list.
   - **Severity: LOW-MEDIUM** — depends on threat model (internal registry → acceptable; public → risk).

7. **Email verification only at creation**:
   - `Identity` stores `email_verified`, but changes to user email are not re-verified.
   - If user's Google email is changed without re-auth, stale verified flag remains.
   - **Severity: LOW** — Google email rarely changes; re-sign-in would create new identity.

8. **PAT last_used_at updated via `update_column` (non-transactional)**:
   - Bypass DB validations; concurrent requests may have race on update.
   - Does not invalidate request if update fails.
   - **Severity: LOW** — observability only; no security gate depends on this.

9. **No audit logging for auth state changes**:
   - PAT creation/revocation, sign-in, sign-out logged minimally (Rails.logger.warn for failures only).
   - TagEvent logs repository mutations but not identity/auth events.
   - **Severity: LOW** — compliance/forensics gap.

10. **Regex DoS risk in tag protection custom regex**:
    - `tag_protection_pattern` validated only by Ruby Regexp.new; no ReDoS guard.
    - Malicious regex (e.g., `(a+)+b`) on large tag names could hang.
    - **Severity: LOW** — admin-only policy setting; less likely to be exploited externally.

### Low-risk or design notes

- **Plaintext PAT in flash message**: Displayed once at creation, then only the digest is stored. Acceptable (follows GitHub model); user must save immediately.
- **SQLite as primary DB**: Not production-hardened; constraints may be slower than Postgres. Acceptable for registry use case.
- **Anonymous pull enabled by default**: Configurable via `REGISTRY_ANONYMOUS_PULL_ENABLED` env. Sensible default for registry-as-service.
- **No OAuth2 bearer token endpoint**: Design choice (HTTP Basic only). Aligns with Docker Registry spec; trade-off is no token refresh/expiry per request.

---

## TODO / Unclear

- [ ] Verify OmniAuth state parameter is validated on callback (integration test coverage).
- [ ] Test Turbo frame compatibility with DELETE /auth/sign_out.
- [ ] Test tag protection bypass via blob mount vs. manifest PUT.
- [ ] Enumerate all repository members after ownership transfer; orphaned member cleanup.
- [ ] PAT scope model (is feature planned?).
- [ ] CSP enablement timeline.
- [ ] Audit logging for auth events (create PAT, revoke PAT, sign-in, sign-out).
- [ ] ReDoS hardening for custom tag protection regex.
- [ ] Repository visibility rules (private/public or ACL model).

