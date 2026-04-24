# Docker Registry — User Manual

## Overview

This application is a self-hosted Docker V2 container image registry implemented in Rails 8.1, paired with a web UI for browsing and administering repositories. Operators use it to host private (or internal) Docker images, push/pull them with the standard `docker` CLI, and manage access via Google sign-in and Personal Access Tokens (PATs). The target reader is a new operator standing up or using this registry day-to-day.

Single-platform Docker V2 images only. Multi-arch / OCI index / manifest list images are rejected (HTTP 415).

---

## Part 1 — Docker Client (V2 Registry API)

All paths below are rooted at the registry host (e.g., `registry.example.com`). Responses follow the [Docker Registry HTTP API V2 spec](https://docs.docker.com/registry/spec/api/). The header `Docker-Distribution-API-Version: registry/2.0` is always returned on V2 endpoints.

### 1.1 Ping / Version Check

- **What the user does**: implicitly, `docker` CLI issues `GET /v2/` on first contact.
- **Endpoints fired**: `GET /v2/`
- **Preconditions**: service is running. No credentials needed when `REGISTRY_ANONYMOUS_PULL_ENABLED=true` (default).
- **Observable outcome**:
  - Anonymous pull enabled → `200 OK`, body `{}`, header `Docker-Distribution-API-Version: registry/2.0`.
  - Anonymous pull disabled → `401 Unauthorized`, header `WWW-Authenticate: Basic realm="Registry"`, error code `UNAUTHORIZED`.

### 1.2 Catalog / Discovery

- **What the user does**: `curl https://<host>/v2/_catalog` or `docker search` (client-specific).
- **Endpoints fired**:
  - `GET /v2/_catalog?n=<page_size>&last=<last_repo>` — list repositories
  - `GET /v2/<name>/tags/list?n=<page_size>&last=<last_tag>` — list tags per repo
- **Preconditions**: none (anonymous pull) or valid PAT in HTTP Basic.
- **Observable outcome**: JSON `{repositories: [...]}` / `{name: "...", tags: [...]}`; `Link` header with `rel="next"` when more pages exist. `n` is clamped to `[1, 1000]` (default 100).

### 1.3 Pull Flow (Monolithic)

- **What the user does**: `docker pull <host>/<name>:<tag>`
- **Endpoints fired**:
  1. `GET /v2/<name>/manifests/<tag>` (accept header for manifest v2)
  2. `GET /v2/<name>/blobs/<config-digest>` (image config)
  3. `GET /v2/<name>/blobs/<layer-digest>` for each layer
- **Preconditions**: repo must exist; anonymous pull is allowed by default.
- **Observable outcome**: manifest returns `Docker-Content-Digest`, `Content-Type: application/vnd.docker.distribution.manifest.v2+json`. Blobs stream with `Content-Length` and `Content-Type`. Each manifest GET (not HEAD) increments `pull_count` and records a `PullEvent`.

### 1.4 Push Flow (Monolithic)

- **What the user does**: `docker push <host>/<name>:<tag>` (small layers auto-use monolithic).
- **Endpoints fired** (per blob):
  - `POST /v2/<name>/blobs/uploads?digest=<digest>` with blob bytes as body
  - Finally `PUT /v2/<name>/manifests/<tag>` with manifest JSON
- **Preconditions**: `docker login` with email + PAT; PAT identity must have write access (owner or writer/admin member) on the repo. First pusher becomes repository owner (repo is auto-created on first blob upload).
- **Observable outcome**: `201 Created` + `Location` header pointing at the digest URL.

### 1.5 Push Flow (Chunked)

- **What the user does**: `docker push` with larger layers — CLI automatically uses chunked upload.
- **Endpoints fired**:
  1. `POST /v2/<name>/blobs/uploads` → get `Docker-Upload-UUID`, `Location`, initial `Range`
  2. `PATCH /v2/<name>/blobs/uploads/<uuid>` with each chunk (repeat)
  3. `PUT /v2/<name>/blobs/uploads/<uuid>?digest=<digest>` with final chunk to finalize
  4. `PUT /v2/<name>/manifests/<tag>` after all blobs uploaded
- **Preconditions**: authenticated + write access, same as monolithic.
- **Observable outcome**: each PATCH returns `202 Accepted` with updated `Range: 0-<byte_offset-1>`. Final PUT returns `201` with `Docker-Content-Digest` + `Location`.

### 1.6 Blob Mount (Cross-Repo Reuse)

- **What the user does**: typically invisible — `docker push` detects a blob that already exists elsewhere and asks the registry to reuse it.
- **Endpoints fired**: `POST /v2/<name>/blobs/uploads?mount=<digest>&from=<other-repo>`
- **Preconditions**: authenticated + write access on target repo.
- **Observable outcome**:
  - Source blob exists on disk and in DB → `201 Created`, mount succeeds, `references_count` incremented, no upload needed.
  - Source blob not found → `202 Accepted`, silently falls back to a normal chunked-upload start.

### 1.7 Delete Flow

- **What the user does**: no standard `docker` CLI verb; typically via `curl` or web UI.
- **Endpoints fired**:
  - `DELETE /v2/<name>/manifests/<tag-or-digest>` → removes manifest + tags (`202 Accepted`)
  - `DELETE /v2/<name>/blobs/<digest>` → removes blob from DB + filesystem (`202 Accepted`)
- **Preconditions**: authenticated + delete access (owner or admin member). No tag protection hit.
- **Observable outcome**:
  - Tag protected by policy → `409 Conflict`, code `DENIED`, detail includes tag + policy.
  - `DELETE` blob does **not** check references — caller must ensure the blob is truly unreferenced.

### 1.8 Upload Cancellation

- **What the user does**: CLI may cancel an in-flight chunked upload.
- **Endpoints fired**: `DELETE /v2/<name>/blobs/uploads/<uuid>`
- **Preconditions**: authenticated.
- **Observable outcome**: `204 No Content`; BlobStore upload dir and DB record removed. Idempotent.

### 1.9 Authentication (Docker client)

- Docker client authenticates via **HTTP Basic**: `Authorization: Basic base64(email:raw_pat)`.
- There is **no token-issuing endpoint** (no `/v2/token`). PAT = password substitute.
- On failure: `401 Unauthorized` with `WWW-Authenticate: Basic realm="Registry"`, error code `UNAUTHORIZED`.
- Insufficient scope (authenticated but lacks write/delete): `403 Forbidden`, error code `DENIED`, detail `insufficient_scope`.

**Note:** The discovery `auth.md` states Docker V2 authentication is HTTP Basic only. The `v2-api.md` mentions "bearer challenges" in the edge cases section but no bearer flow is actually implemented — the challenge returned is always `Basic realm="Registry"`. Treat HTTP Basic as the sole mechanism.

---

## Part 2 — Web UI

All routes are served by the same Rails app. Dark mode is available on every page via a nav toggle (persisted in `localStorage`, honors `prefers-color-scheme`).

### 2.1 Home / Repository List — `GET /`

- **How to reach it**: the root of the site.
- **Role**: public. Anonymous users see a "Sign in with Google" button; signed-in users see email, Tokens link, Sign out.
- **What the user can do**: browse the full grid of repositories; search by name/description/maintainer; sort by name, size, or pulls.
- **Key interactions**:
  - Stimulus `search_controller` debounces typing at 300ms; submits the search form to a Turbo Frame named `repositories`.
  - Sort dropdown change triggers the same frame refresh.
  - Empty-state copy appears when no repos exist or search yields zero results.

### 2.2 Repository Detail — `GET /repositories/:name`

- **How to reach it**: click a repo card on the home page, or navigate directly.
- **Role**: signed-in required.
- **What the user can do**:
  - View repo metadata, tag list, owner, maintainer, description, size, pulls, tag-protection policy.
  - Copy a `docker pull` command for the latest tag (clipboard Stimulus controller).
  - Edit description, maintainer, and tag-protection policy (collapsible form, `PATCH /repositories/:name`).
  - Delete the repository (danger zone, Turbo confirm, `DELETE /repositories/:name`).
- **Key interactions**:
  - `tag_protection_controller` Stimulus: shows/hides the regex input when policy is `custom_regex`.
  - Delete buttons for protected tags render as disabled span with `cursor-not-allowed` and `title` tooltip.

**Note:** The `auth.md` discovery flags that `RepositoriesController#update` (the PATCH endpoint used by the edit form) is missing `authorize_for!(:write)` — any authenticated user can update settings. This is a known security finding (HIGH), not a documented feature.

### 2.3 Tag Detail — `GET /repositories/:name/tags/:tag`

- **How to reach it**: click a tag name in the repo's tag list.
- **Role**: signed-in required.
- **What the user can do**:
  - Inspect manifest digest, size, architecture, OS, pull count, last pulled time.
  - View the ordered layer stack (position, size, digest).
  - View parsed docker config JSON (falls back to raw string on parse error).
  - Copy `docker pull` command.
  - Delete the tag (danger zone; disabled if protected).
- **Key interactions**: `clipboard_controller`, Turbo confirmation on delete, inline "Copied!" feedback for 2s.

### 2.4 Tag History — `GET /repositories/:name/tags/:tag/history`

- **How to reach it**: "History" link from tag detail.
- **Role**: signed-in required.
- **What the user can do**: see the audit trail of create/update/delete/ownership_transfer events with previous and new digests, actor, timestamp (minute precision).

### 2.5 Help / Setup Guide — `GET /help`

- **How to reach it**: "Help" link in the nav.
- **Role**: public.
- **What the user can do**: read setup snippets for Docker daemon insecure-registry config, push/pull usage, Kubernetes/containerd mirror config, nginx reverse proxy TLS, and the warning about single-platform-only support. The registry host is interpolated from config into every code block.

### 2.6 Personal Access Tokens — `GET /settings/tokens`

- **How to reach it**: "Tokens" link in nav (signed-in only).
- **Role**: signed-in required; users only see their own PATs.
- **What the user can do**:
  - Create a new token (name, kind=CLI or CI, optional `expires_in_days`). The **raw token is shown once** in a flash `<pre>` block — copy manually.
  - View table of existing tokens with status Active / Expired / Revoked, last-used, expires-at.
  - Revoke a token (`DELETE /settings/tokens/:id`, Turbo confirm).

### 2.7 Auth Pages

- `GET /auth/:provider/callback` — Google OAuth2 callback handler.
- `GET /auth/failure` — OAuth failure page with flash alert.
- `DELETE /auth/sign_out` — sign out, session reset, redirect to `/`.

---

## Part 3 — Authentication & Accounts

### 3.1 Signing in with Google OAuth

1. Click "Sign in with Google" in the nav.
2. Rails redirects to `POST /auth/google_oauth2` → Google consent screen.
3. Google returns to `GET /auth/google_oauth2/callback`.
4. The controller verifies `email_verified=true` from Google. On success: `reset_session`, store `session[:user_id]`, redirect to `/` with a "Signed in as {email}" notice.
5. On failure (e.g., `email_mismatch`, `invalid_profile`, `provider_outage`): redirect to `/auth/failure`.

Admin users: if the signed-in email matches `REGISTRY_ADMIN_EMAIL`, the `admin` flag is set at account creation.

### 3.2 Creating & Managing Personal Access Tokens (PATs)

- Go to `/settings/tokens` while signed in.
- Fill in **Name**, **Kind** (`cli` or `ci`), optional **expires_in_days**.
- On success the **raw token** (`oprk_` prefix + 32 bytes urlsafe base64) is shown once in a flash message. Copy it immediately — only the SHA256 digest is persisted.
- Tokens are bound to the user's **identity** (currently Google). Each active PAT grants the full write/delete scope of that identity.
- To revoke, click "Revoke" in the PAT table — sets `revoked_at`, removes from the `active` scope; subsequent V2 auth attempts will 401.

### 3.3 Roles & Permissions

Access is identity-based, per-repository:

| Role | Rule |
|------|------|
| **Owner** | The first identity to push a blob to the repo. Can read, push, delete, transfer ownership, edit settings, delete the repo. |
| **Writer** member (`RepositoryMember.role = "writer"`) | Read + push. Cannot delete the repo or tags/manifests. |
| **Admin** member (`RepositoryMember.role = "admin"`) | Read + push + delete. Cannot transfer ownership. |
| **Authenticated non-member** | Read only (pull, catalog, tags). |
| **Anonymous** | Read only **when** `REGISTRY_ANONYMOUS_PULL_ENABLED=true` (default). Otherwise 401 on GET. |

Web UI does not currently gate list/show visibility — all authenticated users can see every repo.

### 3.4 How `docker login` Works with PATs

```
docker login <host>
Username: you@example.com
Password: oprk_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

Docker stores credentials in `~/.docker/config.json`. On every V2 request, it sends `Authorization: Basic base64(email:pat)`. The registry:

1. Extracts email + raw PAT from the header.
2. SHA256-hashes the PAT and looks up an **active** `PersonalAccessToken`.
3. Verifies the email matches the PAT identity's user email (case-insensitive).
4. Sets `@current_user`, `@current_pat`, and updates `last_used_at`.

Failures (missing header, expired/revoked/unknown PAT, email mismatch, blank email/token) all return `401` + `WWW-Authenticate: Basic realm="Registry"`.

### 3.5 Signing Out

Click "Sign out" in nav → `DELETE /auth/sign_out` → `reset_session` → redirect to `/` with a notice. The sign-out button opts out of Turbo Drive so the DELETE is always delivered.

---

## Part 4 — Administration / Background Tasks

Background jobs run under SolidQueue via `config/recurring.yml`.

### 4.1 CleanupOrphanedBlobsJob

- **Cadence**: every 30 minutes.
- **What it does**:
  - Deletes `Blob` rows (and filesystem entries) where `references_count == 0`.
  - Destroys `Manifest` rows that no longer have any `Tag` (orphans).
  - Calls `BlobStore.cleanup_stale_uploads(max_age: 1.hour)` to sweep abandoned upload session dirs.
- Batched (`BATCH_SIZE=100`); reloads each blob inside the loop so a concurrent increment is race-safe.

### 4.2 EnforceRetentionPolicyJob

- **Cadence**: daily at 03:00.
- **What it does**: only runs when `RETENTION_ENABLED=true`. For every manifest with `last_pulled_at < RETENTION_DAYS_WITHOUT_PULL` days ago (default 90) OR `pull_count < RETENTION_MIN_PULL_COUNT` (default 5), deletes each unprotected tag via `TagEvent.create!(action: "delete", actor: "retention-policy")`.
- **Protections honored**: the repo's `tag_protection_policy` (none, semver, all_except_latest, custom_regex). `RETENTION_PROTECT_LATEST=true` (default) also spares the `latest` tag.

### 4.3 PruneOldEventsJob

- **Cadence**: daily at 04:00.
- **What it does**: batch-deletes `PullEvent` rows older than 90 days (`in_batches.delete_all`). Silent no-op when nothing to prune.

### 4.4 Tag Protection & Retention Configuration

- **Per-repo** via the web UI (Repository Detail → edit form):
  - Policy dropdown: `none`, `semver`, `all_except_latest`, `custom_regex`.
  - Custom regex input appears only when `custom_regex` is selected (Stimulus toggle); stored in `repository.tag_protection_pattern`.
- **Global** via environment variables:
  - `RETENTION_ENABLED` (default `false`)
  - `RETENTION_DAYS_WITHOUT_PULL` (default `90`)
  - `RETENTION_MIN_PULL_COUNT` (default `5`)
  - `RETENTION_PROTECT_LATEST` (default `true`)
  - `REGISTRY_ANONYMOUS_PULL_ENABLED` (default `true`)
  - `REGISTRY_ADMIN_EMAIL` (sets the admin flag on sign-in for a matching email)

### 4.5 Audit Logs

- **Tag events** (`TagEvent`): every create/update/delete/ownership_transfer on a tag is recorded with `tag_name`, `action`, `previous_digest`, `new_digest`, `actor`, `actor_identity_id`, `occurred_at`. Retained indefinitely (not pruned). Viewable at `GET /repositories/:name/tags/:tag/history`.
- **Pull events** (`PullEvent`): every manifest GET (not HEAD) records user_agent, remote_ip, occurred_at. Used to drive retention and analytics. Pruned after 90 days by `PruneOldEventsJob`. No direct UI view; surfaced indirectly via manifest `pull_count` and `last_pulled_at` on tag detail.
- **Auth events** (sign-in, sign-out, PAT create/revoke): **not audit-logged** — only `Rails.logger.warn` on failures. Known observability gap.
