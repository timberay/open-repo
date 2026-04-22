# Open Repo

A self-hosted Docker Registry V2 server with a web management UI, built with Ruby on Rails 8. Designed for internal teams to store, manage, and serve build images used by Jenkins, Kubernetes, and CI/CD pipelines.

---

## Table of Contents

- [Overview](#overview)
- [Technology Stack](#technology-stack)
- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [Configuration](#configuration)
- [Development](#development)
- [Usage](#usage)
- [Web UI Features](#web-ui-features)
- [Docker Registry V2 API](#docker-registry-v2-api)
- [Service Layer (Internal)](#service-layer-internal)
- [Data Models](#data-models)
- [Background Jobs](#background-jobs)
- [Retention Policy](#retention-policy)
- [Garbage Collection](#garbage-collection)
- [Pull Tracking & Audit Log](#pull-tracking--audit-log)
- [Testing](#testing)
- [Deployment](#deployment)
- [Project Structure](#project-structure)
- [License](#license)

---

## Overview

Open Repo exposes two surfaces on top of the same storage backend:

- **Docker CLI surface** — a Docker Registry V2-compliant API for `docker push` / `docker pull`, with chunked uploads, cross-repo blob mount, HEAD manifest, and pagination.
- **Web UI surface** — a Hotwire-powered management console to browse repositories, inspect manifests/layers/configs, edit metadata, enforce tag protection, review audit logs, and import/export images as tar files.

Everything runs on a single Rails monolith with SQLite (Solid Cache/Queue/Cable), so there is no Redis, no Sidekiq, no external broker required.

### Top-level Features

- **Docker Registry V2 API** — full `docker push` / `docker pull` support with monolithic & chunked uploads, cross-repo blob mount, HEAD manifest, and Docker-spec-compliant error bodies.
- **Web UI** — browse repositories and tags, view image config (OS, arch, env, cmd), edit descriptions/maintainers, configure tag protection policies, copy pull commands, and review per-tag change history.
- **Image Import/Export** — upload/download Docker images as tar files via async background jobs (compatible with `docker save` / `docker load`).
- **Pull Tracking** — per-manifest pull counts, last-pulled timestamp, and detailed `PullEvent` history (IP, user agent, tag name).
- **Tag Audit Log** — immutable `TagEvent` records for tag create/update/delete with previous and new digests.
- **Tag Comparison** — diff layers and config between two manifests (`TagDiffService`).
- **Dependency Graph** — identify repositories sharing layer blobs to assess deletion impact and blob-mount opportunities (`DependencyAnalyzer`).
- **Tag Protection** — four policy modes (`none` / `semver` / `all_except_latest` / `custom_regex`) enforced inside a row-locked transaction, with idempotent push support for CI retry safety.
- **Garbage Collection** — reference-counted blobs, orphan manifest cleanup, stale upload cleanup, expired export cleanup.
- **Retention Policy** — configurable auto-expiration of unused images based on pull activity; honors tag protection.
- **Dark Mode** — responsive TailwindCSS design with a Stimulus-powered light/dark toggle and FOUC prevention.

---

## Technology Stack

| Layer | Technology |
|-------|-----------|
| Framework | Ruby on Rails 8.1 |
| Language | Ruby 3.4 |
| Frontend | Hotwire (Turbo + Stimulus) |
| Styling | TailwindCSS |
| Database | SQLite3 |
| Cache | Solid Cache |
| Background Jobs | Solid Queue |
| Action Cable | Solid Cable |
| Blob Storage | Local filesystem (content-addressable) |
| Backend Tests | RSpec |
| E2E Tests | Playwright |
| Proxy (production) | Thruster in front of Puma |
| Deployment | Kamal 2 or Docker Compose |

---

## Prerequisites

- Ruby 3.4+
- Node.js 18+ and npm
- SQLite3

---

## Installation

```bash
bundle install
npm install
bin/rails db:prepare
```

---

## Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `STORAGE_PATH` | `storage/registry` | Blob storage root directory |
| `REGISTRY_HOST` | `localhost:3000` | Hostname shown in `docker pull` commands in the UI |
| `SENDFILE_HEADER` | _(none)_ | `X-Accel-Redirect` (Nginx) or `X-Sendfile` (Apache) for zero-copy blob downloads |
| `PUMA_THREADS` | `16` | Puma thread count (increase for concurrent pulls) |
| `PUMA_WORKERS` | `2` | Puma worker count |
| `RETENTION_ENABLED` | `false` | Master switch for retention policy |
| `RETENTION_DAYS_WITHOUT_PULL` | `90` | Days without a pull before a manifest is eligible for expiration |
| `RETENTION_MIN_PULL_COUNT` | `5` | Manifests with fewer total pulls than this are eligible |
| `RETENTION_PROTECT_LATEST` | `true` | Never auto-delete the `latest` tag |

---

## Development

```bash
bin/dev
```

Starts the Rails server on http://localhost:3000 with the TailwindCSS watcher.

---

## Usage

### Push and Pull Images

```bash
# Tag and push
docker tag myimage:v1 localhost:3000/myimage:v1
docker push localhost:3000/myimage:v1

# Pull
docker pull localhost:3000/myimage:v1
```

> **Note:** For HTTP registries (non-TLS), add `"insecure-registries": ["localhost:3000"]` to `/etc/docker/daemon.json` and restart Docker. See the in-app Help page for Kubernetes/containerd setup.

### Web UI

- **http://localhost:3000** — repository list with real-time search and sort
- **Repository detail** — tag table, pull counts, pull-command copy button, metadata editor, tag protection configuration
- **Tag detail** — manifest info, image config (JSON), layer list, history link
- **Tag history** — timestamped audit log of create/update/delete events with previous/new digests
- **Help page** — Docker daemon, Kubernetes, and Nginx configuration guides

### Registry V2 API Examples

```bash
# Version check
curl http://localhost:3000/v2/

# List repositories (paginated via ?n=&last=)
curl http://localhost:3000/v2/_catalog

# List tags
curl http://localhost:3000/v2/myimage/tags/list

# Get manifest
curl -H "Accept: application/vnd.docker.distribution.manifest.v2+json" \
     http://localhost:3000/v2/myimage/manifests/v1
```

### Supported Image Formats

This registry accepts **single-platform Docker V2 Schema 2** manifests only. Multi-architecture manifest lists and OCI manifests are rejected with `415 Unsupported Media Type`. Build images with `--platform linux/amd64` (or the target architecture) before pushing.

---

## Web UI Features

### Repository Index (`GET /`)

- Responsive card grid (1 column on mobile, 2 on tablet, 3 on desktop).
- **Real-time search** over name, description, and maintainer. A Stimulus `search_controller` debounces input by 300 ms and updates a `turbo_frame_tag "repositories"` without a full page reload.
- **Sort options**: Recent (default), Name (A–Z), Size (descending), Pulls (sum of `manifest.pull_count` across all tags).
- Cards show: name, description, maintainer, tag count badge, total size (human-readable).

### Repository Detail (`GET /repositories/:name`)

- Collapsible **metadata editor** for:
  - `description` (textarea)
  - `maintainer` (text)
  - `tag_protection_policy` — `none` / `semver` / `all_except_latest` / `custom_regex`
  - `tag_protection_pattern` — regex input, shown conditionally by the `tag_protection_controller` Stimulus controller when the policy is `custom_regex`; validated as a real Ruby regex.
- **Docker pull command** with a one-click copy button (Stimulus `clipboard_controller`, 2-second "Copied!" feedback).
- **Tags table** — desktop CSS Grid (7 columns: tag name, digest, size, arch/os, pulls, updated, actions); mobile card stack.
  - Protected tags show a 🔒 badge with the policy name and disable the delete button.
  - Delete button triggers a native confirm dialog via `turbo_confirm`.
- **Delete repository** button — cascades to all tags/manifests after confirmation.

### Tag Detail (`GET /repositories/:name/tags/:tag_name`)

- Tag header: full name, short digest (12 chars), size, architecture/OS, pull count.
- **Layers section** listing every layer in `position` order with digest + size (desktop grid / mobile cards).
- **Docker Config section** — pretty-printed JSON extracted from the config blob (`manifest.docker_config`).
- **Docker pull command** with copy button.
- Delete button disabled for protected tags.

### Tag History (`GET /repositories/:name/tags/:tag_name/history`)

- All `TagEvent` rows for this tag, ordered by `occurred_at DESC`.
- Each row renders: color-coded action badge (create = green, update = amber, delete = red), timestamp, `previous_digest` and `new_digest` (short format), and the `actor` field.

### Help Page (`GET /help`)

- Static guide covering Docker daemon `insecure-registries` config, push/pull examples, Kubernetes/containerd mirror configuration, and an Nginx TLS reverse-proxy snippet.
- Explicit warning about single-platform Docker V2 Schema 2 support.

### Global UI

- Top bar: Open Repo logo, Help link, **dark mode toggle** (`theme_controller`, localStorage-backed, respects `prefers-color-scheme`, FOUC-prevented by an inline script in the layout).
- Flash messages (alert / notice) rendered above content.
- Health check endpoint: `GET /up` (Rails 8 built-in).

---

## Docker Registry V2 API

All V2 responses include `Docker-Distribution-API-Version: registry/2.0`. Errors follow the Docker spec:

```json
{ "errors": [{ "code": "BLOB_UNKNOWN", "message": "...", "detail": {} }] }
```

Error mapping in `V2::BaseController#rescue_from`:

| Exception | HTTP | Code |
|-----------|------|------|
| `Registry::BlobUnknown` | 404 | `BLOB_UNKNOWN` |
| `Registry::BlobUploadUnknown` | 404 | `BLOB_UPLOAD_UNKNOWN` |
| `Registry::ManifestUnknown` | 404 | `MANIFEST_UNKNOWN` |
| `Registry::ManifestInvalid` | 400 | `MANIFEST_INVALID` |
| `Registry::NameUnknown` | 404 | `NAME_UNKNOWN` |
| `Registry::DigestMismatch` | 400 | `DIGEST_INVALID` |
| `Registry::Unsupported` | 415 | `UNSUPPORTED` |
| `Registry::TagProtected` | 409 | `DENIED` |

### Endpoints

| Method | Path | Controller | Purpose |
|--------|------|-----------|---------|
| `GET` | `/v2/` | `v2/base#index` | Version ping |
| `GET` | `/v2/_catalog` | `v2/catalog#index` | Repository list, paginated (`n`, `last`, `Link` header) |
| `GET` | `/v2/:name/tags/list` | `v2/tags#index` | Tag list, paginated (supports `:ns/:name` namespaced repos) |
| `GET`/`HEAD` | `/v2/:name/manifests/:reference` | `v2/manifests#show` | Fetch manifest by tag or digest |
| `PUT` | `/v2/:name/manifests/:reference` | `v2/manifests#update` | Push manifest |
| `DELETE` | `/v2/:name/manifests/:reference` | `v2/manifests#destroy` | Delete manifest |
| `GET`/`HEAD` | `/v2/:name/blobs/:digest` | `v2/blobs#show` | Stream blob via `send_file` (supports `SENDFILE_HEADER`) |
| `DELETE` | `/v2/:name/blobs/:digest` | `v2/blobs#destroy` | Delete blob |
| `POST` | `/v2/:name/blobs/uploads` | `v2/blob_uploads#create` | Start upload / monolithic / cross-repo mount |
| `PATCH` | `/v2/:name/blobs/uploads/:uuid` | `v2/blob_uploads#update` | Append chunk (updates `Range` header) |
| `PUT` | `/v2/:name/blobs/uploads/:uuid` | `v2/blob_uploads#complete` | Finalize with digest verification |
| `DELETE` | `/v2/:name/blobs/uploads/:uuid` | `v2/blob_uploads#destroy` | Cancel upload session |

Pagination for catalog and tag listing: `?n=100&last=<cursor>`, clamped to 1–1000, with a `Link: </v2/...>; rel="next"` header when more pages exist.

### Three Upload Modes

1. **Blob mount** (cross-repo blob reuse) — `POST /v2/<repo>/blobs/uploads?mount=<digest>&from=<source_repo>`. If the blob already exists, `references_count` is incremented and the server returns `201` with a `Location` header. No data transfer.
2. **Monolithic upload** — `POST /v2/<repo>/blobs/uploads?digest=<digest>` with the entire blob as the body. The server verifies the digest and creates the `Blob` in a single request.
3. **Chunked upload** — `POST` to start (returns a `uuid` and `Location`), `PATCH` repeatedly to append chunks, `PUT ?digest=<digest>` to finalize. Each `PATCH` response advances the `Range: 0-<byte_offset-1>` header.

### Manifest Push Pipeline (`PUT /v2/:name/manifests/:ref`)

Orchestrated by `ManifestProcessor#call(repo_name, reference, content_type, payload)`:

1. Reject anything other than `application/vnd.docker.distribution.manifest.v2+json` (multi-arch / OCI → `415`).
2. Validate JSON and `schemaVersion == 2`.
3. Verify the config blob and every layer blob exist in the blob store.
4. Compute the manifest digest (SHA-256 of the payload).
5. **Row-lock** on the `Repository` (`repository.with_lock`) and call `repository.enforce_tag_protection!(tag_name, new_digest:)`:
   - Protected tag + different digest → `Registry::TagProtected` (409).
   - Protected tag + **same** digest → allowed (idempotent, CI-retry-safe).
6. Upsert the `Manifest` keyed on unique `digest`, parse config JSON to extract `architecture`, `os`, and the nested `config` object (stored in `docker_config`).
7. Replace `Layer` rows (one per blob in order); increment `blob.references_count` for each.
8. Attach the tag, emitting a `TagEvent` (`action: "create"` or `"update"`, with previous/new digests).
9. Recompute `repository.total_size` as the sum of all layer blob sizes.

### Pull Side Effects (`GET /v2/:name/manifests/:ref`)

On every pull (HEAD does **not** count):

- Increment `manifest.pull_count`.
- Update `manifest.last_pulled_at`.
- Insert a `PullEvent` with `tag_name` (nil if pulled by digest), `user_agent`, `remote_ip`, and `occurred_at`.

---

## Service Layer (Internal)

Located in `app/services/`.

| Service | Responsibility |
|---------|----------------|
| `DigestCalculator` | SHA-256 computation (`compute`) and verification (`verify!`). Streams IO in 64 KB chunks; raises `Registry::DigestMismatch` on mismatch. |
| `BlobStore` | Content-addressable filesystem storage at `<STORAGE_PATH>/blobs/<alg>/<shard>/<hex>` (shard = first two hex chars). Atomic writes via temp file + rename. Methods: `get`, `put`, `exists?`, `delete`, `size`, `create_upload`, `append_upload`, `upload_size`, `finalize_upload`, `cancel_upload`, `cleanup_stale_uploads(max_age:)`. |
| `ManifestProcessor` | Push orchestration — validation, digest computation, row-locked tag protection enforcement, manifest/layer/tag persistence, `total_size` recompute. |
| `ImageImportService` | Reads a `docker save` tar, promotes its config and layers into the blob store, builds a V2 Schema 2 manifest, and delegates to `ManifestProcessor`. Falls back to `"imported"` / `"latest"` when `RepoTags` is missing. |
| `ImageExportService` | Inverse of import — writes a Docker-compatible tar with `manifest.json`, `<config>.json`, and one `<layer>/layer.tar` per layer, suitable for `docker load`. |
| `TagDiffService` | Returns `common_layers`, `removed_layers`, `added_layers`, `size_delta`, and a key-by-key `config_diff` between two manifests. |
| `DependencyAnalyzer` | For a given repository, returns other repositories ranked by shared layer count (`shared_layers`, `total_layers`, `ratio`). Useful for blob-mount planning and deletion impact analysis. |

---

## Data Models

All models live in `app/models/`.

| Model | Purpose / Notable Columns |
|-------|---------------------------|
| `Repository` | `name` (unique, may contain `/`), `description`, `maintainer`, `tag_protection_policy`, `tag_protection_pattern`, `tags_count` (counter cache), `total_size`. Exposes `tag_protected?(name)` and `enforce_tag_protection!(name, new_digest:, existing_tag:)`. |
| `Manifest` | `digest` (unique), `media_type`, `payload`, `size`, `config_digest`, `architecture`, `os`, `docker_config`, `pull_count`, `last_pulled_at`. |
| `Tag` | `(repository_id, name)` unique. `belongs_to :repository, counter_cache: true` and `belongs_to :manifest`. `to_param` returns `name` for URL routing. |
| `Blob` | `digest` (unique), `size`, `content_type`, `references_count`. When `references_count` reaches 0, the blob is GC-eligible. |
| `Layer` | Join table between `Manifest` and `Blob` with `position` (0-based). Unique on `(manifest_id, position)` and `(manifest_id, blob_id)`. |
| `BlobUpload` | Tracks chunked upload sessions: `uuid`, `byte_offset`, `repository_id`. |
| `PullEvent` | Immutable pull audit row: `manifest_id`, `tag_name` (nil for digest pulls), `user_agent`, `remote_ip`, `occurred_at`. Pruned after 90 days. |
| `TagEvent` | Immutable tag audit row: `action` (`create` / `update` / `delete`), `previous_digest`, `new_digest`, `actor` (`"anonymous"` or `"retention-policy"`), `occurred_at`. Retained indefinitely. |
| `Import` | Async tar import state: `tar_path`, `repository_name`, `tag_name`, `status` (`pending` / `processing` / `completed` / `failed`), `progress`, `error_message`. |
| `Export` | Async tar export state: `repository_id`, `tag_name`, `status`, `output_path`, `error_message`. |

---

## Background Jobs

Managed by Solid Queue. Recurring schedules live in `config/recurring.yml`.

| Job | Schedule | Purpose |
|-----|----------|---------|
| `CleanupOrphanedBlobsJob` | Every 30 min | (1) Delete `Blob` rows with `references_count == 0` after a reload re-check (race-safe); (2) destroy manifests with no attached tags, decrementing layer blob refs; (3) `blob_store.cleanup_stale_uploads(max_age: 1.hour)`; (4) delete completed/failed `Export` rows older than 1 hour (plus their files); (5) delete completed/failed `Import` rows older than 24 hours (plus their files). |
| `EnforceRetentionPolicyJob` | Daily 3 AM | Runs only when `RETENTION_ENABLED=true`. Finds manifests where `last_pulled_at < now − RETENTION_DAYS_WITHOUT_PULL` (or NULL) **and** `pull_count < RETENTION_MIN_PULL_COUNT`. Skips `latest` if `RETENTION_PROTECT_LATEST=true`. Skips any tag where `repository.tag_protected?` is true. Deletes remaining tags and emits `TagEvent(action: "delete", actor: "retention-policy")`. |
| `PruneOldEventsJob` | Daily 4 AM | Batch-deletes `PullEvent` rows with `occurred_at < 90.days.ago`. |
| `ProcessTarImportJob` | On-demand | Transitions `Import` from `pending` → `processing` (`progress: 10`) → `completed` (`progress: 100`) or `failed`. Calls `ImageImportService`. |
| `PrepareExportJob` | On-demand | Writes a tar to `<STORAGE_PATH>/tmp/exports/` and transitions `Export` to `completed` or `failed`. |
| `clear_solid_queue_finished_jobs` | Hourly at :12 | Clears finished Solid Queue jobs in batches. |

---

## Retention Policy

Retention is **opt-in** and governed by four environment variables:

- `RETENTION_ENABLED` — master switch (default `false`).
- `RETENTION_DAYS_WITHOUT_PULL` — age threshold (default `90`).
- `RETENTION_MIN_PULL_COUNT` — minimum lifetime pulls to keep (default `5`).
- `RETENTION_PROTECT_LATEST` — always keep `latest` (default `true`).

A manifest is a candidate for expiration only if **both** `last_pulled_at < threshold` (or NULL) **and** `pull_count < min_pull_count` hold.

**Interaction with tag protection:** the retention job additionally calls `repository.tag_protected?(tag.name)` and skips protected tags. Retention cannot override explicit protection policies.

---

## Garbage Collection

Blob storage uses reference counting:

- `Blob.references_count` is incremented by `ManifestProcessor` when creating layers.
- It is decremented by `RepositoriesController#destroy`, `V2::ManifestsController#destroy`, and `CleanupOrphanedBlobsJob#cleanup_orphaned_manifests` (which detects manifests that lost all tags).
- When `references_count` reaches 0, the blob becomes eligible for deletion. `CleanupOrphanedBlobsJob` reloads the row before deleting, closing the race with concurrent pushes that might have mounted the blob.

Web UI tag deletion only destroys the `Tag` row — the corresponding `Manifest` is left for the orphan sweep on the next job run. This keeps delete operations fast and makes deletion undoable until GC catches up.

Other sweeps handled by the same job: stale upload session directories (>1 hour old), completed/failed exports (>1 hour old), and completed/failed imports (>24 hours old).

---

## Pull Tracking & Audit Log

Two independent event streams are recorded by the system:

**`PullEvent` — per-pull observability.** Emitted on every `GET /v2/:name/manifests/:ref`. Captures `user_agent`, `remote_ip`, `tag_name` (nil if pulled by digest), `occurred_at`, plus the associated `manifest_id` and `repository_id`. Pruned after 90 days by `PruneOldEventsJob`.

**`TagEvent` — immutable change log.** Emitted by `ManifestProcessor` (create/update), `V2::ManifestsController#destroy` (delete, one per attached tag), `TagsController#destroy` (Web UI delete), and `EnforceRetentionPolicyJob` (delete, actor `"retention-policy"`). Surfaced in the Web UI on the tag history page. Not auto-pruned.

---

## Testing

```bash
# RSpec (backend + integration)
bundle exec rspec

# Playwright E2E
npx playwright test

# Docker CLI integration (requires a running server + Docker)
test/integration/docker_cli_test.sh
```

---

## Deployment

### Kamal 2 (recommended)

```bash
kamal setup
kamal deploy
```

### Docker Compose

```bash
docker-compose up --build
```

### Nginx Reverse Proxy

For production with TLS, place Nginx in front with:

```nginx
client_max_body_size 0;
proxy_request_buffering off;
```

This lets Docker stream large blob uploads without buffering them to disk on the proxy. See the in-app Help page for a complete configuration example, including `X-Accel-Redirect` wiring so `SENDFILE_HEADER` can deliver blobs directly from disk.

---

## Project Structure

```
app/
├── controllers/
│   ├── repositories_controller.rb    # Web UI CRUD
│   ├── tags_controller.rb            # Tag detail, history, delete
│   ├── help_controller.rb            # Setup guide page
│   └── v2/                           # Docker Registry V2 API
│       ├── base_controller.rb        # Error mapping, API version header
│       ├── blob_uploads_controller.rb
│       ├── blobs_controller.rb
│       ├── catalog_controller.rb
│       ├── manifests_controller.rb
│       └── tags_controller.rb
├── models/                           # ActiveRecord models
│   ├── repository.rb, manifest.rb, tag.rb, blob.rb, layer.rb
│   ├── blob_upload.rb, tag_event.rb, pull_event.rb
│   └── import.rb, export.rb
├── services/
│   ├── blob_store.rb                 # Content-addressable filesystem storage
│   ├── digest_calculator.rb          # SHA-256 computation and verification
│   ├── manifest_processor.rb         # Manifest validation, metadata extraction
│   ├── image_import_service.rb       # Docker tar → registry import
│   ├── image_export_service.rb       # Registry → Docker tar export
│   ├── tag_diff_service.rb           # Layer/config comparison between tags
│   └── dependency_analyzer.rb        # Shared layer analysis across repos
├── jobs/
│   ├── cleanup_orphaned_blobs_job.rb
│   ├── enforce_retention_policy_job.rb
│   ├── prune_old_events_job.rb
│   ├── process_tar_import_job.rb
│   └── prepare_export_job.rb
├── javascript/controllers/
│   ├── search_controller.js          # Debounced Turbo Frame search
│   ├── clipboard_controller.js       # Copy docker pull command
│   ├── theme_controller.js           # Dark mode toggle + localStorage
│   └── tag_protection_controller.js  # Conditional regex input visibility
└── views/
    ├── repositories/                 # Index, show, card partial
    ├── tags/                         # Show, history
    └── help/                         # Setup guide

config/
├── routes.rb                         # Web UI + V2 API routes
└── recurring.yml                     # Solid Queue recurring schedules
```

---

## License

This project is licensed under the MIT License.
