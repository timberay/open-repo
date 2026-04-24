# Test Plan — Use Cases per Feature

## Conventions

- Each feature block has: **ID**, **preconditions**, **steps**, **expected observables**, **edge cases**.
- IDs are `UC-<area>-<nnn>` where area ∈ `{V2, UI, AUTH, JOB, MODEL}`.
- Each edge case is its own sub-ID: `UC-V2-001.e1`, `.e2`, etc.
- "Signed-in user" = valid Rails session (`session[:user_id]`).
- "Authenticated V2 client" = HTTP Basic with `email:raw_pat` where PAT is active.
- Unless otherwise stated, `REGISTRY_ANONYMOUS_PULL_ENABLED=true` (default).

---

## V2 Registry API

### UC-V2-001: Ping (`GET /v2/`)

- **Preconditions**: service up.
- **Steps**:
  1. Issue `GET /v2/` with no credentials.
- **Expected**: `200 OK`, body `{}`, header `Docker-Distribution-API-Version: registry/2.0`.
- **Edge cases**:
  - **e1**: anonymous call, anon pull enabled → 200 with version header.
  - **e2**: anonymous call, anon pull disabled → 401 + `WWW-Authenticate: Basic realm="Registry"` + error code `UNAUTHORIZED`.
  - **e3**: valid PAT in HTTP Basic, anon pull disabled → 200.
  - **e4**: invalid / expired PAT, anon pull disabled → 401.
  - **e5**: malformed `Authorization` header (e.g., Bearer token) → 401.

### UC-V2-002: Catalog list (`GET /v2/_catalog`)

- **Preconditions**: at least one repository exists.
- **Steps**: `GET /v2/_catalog?n=100`.
- **Expected**: 200, body `{repositories: [...]}`, `Link` header when more pages exist.
- **Edge cases**:
  - **e1**: empty registry → `{repositories: []}`.
  - **e2**: `n=0` → clamped to 1.
  - **e3**: `n=99999` → clamped to 1000.
  - **e4**: `last=<beyond-all-repos>` → empty array, no error.
  - **e5**: anonymous with anon pull disabled → 401.
  - **e6**: multi-segment namespace repo names (e.g., `org/team/repo`) appear correctly.
  - **e7**: pagination `Link` header format matches RFC 5988 `</v2/_catalog?last=X&n=Y>; rel="next"`.

### UC-V2-003: Tags list (`GET /v2/:name/tags/list`)

- **Preconditions**: repo exists with N tags.
- **Steps**: `GET /v2/<name>/tags/list?n=50`.
- **Expected**: 200, `{name: "...", tags: [...]}`, optional `Link` for pagination.
- **Edge cases**:
  - **e1**: unknown repo → 404 + `NAME_UNKNOWN`.
  - **e2**: repo with zero tags → `{name, tags: []}`.
  - **e3**: namespace repo (`org/repo`) resolves via route constraint.
  - **e4**: `n` clamped like catalog.
  - **e5**: pagination continues correctly across pages.

### UC-V2-004: Manifest pull by tag (`GET /v2/:name/manifests/:reference`)

- **Preconditions**: repo + tag + manifest exist.
- **Steps**: `GET /v2/<name>/manifests/<tag>`.
- **Expected**: 200, headers include `Docker-Content-Digest`, `Content-Type: application/vnd.docker.distribution.manifest.v2+json`, `Content-Length`. Body is manifest JSON. `pull_count` increments and a `PullEvent` is recorded.
- **Edge cases**:
  - **e1**: HEAD request — same headers, no body, no pull_count increment.
  - **e2**: unknown repo → 404 + `NAME_UNKNOWN`.
  - **e3**: unknown tag → 404 + `MANIFEST_UNKNOWN`.
  - **e4**: anon pull disabled + no creds → 401.
  - **e5**: reference is a digest (`sha256:...`) → resolves by digest.
  - **e6**: reference is a digest that doesn't exist → 404 + `MANIFEST_UNKNOWN`.
  - **e7**: PullEvent records remote_ip + user_agent + occurred_at.
  - **e8**: concurrent pulls — pull_count increments atomically.

### UC-V2-005: Manifest push (`PUT /v2/:name/manifests/:reference`) — happy path

