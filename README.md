# Open Repo

A self-hosted Docker Registry V2 server with web management UI, built with Ruby on Rails 8. Designed for internal teams to store, manage, and serve build images used by Jenkins, Kubernetes, and CI/CD pipelines.

## Features

- **Docker Registry V2 API** — full `docker push` / `docker pull` support with chunked uploads, cross-repo blob mount, and HEAD manifest
- **Web UI** — browse repositories and tags, view image config (OS, arch, env, cmd), edit descriptions and maintainers
- **Image Import/Export** — upload/download Docker images as tar files via async background jobs
- **Pull Tracking** — per-manifest pull counts, last pulled timestamp, and detailed pull event history (IP, user agent)
- **Tag Audit Log** — records tag create/update/delete events with previous and new digests
- **Tag Comparison** — diff layers and config between two tags to see what changed
- **Dependency Graph** — identify repositories sharing layers to assess deletion impact
- **Garbage Collection** — automatic cleanup of orphaned blobs, stale uploads, and expired exports
- **Retention Policy** — configurable auto-expiration of unused images based on pull activity
- **Dark Mode** — responsive design with TailwindCSS, light/dark theme toggle

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
| Blob Storage | Local filesystem (content-addressable) |
| Backend Tests | RSpec |
| E2E Tests | Playwright |

## Prerequisites

- Ruby 3.4+
- Node.js 18+ and npm
- SQLite3

## Installation

```bash
bundle install
npm install
bin/rails db:prepare
```

## Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `STORAGE_PATH` | `storage/registry` | Blob storage directory |
| `REGISTRY_HOST` | `localhost:3000` | Hostname shown in `docker pull` commands |
| `SENDFILE_HEADER` | _(none)_ | Set to `X-Accel-Redirect` (Nginx) or `X-Sendfile` (Apache) for production |
| `PUMA_THREADS` | `16` | Puma thread count (increase for concurrent pulls) |
| `PUMA_WORKERS` | `2` | Puma worker count |
| `RETENTION_ENABLED` | `false` | Enable auto-expiration of unused images |
| `RETENTION_DAYS_WITHOUT_PULL` | `90` | Days without pull before eligible for cleanup |
| `RETENTION_MIN_PULL_COUNT` | `5` | Images with fewer pulls than this are eligible |
| `RETENTION_PROTECT_LATEST` | `true` | Never auto-delete `latest` tags |

## Development

```bash
bin/dev
```

Starts Rails server on http://localhost:3000 with TailwindCSS watcher.

## Usage

### Push and Pull Images

```bash
# Tag and push
docker tag myimage:v1 localhost:3000/myimage:v1
docker push localhost:3000/myimage:v1

# Pull
docker pull localhost:3000/myimage:v1
```

> **Note:** For HTTP registries (non-TLS), add `"insecure-registries": ["localhost:3000"]` to `/etc/docker/daemon.json` and restart Docker. See the in-app Help page for K8s/containerd setup.

### Web UI

- **http://localhost:3000** — repository list with search and sort
- **Repository detail** — tag list, pull counts, docker pull command, description/maintainer editing
- **Tag detail** — manifest info, image config, layer list, tag change history
- **Help page** — Docker daemon, Kubernetes, and Nginx configuration guides

### Registry V2 API

```bash
# Check API
curl http://localhost:3000/v2/

# List repositories
curl http://localhost:3000/v2/_catalog

# List tags
curl http://localhost:3000/v2/myimage/tags/list

# Get manifest
curl -H "Accept: application/vnd.docker.distribution.manifest.v2+json" \
     http://localhost:3000/v2/myimage/manifests/v1
```

### Supported Image Formats

This registry accepts **single-platform Docker V2 Schema 2** manifests only. Multi-architecture manifest lists and OCI manifests are rejected with `415 Unsupported Media Type`.

## Testing

```bash
# RSpec (backend + integration)
bundle exec rspec

# Playwright E2E
npx playwright test

# Docker CLI integration
test/integration/docker_cli_test.sh
```

## Background Jobs

Managed by Solid Queue with recurring schedules (see `config/recurring.yml`):

| Job | Schedule | Purpose |
|-----|----------|---------|
| `CleanupOrphanedBlobsJob` | Every 30 min | Delete unreferenced blobs, stale uploads, expired exports |
| `EnforceRetentionPolicyJob` | Daily 3 AM | Auto-delete tags on images not pulled within threshold |
| `PruneOldEventsJob` | Daily 4 AM | Remove pull events older than 90 days |

## Deployment

### Kamal (recommended)

```bash
kamal setup
kamal deploy
```

### Docker Compose

```bash
docker-compose up --build
```

### Nginx Reverse Proxy

For production with TLS, place Nginx in front with `client_max_body_size 0` and `proxy_request_buffering off`. See the in-app Help page for a complete configuration example.

## Project Structure

```
app/
├── controllers/
│   ├── repositories_controller.rb    # Web UI CRUD
│   ├── tags_controller.rb            # Tag detail, history, compare, export
│   ├── help_controller.rb            # Setup guide page
│   └── v2/                           # Docker Registry V2 API
│       ├── base_controller.rb
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
│   ├── digest_calculator.rb          # SHA256 computation and verification
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
└── views/
    ├── repositories/                 # Index, show, card partial
    ├── tags/                         # Show, history
    └── help/                         # Setup guide
```

## License

This project is licensed under the MIT License.
