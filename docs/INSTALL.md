# Installing Open Repo (Docker Compose + Caddy)

This is the single-host distribution: one Docker Compose stack — the Rails app
plus a Caddy reverse proxy that terminates TLS with automatic HTTPS. Everything
durable (4 SQLite databases, Active Storage, content-addressed blobs) lives on
one named volume. No external database, Redis, or registry is required.

For multi-server / zero-downtime deploys, use Kamal instead
(`config/deploy.yml`); see [`PRE_SERVER_REGISTRATION_TODO.md`](PRE_SERVER_REGISTRATION_TODO.md).

## Prerequisites

- A Linux host with **Docker Engine** + **Docker Compose v2** (`docker compose version`).
- **`config/master.key`** present in the checkout — it decrypts
  `config/credentials.yml.enc` (Google OAuth client + `secret_key_base`). The
  installer copies it into `.env` for you. Without it the app boots but every
  login fails. If you don't have it, the deploying developer does; or regenerate
  per `PRE_SERVER_REGISTRATION_TODO.md` (B4/B7).
- A **DNS name** for the registry (`REGISTRY_HOST`) whose A/AAAA record points at
  this host, with inbound **TCP 80 and 443** open. Caddy needs both to issue and
  renew the Let's Encrypt certificate. (Internal-only without public DNS? See
  [Internal CA](#internal-only-no-public-dns) below.)
- A **Google OAuth 2.0 client** (Web application) — used for web sign-in.

## Quick start

```bash
git clone <this-repo> open-repo && cd open-repo
cp .env.example .env          # the installer also does this if .env is absent
$EDITOR .env                  # set REGISTRY_HOST and REGISTRY_ADMIN_EMAIL
./install.sh
```

`install.sh` is idempotent: it checks Docker, fills `RAILS_MASTER_KEY` from
`config/master.key`, validates the required settings, builds the image, starts
the stack, waits for health, and smoke-tests `/up` and `/v2/`. Re-run it any
time; `./install.sh --down` stops the stack but keeps your data volume.

## Configure `.env`

| Variable | Required | Notes |
|---|---|---|
| `RAILS_MASTER_KEY` | yes | Auto-filled from `config/master.key`; set by hand only if absent. |
| `REGISTRY_HOST` | yes | Registry FQDN, no scheme (e.g. `registry.example.com`). Used in every docker command and for the TLS cert. |
| `REGISTRY_ADMIN_EMAIL` | yes | Google account that owns auto-created repos / break-glass admin. See the ordering trap below. |
| `RAILS_ASSUME_SSL` / `RAILS_FORCE_SSL` | yes (Caddy) | Keep both `true` behind Caddy. Both `false` only for plain-HTTP-no-proxy. |
| `REGISTRY_ALLOWED_EMAIL_DOMAINS` | no | Comma-separated sign-up allowlist. Empty = any Google-verified email. |
| `REGISTRY_ANONYMOUS_PULL` | no | `true` (default) allows `docker pull` without a token; `false` requires a PAT. |

`.env` is gitignored — it holds your master key; never commit it.

## Go-live steps (in order)

The installer can't do these for you, and **order matters**:

1. **DNS + firewall.** Point `REGISTRY_HOST` at this host; open 80 + 443. Watch
   the cert issue: `docker compose logs -f caddy`.
2. **Google OAuth console.** In GCP → APIs & Services → Credentials, on your
   OAuth client add:
   - Authorized redirect URI: `https://<REGISTRY_HOST>/auth/google_oauth2/callback`
   - Authorized JavaScript origin: `https://<REGISTRY_HOST>`

   Put the client id/secret into Rails credentials (`bin/rails credentials:edit`,
   under `google_oauth:`) — done once by the developer who holds the master key;
   a mismatched redirect URI gives `redirect_uri_mismatch`.
3. **⚠️ Admin first sign-in (ordering trap).** Have `REGISTRY_ADMIN_EMAIL` open
   `https://<REGISTRY_HOST>/sign_in` and sign in with Google **before any
   `docker push`**. The first push to a new repo assigns ownership to that user;
   if they haven't signed in yet, the push fails. This is the single most common
   first-deploy mistake.
4. **Create a token and log in.** At `https://<REGISTRY_HOST>/settings/tokens`
   create a Personal Access Token (`oprk_…`), then from any client:

   ```bash
   docker login <REGISTRY_HOST> -u <ADMIN_EMAIL> -p <oprk_token>
   docker tag alpine:latest <REGISTRY_HOST>/alpine:1 && docker push <REGISTRY_HOST>/alpine:1
   docker pull <REGISTRY_HOST>/alpine:1
   ```

> **Single-platform only.** Build images with `--platform linux/amd64` (or your
> target arch). Multi-arch manifest lists / OCI image indexes are rejected with
> `415` by design.

## Operations

```bash
docker compose ps                 # status
docker compose logs -f app        # app logs   (GC/retention run inside Puma)
docker compose logs -f caddy      # TLS / proxy logs
./install.sh --no-build           # restart without rebuilding
./install.sh --down               # stop; keeps the data volume
```

### Data & backup

All state is on the `open-repo_open_repo_storage` Docker volume
(`/rails/storage` in the container): `production*.sqlite3` ×4, Active Storage,
and `registry/blobs`. **There is no automatic off-host backup** — set one up
(it's blocker B18 in `PRE_SERVER_REGISTRATION_TODO.md`):

- SQLite: copy with the online backup API, never `cp` a live WAL DB —
  `sqlite3 production.sqlite3 ".backup '/dest/production.sqlite3'"` (×4).
- Blobs: `rsync`/`aws s3 sync` of `registry/blobs` (content-addressed, safe to
  copy live).
- **Restore needs the matching `master.key`** — back it up separately, or a
  restored volume can't decrypt OAuth credentials. Rehearse a restore before you
  rely on it.

### Upgrading

```bash
git pull
./install.sh         # rebuilds the image; db:prepare runs on boot (idempotent)
```

### Internal-only (no public DNS)

Auto-HTTPS via Let's Encrypt needs public DNS. For an internal network, edit
`Caddyfile` to use Caddy's local CA and trust its root on the client hosts:

```caddyfile
{$REGISTRY_HOST} {
    tls internal
    reverse_proxy app:80
}
```

or point `tls` at your corporate certificate:
`tls /etc/caddy/cert.pem /etc/caddy/key.pem` (mount them into the caddy service).

## Troubleshooting

| Symptom | Likely cause |
|---|---|
| `docker login` → `http: server gave HTTP response to HTTPS client` | TLS not up yet (cert still issuing) or `REGISTRY_HOST` ≠ the cert's name. |
| Cert never issues | DNS not pointing here, or 80/443 blocked (ACME HTTP-01 needs 80). |
| First push → 500 | Admin hasn't completed Google sign-in yet (step 3). |
| Every login fails | `RAILS_MASTER_KEY` wrong/empty, or `google_oauth` not in credentials / redirect URI mismatch. |
| `app` unhealthy | `docker compose logs app` — usually a bad master key or a full disk. |