- **Preconditions**: authenticated V2 client with write access; config + all layer blobs already uploaded.
- **Steps**: `PUT /v2/<name>/manifests/<tag>` with `Content-Type: application/vnd.docker.distribution.manifest.v2+json` and manifest JSON body.
- **Expected**: 201 Created, `Location: /v2/<name>/manifests/sha256:...`, `Docker-Content-Digest` header. Manifest + Tag + TagEvent(action: "create" or "update") created.
- **Edge cases**:
  - **e1**: unsupported media type (OCI index, schema v1, manifest list) → 415 + `UNSUPPORTED`.
  - **e2**: `schemaVersion != 2` in body → 400 + `MANIFEST_INVALID` + "unsupported schema version".
  - **e3**: config blob missing → 400 + `MANIFEST_INVALID` + "config blob not found".
  - **e4**: layer blob missing → 400 + `MANIFEST_INVALID` + "layer blob not found: <digest>".
  - **e5**: unauthenticated → 401 + `UNAUTHORIZED`.
  - **e6**: authenticated, no write access → 403 + `DENIED` + `insufficient_scope`.
  - **e7**: push to protected tag (semver / all_except_latest / custom_regex) with **different** digest → 409 + `DENIED` + detail {tag, policy}.
  - **e8**: push to protected tag with **same** digest (idempotent retry) → 201.
  - **e9**: first push to non-existent repo — authenticated user becomes owner.
  - **e10**: concurrent first-push race (two clients) — only one becomes owner; the other either succeeds as writer or 403.
  - **e11**: concurrent push to same tag with different digests — one 201, one 409 (TagProtected or version conflict).
  - **e12**: empty layers array (valid per spec) → 201.
  - **e13**: missing config field → 400 + `MANIFEST_INVALID`.
  - **e14**: malformed config JSON (blob content) → architecture/os fallback to nil; manifest still succeeds.
  - **e15**: namespace repo manifest push succeeds. **Note**: `config/routes.rb` defines `:name` and `:ns/:name` scopes only — three-segment names like `org/team/app` are intentionally rejected by route constraint. Two-segment form (`org/app`) is the supported maximum and is covered by `test/controllers/v2/manifest_push_edges_test.rb`. Original three-segment wording was a TEST_PLAN error, corrected 2026-04-24.
  - **e16**: Content-Type header mismatch with payload schema — schema check runs before content-type rejection.

### UC-V2-006: Manifest delete (`DELETE /v2/:name/manifests/:reference`)

- **Preconditions**: authenticated V2 client with delete access; manifest + tags exist.
- **Steps**: `DELETE /v2/<name>/manifests/<tag-or-digest>`.
- **Expected**: 202 Accepted. Manifest destroyed, tags cascade-deleted, TagEvents recorded, layer blob `references_count` decremented.
- **Edge cases**:
  - **e1**: tag protected by policy → 409 + `DENIED`.
  - **e2**: delete by digest that points to manifest with multiple tags — all tags cascade-deleted.
  - **e3**: unknown manifest → 404 + `MANIFEST_UNKNOWN`.
  - **e4**: unauthenticated → 401.
  - **e5**: authenticated writer (not admin/owner) → 403 + `DENIED`.
  - **e6**: blob reference counts drop to 0 — blobs remain (auto-cleanup by CleanupOrphanedBlobsJob).

### UC-V2-007: Blob pull (`GET /v2/:name/blobs/:digest`)

- **Preconditions**: blob exists in DB + BlobStore.
- **Steps**: `GET /v2/<name>/blobs/<digest>`.
- **Expected**: 200, headers `Docker-Content-Digest`, `Content-Length`, `Content-Type`. Body streams blob content.
- **Edge cases**:
  - **e1**: HEAD request → headers only, no body.
  - **e2**: unknown digest in DB → 404 + `BLOB_UNKNOWN`.
  - **e3**: digest in DB but file missing from BlobStore → treated as not existing → 404.
  - **e4**: anon pull disabled + no creds → 401.
  - **e5**: non-sha256 digest algorithm (structurally supported but rare).

### UC-V2-008: Blob delete (`DELETE /v2/:name/blobs/:digest`)

- **Preconditions**: authenticated V2 client with delete access.
- **Steps**: `DELETE /v2/<name>/blobs/<digest>`.
- **Expected**: 202 Accepted. Blob removed from DB + BlobStore.
- **Edge cases**:
  - **e1**: blob still referenced by a manifest — delete still succeeds (no cascade/check); subsequent pulls of that manifest 404 on blob.
  - **e2**: unknown digest → 404 + `BLOB_UNKNOWN`.
  - **e3**: unauthenticated → 401.
  - **e4**: writer (not admin/owner) → 403 + `DENIED`.
  - **e5**: blob file missing but DB row present → DB row removed, FS delete silent.

### UC-V2-009: Blob upload initiation (`POST /v2/:name/blobs/uploads`) — chunked start

- **Preconditions**: authenticated V2 client with write access (or will create repo + become owner).
- **Steps**: `POST /v2/<name>/blobs/uploads` (no params).
- **Expected**: 202 Accepted, headers `Docker-Upload-UUID`, `Location: /v2/<name>/blobs/uploads/<uuid>`, `Range: 0-0`.
- **Edge cases**:
  - **e1**: unauthenticated → 401.
  - **e2**: repo doesn't exist yet — repo auto-created, client identity becomes owner.
  - **e3**: first-pusher race — `RecordNotUnique` caught, loser still gets a valid upload session (authz gated at manifest PUT).

### UC-V2-010: Blob upload monolithic (`POST /v2/:name/blobs/uploads?digest=:digest` with body)

- **Preconditions**: authenticated V2 client with write access.
- **Steps**: `POST /v2/<name>/blobs/uploads?digest=sha256:...` with blob bytes.
- **Expected**: 201 Created, `Docker-Content-Digest`, `Location` to digest URI.
- **Edge cases**:
  - **e1**: body digest mismatches query digest → 400 + `DIGEST_INVALID`.
  - **e2**: empty body but `?digest` provided → 400 + `DIGEST_INVALID` (empty doesn't match).
  - **e3**: duplicate upload (blob already exists) → idempotent 201 (BlobStore.put short-circuits).

### UC-V2-011: Blob mount (`POST /v2/:name/blobs/uploads?mount=:digest&from=:other-repo`)

- **Preconditions**: authenticated V2 client with write access on target repo.
- **Steps**: `POST /v2/<name>/blobs/uploads?mount=sha256:...&from=<other>`.
- **Expected (success)**: 201 Created, `Location` to digest URI, source blob's `references_count` incremented.
- **Edge cases**:
  - **e1**: source blob missing → 202, falls back to chunked start (ignores mount).
  - **e2**: mount to same repo for an existing blob — succeeds, refs_count++ (dedup).
  - **e3**: `mount=` present but malformed → falls back to chunked start.
  - **e4**: DB row present but file missing from BlobStore → treated as not-existing, falls back.
  - **e5**: unauthenticated → 401.

### UC-V2-012: Chunked upload PATCH (`PATCH /v2/:name/blobs/uploads/:uuid`)

- **Preconditions**: active upload session.
- **Steps**: `PATCH /v2/<name>/blobs/uploads/<uuid>` with chunk bytes.
- **Expected**: 202, `Docker-Upload-UUID`, `Location`, `Range: 0-<byte_offset-1>`.
- **Edge cases**:
  - **e1**: unknown UUID → 404 + `BLOB_UPLOAD_UNKNOWN`.
  - **e2**: PATCH after session finalized → 404.
  - **e3**: empty chunk body → byte_offset unchanged; still 202.
  - **e4**: unauthenticated → 401.

### UC-V2-013: Chunked upload finalize (`PUT /v2/:name/blobs/uploads/:uuid?digest=:digest`)

- **Preconditions**: active upload session.
- **Steps**: `PUT /v2/<name>/blobs/uploads/<uuid>?digest=sha256:...` with optional final chunk.
- **Expected**: 201, `Docker-Content-Digest`, `Location` to digest URI; Blob + file created; BlobUpload row destroyed.
- **Edge cases**:
  - **e1**: digest mismatch vs uploaded bytes → 400 + `DIGEST_INVALID`.
  - **e2**: finalize with body-only (no prior PATCH) → valid, creates blob.
  - **e3**: finalize twice on same UUID → second 404 (`BLOB_UPLOAD_UNKNOWN`).
  - **e4**: `?digest` param missing → 400 + `DIGEST_INVALID`.
  - **e5**: unauthenticated → 401.

### UC-V2-014: Upload cancel (`DELETE /v2/:name/blobs/uploads/:uuid`)

- **Preconditions**: active upload session.
- **Steps**: `DELETE /v2/<name>/blobs/uploads/<uuid>`.
- **Expected**: 204 No Content. BlobStore upload dir + DB row removed.
- **Edge cases**:
  - **e1**: unknown UUID → 404 BLOB_UPLOAD_UNKNOWN. (Originally specced as "still 204 (idempotent)" — reality is 404 because `find_upload!` raises before the destroy can run; first DELETE is 204, second DELETE on the same UUID is 404. Rewritten 2026-04-24 after `test/controllers/v2/blob_upload_edges_test.rb` pinned actual behavior.)
  - **e2**: cancel then PATCH → 404.
  - **e3**: unauthenticated → 401.

### UC-V2-015: Error response format

- **Preconditions**: any failing V2 request.
- **Steps**: trigger any error (e.g., unknown repo).
- **Expected**: JSON body `{errors: [{code, message, detail}]}` per Docker distribution spec.
- **Edge cases**:
  - **e1**: all defined codes encountered — `BLOB_UNKNOWN`, `BLOB_UPLOAD_UNKNOWN`, `MANIFEST_UNKNOWN`, `MANIFEST_INVALID`, `NAME_UNKNOWN`, `DIGEST_INVALID`, `UNSUPPORTED`, `DENIED`, `UNAUTHORIZED`.
  - **e2**: `Docker-Distribution-API-Version` header always present even on error.
  - **e3**: 401 always carries `WWW-Authenticate: Basic realm="Registry"`.

### UC-V2-016: Tag protection atomicity

- **Preconditions**: repo with protected-tag policy; an existing tag pointing at a baseline manifest; two simultaneous PUT manifest requests against that tag.
- **Steps**: race them inside `repository.with_lock`.
- **Expected**: at most one new manifest row ever lands while the tag is mutated; the surviving tag never points at a digest that bypassed `enforce_tag_protection!`.
- **Edge cases**:
  - **e1**: both PUTs carry the **same digest** as the existing tag (idempotent CI retry) → both 201, no new Manifest row, tag unchanged.
  - **e2**: one PUT carries the **baseline digest** (idempotent path → 201), the other carries a **fresh digest** (denied path → 409 `DENIED`). Tag never flips to the loser's digest, no orphan Manifest row from the loser. The "both differ from baseline AND from each other" reading is unsatisfiable: `enforce_tag_protection!` denies *any* non-idempotent write to a protected tag, so symmetric-difference racers would both 409 with no atomicity signal to assert. The implemented baseline-vs-fresh shape is the only one that exercises the load-bearing invariant (protection check + `manifest.save!` atomic under `with_lock`).

---

## Web UI

### UC-UI-001: Repository list (`GET /`)

- **Preconditions**: any visitor.
- **Steps**: open `/`.
- **Expected**: grid of repositories renders; nav shows "Sign in" (anonymous) or email + Tokens + Sign out.
- **Edge cases**:
  - **e1**: zero repositories → "No repositories yet / Push an image to get started".
  - **e2**: 1000+ repos loaded in memory (no pagination) — perf is documented quirk.
  - **e3**: repo names with slashes (`org/repo`) render without broken links.
  - **e4**: description/maintainer with emoji, CJK, RTL text — no layout break, `line-clamp-2`.
  - **e5**: dark mode toggle persists across navigation.

### UC-UI-002: Repository search & sort

- **Preconditions**: at least one repo.
- **Steps**: type in search input; change sort dropdown.
- **Expected**: Turbo Frame `repositories` updates; 300ms debounce.
- **Edge cases**:
  - **e1**: zero results → "No results found" empty state.
  - **e2**: rapid typing — only one request fires per 300ms pause; no request cancellation between.
  - **e3**: Korean/Japanese/Arabic query matches via SQL LIKE.
  - **e4**: sort by name / size / pulls — results re-order correctly.
  - **e5**: scroll position lost on frame refresh (known pitfall).
  - **e6**: search query containing `/` matches multi-segment repo names.

### UC-UI-003: Repository detail (`GET /repositories/:name`)

- **Preconditions**: signed-in user; repo exists.
- **Steps**: navigate to repo page.
- **Expected**: metadata + tag list + protection policy badge + docker pull copy-button render.
- **Edge cases**:
  - **e1**: repo with zero tags → "No tags found" empty state.
  - **e2**: 100+ tags — mobile card stack vs. desktop table renders correctly.
  - **e3**: signed-out user accessing — Auth::Unauthenticated rescue → redirect to OAuth.
  - **e4**: clipboard copy on http (insecure context) — `navigator.clipboard` fails silently; console.error logged.
  - **e5**: repo name with `/` — route resolves; all links use `@repository.name`.

### UC-UI-004: Repository edit (`PATCH /repositories/:name`)

- **Preconditions**: signed-in user; open "Edit description & maintainer" summary.
- **Steps**: change description, maintainer, and/or tag-protection policy; submit.
- **Expected**: row updated; flash notice or inline errors.
- **Edge cases**:
  - **e1**: change policy to `custom_regex` — Stimulus `tag-protection` controller reveals regex input.
  - **e2**: set `custom_regex` with empty pattern → Rails validation error inline.
  - **e3**: invalid regex (unbalanced parens) → validation error.
  - **e4**: very long description (1000+ chars) → validated / line-clamped on cards.
  - **e5**: **known security gap**: unauthenticated authorization — any signed-in user (not just owner/admin) can submit; verify that current behavior persists until fixed, or that fix rejects non-writers with 403.
  - **e6**: CSRF token stripped → request rejected.
  - **e7**: policy switch from custom to semver — regex input hidden but DB pattern preserved.

### UC-UI-005: Repository delete (`DELETE /repositories/:name`)

- **Preconditions**: signed-in owner.
- **Steps**: click danger-zone delete, confirm Turbo dialog.
- **Expected**: repo + cascading tags/manifests destroyed; redirect to `/` with notice.
- **Edge cases**:
  - **e1**: non-owner attempt → ForbiddenAction rescue → alert flash.
  - **e2**: Turbo confirm dismissed → request not sent.
  - **e3**: concurrent delete while another user views repo → stale show page 404 on next action.
  - **e4**: unauthenticated attempt → redirect to OAuth.

### UC-UI-006: Tag detail (`GET /repositories/:name/tags/:tag`)

- **Preconditions**: signed-in user; tag + manifest exist.
- **Steps**: open tag page.
- **Expected**: manifest metadata, layer list, docker config JSON, copy pull command.
- **Edge cases**:
  - **e1**: `manifest.docker_config` is nil → section hidden.
  - **e2**: `docker_config` invalid JSON → raw string shown (rescue fallback).
  - **e3**: 100+ layers → scrollable layer list, mobile stacking works.
  - **e4**: protected tag → delete button rendered disabled with tooltip; clicking has no effect.
  - **e5**: tag with nil `bytes` → `human_size` returns "0 B".
  - **e6**: short_digest helper with nil → empty string.

### UC-UI-007: Tag delete (`DELETE /repositories/:name/tags/:tag`)

- **Preconditions**: signed-in user with delete access.
- **Steps**: danger zone → confirm.
- **Expected**: tag destroyed; TagEvent(delete) recorded; redirect to repo.
- **Edge cases**:
  - **e1**: protected tag — server-side enforce → flash alert (even if UI was bypassed).
  - **e2**: non-delete-access user → ForbiddenAction alert.
  - **e3**: viewing tag history during delete — history page 404 next request.

### UC-UI-008: Tag history (`GET /repositories/:name/tags/:tag/history`)

- **Preconditions**: signed-in; tag exists.
- **Steps**: click History link.
- **Expected**: event cards show action badges, previous/new digests, actor, occurred_at (minute precision).
- **Edge cases**:
  - **e1**: tag with zero events → "No history events" empty state.
  - **e2**: events missing `previous_digest` or `new_digest` → guards prevent nil display.
  - **e3**: multiple events within 1 second → ordered DESC by occurred_at.
  - **e4**: actor email shown (intentional PII surface).

### UC-UI-009: Help page (`GET /help`)

- **Preconditions**: any visitor.
- **Steps**: click Help link.
- **Expected**: setup snippets with interpolated registry host; multi-platform warning visible.
- **Edge cases**:
  - **e1**: registry_host config missing → nil renders in `<pre>` blocks (looks broken).
  - **e2**: dark-mode code blocks legible (bg-slate-900 / dark:text-blue-300).
  - **e3**: mobile: code blocks scroll horizontally.

### UC-UI-010: Dark mode toggle

- **Preconditions**: any visitor.
- **Steps**: click sun/moon icon in nav.
- **Expected**: `html.dark` class toggles; `localStorage.theme` written; icons swap.
- **Edge cases**:
  - **e1**: system prefers dark + no localStorage → dark applied on first paint.
  - **e2**: JS disabled → `prefers-color-scheme` still applies but FOUC likely.
  - **e3**: Turbo cache restores page — FOUC prevention script runs before stylesheet.
  - **e4**: badge contrast in dark mode (warning/accent variants).

### UC-UI-011: PAT index (`GET /settings/tokens`)

- **Preconditions**: signed-in user.
- **Steps**: open `/settings/tokens`.
- **Expected**: create-form + table of existing tokens with status badges.
- **Edge cases**:
  - **e1**: zero PATs → empty table.
  - **e2**: mix of Active/Expired/Revoked displayed with correct badges.
  - **e3**: signed-out → redirect to OAuth.
  - **e4**: many PATs — mobile table overflow.

### UC-UI-012: PAT create (`POST /settings/tokens`)

- **Preconditions**: signed-in user.
- **Steps**: submit form with name, kind, expires_in_days.
- **Expected**: raw token rendered once in flash `<pre>` block; row added to table.
- **Edge cases**:
  - **e1**: empty name → validation error flash.
  - **e2**: duplicate name for same identity → validation error (uniqueness per identity).
  - **e3**: `expires_in_days = 0 / -1 / "abc" / ""` → `parse_expires_in` returns nil (never-expires).
  - **e4**: `kind` not in `cli`/`ci` → validation error.
  - **e5**: raw_token shown in flash persists until next navigation (no "copy to clipboard" button on this screen).
  - **e6**: raw_token never retrievable again.

### UC-UI-013: PAT revoke (`DELETE /settings/tokens/:id`)

- **Preconditions**: signed-in user owns PAT.
- **Steps**: click Revoke → Turbo confirm.
- **Expected**: `revoked_at` set; row shows "Revoked" badge; redirect with notice.
- **Edge cases**:
  - **e1**: revoke another user's PAT by ID → 404 (scoped to current identity).
  - **e2**: revoke twice → second request still 200 (idempotent at controller) or 404.
  - **e3**: V2 request using revoked PAT next → 401.

---

## Auth

### UC-AUTH-001: Google OAuth sign-in happy path

- **Preconditions**: `google_oauth2` provider configured.
- **Steps**: click "Sign in with Google" → consent → callback.
- **Expected**: session created, `session[:user_id]` set, redirect to `/` with notice.
- **Edge cases**:
  - **e1**: existing user (same email) → identity linked; `reset_session` before assigning user_id.
  - **e2**: new user + admin email matches `REGISTRY_ADMIN_EMAIL` → `admin=true`.
  - **e3**: `email_verified=false` from Google → `Auth::EmailMismatch` → /auth/failure.
  - **e4**: invalid profile payload → /auth/failure with `invalid_profile`.
  - **e5**: OAuth provider timeout → `provider_outage` → /auth/failure.
  - **e6**: state parameter mismatch — `omniauth-rails_csrf_protection` rejects; verify integration.
  - **e7**: concurrent sign-in in two tabs — latter `reset_session` invalidates former.

### UC-AUTH-002: Sign out (`DELETE /auth/sign_out`)

- **Preconditions**: signed-in session.
- **Steps**: click Sign out.
- **Expected**: `reset_session`; redirect to `/`.
- **Edge cases**:
  - **e1**: not-signed-in → idempotent, still redirect.
  - **e2**: Turbo intercepts DELETE — verify button opts out of Turbo Drive (commit `6f4632e`).
  - **e3**: concurrent use in another tab → next request redirects to OAuth.

### UC-AUTH-003: OAuth failure (`GET /auth/failure`)

- **Preconditions**: failed OAuth callback (any reason).
- **Steps**: arrive at `/auth/failure`.
- **Expected**: flash alert includes strategy + message.
- **Edge cases**:
  - **e1**: `email_mismatch`, `invalid_profile`, `provider_outage` strategies distinct messages.
  - **e2**: XSS-in-message sanitization — Rails auto-escape must apply.

### UC-AUTH-004: V2 HTTP Basic — valid PAT

- **Preconditions**: PAT active, not expired, email matches identity.
- **Steps**: any V2 request with `Authorization: Basic base64(email:raw_pat)`.
- **Expected**: auth succeeds, `@current_user` set, `pat.last_used_at` updated, request proceeds.
- **Edge cases**:
  - **e1**: `last_used_at` updated via `update_column` (non-transactional).
  - **e2**: case-insensitive email match (GoogleAdapter lowercases).

### UC-AUTH-005: V2 HTTP Basic — invalid / missing

- **Preconditions**: varies.
- **Steps**: V2 request with bad creds.
- **Expected**: 401 + `WWW-Authenticate: Basic realm="Registry"` + `{errors: [{code: "UNAUTHORIZED", ...}]}`.
- **Edge cases**:
  - **e1**: no Authorization header → 401.
  - **e2**: Bearer token provided → 401 (no bearer support).
  - **e3**: malformed Basic (unparseable base64) → 401.
  - **e4**: empty email or PAT → 401 (early guard in `PatAuthenticator`).
  - **e5**: wrong email for PAT identity → `Auth::PatInvalid` → 401.
  - **e6**: case-mismatch email that normalizes equal → succeeds.
  - **e7**: valid email but unknown PAT → 401.

### UC-AUTH-006: Expired PAT

- **Preconditions**: PAT with `expires_at < now`.
- **Steps**: V2 request.
- **Expected**: 401 (`active` scope filters out).
- **Edge cases**:
  - **e1**: `expires_at` exactly now — boundary semantics per `active` scope.
  - **e2**: PAT with nil `expires_at` never expires.

### UC-AUTH-007: Revoked PAT

- **Preconditions**: PAT with `revoked_at` set.
- **Steps**: V2 request.
- **Expected**: 401.
- **Edge cases**:
  - **e1**: revoked mid-request — `update_column(:last_used_at)` may still run even though next auth 401s (non-atomic; observability only).
  - **e2**: revoke in Web UI while `docker push` active — next V2 hit 401, earlier in-flight may have already authenticated.

### UC-AUTH-008: Authorization — write access

- **Preconditions**: PAT belongs to identity that is not owner and not a writer/admin member.
- **Steps**: attempt manifest PUT or blob upload.
- **Expected**: 403 + `DENIED` + `insufficient_scope`.
- **Edge cases**:
  - **e1**: writer member → 201.
  - **e2**: admin member → 201.
  - **e3**: owner → 201.
  - **e4**: transfer ownership, previous owner becomes admin member — still writes succeed.

### UC-AUTH-009: Authorization — delete access

- **Preconditions**: as above.
- **Steps**: DELETE manifest/blob.
- **Expected**: 403 unless owner or admin.
- **Edge cases**:
  - **e1**: writer tries delete → 403.
  - **e2**: admin member → 202.
  - **e3**: owner → 202.

### UC-AUTH-010: Anonymous pull gating

- **Preconditions**: env var toggled.
- **Steps**: anonymous GET on whitelisted V2 endpoints.
- **Expected**: 200 when `REGISTRY_ANONYMOUS_PULL_ENABLED=true`; 401 when false.
- **Edge cases**:
  - **e1**: whitelist = base index, catalog, tags list, manifests show, blobs show (+HEAD).
  - **e2**: anonymous on a write endpoint (POST/PUT/PATCH/DELETE) → 401 regardless of flag.

### UC-AUTH-011: First-pusher repo creation

- **Preconditions**: authenticated client; repo does not exist.
- **Steps**: `POST /v2/<name>/blobs/uploads`.
- **Expected**: repo row created; `owner_identity_id` set to client's primary identity.
- **Edge cases**:
  - **e1**: two clients race — one wins ownership, other catches `RecordNotUnique` and still gets an upload session.
  - **e2**: client aborts before manifest PUT — repo exists but empty; CleanupOrphanedBlobsJob does not delete repos.
  - **e3**: manifest PUT from non-owner-writer after repo exists → authz gate enforced.

### UC-AUTH-012: Rack::Attack throttling

- **Preconditions**: none.
- **Steps**: flood requests.
- **Expected**:
  - `/auth/*` POST limited to 10 req/min/IP.
  - `/v2/*` non-GET/HEAD limited to 30 req/min/IP.
- **Edge cases**:
  - **e1**: valid PATs under heavy load — no per-PAT throttle (only IP).
  - **e2**: 429 response format.
  - **e3**: GET/HEAD on V2 not throttled.

### UC-AUTH-013: CSRF

- **Preconditions**: Web UI session.
- **Steps**: submit a form.
- **Expected**: CSRF token enforced; missing/invalid → rejected.
- **Edge cases**:
  - **e1**: OAuth callback (`Auth::SessionsController#create`) skips forgery protection — state param must validate (verify `omniauth-rails_csrf_protection`).
  - **e2**: V2 API endpoints skip CSRF (API context).
  - **e3**: Turbo form includes CSRF token automatically — verify.

### UC-AUTH-014: Tag protection bypass via blob mount

- **Preconditions**: repo with protected tag policy; attacker with write access.
- **Steps**: attempt to sneak a mutated blob via `POST /v2/<name>/blobs/uploads?mount=...`.
- **Expected**: blob-mount itself does not touch tags; the protected tag's manifest still points at original digest. Tag protection is only enforced at manifest PUT.
- **Edge cases**:
  - **e1**: confirm no mutation of existing tags via mount.
  - **e2**: mount + subsequent manifest PUT to protected tag → 409.

### UC-AUTH-015: Repository visibility

- **Status**: ✅ BY-DESIGN. This application is single-tenant / public-only by intent. There is no private/public gating in the data model (no `Repository#visibility` column, no `Membership#viewer` role) because the operational pattern is "every authenticated user inside the trust boundary may read every repo." If this ever changes, the data model + every list/show controller need a coordinated migration; that would be a Pipeline-Phases feature, not a test gap.
- **Preconditions**: any signed-in or anonymous user.
- **Steps**: `GET /repositories` and `GET /repositories/:name`.
- **Expected**: all repos visible to everyone (no per-repo gating).
- **Edge cases**:
  - **e1**: anonymous user — `RepositoriesController#index`/`#show` have no auth filter (locked in by `test/controllers/repositories_controller_test.rb` "GET /repositories/:name renders for anonymous" + "GET / renders empty state for anonymous").
  - **e2**: threat-model rationale — single-tenant deployment; see Wave 6 closure note in `docs/qa-audit/QA_REPORT.md`.

### UC-AUTH-016: Session cookie hygiene

- **Preconditions**: Rails 8.1 defaults.
- **Steps**: inspect `Set-Cookie` on sign-in.
- **Expected**: HTTP-only, SameSite=Lax (Rails default).
- **Edge cases**:
  - **e1**: Secure flag set when served over HTTPS.
  - **e2**: stale `session[:user_id]` (user deleted) — `current_user` helper clears session.

### UC-AUTH-017: Email verification at sign-in

- **Preconditions**: first-time OAuth.
- **Steps**: Google returns `email_verified=true/false`.
- **Expected**: true → account created; false → `Auth::EmailMismatch`.
- **Edge cases**:
  - **e1**: existing user with verified email tries re-sign-in → succeeds.
  - **e2**: email changed at Google after account creation — `email_verified` not re-verified (known gap).

---

## Jobs

### UC-JOB-001: CleanupOrphanedBlobsJob

- **Preconditions**: SolidQueue running; orphan data exists.
- **Steps**: trigger job (cron or manually).
- **Expected**: Blobs with `references_count=0` removed from DB + FS; Manifests without Tags destroyed; upload sessions older than 1 hour cleaned.
- **Edge cases**:
  - **e1**: blob refs_count incremented mid-loop — reload before destroy re-checks and skips.
  - **e2**: batch interruption — next run continues (BATCH_SIZE=100).
  - **e3**: blob file missing, DB row present → FileUtils.rm_f silent.
  - **e4**: blob file present, DB row gone — not addressed by this job (known FS drift).
  - **e5**: stale upload dir with unparseable timestamp → skipped silently.
  - **e6**: stale upload across DST / timezone change.

### UC-JOB-002: EnforceRetentionPolicyJob

- **Preconditions**: `RETENTION_ENABLED=true`.
- **Steps**: run job.
- **Expected**: for each manifest past threshold, delete each unprotected tag via TagEvent(action: "delete", actor: "retention-policy"); protected and `latest` tags (when `RETENTION_PROTECT_LATEST=true`) skipped.
- **Edge cases**:
  - **e1**: `RETENTION_ENABLED=false` (default) → no-op.
  - **e2**: `RETENTION_ENABLED` lowercase `"true"` vs any other value — case-sensitive string check.
  - **e3**: ENV coercion — non-numeric `RETENTION_DAYS_WITHOUT_PULL` → `to_i` returns 0 → all manifests match.
  - **e4**: manifest with `last_pulled_at=NULL` + `pull_count=0` → matches (OR with NULL).
  - **e5**: `semver` policy — `v1.0.0`, `v1`, `v1.0`, `v1.0.0-rc`, `v1.0.0+build` boundary matches.
  - **e6**: `all_except_latest` — only `latest` protected.
  - **e7**: `custom_regex` — invalid regex causes job error? confirm rescue path.
  - **e8**: multiple tags on same manifest — each evaluated independently.
  - **e9**: concurrent tag delete by user — `manifest.tags.find_each` re-queries safely.
  - **e10**: retention actor string, not Identity instance → TagEvent accepts string.

### UC-JOB-003: PruneOldEventsJob

- **Preconditions**: PullEvents older than 90 days exist.
- **Steps**: run job.
- **Expected**: rows older than 90 days removed via `in_batches.delete_all`.
- **Edge cases**:
  - **e1**: boundary — event exactly 90 days old NOT pruned (strict `<`).
  - **e2**: zero old events — silent no-op.
  - **e3**: large dataset — batched automatically.
  - **e4**: concurrent PullEvent inserts during prune — safe.
  - **e5**: **no dedicated test file exists** — verify behavior manually.

---

## Model / Service

### UC-MODEL-001: Repository

- **Preconditions**: DB writable.
- **Steps**: create repo with name.
- **Expected**: unique name enforced; `tag_protection_pattern` required when policy is `custom_regex`.
- **Edge cases**:
  - **e1**: create with duplicate name → validation fails.
  - **e2**: switch policy from `custom_regex` to `none` → pattern cleared by callback.
  - **e3**: invalid regex → validation fails (`Regexp.new` test).
  - **e4**: `tag_protected?(tag_name)` across all policy types.
  - **e5**: `enforce_tag_protection!` with same digest → no raise.
  - **e6**: `writable_by?(identity)` / `deletable_by?(identity)` — owner, writer, admin member.

### UC-MODEL-002: PersonalAccessToken

- **Preconditions**: identity exists.
- **Steps**: create PAT.
- **Expected**: raw token `oprk_`+urlsafe_base64(32); digest stored; `active` scope filters expired/revoked.
- **Edge cases**:
  - **e1**: name uniqueness per identity.
  - **e2**: `authenticate_raw("")` returns nil.
  - **e3**: `authenticate_raw(valid)` returns PAT; updates `last_used_at` via `update_column`.
  - **e4**: `revoke!` sets `revoked_at`, removes from `active`.
  - **e5**: token_digest uniqueness (collision effectively impossible but constrained).

### UC-MODEL-003: Identity

- **Preconditions**: user exists.
- **Steps**: create identity with provider + uid.
- **Expected**: `uid` uniqueness per provider; `email` presence.
- **Edge cases**:
  - **e1**: same uid different provider → OK.
  - **e2**: duplicate (provider, uid) → fails.
  - **e3**: destroy identity cascades to PATs and RepositoryMembers.

### UC-MODEL-004: Manifest / Layer / Blob

- **Preconditions**: schema up.
- **Steps**: create manifest via ManifestProcessor.
- **Expected**: layers ordered by position; blob refs_count incremented; destroy manifest cascades layers.
- **Edge cases**:
  - **e1**: unique (manifest_id, position) / (manifest_id, blob_id).
  - **e2**: blob refs_count decremented when layers destroyed.
  - **e3**: manifest digest uniqueness.
  - **e4**: tags nullify (not destroy) when manifest destroyed (but V2 DELETE cascades via controller).

### UC-MODEL-005: TagEvent / PullEvent

- **Preconditions**: tag + manifest mutations.
- **Steps**: push/delete tag, pull manifest.
- **Expected**: TagEvent records action + digests + actor; PullEvent records user_agent/remote_ip/occurred_at.
- **Edge cases**:
  - **e1**: TagEvent with string actor (retention job).
  - **e2**: PullEvent pruning boundary.
  - **e3**: tag history ordering (DESC by occurred_at).
  - **e4**: ownership_transfer action creates TagEvent.

### UC-MODEL-006: RepositoryMember

- **Preconditions**: repo + identity.
- **Steps**: add member with role.
- **Expected**: role ∈ `writer`, `admin`; unique (repo, identity).
- **Edge cases**:
  - **e1**: duplicate membership blocked.
  - **e2**: `transfer_ownership_to!` adds previous owner as admin member atomically.
  - **e3**: orphaned members after multiple transfers — known question.

### UC-MODEL-007: BlobStore service

- **Preconditions**: configured root path.
- **Steps**: put / get / exists? / delete / create_upload / append_upload / finalize_upload / cancel_upload / cleanup_stale_uploads.
- **Expected**: atomic rename on finalize; sharded path by digest.
- **Edge cases**:
  - **e1**: `put` idempotent when target exists.
  - **e2**: `finalize_upload` digest verification fails → raise `DigestMismatch`; upload dir NOT cleaned (manual cancel).
  - **e3**: IO without `rewind` (nil io).
  - **e4**: large blobs streamed in 64KB chunks.
  - **e5**: filesystem full mid-write → rescue cleans tmp.
  - **e6**: stale upload sweep uses `max_age.ago` comparison.

### UC-MODEL-008: DigestCalculator service

- **Preconditions**: io or string.
- **Steps**: `compute`, `verify!`.
- **Expected**: `sha256:<hex>`; rewinds io.
- **Edge cases**:
  - **e1**: string input.
  - **e2**: File vs StringIO rewind.
  - **e3**: verify! mismatch raises `DigestMismatch`.
  - **e4**: large IO memory-efficient (64KB chunks).

### UC-MODEL-009: ManifestProcessor service

- **Preconditions**: payload + config/layer blobs uploaded.
- **Steps**: `call(repo_name, reference, content_type, payload, actor:)`.
- **Expected**: repo create/find; manifest find_or_initialize by digest; layers created; tag updated; TagEvent; inside `repository.with_lock`.
- **Edge cases**:
  - **e1**: unsupported media type → `ManifestInvalid`.
  - **e2**: `schemaVersion != 2` → `ManifestInvalid`.
  - **e3**: config blob missing → `ManifestInvalid` before writes.
  - **e4**: layer blob missing → `ManifestInvalid`.
  - **e5**: protected tag different digest → `TagProtected` raised inside lock.
  - **e6**: protected tag same digest → idempotent pass.
  - **e7**: malformed config JSON → `{architecture: nil, os: nil, config_json: nil}` fallback.
  - **e8**: concurrent same-digest pushes → find_or_initialize safe under lock.
  - **e9**: concurrent different-digest same-tag → one succeeds, others TagProtected.
  - **e10**: missing admin email on repo creation → `RecordNotFound` (unrescued, deployment error).
  - **e11**: Blob `references_count` incremented per layer.
  - **e12**: payload bytesize stored as manifest.size.
  - **e13**: tag retry idempotency (CI) — no spurious TagEvent.
