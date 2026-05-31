# Pre-Server-Registration TODO (Master Checklist)

> **Date:** 2026-05-31
> **Scope:** Everything required to run **open_repo** (Rails 8 + Kamal 2 single-node Docker registry) in
> REAL mode before announcing/registering the server. This is the authoritative, exhaustive checklist.
> Actual implementation happens later — treat every item below as a gate.
> **Method:** Whole-codebase audit (multi-agent adversarial workflow) + per-task source verification by hand.

---

## TL;DR

- **The code is real, not mocked.** Every production path is a genuine implementation — real SHA256 digests,
  real filesystem `BlobStore`, real Google OAuth, real PAT hashing, real recurring jobs, real catalog/tag
  pagination with clamping + `Link` headers. There is **nothing to "switch from mock to real" in code.**
- The only mock affordance — `POST /testing/sign_in` — is double-gated in `config/routes.rb:13`
  (`Rails.env.test?` **or** `development? && USE_MOCK_REGISTRY=true`) and is **never mounted in production.**
- The remaining work is **configuration, secrets, a handful of go-live decisions, and a few small code
  hardening fixes** (idempotency / write-amplification / graceful errors) — not feature work.
- **Blocker count: 18.** Plus 4 go-live decisions that gate the blockers, ~24 high-priority items, and
  ~12 medium/low items. The single most dangerous trap is the **first-push admin-bootstrap ordering**
  (set `REGISTRY_ADMIN_EMAIL` only *after* that user has signed in via Google) and **TLS** (Docker refuses
  Basic-auth over plain HTTP to a remote host).
- 🚨 **SECURITY INCIDENT (CRITICAL, do B0 first).** The GitHub source repo is now PUBLIC
  (`timberay/open-repo`, renamed 2026-05-31) **and `config/master.key` is exposed in git history**
  (committed in `8384a4f`, untracked later in `4cb4319` — but history is permanent). The exposed key
  **decrypts the committed `config/credentials.yml.enc`**, leaking `secret_key_base` + the Google OAuth
  `client_id`/`client_secret`. Treat all of these as compromised and rotate. See **B0**.

---

## How to use this checklist

1. Resolve **Decisions required first** — they unblock everything downstream and are referenced by ID.
2. Work **Blockers → High → Medium/Low**. Each item lists Type, Files (with line numbers), Why, exact Steps
   (shell / `kamal` / edits with `<PLACEHOLDER>` for real values), Acceptance (command + expected result),
   and Depends on.
3. Finish with the **First-deploy runbook (ordered)** and the **Post-deploy smoke test** — those prove the
   whole chain end-to-end (DNS → TLS → auth → push → pull) before real users touch it.

---

## Decisions required first

These are the go-live decisions. Record each one (chosen value, owner, rationale) in this file. Downstream
tasks reference them by ID (D1–D4 plus the smaller decisions D5–D9).

- [ ] **D1 — TLS termination strategy.** Choose ONE (mutually exclusive):
  - [ ] **Option A — Kamal built-in proxy (kamal-proxy) + Let's Encrypt** (recommended single-node). Auto-renewing
    certs, zero extra infra; requires ports 80+443 open and public DNS for the ACME HTTP-01 challenge.
  - [ ] **Option B — External Nginx TLS reverse proxy.** Full control, corporate/internal CA, multi-service/LB; you
    own cert renewal and the Nginx config.
  - Record: registry **FQDN** = `<REGISTRY_DNS_NAME>`, cert source, who renews. Both options require
    `config.assume_ssl=true` because TLS is terminated upstream of Rails.
- [ ] **D2 — Single-node vs multi-node.** Current data layer (filesystem blobs + 4 local SQLite DBs + on-disk
  upload sessions) is **single-node only**. Multi-node requires an S3/GCS BlobStore adapter + external Postgres/MySQL
  + shared upload storage. Confirm **single-node** for launch, or scope the migration separately.
- [ ] **D3 — Anonymous (public) pull on/off.** `REGISTRY_ANONYMOUS_PULL` defaults to **`"true"` = world-readable**
  (`config/initializers/registry.rb:4`). Decide PUBLIC (leave true, but complete the write-amplification + GET-throttle
  tasks) or PRIVATE (`false`).
- [ ] **D4 — Error/exception sink + log retention.** Pick Sentry (recommended) / Honeybadger / Rollbar / lograge-only.
  Today 500s are invisible (STDOUT info only, no reporter). Decide the sink, the env var name (e.g. `SENTRY_DSN`), and
  where the DSN lives.
- [ ] **D5 — Expected max image/layer size.** Drives whether `MAX_REQUEST_BODY` (and any Nginx body cap) must be lifted.
- [ ] **D6 — Container image registry** (where Kamal stores the *built app image* — SEPARATE from the registry this app *is*):
  ghcr.io / Docker Hub / registry.digitalocean.com / other.
- [ ] **D7 — `:read` authorization stays always-true for launch?** Every authenticated user can read every repo
  (Stage-3 visibility deferral, `repository_authorization.rb:18`). Confirm acceptable, or schedule the feature.
- [ ] **D8 — PAT scope/expiry policy.** PATs carry full user authority (no scopes); `kind` is cosmetic; blank expiry =
  never expires. Accept by-design, or implement scopes / expiry coercion + cap.
- [ ] **D9 — Docker Compose docs: remove or re-add?** No `docker-compose.yml` exists; README/TOOLS/STACK still advertise it.
- [ ] **D10 — Zero-copy blob delivery (`SENDFILE_HEADER`) a launch requirement?** Drives wire-it vs drop-the-claim.
- [ ] **D11 — `config.hosts` Host authorization: open or allowlisted** for the real FQDN.
- [ ] **D12 — Timezone for maintenance windows / token-expiry display:** accept container UTC, or set `config.time_zone`.

---

## Blockers (must do before server registration)

- [x] **B0. 🚨 RESOLVED (2026-05-31) — Rotated the leaked master key + all credentials + purged from git history**
  - **Type:** secret + ops (incident response — was done BEFORE anything else)
  - **Done:** ✅ repo set Private · ✅ `config/master.key` purged from git history (`git filter-repo`) + force-pushed (remote `main` confirmed clean) · ✅ `master.key` regenerated (new, git-ignored) · ✅ `secret_key_base` rotated · ✅ old leaked key no longer decrypts (verified) · ✅ Google OAuth `client_secret` reset in Google Cloud Console + new `google_oauth` values added via `bin/rails credentials:edit` and committed (`df011a7`). Leak fully remediated — safe to make the repo Public again if desired. (Note: GitHub may retain old commit objects via PR refs/cache; rotation — done — is what neutralizes the leak.)
  - **Files:** `config/master.key` (in history at `8384a4f`), `config/credentials.yml.enc`, Google Cloud Console
  - **Why:** `config/master.key` (value `b53d6b71…`) was committed in `8384a4f` and remains in the permanent git
    history of a now-PUBLIC repo. It successfully decrypts the committed `config/credentials.yml.enc`, exposing
    `secret_key_base` and the Google OAuth `client_id`/`client_secret`. Anyone can `git show 8384a4f:config/master.key`
    and decrypt every secret. A leaked `secret_key_base` allows session/cookie forgery; a leaked OAuth secret allows
    app impersonation. History-scrubbing alone is NOT enough — assume already-cloned/indexed; **rotation is mandatory.**
  - **Steps (in order):**
    1. **Contain now:** set the repo back to **Private** until rotation is complete (reduces the exposure window).
    2. **Rotate Google OAuth:** in Google Cloud Console → APIs & Services → Credentials → the OAuth client → **reset
       the client secret** (and consider a fresh client). The old `client_secret` is burned.
    3. **Rotate Rails secrets:** delete `config/master.key` + `config/credentials.yml.enc`, regenerate with
       `bin/rails credentials:edit` (creates a NEW master.key + a fresh `secret_key_base`), and re-enter the
       NEW `google_oauth.client_id`/`client_secret` from step 2. Keep the new `master.key` OUT of git.
    4. **Purge history:** `git filter-repo --path config/master.key --invert-paths` (or BFG), then
       `git push --force-with-lease` all branches/tags. Coordinate — this rewrites history.
    5. **Invalidate live sessions:** the new `secret_key_base` logs everyone out (expected/desired).
  - **Acceptance:** `git log --all -- config/master.key` is empty · the OLD key (fingerprint `b53d6b71…`) no longer
    decrypts `credentials.yml.enc` (running the old key against `bin/rails runner 'Rails.application.credentials.config'`
    raises `InvalidMessage`) · the old Google client secret is shown as reset in the console · repo visibility is the
    intended one.
  - **Depends on:** nothing — this is first.

- [ ] **B1. Set the real container image name + namespace in `config/deploy.yml`**
  - **Type:** config
  - **Files:** `config/deploy.yml:5`
  - **Why:** `image` is the unnamespaced `open_repo` (line 5). On any authenticated registry (ghcr.io, Docker Hub, …)
    the image MUST be `<namespace>/<name>` or `kamal deploy` tags/pushes to a path you cannot write to → push 401/404.
    This is the *container image* registry (where Kamal stores the built app image), NOT the Docker-registry app this
    project IS — do not confuse them.
  - **Steps:**
    1. Per **D6**, pick the container image registry.
    2. Edit `config/deploy.yml:5`: `image: <REGISTRY_NAMESPACE>/open_repo` (ghcr.io → `image: <GH_ORG>/open_repo`;
       Docker Hub → `image: <DOCKERHUB_USER>/open_repo`).
    3. Keep `service: open_repo` on line 2 (controls container/Traefik names; no namespace needed).
  - **Acceptance:** `kamal config | grep -E '^\s*image:'` shows `<REGISTRY_NAMESPACE>/open_repo` · after build,
    `docker manifest inspect <registry.server>/<REGISTRY_NAMESPACE>/open_repo:<git-sha>` returns JSON.
  - **Depends on:** D6

- [ ] **B2. Point `registry.server` at the real container registry and wire login creds**
  - **Type:** config + secret
  - **Files:** `config/deploy.yml:28-37`, `.kamal/secrets`
  - **Why:** `registry.server` is `localhost:5555` (line 30) and `username`/`password` are commented (lines 33-37).
    Kamal cannot authenticate to push the image; `kamal deploy` fails at build/push.
  - **Steps:**
    1. Edit `config/deploy.yml:30`: `server: ghcr.io` (or `registry-1.docker.io` / `registry.digitalocean.com` / `<REAL_REGISTRY_HOST>`).
       For Docker Hub you may OMIT `server:` entirely.
    2. Uncomment `username:` → `<REGISTRY_USERNAME>` (literal string; for ghcr.io this is your GH user/org).
    3. Uncomment the password block so it reads `password:` then `  - KAMAL_REGISTRY_PASSWORD`.
    4. In `.kamal/secrets` add ONE active source for `KAMAL_REGISTRY_PASSWORD`. ghcr.io:
       `KAMAL_REGISTRY_PASSWORD=$(gh config get -h github.com oauth_token)` or a PAT with `write:packages`. Docker Hub:
       create an access token and `KAMAL_REGISTRY_PASSWORD=$DOCKER_HUB_TOKEN`. Use the SAME resolution strategy as
       `RAILS_MASTER_KEY` (see B5).
    5. Verify it resolves in the deploy shell: `echo $KAMAL_REGISTRY_PASSWORD | head -c4` is non-empty, or `kamal secrets print` shows it.
  - **Acceptance:** `kamal registry login` prints `Login Succeeded` locally and on every server · `kamal build push`
    completes with no 401/denied · `grep -n KAMAL_REGISTRY_PASSWORD .kamal/secrets` shows an active (uncommented) line.
  - **Depends on:** B1, B5, D6

- [ ] **B3. Set the real deploy host(s) under `servers.web`; keep the single web role (jobs in Puma)**
  - **Type:** config
  - **Files:** `config/deploy.yml:9-14`, `config/puma.rb:21`
  - **Why:** `servers.web` is the placeholder `192.168.0.1` (line 10) — Kamal cannot SSH to a real host. The `job:` role
    is commented; for single-node `SOLID_QUEUE_IN_PUMA` we intentionally keep ONE web role (jobs run inside Puma).
    Splitting roles would **double-run recurring jobs** against the single-writer SQLite.
  - **Steps:**
    1. Edit `config/deploy.yml:10`: replace `192.168.0.1` with `<REAL_HOST>` (public IP or DNS reachable by SSH as root, or set `ssh.user`).
    2. Leave the `job:` block (lines 11-14) COMMENTED — recurring jobs run in Puma via `SOLID_QUEUE_IN_PUMA`
       (`config/puma.rb:21`). Do NOT add a job role unless you ALSO remove `SOLID_QUEUE_IN_PUMA`, or `recurring.yml` jobs run twice.
    3. If the SSH user is not root, uncomment lines 93-95 (`ssh:` / `  user: <SSH_USER>`) and ensure that user can run docker.
    4. Confirm SSH key auth: `ssh root@<REAL_HOST> docker --version` returns a version.
  - **Acceptance:** `kamal config | grep -A2 'servers'` shows `<REAL_HOST>` · `kamal deploy` reaches the host (no SSH errors) ·
    after deploy `kamal app exec 'bin/rails runner "puts SolidQueue::Process.count"'` returns >= 1.
  - **Depends on:** D2

- [ ] **B4. Provision the real `config/master.key` (`RAILS_MASTER_KEY`) and verify credentials decrypt**
  - **Type:** secret
  - **Files:** `config/master.key` (ABSENT from checkout), `config/credentials.yml.enc` (committed, 760 bytes),
    `.kamal/secrets:20`, `config/deploy.yml:41-42`
  - **Why:** `.kamal/secrets:20` runs `RAILS_MASTER_KEY=$(cat config/master.key)` but `config/master.key` is gitignored
    (`.gitignore` `/config/*.key`) and not in the checkout. Without it credentials cannot decrypt: the app boots but
    `Rails.application.credentials.dig(:google_oauth, ...)` is nil → every Google login fails AND `secret_key_base`
    cannot be derived → cookie/session signing breaks. Assets were precompiled with `SECRET_KEY_BASE_DUMMY=1`
    (`Dockerfile:55`) so runtime `secret_key_base` depends entirely on this key. **Silent failure, not a clean crash.**
  - **Steps:**
    1. Decide recoverable vs regenerate. Candidate sources, in order: (a) the dev who created `credentials.yml.enc`
       (their local `config/master.key`), (b) a password/secret manager, (c) the deploy host if a prior deploy placed it.
    2. If genuinely lost: you cannot recover. Delete BOTH `config/credentials.yml.enc` and `config/master.key`, run
       `EDITOR="code --wait" bin/rails credentials:edit` (generates a fresh pair), re-enter `google_oauth` keys
       (see B7), commit the new `credentials.yml.enc`; never commit `master.key`.
    3. Place the real key at `config/master.key`, `chmod 600 config/master.key`. Confirm `git status` shows it ignored.
    4. Verify locally:
       `RAILS_MASTER_KEY=$(cat config/master.key) bin/rails runner "p Rails.application.credentials.dig(:google_oauth)&.keys"`
       prints the OAuth keys, not nil.
    5. `kamal secrets print` shows `RAILS_MASTER_KEY` populated (~32 hex chars).
  - **Acceptance:** `test -f config/master.key && echo present` → `present` · `git check-ignore config/master.key` →
    `config/master.key` · `bin/rails runner 'puts Rails.application.credentials.dig(:google_oauth, :client_id).present?'`
    → `true` · after deploy `kamal app exec 'bin/rails runner "p Rails.application.credentials.dig(:google_oauth).present?"'` → `true`.
  - **Depends on:** (decide recoverable vs regenerate)

- [ ] **B5. Make `.kamal/secrets` `RAILS_MASTER_KEY` resolution robust (the `cat config/master.key` fragility)**
  - **Type:** config + secret
  - **Files:** `.kamal/secrets:20`, `config/deploy.yml:41-42`
  - **Why:** `kamal deploy` runs `.kamal/secrets` on the MACHINE THAT INVOKES THE DEPLOY (operator laptop / CI runner),
    not on the server. On any machine without `config/master.key`, `cat` fails → empty `RAILS_MASTER_KEY` → Kamal pushes an
    empty secret → container boots without a usable key and silently fails OAuth + sessions. (CI today only test/lint/scan
    in `RAILS_ENV=test`, so CI is not broken yet — but any deploy from CI/another box hits this.)
  - **Steps:** Choose ONE and document it in `.kamal/secrets`:
    - **Option A (env passthrough, simplest for CI):** `RAILS_MASTER_KEY=${RAILS_MASTER_KEY:-$(cat config/master.key)}`.
    - **Option B (password manager, recommended):** use the commented `kamal secrets fetch/extract` examples at
      `.kamal/secrets:5-8` (1Password etc.).
    - Either way, fail loudly if empty:
      `[ -n "$RAILS_MASTER_KEY" ] || { echo 'RAILS_MASTER_KEY is empty (no master.key and no env/secret-manager value)'; exit 1; }`.
    - Keep `config/deploy.yml:41-42` `env.secret: [RAILS_MASTER_KEY]` unchanged.
  - **Acceptance:** On a machine WITHOUT `config/master.key` but WITH `RAILS_MASTER_KEY` exported (A) or a configured PW
    manager (B): `kamal secrets print` resolves a non-empty value · with neither present, the guard exits non-zero with the message.
  - **Depends on:** B4

- [ ] **B6. Set `REGISTRY_HOST` in `env.clear` to the real `host[:port]` (drives every `/help` docker command)**
  - **Type:** config
  - **Files:** `config/deploy.yml:43-46` (env.clear), `config/application.rb:49`, `app/views/help/show.html.erb`, `app/helpers/repositories_helper.rb`
  - **Why:** `config.registry_host` defaults to `localhost:3000` (`config/application.rb:49`). It is interpolated into every
    `docker login/tag/push/pull` and containerd/insecure-registries snippet on `/help` and on repo pages. With the default,
    every copy-paste command points at `localhost:3000` (wrong host AND wrong port — prod serves on 80/443, not 3000). It is
    NOT currently injected via deploy.yml (env.clear has only `SOLID_QUEUE_IN_PUMA`).
  - **Steps:**
    1. Edit `config/deploy.yml` under `env.clear`: add `REGISTRY_HOST: <REGISTRY_DNS_NAME>` (no scheme; with TLS on 443 omit
       the port, e.g. `registry.example.com`; non-standard port → include it, e.g. `registry.example.com:8080`). Match
       `proxy.host` (Option A) / Nginx `server_name` (Option B) / the cert's DNS name exactly.
    2. Redeploy (or `kamal env push`) so the new env reaches the container.
  - **Acceptance:** `kamal app exec 'bin/rails runner "puts Rails.configuration.registry_host"'` prints `<REGISTRY_DNS_NAME>` ·
    `GET https://<REGISTRY_DNS_NAME>/help` shows `docker login <REGISTRY_DNS_NAME> …` (not `localhost:3000`) ·
    `kamal app exec 'printenv REGISTRY_HOST'` returns `<REGISTRY_DNS_NAME>`.
  - **Depends on:** D1

- [ ] **B7. Verify Google OAuth credentials decrypt and are populated (`client_id` + `client_secret`)**
  - **Type:** secret
  - **Files:** `config/credentials.yml.enc`, `config/initializers/omniauth.rb:3-6`
  - **Why:** `omniauth.rb:3-4` reads `Rails.application.credentials.dig(:google_oauth, :client_id)` / `(:client_secret)`. If
    `credentials.yml.enc` was scaffolded with only `secret_key_base` (or empty `google_oauth`), OmniAuth initializes with nil
    creds → Google returns `invalid_client` / callback fails → no user can sign in → no PATs → no authenticated push. The file
    being present (760 bytes) does NOT prove the keys are filled.
  - **Steps:**
    1. After B4, inspect KEYS (not values) on a trusted machine: `bin/rails credentials:show | grep -A3 google_oauth`. Expect a
       `google_oauth:` block with non-empty `client_id:` and `client_secret:`.
    2. If missing/empty: `EDITOR="code --wait" bin/rails credentials:edit` and add:
       ```yaml
       google_oauth:
         client_id: <from Google Cloud Console>
         client_secret: <from Google Cloud Console>
       ```
       Save; Rails re-encrypts. Commit the updated encrypted file (safe to commit).
  - **Acceptance:**
    `bin/rails runner 'puts Rails.application.credentials.dig(:google_oauth, :client_id).present? && Rails.application.credentials.dig(:google_oauth, :client_secret).present?'`
    → `true` · after deploy `kamal app exec 'bin/rails runner "puts Rails.application.credentials.dig(:google_oauth, :client_secret).present?"'` → `true`.
  - **Depends on:** B4, External Google Cloud Console OAuth setup (see External setup)

- [ ] **B8. External Google Cloud Console OAuth client setup (operator does this in the GCP web console)**
  - **Type:** ops (external)
  - **Files:** `config/initializers/omniauth.rb`, `config/routes.rb:4`
  - **Why:** The `client_id`/`client_secret` only work if a matching OAuth 2.0 Client exists in GCP with the EXACT production
    redirect URI. A mismatch (http vs https, wrong host, missing `/auth/google_oauth2/callback`, trailing slash) → `Error 400:
    redirect_uri_mismatch` → nobody logs in. Cannot be verified by tests.
  - **Steps:**
    1. GCP → APIs & Services → Credentials → create/reuse an OAuth 2.0 Client ID, type **Web application**.
    2. Authorized redirect URI (EXACT): `https://<PROD_HOST>/auth/google_oauth2/callback`. (`routes.rb:4` maps
       `/auth/:provider/callback`; omniauth-google-oauth2 1.2.2 provider = `google_oauth2`.) Use https. Register every served host variant.
    3. Authorized JavaScript origins: `https://<PROD_HOST>` (no path). Add each served host variant.
    4. Configure the OAuth consent screen (app name, support email, developer contact). External-unverified: add launch users as
       Test users OR publish. Scopes requested: `email,profile` (`omniauth.rb:6`) — non-sensitive, no Google verification required,
       but the consent screen MUST be configured or login is "access blocked".
    5. Copy Client ID/Secret into Rails credentials under `google_oauth:` (B7). Document GCP project + client name + owning account.
    6. Separate staging/prod hosts → add a redirect URI for each (or separate clients).
  - **Acceptance:** GCP lists exactly `https://<PROD_HOST>/auth/google_oauth2/callback` and origin `https://<PROD_HOST>` ·
    manual: visit `https://<PROD_HOST>/sign_in` → "Sign in with Google" → consent → land authenticated (no `redirect_uri_mismatch`/`access blocked`).
  - **Depends on:** D1 (https scheme), final production host(s)

- [ ] **B9. [D1=A] Enable Kamal built-in proxy with Let's Encrypt TLS**
  - **Type:** config
  - **Files:** `config/deploy.yml:23-25`
  - **Why:** If Option A, the proxy block (lines 23-25) is commented out, so kamal-proxy serves plain HTTP on 80 with no cert.
    Without `proxy.ssl` + `proxy.host` there is no HTTPS endpoint and Docker refuses Basic auth to the remote host.
  - **Steps:**
    1. Uncomment and set:
       ```yaml
       proxy:
         ssl: true
         host: <REGISTRY_DNS_NAME>
         app_port: 80
       ```
       `app_port: 80` because `Dockerfile:76` `EXPOSE 80` + `CMD ./bin/thrust ./bin/rails server` → Thruster listens on 80
       and proxies to Puma:3000. Do NOT set `app_port: 3000`.
    2. Confirm `servers.web` is the real host and DNS A/AAAA for `<REGISTRY_DNS_NAME>` points at it BEFORE deploy (HTTP-01).
    3. Open inbound 80 (ACME + redirect) and 443 (TLS). 80 MUST stay open (closing it breaks issuance/renewal).
    4. Do NOT publish the container port to the host directly (kamal-proxy fronts it). Deploy with `kamal deploy`.
  - **Acceptance:** `kamal proxy logs` shows ssl enabled + issued cert · `curl -I https://<REGISTRY_DNS_NAME>/up` → 200 over a
    valid (non-self-signed) chain (`openssl s_client -connect <REGISTRY_DNS_NAME>:443` verify return code 0) ·
    `curl -sI http://<REGISTRY_DNS_NAME>/up` → 301/308 to https.
  - **Depends on:** D1=A, B10

- [ ] **B10. Enable `config.assume_ssl` (both options) and `config.force_ssl` with `/up` redirect exclusion**
  - **Type:** config
  - **Files:** `config/environments/production.rb:28,31,34`
  - **Why:** Both are commented (`production.rb:28` assume_ssl, `:31` force_ssl, `:34` ssl_options). With TLS terminated upstream,
    Rails receives plaintext on 80 and without `assume_ssl` marks cookies non-Secure and generates `http://` URLs. `force_ssl`
    adds HSTS, Secure cookies, and the http→https redirect. `config/deploy.yml:19` explicitly notes the SSL proxy "requires
    turning on config.assume_ssl and config.force_ssl". Enable as a MATCHED PAIR.
  - **Steps:**
    1. Uncomment `production.rb:28` → `config.assume_ssl = true` (required in BOTH Option A and B).
    2. Uncomment `production.rb:31` → `config.force_ssl = true`.
    3. Uncomment `production.rb:34` → `config.ssl_options = { redirect: { exclude: ->(request) { request.path == "/up" } } }`
       so the Kamal/host healthcheck (probed over plain HTTP) is not 301-redirected.
    4. Because `assume_ssl=true`, Rails sees push/pull (incl. POST/PUT/PATCH to `/v2`) as already-HTTPS, so `force_ssl` does NOT
       redirect them once the client uses `https://`. No special `/v2` exclusion needed — verify with the push in B12.
    5. **Do NOT enable `force_ssl` without `assume_ssl` behind a proxy** or you get a redirect loop.
  - **Acceptance:** `bin/rails runner -e production 'p [Rails.application.config.assume_ssl, Rails.application.config.force_ssl]'`
    → `[true, true]` · `curl -sI https://<REGISTRY_DNS_NAME>/` shows `Strict-Transport-Security` · `curl -sI http://<REGISTRY_DNS_NAME>/up`
    → 200 (NOT a redirect) · an authenticated `docker push` over HTTPS completes with no `http: server gave HTTP response to HTTPS client`.
  - **Depends on:** D1

- [ ] **B11. [D1=B] Front the app with an external Nginx TLS reverse proxy**
  - **Type:** config
  - **Files:** `config/deploy.yml`, `app/views/help/show.html.erb:122-138`, `README.md`
  - **Why:** If Option B, you must NOT let kamal-proxy also terminate TLS (double-proxy / :443 conflict), you must publish the
    app so Nginx can reach it, and Nginx must pass `X-Forwarded-Proto=https` and lift the body cap. Missing X-Forwarded-Proto →
    http:// URLs / force_ssl bounces pushes; missing `client_max_body_size 0` → Nginx 413s large blob PUTs before Rails.
  - **Steps:**
    1. Decide how Nginx reaches the app: (i) disable kamal-proxy and publish the container to a host port (e.g. `127.0.0.1:3000->80`)
       so Nginx `proxy_pass http://127.0.0.1:3000`; or (ii) keep kamal-proxy on a localhost-only port and proxy_pass to it. Do not let
       kamal-proxy hold :443 if Nginx wants :443.
    2. Base the server block on `app/views/help/show.html.erb:122-138` / README. Critical directives:
       ```nginx
       listen 443 ssl; server_name <REGISTRY_DNS_NAME>;
       ssl_certificate <...>; ssl_certificate_key <...>;   # certbot or corporate CA — record renewal owner
       client_max_body_size 0; proxy_request_buffering off; # stream large blobs, avoid 413
       proxy_read_timeout 3600s; proxy_send_timeout 3600s;  # GB layers take minutes
       proxy_set_header X-Forwarded-Proto $scheme;
       proxy_set_header Host $host;
       proxy_set_header X-Real-IP $remote_addr;
       proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
       ```
    3. Add a port-80 server block that 301-redirects to https EXCEPT keep `/up` reachable over HTTP for healthchecks.
    4. Enable `config.assume_ssl=true` (B10) so Rails trusts X-Forwarded-Proto.
    5. Verify the Help-page Nginx snippet matches the real upstream port you deploy.
  - **Acceptance:** `curl -I https://<REGISTRY_DNS_NAME>/up` → 200 over the deployed cert · `curl -sI http://<REGISTRY_DNS_NAME>/`
    → 301/308 to https while `/up` still serves over HTTP · a multi-hundred-MB push succeeds (no 413) ·
    `nginx -T | grep -E 'client_max_body_size|proxy_request_buffering|proxy_read_timeout'` shows the values.
  - **Depends on:** D1=B, B10

- [ ] **B12. End-to-end TLS auth acceptance: 401+`WWW-Authenticate` over HTTPS, docker login, push, pull**
  - **Type:** ops
  - **Files:** `app/controllers/v2/base_controller.rb:61`, `test/integration/docker_cli_test.sh`
  - **Why:** This is the actual goal. The `WWW-Authenticate: Basic realm="Registry"` challenge (`base_controller.rb:61`) is only
    usable by the Docker client over HTTPS to a non-localhost host. These checks prove the whole chain (DNS → TLS → assume_ssl →
    Basic challenge → PAT auth) before announcing the server.
  - **Steps:**
    1. Ensure `REGISTRY_ADMIN_EMAIL` is set, that account has completed Google sign-in, and has minted a PAT (`oprk_…`) — see B13.
    2. From a REMOTE machine (not the registry host): `curl -I https://<REGISTRY_DNS_NAME>/v2/` → expect 401 with
       `WWW-Authenticate: Basic realm="Registry"` and `Docker-Distribution-API-Version: registry/2.0`.
    3. `docker login <REGISTRY_DNS_NAME> -u <ADMIN_EMAIL> -p <oprk_token>` → `Login Succeeded`.
    4. `docker tag <local image> <REGISTRY_DNS_NAME>/test:1 && docker push <REGISTRY_DNS_NAME>/test:1` → succeeds, no TLS/redirect errors.
    5. `docker rmi <REGISTRY_DNS_NAME>/test:1 && docker pull <REGISTRY_DNS_NAME>/test:1` → succeeds.
    6. Optionally run `test/integration/docker_cli_test.sh` against the live HTTPS host.
  - **Acceptance:** the 401+header over TLS, `Login Succeeded`, and push+pull from a non-localhost client all pass.
  - **Depends on:** B9 or B11, B10, B6, B13

- [ ] **B13. Bootstrap the first-push admin: set `REGISTRY_ADMIN_EMAIL` and pre-create that OAuth user (ORDERING TRAP)**
  - **Type:** config + ops
  - **Files:** `config/deploy.yml` env.clear, `config/initializers/registry.rb:2`, `app/services/manifest_processor.rb:18-20`, `db/seeds.rb` (empty)
  - **Why:** `manifest_processor.rb:18-20` runs `User.find_by!(email: REGISTRY_ADMIN_EMAIL).primary_identity` inside
    `find_or_create_by!` on FIRST push to a NEW repo. `registry.rb:2` defaults `admin_email` to nil and `db/seeds.rb` is empty, so a
    first `docker push` to a fresh server raises `RecordNotFound` → 500 (and `find_by!` on a nil email also fails).
  - **Steps:**
    1. Add to `config/deploy.yml` env.clear: `REGISTRY_ADMIN_EMAIL: <ADMIN_EMAIL>` (the exact Google account that will own auto-created repos).
    2. Deploy, THEN have `<ADMIN_EMAIL>` complete a Google sign-in on the live site (creates User + primary_identity). **This MUST
       happen before the first push.** Setting `REGISTRY_ADMIN_EMAIL` before that user has signed in is the ordering trap.
    3. After step 2, if env changed without a redeploy, `kamal env push`.
    4. Hardening (covered by B14): replace the bare `find_by!` with a clear `Registry::AdminBootstrapMissing` error.
  - **Acceptance:** `kamal app exec 'bin/rails runner "puts Rails.configuration.x.registry.admin_email"'` prints `<ADMIN_EMAIL>` ·
    `kamal app exec 'bin/rails runner "puts User.find_by(email: Rails.configuration.x.registry.admin_email)&.primary_identity&.id.inspect"'`
    prints a non-nil id · a first `docker push <REGISTRY_DNS_NAME>/myapp:latest` returns 201/200 (not 500) and `Repository.find_by(name: 'myapp')` exists.
  - **Depends on:** B4 (OAuth must decrypt), B12 (push must work over TLS)

- [ ] **B14. CODE: Graceful error for first-push admin bootstrap (`RecordNotFound`→500) + nil `primary_identity` guard**
  - **Type:** code
  - **Files:** `app/services/manifest_processor.rb:18-21`, `app/errors/registry.rb`, `app/controllers/v2/base_controller.rb`, `test/services/manifest_processor_test.rb:282`
  - **Why:** `manifest_processor.rb:18-21` does `User.find_by!(email: admin_email).primary_identity` inside `find_or_create_by!`. On a
    fresh server the admin may be set but not yet signed in → `RecordNotFound`; `base_controller.rb` has no `rescue_from` for it → opaque
    500. Even if the user exists, `.primary_identity` can be nil (`optional: true`) → `NoMethodError` → 500. NOTE:
    `manifest_processor_test.rb:282` currently PINS the raw `RecordNotFound` as intentional — update it and confirm the 500→clear-error conversion is desired.
  - **Steps (TDD):**
    1. Add `class AdminBootstrapMissing < Error; end` to `app/errors/registry.rb`.
    2. In `manifest_processor.rb`, replace the owner block: `admin = User.find_by(email: admin_email)`; raise
       `Registry::AdminBootstrapMissing` naming `REGISTRY_ADMIN_EMAIL` when admin nil; `identity = admin.primary_identity`; raise same
       error ("…has not completed first sign-in") when identity nil; set `r.owner_identity = identity`.
    3. In `base_controller.rb` add `rescue_from Registry::AdminBootstrapMissing, with: ->(e) { render_error("DENIED", e.message, 503) }`.
    4. Update `manifest_processor_test.rb:282` to `assert_raises(Registry::AdminBootstrapMissing)` with a message mentioning
       `REGISTRY_ADMIN_EMAIL`; add a case where admin exists but `primary_identity` is nil.
    5. Add an integration test: PUT manifest to a fresh repo with a bad admin email returns the chosen status with
       `errors[0].message` containing `REGISTRY_ADMIN_EMAIL`.
  - **Acceptance:** `bin/rails test test/services/manifest_processor_test.rb` green with the new assertion · the new controller test
    passes · `manifest_processor.rb` has no bare `find_by!` in owner assignment and guards nil `primary_identity`.
  - **Depends on:** (confirm 500→clear-error conversion)

- [ ] **B15. Run `kamal setup` to install Docker/proxy on the host before the first deploy**
  - **Type:** ops
  - **Files:** `config/deploy.yml`, `.kamal/hooks/` (only `*.sample`, none active)
  - **Why:** Kamal 2.x requires Docker present on the server and kamal-proxy installed; a bare host needs `kamal setup` (not just
    `kamal deploy`) the first time. The operator must know setup is a distinct first step.
  - **Steps:**
    1. Ensure Docker is installable/installed on `<REAL_HOST>` (kamal can install it); verify SSH root/sudo.
    2. Run `kamal setup` once (installs Docker if missing, boots kamal-proxy, pushes env, runs the first deploy).
    3. Subsequent releases: `kamal deploy`.
    4. Optional clean-checkout guard: copy `.kamal/hooks/pre-build.sample` → `.kamal/hooks/pre-build` (remove `.sample`, keep executable).
  - **Acceptance:** `kamal setup` completes; `ssh root@<REAL_HOST> docker ps` shows the app container + kamal-proxy ·
    `kamal app version` returns the deployed git sha.
  - **Depends on:** B3, B2, B4

- [ ] **B16. Verify first-boot migrations run AND seed/confirm admin so the first push does not 500**
  - **Type:** ops
  - **Files:** `bin/docker-entrypoint:4`, `Dockerfile:77`, `config/database.yml:25-40`, `db/seeds.rb`, `app/services/manifest_processor.rb:18-20`
  - **Why:** First boot must create+migrate FOUR SQLite DBs (primary/cache/queue/cable). `bin/docker-entrypoint:4` runs
    `bin/rails db:prepare` ONLY when the last two CMD args are exactly `./bin/rails server`. `Dockerfile:77` CMD is
    `["./bin/thrust","./bin/rails","server"]` so the guard passes today — but it is fragile: any CMD change silently SKIPS
    migrations → every request 500s with missing tables. Separately, the admin must already exist (B13).
  - **Steps:**
    1. After first deploy confirm all four DB files: `kamal app exec 'ls -la /rails/storage'` shows
       `production.sqlite3`, `production_cache.sqlite3`, `production_queue.sqlite3`, `production_cable.sqlite3`.
    2. Confirm schema current: `kamal app exec 'bin/rails runner "puts ActiveRecord::Migrator.current_version"'` non-zero and
       `kamal app exec 'bin/rails db:migrate:status'` shows no `down`.
    3. Do NOT change CMD without re-checking the `${@: -2:1}`/`${@: -1:1}` match. Optional hardening (separate commit): broaden the
       guard to match `server` anywhere in args OR an env flag; test locally with the real CMD.
    4. `db:prepare` runs on EVERY boot (idempotent) — acceptable single-node; do not run migrations manually.
  - **Acceptance:** `kamal app exec 'bin/rails runner "puts ActiveRecord::Base.connection.tables.size"'` > 0 ·
    `kamal app exec 'bin/rails db:migrate:status | grep -c down'` → 0 · `GET https://<REGISTRY_DNS_NAME>/` → 200 (no missing-table 500).
  - **Depends on:** B12, B19

- [ ] **B17. Verify the Solid Queue supervisor runs and ALL FOUR recurring jobs fire on the single node**
  - **Type:** ops
  - **Files:** `config/deploy.yml:46`, `config/puma.rb:21`, `config/recurring.yml`, `config/queue.yml`, `config/environments/production.rb:53-54`
  - **Why:** All GC/retention/prune hang off Solid Queue. `deploy.yml:46` sets `SOLID_QUEUE_IN_PUMA: true` and `puma.rb:21` loads
    `plugin :solid_queue if ENV['SOLID_QUEUE_IN_PUMA']`. If the plugin silently fails or the queue DB isn't migrated, then
    `cleanup_orphaned_blobs` (30m), `enforce_retention_policy` (3am), `prune_old_events` (4am), `clear_solid_queue_finished_jobs`
    (hourly) NEVER run → orphaned blobs accumulate, the shared volume fills, and ALL FOUR SQLite DBs corrupt at once (latent total
    outage). No test asserts this in prod — VERIFY on the live node.
  - **Steps:**
    1. Keep `SOLID_QUEUE_IN_PUMA: true` (already present). Do NOT add a separate `job:` role.
    2. `kamal app exec 'ps aux | grep -i solid_queue'` → expect a Supervisor/Dispatcher/Worker tree.
    3. `kamal app exec "bin/rails runner 'pp SolidQueue::RecurringTask.pluck(:key).sort'"` → includes
       `cleanup_orphaned_blobs`, `clear_solid_queue_finished_jobs`, `enforce_retention_policy`, `prune_old_events` (4 keys).
    4. `kamal app exec "bin/rails runner 'pp SolidQueue::Process.pluck(:kind, :last_heartbeat_at)'"` → Supervisor + Dispatcher + Worker, heartbeats < 1 min.
    5. Force one: `kamal app exec "bin/rails runner 'CleanupOrphanedBlobsJob.perform_now'"`; check logs for no error.
    6. FALLBACK if recurring tasks are missing under the in-Puma plugin: switch to a dedicated job role (uncomment `job:` lines
       11-14 with `cmd: bin/jobs`) and re-verify the 4 rows. Add a post-deploy checklist line that re-runs the `RecurringTask.count` assertion.
  - **Acceptance:** `SolidQueue::RecurringTask.count == 4` with the exact keys · Supervisor heartbeat < 1 min · a manual
    `CleanupOrphanedBlobsJob` reaches `finished_at` within a minute · past the top of the hour, `clear_solid_queue_finished_jobs` has a recorded run.
  - **Depends on:** B12, B19

- [ ] **B18. Implement a real off-server backup of the volume + a standalone restore drill (incl. master.key co-restore)**
  - **Type:** ops
  - **Files:** `config/deploy.yml:70`, `lib/tasks/`, `bin/`, `config/recurring.yml`, `.kamal/secrets`
  - **Why:** `config/deploy.yml:70` literally says "Recommended to change this to a mounted volume path that is backed up off
    server" but NOTHING implements backup (grep for backup/rsync/VACUUM returns nothing). A single-host SQLite + filesystem
    registry with no backup means one disk failure / fat-fingered `docker volume rm` / corruption loses every image and all
    metadata permanently. A backup never restored is not a backup. **Restoring the volume WITHOUT the matching `RAILS_MASTER_KEY`
    yields a booting app that cannot decrypt OAuth creds** — the key must be restored alongside.
  - **Steps:**
    1. Choose a backup target (S3/GCS or remote host over rsync/ssh); store creds in `.kamal/secrets`, not the image.
    2. Back up SQLite SAFELY (never `cp` a live WAL DB): for each of the 4 DBs use the online backup API, e.g.
       `sqlite3 storage/production.sqlite3 ".backup '/tmp/backup/production.sqlite3'"` (repeat cache/queue/cable).
    3. Back up blobs with rsync / `aws s3 sync` of `storage/registry/blobs` (content-addressed, never mutated → safe to copy live, cheap incremental).
    4. Skip `storage/registry/uploads` (in-flight, disposable).
    5. Wrap in `bin/backup` or `lib/tasks/backup.rake`, run INSIDE the container, push artifacts off-host.
    6. Schedule via `config/recurring.yml` (e.g. `backup_volume: { class: BackupVolumeJob, schedule: every day at 2am }`) so it shares the in-Puma supervisor.
    7. **Restore drill (standalone go-live gate):** on a throwaway host, place the 4 `.sqlite3` files + `blobs/` tree on a fresh
       volume AND the separately-stored `master.key`, boot, confirm `docker pull <known image>` succeeds AND Google OAuth decrypts.
    8. Add a retention rule on the target (e.g. 7 daily + 4 weekly).
  - **Acceptance:** one backup run produces 4 `.sqlite3` snapshots + a `blobs/` mirror off-server ·
    `sqlite3 <restored>/production.sqlite3 'PRAGMA integrity_check;'` → `ok` · full restore drill: a fresh container from the
    restored volume + restored master.key serves `docker pull` AND decrypts OAuth; result recorded here · backups appear on schedule (check 2 cycles).
  - **Depends on:** B4, High H1 (volume sizing)

---

## High priority (should do)

- [ ] **H1. Size and document the single persistent volume (blobs + 4 SQLite DBs + upload sessions)**
  - **Type:** config/decision
  - **Files:** `config/deploy.yml:69-72`, `config/database.yml`, `config/cache.yml`, `config/application.rb:48`
  - **Why:** Everything writable lives on ONE Docker volume `open_repo_storage:/rails/storage`: layer blobs, in-flight upload
    bytes, and all four SQLite DBs. A full volume corrupts/aborts writes to cache, queue, AND cable at once — taking down job
    processing, Rack::Attack throttling (solid_cache), and ActionCable together.
  - **Steps:**
    1. Model `total_blob_bytes = sum(unique layer sizes)` × repos × retained tags (dedup via `references_count`). Budget the 4 DBs
       (primary grows with manifests/pull_events/tag_events; cache bounded by `config/cache.yml` max_size ~256MB; queue bounded by
       hourly clear; cable tiny). Reserve ~2-4GB for SQLite WAL/-shm + VACUUM scratch (VACUUM needs free ≈ DB size).
    2. Reserve transient headroom = `peak_concurrent_pushes × max_layer_size` for in-flight uploads.
    3. Volume size = `blob_growth(12mo) + sqlite_budget + upload_headroom + 30%`. Add the number + formula as a comment above the `volumes:` block.
    4. Bind-mount option: point at a partition you can grow (LVM/EBS); record the resize procedure.
  - **Acceptance:** `deploy.yml volumes:` has a comment stating the chosen size + formula · on the host
    `docker volume inspect open_repo_storage` (or the bind partition) shows capacity >= budget · `df -h <mountpoint>` after a representative push run < 70% used.
  - **Depends on:** D2

- [ ] **H2. Confirm persistent volume mount + storage layout, and that data survives a redeploy**
  - **Type:** ops
  - **Files:** `config/deploy.yml:72`, `config/database.yml`, `config/application.rb:48`, `config/storage.yml`, `Dockerfile:66`
  - **Why:** All durable state lives on the volume: the 4 SQLite DBs, Active Storage `:local`, and blob bytes
    (`application.rb:48` `STORAGE_PATH` default `/rails/storage/registry`). If the volume is missing/not mounted, data is lost on
    every redeploy and SQLite writes go to the ephemeral container layer.
  - **Steps:**
    1. Keep the named volume for single-node. For backups, consider a HOST bind path (`/srv/open_repo/storage:/rails/storage`)
       owned by uid 1000 (`Dockerfile:66` runs `USER 1000:1000`).
    2. Leave `STORAGE_PATH` unset (default is on the mounted volume); only set it to relocate to a subdir of a mounted volume.
    3. Verify the mount + persistence (acceptance). Set up disk monitoring (H3) + the off-server backup (B18).
  - **Acceptance:** `kamal app exec 'df -h /rails/storage'` shows the mounted volume (not overlay root) with free space ·
    `kamal app exec 'ls /rails/storage/registry'` lists blob dirs after a push; push a tag, `kamal deploy`, then `docker pull` the
    same tag succeeds · `kamal app exec 'stat -c %U /rails/storage'` shows it writable by uid 1000.
  - **Depends on:** B3, D2

- [ ] **H3. Add disk-capacity monitoring/alerting + write backpressure before the volume fills**
  - **Type:** ops/code
  - **Files:** `app/controllers/v2/blob_uploads_controller.rb`, `config/recurring.yml`, `config/deploy.yml`
  - **Why:** Zero disk monitoring. Because blobs + all 4 SQLite DBs share one volume, hitting 100% does not cleanly 507 — it causes
    `SQLITE_FULL`/`disk I/O error` on pushes AND corrupts cache/queue, and the only error sink is stdout. Pushes keep being accepted and
    write partial bytes until exhaustion. No backpressure rejects new uploads when nearly full.
  - **Steps:**
    1. Recurring job (`config/recurring.yml`) running `df` against `Rails.configuration.storage_path`'s filesystem; log/alert at
       warn 80% / critical 90%.
    2. Wire the alert to the chosen sink (D4); at minimum log at `:error`.
    3. Backpressure in `V2::BlobUploadsController#create` (`handle_start_upload`/`handle_monolithic_upload`): if free bytes <
       `DISK_MIN_FREE_BYTES`, reject with HTTP 507 BEFORE writing upload bytes.
    4. Make thresholds env-configurable (`DISK_WARN_PCT`, `DISK_CRITICAL_PCT`, `DISK_MIN_FREE_BYTES`); document defaults in deploy.yml.
    5. Confirm Docker json-file rotation is set (H7) so monitoring logs don't fill the disk.
  - **Acceptance:** simulate low disk → a new `docker push` is rejected with 507 (not a partial/corrupt write) · the monitoring job
    emits a warning when crossing the threshold (lower `DISK_WARN_PCT` to verify) · unit test: `#create` returns 507 when free < `DISK_MIN_FREE_BYTES` (stub the free-space check).
  - **Depends on:** D4

- [ ] **H4. CODE: Fix re-push reference-count leak in `ManifestProcessor#create_layers!` (blobs become un-GC-able)**
  - **Type:** code
  - **Files:** `app/services/manifest_processor.rb:91-102`, `app/models/layer.rb`, `app/jobs/cleanup_orphaned_blobs_job.rb`
  - **Why:** `create_layers!` (`manifest_processor.rb:92-101`) does `manifest.layers.destroy_all` then per layer
    `blob.increment!(:references_count)` + `Layer.create!`. `Layer` has NO `before_destroy`/dependent callback, so `destroy_all`
    removes Layer rows WITHOUT decrementing `references_count`. Because line 36 uses `find_or_initialize_by(digest:)`, re-pushing the
    SAME manifest (idempotent push, retries, CI re-pushes) re-runs `create_layers!`: destroys+recreates layers but only ever
    INCREMENTS. Each re-push permanently inflates every blob's `references_count`, so `CleanupOrphanedBlobsJob` (deletes only
    `references_count==0`) NEVER reclaims them — a slow storage leak that defeats GC and fills the shared volume.
  - **Steps (TDD):**
    1. Failing test: push manifest M (each layer blob refs → 1), push identical M again, assert each blob's `references_count`
       still 1 (today it's 2 — red).
    2. Fix: for an already-persisted manifest with layers, SKIP `create_layers!` entirely (content-addressed digest → layer set
       never changes). Or add a `before_destroy` on `Layer` that decrements `blob.references_count` so `destroy_all` rebalances, then re-increment on create.
    3. Keep all changes inside the existing `repository.with_lock` block (race-safe).
    4. Run `bin/rails test test/jobs test/services test/models`.
  - **Acceptance:** new test green (same manifest twice → `references_count == 1`) · existing
    `test/jobs/cleanup_orphaned_blobs_job_test.rb` + services/models tests pass · manual: push, push again, delete tag+manifest, run
    `CleanupOrphanedBlobsJob` → blobs reach `references_count 0` and are deleted from disk.
  - **Depends on:** —

- [ ] **H5. CODE: Reap stale `blob_uploads` DB rows together with the tmp upload bytes (orphan row leak)**
  - **Type:** code
  - **Files:** `app/services/blob_store.rb:90-108`, `app/jobs/cleanup_orphaned_blobs_job.rb`, `app/models/blob_upload.rb`, `test/jobs/cleanup_orphaned_blobs_job_test.rb:177-198`
  - **Why:** An upload is two-sided: `handle_start_upload` (`blob_uploads_controller.rb:96-99`) creates BOTH a `blob_uploads` DB row
    AND an on-disk `uploads/<uuid>/` dir. If a client never completes/cancels, the reaper `BlobStore#cleanup_stale_uploads`
    (`blob_store.rb:90-108`) deletes ONLY the on-disk dir after 1h — it never deletes the row. Orphan `blob_uploads` rows accumulate
    forever in the single-writer primary DB, and after the dir is reaped the row points at a non-existent upload. Shipped tests
    (`:177-198`) only assert the DIR is removed.
  - **Steps (TDD):**
    1. Failing test: create a `BlobUpload` row + matching `uploads/<uuid>` dir older than max_age; run
       `CleanupOrphanedBlobsJob.perform_now`; assert BOTH `Dir.exist? == false` AND `BlobUpload.find_by(uuid:) == nil` (row survives today — red).
    2. Use the DB row's `created_at` as the staleness source of truth; reap rows where `created_at < max_age.ago`, deleting the
       on-disk dir AND `destroy!` the row, in `find_each` batches.
    3. Keep the filesystem sweep for orphaned dirs with NO matching row (monolithic temp dirs, half-rolled-back creates); keep `max_age` consistent (currently 1h).
    4. Preserve crash-safety (existing rescue of `ArgumentError`/`TypeError` on corrupt `startedat`).
  - **Acceptance:** new test passes (stale upload → both row + dir removed); fresh (<1h) keeps both (negative test) ·
    `bin/rails test test/jobs/cleanup_orphaned_blobs_job_test.rb` green · prod:
    `kamal app exec 'bin/rails runner "p BlobUpload.where(\"created_at < ?\", 1.hour.ago).count"'` trends to 0 after the job runs.
  - **Depends on:** —

- [ ] **H6. CODE: Stop per-anonymous-pull DB write amplification (3 SQLite writes per pull)**
  - **Type:** code
  - **Files:** `app/controllers/v2/manifests_controller.rb:120-133`, `test/controllers/v2/manifests_controller_test.rb`
  - **Why:** `record_pull_event` (`manifests_controller.rb:120-133`) runs THREE writes on the single-writer primary for every
    successful GET manifest: `manifest.increment!(:pull_count)`, `manifest.update_column(:last_pulled_at, …)`, and
    `PullEvent.create!`. The v2 throttle only matches non-GET/HEAD, so anonymous GETs are unthrottled. With `REGISTRY_ANONYMOUS_PULL=true`
    a scraper drives unbounded write load + unbounded `PullEvent` growth against the DB that serves pushes.
  - **Steps:**
    1. Collapse the two UPDATEs into one:
       `Manifest.where(id: manifest.id).update_all(["pull_count = pull_count + 1, last_pulled_at = ?", Time.current])`.
    2. Gate `PullEvent.create!` on `current_user.present?` (skip for anonymous pulls).
    3. Preserve remote_ip/user_agent attribution for authenticated pulls; verify `anonymous_pull_regression_test` only asserts the
       `remote_ip` COLUMN exists, not that anonymous pulls create rows, before changing.
    4. Tests: anonymous GET (anonymous_pull_enabled=true) → `PullEvent.count` unchanged AND `pull_count +1` AND `last_pulled_at`
       updated by one call; authenticated GET → exactly one `PullEvent` row + `pull_count +1`.
  - **Acceptance:** `bin/rails test test/controllers/v2/manifests_controller_test.rb` passes new assertions ·
    `bin/rails test test/integration/anonymous_pull_regression_test.rb` still green · `record_pull_event` does one manifest UPDATE and gates `PullEvent.create!` on `current_user`.
  - **Depends on:** D3

- [ ] **H7. Configure Docker json-file log driver with size+count rotation in Kamal**
  - **Type:** config
  - **Files:** `config/deploy.yml`, `config/environments/production.rb:36-41`
  - **Why:** `production.rb:36-41` logs to STDOUT at info; Docker's default json-file driver grows UNBOUNDED on the box that shares
    one volume with all four SQLite DBs + blobs — an unbounded log can fill the disk and corrupt SQLite writes. No `logging:` block exists in deploy.yml.
  - **Steps:**
    1. Add a top-level `logging:` block:
       ```yaml
       logging:
         driver: json-file
         options:
           max-size: 100m
           max-file: 5
       ```
       (100m × 5 = 500MB cap; drop to 50m × 5 on a small box.) Document the cap in a comment.
    2. Applies to NEW container starts — the next `kamal deploy` recreates the container. Truncate existing unbounded logs on a previously-running box manually.
  - **Acceptance:** `ssh root@<REAL_HOST> 'docker inspect <container> --format "{{json .HostConfig.LogConfig}}"'` shows
    `{"Type":"json-file","Config":{"max-file":"5","max-size":"100m"}}` · after >100MB logs, `ls -la /var/lib/docker/containers/<id>/` shows at most 5 `*-json.log*`.
  - **Depends on:** —

- [ ] **H8. Implement the error reporter (Sentry) + always-on lograge structured request logs**
  - **Type:** code/config
  - **Files:** `Gemfile`, `Gemfile.lock`, `config/initializers/sentry.rb`, `config/environments/production.rb:36-41`, `config/deploy.yml`, `.kamal/secrets`
  - **Why:** Without a reporter, every uncaught exception (incl. the B13/B14 500) is silent. lograge turns multi-line logs into one
    structured JSON line per request so rotation/grep/alerting work, independent of the SaaS sink.
  - **Steps (TDD):**
    1. Add `test/initializers/sentry_test.rb` (or a request test) asserting Sentry is configured in production and a raised
       `StandardError` reaches Sentry's transport (use the test transport / `Sentry.get_current_hub`). Red first.
    2. `Gemfile`: add `gem "sentry-ruby"`, `gem "sentry-rails"` (no-ops without a DSN), and `gem "lograge"`; `bundle install`.
    3. `config/initializers/sentry.rb`:
       ```ruby
       Sentry.init do |c|
         c.dsn = ENV["SENTRY_DSN"]
         c.environment = Rails.env
         c.enabled_environments = %w[production]
         c.traces_sample_rate = 0.0
         c.send_default_pii = false
       end
       ```
       Confirm `config.filter_parameters` scrubs `:password`/`:token`/`Authorization` (see H9).
    4. `production.rb`: after the logger lines — `config.lograge.enabled = true`; `config.lograge.formatter = Lograge::Formatters::Json.new`;
       `custom_options` to log `request_id` + `remote_ip`. Keep `config.logger = ActiveSupport::TaggedLogging.logger(STDOUT)`.
    5. `deploy.yml`: add `SENTRY_DSN` under `env.secret` (NOT clear). Add `SENTRY_DSN=…` to `.kamal/secrets` (mirror the `RAILS_MASTER_KEY` strategy).
    6. Confirm rescued `Registry::*`/`Auth::*` (`base_controller.rb:9-19`, `application_controller.rb:10-11`) return 4xx and should NOT page; Sentry ignores rescued exceptions.
  - **Acceptance:** `bin/rails test` green incl. the Sentry test · boot prod locally with a test DSN, hit a raising route → event
    appears · prod request log lines are single-line JSON with `request_id` + `status` · `kamal app logs | head` shows JSON, not multi-line Rails logs.
  - **Depends on:** D4

- [ ] **H9. Authorization-header / PII scrubbing review for lograge + Sentry (raw PAT must never leak)**
  - **Type:** code
  - **Files:** `config/initializers/filter_parameter_logging.rb`, `config/initializers/sentry.rb`, `config/environments/production.rb` (lograge)
  - **Why:** `filter_parameters` scrubs params, NOT the `Authorization: Basic`/`Bearer` HEADER that carries PAT credentials.
    lograge `custom_options` or Sentry breadcrumbs can capture it. H8 sets `send_default_pii=false`, but no task explicitly verifies the header and raw `oprk_` token never reach logs/Sentry.
  - **Steps:**
    1. Ensure the `Authorization` header is redacted in lograge output and Sentry events (Sentry's Rails integration redacts by
       default with `send_default_pii=false`; verify and add an explicit denylist if `custom_options` echoes headers).
    2. Add a test: a request sending `Authorization: Basic …` produces a log line + a Sentry event with the header redacted; assert the raw `oprk_` token never appears in lograge output.
  - **Acceptance:** the redaction test passes; no `oprk_` token or `Authorization` value in lograge JSON or Sentry payloads.
  - **Depends on:** H8

- [ ] **H10. Make Thruster `MAX_REQUEST_BODY` explicit (=0, unlimited) and document — 0.1.17 default is ALREADY unlimited**
  - **Type:** config
  - **Files:** `config/deploy.yml` env.clear, `Dockerfile:77`
  - **Why:** Thruster 0.1.17 (`Gemfile.lock`) ships `MAX_REQUEST_BODY` DEFAULT = 0 ("no maximum size enforced"). So the current
    container will NOT 413 large layer pushes today. The risk is a silent regression: a future Thruster bump could reintroduce a
    finite default. Setting it explicitly to 0 pins behavior for GB-sized layers.
  - **Steps:**
    1. Add to `config/deploy.yml` `env.clear`:
       ```yaml
       # Registry layers can be multiple GB. Thruster 0.1.17 defaults MAX_REQUEST_BODY=0 (unlimited);
       # pin it so a future Thruster upgrade cannot reintroduce a finite cap that 413s large pushes.
       MAX_REQUEST_BODY: 0
       ```
    2. Do NOT rely on a Rails-side body cap (Rack has none by default; uploads stream chunked PATCH — Thruster is the only gate).
    3. If D1=B (Nginx) ALSO set `client_max_body_size 0; proxy_request_buffering off;` so Nginx doesn't cap/buffer first.
    4. For a deliberate ceiling, set a byte value instead of 0; for a real registry, 0 is correct.
  - **Acceptance:** `docker inspect <container> --format '{{json .Config.Env}}' | tr ',' '\n' | grep MAX_REQUEST_BODY` →
    `MAX_REQUEST_BODY=0` · smoke: push an image whose largest layer is >1GB → layer PUT/PATCH returns 201/202, not 413.
  - **Depends on:** D5, D1

- [ ] **H11. Set request/upload timeouts so large blob uploads are not killed mid-transfer**
  - **Type:** config
  - **Files:** `config/puma.rb`, `config/deploy.yml`
  - **Why:** No rack-timeout (verified absent in Gemfile/Gemfile.lock) and `config/puma.rb` sets no `worker_timeout`/`first_data_timeout`.
    That is GOOD for slow multi-GB uploads but implicit. Real exposure: if D1=B (Nginx), its `proxy_read_timeout`/`client_max_body_size`/`proxy_request_buffering` defaults WILL truncate large pushes.
  - **Steps:**
    1. Do NOT add rack-timeout. Keep Puma without a tight request kill. The default Puma worker timeout is a watchdog for HUNG workers, not slow uploads; raise `worker_timeout 120` only if you observe spurious reaps.
    2. D1=A (kamal-proxy): no extra timeout config; confirm a >5-minute upload succeeds after deploy.
    3. D1=B (Nginx): set `client_max_body_size 0; proxy_request_buffering off; proxy_read_timeout 3600s; proxy_send_timeout 3600s;` (see B11).
    4. Document the chosen timeouts next to the deploy.yml env block / Nginx snippet.
  - **Acceptance:** throttle bandwidth and push a >1GB layer → completes with no 408/499/502 and no Puma worker-timeout reap · D1=B:
    `nginx -T | grep -E 'client_max_body_size|proxy_request_buffering|proxy_read_timeout'` shows the values · D1=A: a >5-min upload succeeds end-to-end.
  - **Depends on:** D1

- [ ] **H12. Fix RAILS_MAX_THREADS vs Puma threads connection-pool mismatch (ConnectionTimeoutError under load)**
  - **Type:** config
  - **Files:** `config/database.yml:9`, `config/puma.rb:8`, `config/deploy.yml` env.clear
  - **Why:** `database.yml:9` `max_connections: ENV.fetch("RAILS_MAX_THREADS"){5}` but `puma.rb:8` threads default to 16
    (`PUMA_THREADS`→`RAILS_MAX_THREADS`→16). Puma runs 16 threads/worker but the SQLite pool defaults to 5; the in-Puma SolidQueue
    supervisor also draws from the same pool. Under concurrent pulls/pushes Rails raises `ActiveRecord::ConnectionTimeoutError` → random 500s.
  - **Steps:**
    1. Set `RAILS_MAX_THREADS` (or `PUMA_THREADS`) in `deploy.yml` env.clear so the pool >= per-worker thread count + queue headroom.
       Since `database.yml` reads `RAILS_MAX_THREADS` for `max_connections` and `puma.rb` reads it for thread count, set one value, e.g. `RAILS_MAX_THREADS: 16`.
    2. Account for the in-Puma SolidQueue supervisor sharing the pool — bump a few above the thread count if you observe timeouts.
  - **Acceptance:** `kamal app exec 'bin/rails runner "puts [ENV[\"RAILS_MAX_THREADS\"], ActiveRecord::Base.connection_pool.size].inspect"'`
    shows pool >= 16 · a concurrent pull load test produces zero `ConnectionTimeoutError` in logs.
  - **Depends on:** —

- [ ] **H13. Verify SQLite WAL / busy_timeout / PRAGMAs (concurrency + safe online-backup precondition)**
  - **Type:** ops/config
  - **Files:** `config/database.yml` (only `timeout: 5000`, no journal_mode/synchronous/mmap)
  - **Why:** The registry does concurrent read-during-write; the backup task (B18) uses `.backup` which needs WAL to be consistent;
    nothing verifies WAL is actually on. Test runs surfaced `SQLite3::BusyException 'database is locked'`. This is a precondition for B18.
  - **Steps:**
    1. Verify WAL is on for all 4 DBs:
       `kamal app exec 'bin/rails runner "puts ActiveRecord::Base.connection.execute(\"PRAGMA journal_mode\").inspect"'` → `wal`
       (repeat against cache/queue/cable connections). If not, configure `journal_mode` (Rails 8 SQLite adapter enables WAL by
       default for new DBs — confirm on the actual volume).
    2. Document a `busy_timeout` decision (the `timeout: 5000` maps to `busy_timeout 5000ms`); raise if BusyException recurs under load.
    3. Confirm a `.backup` snapshot passes `PRAGMA integrity_check`.
  - **Acceptance:** `PRAGMA journal_mode` returns `wal` for the primary (and the other 3) · a documented busy_timeout decision · `.backup` snapshot passes `PRAGMA integrity_check`.
  - **Depends on:** B18

- [ ] **H14. CODE: Reduce `last_used_at` write-per-request amplification on authenticated /v2**
  - **Type:** code
  - **Files:** `app/controllers/v2/base_controller.rb:55`, `test/controllers/v2/base_controller_test.rb`
  - **Why:** `base_controller.rb:55` does `result.pat.update_column(:last_used_at, Time.current)` on EVERY authenticated /v2 request —
    one extra single-writer SQLite UPDATE per authenticated push/pull, independent of the anonymous-pull path H6 fixes.
  - **Steps (TDD):**
    1. Gate the update to fire only when `last_used_at` is stale by N minutes (e.g. 5). Assert no UPDATE on a second request within the window.
    2. Run `bin/rails test test/controllers/v2/base_controller_test.rb`.
  - **Acceptance:** second authenticated request within the window performs no `last_used_at` UPDATE · the controller test is green.
  - **Depends on:** —

- [ ] **H15. Decide anonymous-pull policy and set `REGISTRY_ANONYMOUS_PULL` explicitly**
  - **Type:** config
  - **Files:** `config/deploy.yml` env.clear, `config/initializers/registry.rb:4`, `app/controllers/v2/base_controller.rb:42-46`
  - **Why:** `registry.rb:4` defaults `REGISTRY_ANONYMOUS_PULL` to `"true"` → `base_controller.rb:42-45` lets ANY unauthenticated
    GET/HEAD read catalog/tags/manifests/blobs of EVERY repo. Each anonymous pull drives DB writes (H6) and Rack::Attack only throttles
    non-GET /v2 (H17). Make the choice explicit so it is not the silent `true` default.
  - **Steps:**
    1. Per **D3**: add `REGISTRY_ANONYMOUS_PULL: false` (private) or `REGISTRY_ANONYMOUS_PULL: true` (public intent explicit) to `deploy.yml` env.clear.
    2. If public, complete H6 (write amplification) and decide H18 (GET throttle).
  - **Acceptance:** `kamal app exec 'bin/rails runner "puts Rails.configuration.x.registry.anonymous_pull_enabled"'` prints the intended boolean ·
    false → `curl -si https://<REGISTRY_DNS_NAME>/v2/<repo>/tags/list` returns 401 + `WWW-Authenticate: Basic`; valid `-u <email>:<PAT>` → 200 · true → same unauthenticated curl returns 200.
  - **Depends on:** D3

- [ ] **H16. CODE: Boot-time validation of `REGISTRY_ADMIN_EMAIL` in production**
  - **Type:** code
  - **Files:** `config/initializers/registry.rb:2`, `test/integration/registry_admin_email_boot_test.rb`
  - **Why:** `registry.rb:2` reads `REGISTRY_ADMIN_EMAIL` (default nil) and never validates. A blank admin email is only discovered at
    first-push time (500/503), not at deploy time. Failing fast at boot turns a confusing runtime failure into an obvious deploy failure.
  - **Steps:**
    1. Extract a unit-testable `RegistryConfig.validate_admin_email!(env:, email:)`; call it from the initializer.
    2. Raise a descriptive error only when `Rails.env.production? && admin_email.blank?` (optionally also when it fails
       `URI::MailTo::EMAIL_REGEXP`). Message names `REGISTRY_ADMIN_EMAIL` and references B13.
    3. CRITICAL: do NOT fire in test/development — `bin/rails test` does not set the var; a test-env guard would break the suite.
    4. Add `test/integration/registry_admin_email_boot_test.rb`: raises for production+blank; silent for test/dev and production+present.
  - **Acceptance:** `RAILS_ENV=production REGISTRY_ADMIN_EMAIL= SECRET_KEY_BASE_DUMMY=1 bin/rails runner 'puts 1'` fails fast with the
    message · `bin/rails test` (no var set) still boots/passes · the new boot test passes.
  - **Depends on:** —

- [ ] **H17. CONFIG + TEST: Confirm Rack::Attack counter store under production config and that the middleware actually fires**
  - **Type:** config/test
  - **Files:** `config/initializers/rack_attack.rb`, `config/environments/production.rb:50`, `test/integration/rack_attack_production_active_test.rb`
  - **Why:** rack-attack 6.8.0 sets NO explicit `Rack::Attack.cache.store`, so it falls back to `Rails.cache = :solid_cache_store`
    (SQLite). Consequences: (1) throttle counters add write pressure to the primary DB; (2) existing throttle tests force
    `Rack::Attack.enabled=true` and swap a MemoryStore, so they do NOT prove the throttle is active under real prod config — a silent prod no-op would still pass CI.
  - **Steps:**
    1. Decide the counter store: solid_cache (SQLite) is acceptable single-node but couples to the primary DB. Document the choice (comment in `rack_attack.rb`) or set `Rack::Attack.cache.store` explicitly (e.g. `ActiveSupport::Cache::MemoryStore.new` per-process to avoid SQLite writes).
    2. Confirm Rack::Attack is inserted: `RAILS_ENV=production SECRET_KEY_BASE_DUMMY=1 bin/rails middleware | grep -i Rack::Attack`.
    3. Add `test/integration/rack_attack_production_active_test.rb` that does NOT force enabled/store and asserts the middleware is present in `Rails.application.middleware`.
  - **Acceptance:** middleware list includes `Rack::Attack` · the new test passes and fails if Rack::Attack is removed ·
    live: 31 POST `/v2/<name>/blobs/uploads` from one IP → the 31st returns 429 with `Retry-After: 60` · `Rack::Attack.cache.store.class` is non-nil and the intended store.
  - **Depends on:** —

- [ ] **H18. DECISION (+ optional CODE): Whether GET /v2 endpoints need throttling**
  - **Type:** decision/code
  - **Files:** `config/initializers/rack_attack.rb:8-12`, `test/integration/rack_attack_v2_throttle_test.rb:46-53`
  - **Why:** `rack_attack.rb:8-12` `v2_protected_by_ip` excludes GET/HEAD; the test asserts GET `/v2/_catalog` is NOT throttled. With
    `REGISTRY_ANONYMOUS_PULL=true` all read endpoints are unauthenticated AND unthrottled — combined with per-pull writes, a
    DoS/write-amplification vector. If anonymous pull is OFF, GETs require a PAT (lower risk). GET `/v2/` discovery is hit by every login and is cheap.
  - **Steps:**
    1. Anonymous ON (D3) → add a read throttle:
       `throttle("v2_read_by_ip", limit: 300, period: 1.minute) { |req| req.ip if req.path.start_with?("/v2/") && (req.get? || req.head?) }`.
       A single pull is dozens of GETs — set the limit well above a real multi-layer pull. Leave GET `/v2/` base discovery unthrottled or in a generous bucket.
    2. Anonymous OFF → document the deliberate omission in `rack_attack.rb`.
    3. If added, update `rack_attack_v2_throttle_test.rb`: the "GET /v2/_catalog NOT throttled" test must assert throttling only above the new limit and that a normal pull-sized burst is not throttled.
  - **Acceptance:** decision recorded here (D3/H18) · if added: the throttle test passes updated expectations and an N+1 anonymous GET
    `/v2/_catalog` loop returns 429 while a real pull succeeds · if omitted: the "not throttled" test stays green with a documenting comment.
  - **Depends on:** D3

- [ ] **H19. CONFIG: Enable a production Content-Security-Policy (currently fully commented out)**
  - **Type:** config
  - **Files:** `config/initializers/content_security_policy.rb`, `test/integration/csp_header_test.rb`
  - **Why:** `content_security_policy.rb` is the untouched Rails scaffold — entirely commented, so NO CSP header is sent. The web UI
    renders user-influenced data (repo/tag/PAT names, actor emails) and uses importmap + Stimulus; with no CSP, any stored-XSS slip
    becomes script execution. Session cookie is HttpOnly (good), so CSP is defense-in-depth — standard pre-launch hardening.
  - **Steps:**
    1. Uncomment and tailor: `default_src :self; script_src :self; style_src :self` (+ `:unsafe_inline` only if Tailwind/inline
       styles require — verify); `img_src :self, :data, :https`; `font_src :self, :data`; `object_src :none`; `base_uri :self`; `frame_ancestors :none`.
    2. Enable a nonce for inline/importmap scripts: `content_security_policy_nonce_generator = ->(r){ r.session.id.to_s }`;
       `content_security_policy_nonce_directives = %w(script-src)`; confirm importmap-rails tags carry the nonce.
    3. Roll out `report_only = true` first, dogfood the UI, then flip to enforcing.
    4. Allow `googleusercontent.com` in `img_src` if avatar_url images render (Identity stores avatar_url — check the views).
    5. Add `test/integration/csp_header_test.rb`: GET `/` and `/help` assert the (Report-Only or enforcing) CSP header is present and contains `default-src 'self'` and `object-src 'none'`.
  - **Acceptance:** the CSP test passes · `curl -sI http://HOST/ | grep -i content-security-policy` returns a policy · manual: `/`, `/help`, `/settings/tokens`, a repo show page load enforcing with ZERO CSP console violations (avatars + importmap load).
  - **Depends on:** —

- [ ] **H20. CONFIG: Turn on Secure cookies + force_ssl/assume_ssl + static assertion test**
  - **Type:** config
  - **Files:** `config/environments/production.rb:28,31`, `config/deploy.yml`, `test/integration/session_cookie_hygiene_test.rb`
  - **Why:** Rails 8.1 defaults already give the session cookie HttpOnly + SameSite=Lax (pinned by `session_cookie_hygiene_test.rb`
    tests 1-2). What is MISSING is the Secure flag, only added by `ActionDispatch::SSL` (via `force_ssl=true`, effective behind a
    proxy with `assume_ssl=true`). Both are commented (`production.rb:28,31`). `session_cookie_hygiene_test.rb` test 5 is deliberately
    skipped (force_ssl can't toggle mid-process) — there is NO automated proof Secure is ever set; proof is operational. (This is the same change as B10, framed for cookie hygiene.)
  - **Steps:**
    1. Complete B10 (assume_ssl + force_ssl + `/up` ssl_options exclusion).
    2. Ensure X-Forwarded-Proto is forwarded (B9 kamal-proxy or B11 Nginx) so assume_ssl/force_ssl behave.
    3. Add a static assertion test (mirroring the existing "no SameSite=None" static test) that `production.rb` contains uncommented `config.force_ssl = true`; keep the Secure-runtime test skipped/documented.
  - **Acceptance:** `bin/rails test test/integration/session_cookie_hygiene_test.rb` passes (HttpOnly + SameSite=Lax + new static
    force_ssl assertion) · HTTPS deploy: `Set-Cookie` `_open_repo_session` carries `; secure; HttpOnly; SameSite=Lax` ·
    `curl -sI http://HOST/` → 301/308 to https while `/up` is NOT redirected.
  - **Depends on:** B10, D1

- [ ] **H21. Tune HSTS (max-age, includeSubDomains, preload) and stage it safely**
  - **Type:** config
  - **Files:** `config/environments/production.rb`
  - **Why:** `force_ssl` turns on HSTS with Rails' default (1 year, no subdomains/preload). HSTS is sticky: any browser that receives
    the header pins the FQDN to HTTPS for max-age; includeSubDomains/preload are very hard to undo. If TLS later breaks or a cert lapses, clients are locked out.
  - **Steps:**
    1. Stage with a short max-age first:
       `config.ssl_options = { hsts: { expires: 1.week, subdomains: false, preload: false }, redirect: { exclude: ->(request) { request.path == "/up" } } }`,
       verify, then raise to `expires: 1.year`.
    2. Enable `includeSubDomains` only if every subdomain is HTTPS-only; enable `preload` only if submitting to the preload list (effectively permanent).
    3. Confirm cert auto-renewal is healthy (A: kamal-proxy/Let's Encrypt; B: certbot timer) BEFORE raising max-age.
    4. Keep the `/up` exclusion in `ssl_options.redirect`.
  - **Acceptance:** `curl -sI https://<REGISTRY_DNS_NAME>/` shows `Strict-Transport-Security` with the intended max-age (and
    includeSubDomains/preload only if chosen) · renewal verified (A: future expiry after a forced renew check; B: `certbot renew --dry-run` succeeds).
  - **Depends on:** B10

- [ ] **H22. Confirm `builder.arch=amd64` matches the target server architecture**
  - **Type:** config
  - **Files:** `config/deploy.yml:80-84`, `Dockerfile:44,51`
  - **Why:** `deploy.yml:80-81` pins `builder.arch: amd64`. If `<REAL_HOST>` is arm64 (Graviton/Ampere) the image won't run; if the
    operator's laptop is Apple Silicon, building amd64 emulated via QEMU is slow and can hit the bootsnap QEMU bug the Dockerfile works around (`Dockerfile:44,51`).
  - **Steps:**
    1. `ssh root@<REAL_HOST> uname -m` (x86_64→amd64, aarch64→arm64).
    2. Set `deploy.yml builder.arch` to match. Building amd64 on Apple Silicon → optionally uncomment `deploy.yml:84`
       `remote: ssh://docker@<DOCKER_BUILDER_HOST>` to build natively for speed.
    3. Multi-arch: `arch: [amd64, arm64]` (slower).
  - **Acceptance:** `ssh root@<REAL_HOST> uname -m` matches the configured arch · `kamal app exec 'uname -m'` on the deployed container returns the expected arch and the app boots.
  - **Depends on:** B3

- [ ] **H23. Configure Kamal proxy healthcheck to hit `/up` (and confirm `app_port=80`)**
  - **Type:** config
  - **Files:** `config/deploy.yml`, `config/routes.rb:77`, `config/environments/production.rb:34,44`
  - **Why:** Kamal 2.10.1 (`Gemfile.lock`) gates traffic cutover on a passing healthcheck. The app exposes GET `/up` →
    `rails/health#show` (`routes.rb:77`); `production.rb:44` silences it. deploy.yml declares no proxy/healthcheck/app_port; if you set
    `proxy.app_port` wrong (e.g. 3000) the healthcheck fails and deploy rolls back. (Container serves on 80 via Thruster; Puma is 3000.)
  - **Steps:**
    1. Under `proxy:` (D1=A) add `app_port: 80` and optionally `healthcheck: { path: /up, interval: 3, timeout: 5 }`.
    2. Ensure `/up` is NOT https-redirected: confirm `production.rb:34` `ssl_options` excludes `/up` (B10) so the probe over HTTP succeeds during boot.
    3. Verify the deploy waits for and passes the healthcheck ("Waiting for the first healthcheck…" then success).
  - **Acceptance:** `kamal app exec 'curl -sf http://localhost:80/up'` returns 200 (green HTML) · `kamal deploy` logs show the healthcheck passed before cutover (no rollback).
  - **Depends on:** D1, B10

- [ ] **H24. Wire healthcheck monitoring + external uptime probe on GET /up (+ deeper /v2 liveness)**
  - **Type:** ops
  - **Files:** `config/deploy.yml`, `config/environments/production.rb:44`, `config/routes.rb:77`
  - **Why:** GET `/up` exists and `production.rb:44` silences it, but NOTHING monitors it. Kamal's proxy healthcheck only exists once a
    `proxy:` block exists. With no external monitor, a crashed app (e.g. failed first-boot db:prepare) is invisible until users report
    push failures. `/up` only checks DB connectivity, not Solid Queue or blob storage.
  - **Steps:**
    1. D1=A: uncomment the `proxy:` block; kamal-proxy healthchecks `/up` during deploy and rolls back on failure. Confirm `proxy.healthcheck.path` is `/up`.
    2. Add an EXTERNAL uptime monitor (UptimeRobot/BetterStack/Healthchecks.io) on `https://<REGISTRY_DNS_NAME>/up` at 1-2 min with email/Slack alert.
    3. Add a deeper liveness check: a cron/dead-man's-switch hitting `GET /v2/` (expects 200 + `Docker-Distribution-API-Version`) so V2 breakage is detected.
    4. Do NOT overload `/up` with blob-FS/queue checks (would make a full volume fail deploys); surface those via H3 + B17.
    5. Document the monitor URL + alert channel here.
  - **Acceptance:** `curl -sf https://<REGISTRY_DNS_NAME>/up` → 200; stopping the container makes the external monitor alert within
    its interval · D1=A: an intentionally broken boot is rolled back by the /up healthcheck (visible in `kamal deploy` output) ·
    `curl -s https://<REGISTRY_DNS_NAME>/v2/` → 200 + `Docker-Distribution-API-Version: registry/2.0`.
  - **Depends on:** D1

- [ ] **H25. SolidQueue FAILED-job buildup alerting (distinct from "supervisor not running")**
  - **Type:** ops/code
  - **Files:** `config/recurring.yml`, `config/initializers/sentry.rb` (H8), `SolidQueue::FailedExecution`
  - **Why:** B17 verifies the supervisor runs and H8 wires Sentry, but no task confirms ActiveJob exceptions in recurring jobs (e.g.
    `EnforceRetentionPolicyJob` hitting a locked DB nightly) actually reach Sentry, and `clear_solid_queue_finished_jobs` only clears
    FINISHED (not FAILED) rows — a job failing every night is silent and the queue DB grows.
  - **Steps:**
    1. Confirm a deliberately-raising job produces a Sentry event AND leaves a `SolidQueue::FailedExecution` row.
    2. Document/implement an alert/threshold on `SolidQueue::FailedExecution.count` (e.g. a recurring check that alerts when > 0 for N hours).
  - **Acceptance:** a raising job produces a Sentry event AND a `FailedExecution` row · an alert/threshold on FailedExecution count is documented.
  - **Depends on:** H8, B17

- [ ] **H26. Graceful shutdown / zero-downtime on redeploy (SIGTERM during an in-flight multi-GB push)**
  - **Type:** config/ops
  - **Files:** `Dockerfile` (no STOPSIGNAL), `config/deploy.yml` (no `stop_wait_time`/drain), `config/puma.rb`
  - **Why:** Every `kamal deploy` sends SIGTERM; with GB-layer uploads taking minutes and the in-Puma SolidQueue supervisor needing a
    clean shutdown, the default ~30s docker stop grace can truncate an in-flight push and abruptly kill the queue supervisor.
  - **Steps:**
    1. Set Kamal `stop_wait_time` / drain to exceed expected upload duration (e.g. a few minutes for GB layers).
    2. Verify a redeploy during a large push lets it finish (or fails cleanly) and SolidQueue has no orphaned/stale supervisor rows afterward.
  - **Acceptance:** a redeploy during a large push lets the push finish (or fails cleanly) · `SolidQueue::Process` has no orphaned/stale supervisor rows after deploy.
  - **Depends on:** D5

- [ ] **H27. DECISION (+ CODE if scopes wanted): PAT scope & expiry policy**
  - **Type:** decision/code
  - **Files:** `app/controllers/settings/tokens_controller.rb`, `app/models/personal_access_token.rb`, `app/views/settings/tokens/_form.html.erb`, `app/services/auth/pat_authenticator.rb`
  - **Why:** Three gaps: (1) NO scopes — schema has only `kind` + `expires_at`; PatAuthenticator returns the full user and
    `authorize_for!` grants whatever the USER can do, so a "CI pull-only" PAT can push/delete; `kind` is never consulted. (2) Expiry not
    enforced by kind — `_form` advertises "CLI (default, 90-day)" but `parse_expires_in` treats blank/0/negative as nil = NEVER expires for
    any kind. (3) No server-side max cap — a client can set `expires_in_days=36500`.
  - **Steps (per D8):**
    1. Scopes: accept PAT==full user authority (document by-design) OR add a scopes column + enforce in `authorize_for!`/PatAuthenticator (larger task).
    2. Expiry: for `kind=='cli'` coerce nil/0 to the 90-day default server-side and clamp to a max (e.g. 365), allowing nil only for `kind=='ci'`; OR change the UI copy. Recommended: fix `parse_expires_in`.
    3. Cap: add a server-side max `expires_at`.
    4. If `parse_expires_in` changes: add tokens_controller tests — cli+blank → ~90d; cli+0 → not never; over-cap clamped; ci+blank → nil allowed.
    5. Confirm `PersonalAccessToken.active` already excludes expired tokens (model lines 12-15).
  - **Acceptance:** by-design → a written decision (D8) here · expiry fix → `bin/rails test test/controllers/settings/tokens_controller_test.rb` passes new cases; a "CLI" token with the days field cleared shows expiry ~90 days, not "Never" · if scopes added → a read-only PAT for `docker push` returns 403 while `docker pull` succeeds.
  - **Depends on:** D8

- [ ] **H28. Fix the `/help` page TLS/host snippets that assume `http://localhost` (avoid plain-HTTP Basic-auth footgun)**
  - **Type:** docs/code
  - **Files:** `app/views/help/show.html.erb:11-15,109-113,122-138`, `README.md:492-501`
  - **Why:** Once TLS is on and `REGISTRY_HOST` is real, the Help page still leads with `insecure-registries` (`:11-15`) and an `http://`
    containerd mirror with `insecure_skip_verify=true` (`:109-113`). Copy-pasting these configures an INSECURE client against a now-TLS
    registry → `http: server gave HTTP response to HTTPS client` / auth failures. Sending Basic-auth PATs over plain HTTP also leaks credentials.
  - **Steps:**
    1. Move the HTTPS/reverse-proxy section ABOVE the insecure-registries section; re-label the insecure block "Development / single
       trusted host ONLY — never send tokens over plain HTTP to a remote host".
    2. For the containerd block (`:109-113`), make the HTTPS variant (`endpoint = ["https://<%= @registry_host %>"]`, drop `insecure_skip_verify`) the default; keep http+skip-verify only under a dev-only caveat.
    3. Update the Nginx snippet (`:122-138`) to include `proxy_request_buffering off;` + `X-Forwarded-Proto $scheme` and match the real upstream port.
    4. If D1=A, add a note that TLS is handled by Kamal's built-in proxy and no Nginx is required.
    5. Mirror the reframing in README (~492-501); fold in the compose-doc removal (H30) while editing.
  - **Acceptance:** GET `/help` shows HTTPS/reverse-proxy guidance before the insecure block, insecure block explicitly dev-only ·
    the containerd example defaults to https without `insecure_skip_verify` · `grep -n 'insecure' app/views/help/show.html.erb` shows remaining occurrences only inside the dev-only caveat.
  - **Depends on:** D1

- [ ] **H29. Ensure `/help` shows the correct registry host in production (DX surface of B6)**
  - **Type:** config
  - **Files:** `config/deploy.yml`, `config/application.rb:49`, `app/controllers/help_controller.rb`, `app/views/help/show.html.erb`
  - **Why:** `/help` is fully wired (`help_controller` sets `@registry_host = Rails.configuration.registry_host`; `application.rb:49`
    derives it from `ENV.fetch("REGISTRY_HOST","localhost:3000")`; the view interpolates it into all 8 command snippets). No code change
    needed — the ONLY way `/help` shows the wrong host is if `REGISTRY_HOST` is not injected. (Same as B6, framed for copy-paste DX.)
  - **Steps:**
    1. Add `REGISTRY_HOST: <REGISTRY_DNS_NAME>` under `env.clear` (B6). With TLS, no port; non-standard port → include it.
    2. Confirm no view hardcodes localhost (it uses only `@registry_host`).
  - **Acceptance:** `curl -s https://<REGISTRY_DNS_NAME>/help` shows `docker login <host> …` / `docker push <host>/myapp:latest` with the real host ·
    `kamal app exec 'bin/rails runner "puts Rails.configuration.registry_host"'` prints the real host[:port].
  - **Depends on:** B6, D1

- [ ] **H30. Remove the false Docker Compose deploy claims (no `docker-compose.yml` exists)**
  - **Type:** docs
  - **Files:** `README.md:73,486-490`, `docs/standards/TOOLS.md:86`, `docs/standards/STACK.md:47`
  - **Why:** `ls docker-compose*` → not-found. README advertises `docker-compose up --build` (`:489`) and "Kamal 2 or Docker Compose"
    (`:73`); TOOLS.md:86 lists `docker-compose up --build`; STACK.md:47 says "Kamal 2 (primary) or Docker Compose (local)". An operator following any of these gets `no configuration file provided`.
  - **Steps (per D9 = remove):**
    1. README.md:73 → `Kamal 2`. README.md:486-490 → delete the `### Docker Compose` heading + its fenced block.
    2. TOOLS.md:86 → delete the `docker-compose up --build` line. STACK.md:47 → `Kamal 2`.
    3. Do NOT touch STACK.md:46 (X-Sendfile) here — that is H31.
    4. Optionally note local dev uses `bin/dev`, not compose.
  - **Acceptance:** `grep -rn "docker-compose\|docker compose" --include="*.md" .` returns only matches in this audit doc and
    `docs/superpowers/` — zero in README/TOOLS/STACK · README Deployment section documents only Kamal 2 (+ optional Nginx).
  - **Depends on:** D9

- [ ] **H31. Fix the REGISTRY_ANONYMOUS_PULL default documentation mismatch (README says false, code defaults true)**
  - **Type:** docs
  - **Files:** `README.md:129`, `config/initializers/registry.rb:4`
  - **Why:** README.md:129 documents the default as `false`, but `registry.rb:4` defaults to `"true"`. Dangerous drift: an operator
    believes the registry ships closed when every repo is world-readable AND each anonymous pull does 3 SQLite writes (H6).
  - **Steps (per D3):**
    1. For the docs domain, correct README.md:129 to reflect reality (`true`) and add a bold warning the default is open:
       "Defaults to OPEN (true) — all repositories are world-readable until you set this to false." (If D3 instead changes the code
       default to `false`, that is a behavioral change owned by H15, and the README stays.)
    2. Ensure the runbook has an explicit anonymous-pull decision step.
  - **Acceptance:** README `REGISTRY_ANONYMOUS_PULL` default matches `registry.rb:4` (no drift) · README warns the default is world-readable · runbook contains the decision step.
  - **Depends on:** D3

---

## Medium / Low (nice to have / follow-up)

- [ ] **M1. Add an error sink + Docker log rotation (umbrella; implemented by D4 → H7 + H8).**
  Verify both landed: rotation visible in `docker inspect … HostConfig.LogConfig`; a deliberate 500 produces an event in the sink.
  - **Files:** `config/environments/production.rb:36-41`, `config/deploy.yml`. **Depends on:** D4.

- [ ] **M2. Verify Rack::Attack throttles fire in production (runtime confirmation of H17).**
  - **Type:** ops. **Files:** `config/initializers/rack_attack.rb`, `config/environments/production.rb:50`.
  - **Steps:** `kamal app exec "bin/rails runner 'pp Rails.application.middleware.map(&:name).grep(/Attack/)'"` → `["Rack::Attack"]`;
    `kamal app exec "bin/rails runner 'pp Rack::Attack.cache.store.class'"` → `SolidCache::Store` (or chosen store, non-nil);
    live 11th POST `/auth/...` and 31st non-GET `/v2` within a minute → 429 + `Retry-After: 60`. **Depends on:** H17, first successful deploy.

- [ ] **M3. Verify `STORAGE_PATH` default resolves inside the mounted volume; do not override unless relocating.**
  - **Type:** config. **Files:** `config/application.rb:48`, `config/deploy.yml`, `Dockerfile:15`.
  - **Why:** `application.rb:48` default `/rails/storage/registry` is under the volume mount `/rails/storage` — correct. The footgun is
    setting `STORAGE_PATH` OUTSIDE `/rails/storage` (e.g. `/data`), which writes blobs to the ephemeral layer and loses them on redeploy while DB rows still reference them.
  - **Steps:** Keep `STORAGE_PATH` unset (it is). If relocating, point it at a subdir of a mounted volume and add the matching volume line. Optional boot guard: raise if production && resolved storage_path is not under a configured mount.
  - **Acceptance:** `kamal app exec 'bin/rails runner "puts Rails.configuration.storage_path"'` prints a path under `/rails/storage` · after push + redeploy the image still `docker pull`s.

- [ ] **M4. Verify `EnforceRetentionPolicyJob` and `PruneOldEventsJob` do the right thing (and are enabled on purpose).**
  - **Type:** ops. **Files:** `app/jobs/enforce_retention_policy_job.rb:23,40-42`, `app/jobs/prune_old_events_job.rb:5`, `config/recurring.yml`, `config/deploy.yml`, the related job tests.
  - **Why:** `EnforceRetentionPolicyJob` is a no-op unless `RETENTION_ENABLED=true` (job:40-42) — so by default retention does NOT run
    despite being scheduled daily 3am. It only deletes TAGS; blob reclamation relies on `CleanupOrphanedBlobsJob`'s orphan-manifest
    sweep, coupled to the ref-count fix (H4). `PruneOldEventsJob` hard-codes 90 days (job:5); `pull_events` is the fastest-growing table (worse with anonymous pull, H6).
  - **Steps:** Decide retention policy (set `RETENTION_ENABLED`, `RETENTION_DAYS_WITHOUT_PULL`, `RETENTION_MIN_PULL_COUNT`,
    `RETENTION_PROTECT_LATEST` in env.clear or leave disabled deliberately). Confirm tag protection (`job:23` calls
    `repository.tag_protected?`). Confirm the deletion chain (retention → orphan manifests → CleanupOrphanedBlobs decrements refs → next pass deletes zero-ref blobs) — only reclaims disk if H4 is fixed. Tune the PruneOldEvents window to the SQLite budget; consider env-izing the 90 days.
  - **Acceptance:** `bin/rails test test/jobs/enforce_retention_policy_job_test.rb test/jobs/prune_old_events_job_test.rb test/integration/retention_ownership_interaction_test.rb` green · if enabled, `RETENTION_ENABLED=true` in prod and a manual `EnforceRetentionPolicyJob.perform_now` deletes only intended stale/unprotected/non-latest tags · manual `PruneOldEventsJob.perform_now` → `PullEvent.where("occurred_at < ?", 90.days.ago).count` = 0.
  - **Depends on:** H4, D3.

- [ ] **M5. DECISION: Confirm `:read` authorization always-true is acceptable for launch (or lock it down).**
  - **Type:** decision. **Files:** `app/controllers/concerns/repository_authorization.rb:18`, `config/initializers/registry.rb`.
  - **Why:** `repository_authorization.rb:18` `when :read then true # Stage 3` → every AUTHENTICATED user can read every repo. Combined
    with `REGISTRY_ANONYMOUS_PULL=true`, reads are open to everyone. Pinned by tests (by-design) but a confidentiality decision the operator must explicitly accept (D7).
  - **Steps:** Confirm "any signed-in user can read any repo" is acceptable for the launch audience; record it. If NOT acceptable, this
    is a Stage-3 FEATURE (owner/member read + public/private flag) requiring the brainstorming/plan pipeline + tests. Note: locking `:read` is moot for anonymous endpoints unless `REGISTRY_ANONYMOUS_PULL=false`.
  - **Acceptance:** a recorded decision (D7) accepting `:read=true` for launch OR a tracked Stage-3 follow-up · if by-design, `bin/rails test test/controllers/concerns/repository_authorization_test.rb` stays green.
  - **Depends on:** D3.

- [ ] **M6. DECISION: Single-node SQLite + filesystem blobs acceptable, OR move to Postgres + object storage.**
  - **Type:** decision. **Files:** `config/database.yml`, `config/storage.yml`, `app/services/blob_store.rb`, `config/deploy.yml`.
  - **Why:** The entire data layer is single-node by construction: BlobStore is filesystem-only (S3/GCS commented in `storage.yml`), all
    4 DBs are local SQLite (single-writer, 5000ms busy timeout, `database.yml:10`), upload sessions are local. Fine for one Kamal web host at modest concurrency, but a HARD ceiling — a second node requires S3/GCS blobs + external Postgres + shared uploads.
  - **Steps:** Confirm single-node (D2). Estimate write concurrency: peak simultaneous pushes × writes-per-push vs single writer + 5s
    busy timeout; routine SQLITE_BUSY 500s = trigger to move to Postgres. If multi-node/high-throughput is required, scope separately:
    S3/GCS BlobStore adapter, external Postgres via `DB_HOST` or a Kamal db accessory, shared upload bytes. Record the decision + rationale in deploy.yml/docs.
  - **Acceptance:** a written decision (single-node accepted, or Postgres/object-storage planned) with concurrency rationale · single-node → `servers.web:` lists exactly one host and no `job:` host without object storage + external DB.
  - **Depends on:** D2.

- [ ] **M7. Resolve the dead `SENDFILE_HEADER` claim: wire `x_sendfile_header` + Nginx `X-Accel-Redirect`, OR drop the zero-copy claim.**
  - **Type:** docs/config. **Files:** `README.md:121,340,501`, `config/environments/production.rb`, `app/views/help/show.html.erb:122-139`, `app/controllers/v2/blobs_controller.rb:19`, `docs/standards/STACK.md:46`.
  - **Why:** README documents `SENDFILE_HEADER` in three places and STACK.md:46 credits Thruster with "X-Sendfile", but NOTHING sets
    `config.action_dispatch.x_sendfile_header` anywhere in `config/`. `blobs_controller.rb:19` `send_file` therefore streams the whole
    blob through a Puma thread (no zero-copy). The env var name `SENDFILE_HEADER` is also wrong (Rails reads
    `config.action_dispatch.x_sendfile_header`). The README also promises a Help-page X-Accel-Redirect example that does not exist.
  - **Steps (per D10):**
    - **PATH A (DROP — recommended):** remove the `SENDFILE_HEADER` row from README.md:121; change README.md:340 to "Stream blob via
      `send_file`"; delete the README.md:501 X-Accel-Redirect clause; reword STACK.md:46 to not claim active X-Sendfile; state blob downloads stream through Puma and size `PUMA_THREADS`/`PUMA_WORKERS` accordingly.
    - **PATH B (WIRE — only if zero-copy required):** add to `production.rb` `config.action_dispatch.x_sendfile_header = ENV.fetch("SENDFILE_HEADER", nil)`;
      keep `send_file`; add a REAL `X-Accel-Redirect` example to the Help Nginx block (an `internal;` location aliasing `<STORAGE_PATH>/blobs/...`). Note Kamal's built-in proxy (Thruster) understands X-Sendfile, so `SENDFILE_HEADER=X-Sendfile` may work without Nginx — verify against the chosen proxy.
    - Either path: make README:501's promise match the actual Help content; add a one-line note here reflecting the chosen path.
  - **Acceptance:** PATH A → `grep -rn SENDFILE_HEADER README.md` returns zero; STACK.md no longer asserts active X-Sendfile · PATH B →
    `grep -n x_sendfile_header config/environments/production.rb` shows the new line; a large-blob `curl -sI .../blobs/<digest>` is served without the body passing through Rails (Puma busy-thread count stays flat); the Help Nginx block has the `internal;` location + X-Accel-Redirect mapping matching STORAGE_PATH.
  - **Depends on:** D10, D1.

- [ ] **M8. Document the db:prepare-on-boot brittleness in the runbook (ordering safety note).**
  - **Type:** docs. **Files:** `README.md`, `bin/docker-entrypoint:4`, `Dockerfile:77`.
  - **Why:** Migrations on first boot rely on `bin/docker-entrypoint`'s guard matching the last two CMD args being `./bin/rails server`.
    Today's CMD satisfies it, but any future CMD change silently skips migrations → 500s with no clear error. The operator should know migrations are automatic and re-verify the guard if CMD changes.
  - **Steps:** In the runbook's `kamal setup` step add: "DB migrations run automatically on first boot via `bin/docker-entrypoint`
    (detects `./bin/rails server`, runs `db:prepare`). Do not run migrations manually." Add a caveat to re-verify the guard if the
    Dockerfile CMD ever changes. Provide a verification command.
  - **Acceptance:** runbook explains migrations are automatic and warns about CMD/guard coupling · `kamal app exec --reuse 'bin/rails runner "puts ActiveRecord::Base.connection.migration_context.needs_migration? ? \"PENDING\" : \"OK\""'` prints `OK` after `kamal setup`.

- [ ] **M9. No-op deletion / "blob file missing on disk vs DB row" integrity scrub (post-restore drift).**
  - **Type:** code/ops. **Files:** `app/jobs/cleanup_orphaned_blobs_job.rb`, `app/services/blob_store.rb`.
  - **Why:** `CleanupOrphanedBlobsJob` tolerates a missing file when deleting, but nothing proactively detects drift (a DB blob row with
    no file after a partial restore, or a disk blob with no row). Relevant because the B18 restore drill can produce such drift.
  - **Steps:** Add a rake task or job reporting counts of (blob rows whose file is absent) and (disk blobs with no row); run post-restore.
  - **Acceptance:** the scrub reports 0/0 on a healthy volume.
  - **Depends on:** B18.

- [ ] **M10. Decide `config.hosts` / Host authorization for the real FQDN.**
  - **Type:** decision/config. **Files:** `config/environments/production.rb:82-89` (fully commented).
  - **Why:** With load_defaults 8.1 and a real domain, Host authorization is currently OFF (accepts any Host header). Either deliberately accept open-Host, or set the allowlist; if later enabled without the FQDN it 403s every request.
  - **Steps (per D11):** record the decision; if enabled, set `config.hosts` to include `<REGISTRY_DNS_NAME>` and
    `config.host_authorization = { exclude: ->(r){ r.path == "/up" } }`.
  - **Acceptance:** a recorded decision · if enabled, `curl -H 'Host: evil' https://<host>/v2/` → 403 while the real host → 401.
  - **Depends on:** D11.

- [ ] **M11. Timezone for recurring maintenance windows / token-expiry display.**
  - **Type:** decision/config. **Files:** `config/application.rb:36` (`config.time_zone` commented), `config/recurring.yml` (`3am`/`4am`).
  - **Why:** Jobs fire in container UTC; an operator expecting local maintenance windows is off by the UTC offset, and PAT expiry UI renders in UTC.
  - **Steps (per D12):** accept UTC (add a `recurring.yml` comment stating the effective zone) or set `config.time_zone`.
  - **Acceptance:** a documented decision; `recurring.yml` comment states the effective zone.
  - **Depends on:** D12.

- [ ] **M12. Docker Distribution API conformance smoke checks (content-type/header correctness for non-Docker clients).**
  - **Type:** ops/test. **Files:** `app/controllers/v2/manifests_controller.rb`, `app/controllers/v2/base_controller.rb`, `test/integration/docker_cli_test.sh`.
  - **Why:** The smoke checklist verifies push/pull/login round-trips with the Docker CLI but does not assert protocol-level headers
    other clients require — `Content-Type: application/vnd.docker.distribution.manifest.v2+json` (and OCI variant) on manifest GET,
    `Docker-Content-Digest` on manifest/blob responses, correct `Location` on upload POST/PUT. A round-trip can pass with Docker yet fail Podman/containerd/Skopeo.
  - **Steps:** Add checklist steps asserting `curl -sI` of a manifest returns the correct vnd media type + `Docker-Content-Digest`, and an upload POST returns 202 with a `Location` header; optionally run `skopeo copy`/`crane pull` against the live host.
  - **Acceptance:** manifest GET headers + upload POST `Location`/202 verified; optional `skopeo`/`crane` succeed.
  - **Depends on:** B12.

- [ ] **M13. Secret rotation runbook (master.key, Google client_secret, KAMAL_REGISTRY_PASSWORD, PATs).**
  - **Type:** docs. **Files:** `docs/PRE_SERVER_REGISTRATION_TODO.md`, `.kamal/secrets`, `config/credentials.yml.enc`.
  - **Why:** A leaked master.key compromises all secrets at once; there is no documented re-encrypt → redeploy → `kamal env push` → revoke-old procedure.
  - **Steps:** Write a rotation procedure for each secret with the exact command sequence and no-downtime ordering.
  - **Acceptance:** a written rotation procedure per secret with commands and ordering.

- [ ] **M14. Unused mailer scaffolding (inert).**
  - **Type:** docs/cleanup. **Files:** `app/mailers/application_mailer.rb`.
  - **Why:** Default generated class with `from@example.com`; zero subclasses/views/deliveries — email is never sent (`email_verified` comes from the OAuth profile). No action unless email is later needed; mention, don't delete.

---

## Required ENV vars & credentials checklist

| Var / Credential | Set where | Purpose | Consequence if missing/wrong |
|---|---|---|---|
| `RAILS_MASTER_KEY` | `.kamal/secrets:20` (→ real `config/master.key` or secret manager); `deploy.yml:41-42` `env.secret` | Decrypts credentials; derives `secret_key_base`; signs cookies/sessions | App boots but OAuth login fails and sessions silently break |
| `KAMAL_REGISTRY_PASSWORD` | `.kamal/secrets` | Auth to the *container image* registry (ghcr.io / Docker Hub / …) | `kamal deploy` cannot push the built image |
| Google OAuth (`google_oauth` in `credentials.yml.enc`) | encrypted credentials | Sign in with Google → user + PAT identity | All logins fail; cannot mint PATs → no authenticated push |
| `REGISTRY_ADMIN_EMAIL` | `deploy.yml` env.clear | Owner identity for first push to a NEW repo | First push 500s with `RecordNotFound` (B13/B14) |
| `REGISTRY_HOST` | `deploy.yml` env.clear | `host[:port]` rendered in every `/help` docker command | `/help` shows `localhost:3000`; every copy-paste command wrong (B6/H29) |
| `REGISTRY_ANONYMOUS_PULL` | `deploy.yml` env.clear | Toggles unauthenticated read | Defaults `true` → all repos world-readable + 3 DB writes/pull (D3/H15) |
| `SOLID_QUEUE_IN_PUMA` | already `true` in `deploy.yml:46` | Runs recurring GC/retention/prune in Puma | If unset on single node, GC jobs never run → volume fills (B17) |
| `RAILS_MAX_THREADS` (or `PUMA_THREADS`) | `deploy.yml` env.clear | Puma thread count AND SQLite pool `max_connections` | Pool (default 5) < threads (16) → `ConnectionTimeoutError` 500s (H12) |
| `MAX_REQUEST_BODY` | `deploy.yml` env.clear | Pins Thruster body cap to 0 (unlimited) | Default already 0 in 0.1.17; pin guards a future regression 413ing GB layers (H10) |
| `SENTRY_DSN` (if D4=Sentry) | `deploy.yml` `env.secret` + `.kamal/secrets` | Exception reporting | 500s invisible (no sink) (H8) |
| `STORAGE_PATH` | optional; default `/rails/storage/registry` on the Kamal volume | Blob storage root | Default correct; setting it OUTSIDE `/rails/storage` loses blobs on redeploy (M3) |
| `RETENTION_ENABLED` (+ `RETENTION_DAYS_WITHOUT_PULL`, `RETENTION_MIN_PULL_COUNT`, `RETENTION_PROTECT_LATEST`) | `deploy.yml` env.clear | Enables tag retention | Defaults off → retention silently never runs despite being scheduled (M4) |
| `DISK_WARN_PCT` / `DISK_CRITICAL_PCT` / `DISK_MIN_FREE_BYTES` | `deploy.yml` env.clear | Disk monitoring + upload backpressure | No monitoring → full volume corrupts all 4 SQLite DBs (H3) |
| `JOB_CONCURRENCY` | optional, `deploy.yml:49` | SolidQueue worker count | Default 1 fine for single-node SQLite |

---

## External setup (outside the repo)

- [ ] **Container image registry account (D6).** ghcr.io (PAT with `write:packages`) / Docker Hub (access token) / DigitalOcean / etc.
  Set `registry.server` + `image` namespace (B1/B2) and `KAMAL_REGISTRY_PASSWORD` (B2).
- [ ] **Google Cloud Console OAuth client (B8).** Web-application OAuth 2.0 Client; redirect URI
  `https://<PROD_HOST>/auth/google_oauth2/callback`; JS origin `https://<PROD_HOST>`; consent screen configured (scopes `email,profile`); add Test users or publish. Copy client_id/secret into credentials (B7).
- [ ] **DNS + TLS cert.** Public DNS A/AAAA for `<REGISTRY_DNS_NAME>` → `<REAL_HOST>`. D1=A: open ports 80+443 for Let's Encrypt HTTP-01.
  D1=B: issue + install the Nginx cert (certbot or corporate CA) and own renewal.
- [ ] **Backup target (B18).** S3/GCS bucket or remote rsync/ssh host; creds in `.kamal/secrets`; retention rule; restore drill executed.
- [ ] **External uptime monitor (H24).** UptimeRobot/BetterStack/Healthchecks.io on `https://<REGISTRY_DNS_NAME>/up` (1-2 min) + a `/v2/` liveness probe; alert channel documented.
- [ ] **Error sink account (D4/H8).** Sentry (or chosen) project + DSN.
- [ ] **Operator machine prerequisites.** `kamal`, `docker`, SSH key to `<REAL_HOST>`, `gh` (if ghcr.io token), the real `config/master.key`.

---

## First-deploy runbook (ordered)

Do these in exactly this order. The admin-bootstrap ordering (steps 6-7) is the single most dangerous trap.

1. **Pre-flight decisions (D1–D12).** Resolve at minimum TLS (D1), single-node (D2), anonymous-pull (D3), error sink (D4),
   image registry (D6). Record chosen values here.
2. **Resolve `config/deploy.yml` scaffold placeholders.** `image: <REGISTRY_NAMESPACE>/open_repo` (B1); `registry.server` +
   `username` + `password` (B2); `servers.web: <REAL_HOST>` (B3); `builder.arch` matches the server (H22); add `env.clear` keys
   `REGISTRY_HOST`, `SOLID_QUEUE_IN_PUMA: true` (present), `RAILS_MAX_THREADS`, `MAX_REQUEST_BODY: 0`, anonymous-pull, retention/disk
   as decided; add the `logging:` block (H7).
3. **Set secrets.** Provision the real `config/master.key` (B4, `chmod 600`); make `.kamal/secrets` robust (B5); set
   `KAMAL_REGISTRY_PASSWORD` (B2) and `SENTRY_DSN` (H8) if chosen. Verify: `kamal secrets print` resolves non-empty values;
   `bin/rails runner 'puts Rails.application.credentials.dig(:google_oauth, :client_id).present?'` → `true`.
4. **Google OAuth console (B8).** Create the Web OAuth client; redirect URI `https://<PROD_HOST>/auth/google_oauth2/callback`
   (https, exact host); store client_id/secret in credentials (B7). DNS for `<REGISTRY_DNS_NAME>` must already resolve to `<REAL_HOST>`.
5. **Configure TLS (B9 or B11) + `assume_ssl`/`force_ssl`/`/up` exclusion (B10) + proxy healthcheck/app_port=80 (H23).**
   Do NOT yet set `REGISTRY_ADMIN_EMAIL`.
6. **`kamal setup`.** Provisions Docker + kamal-proxy + first deploy. On first boot `bin/docker-entrypoint` runs `db:prepare`
   automatically (CMD's last two args are `./bin/rails server`) — do NOT run migrations manually. Verify: `curl -I https://<REGISTRY_DNS_NAME>/up` → 200;
   `curl -I https://<REGISTRY_DNS_NAME>/v2/` → 401 + `WWW-Authenticate: Basic realm="Registry"`.
7. **Operator signs in via Google (B13).** Visit `https://<REGISTRY_DNS_NAME>/sign_in` and complete Google OAuth as the EXACT email
   that will become `REGISTRY_ADMIN_EMAIL`. This creates the User + primary Identity rows `manifest_processor.rb` requires.
   **THIS MUST HAPPEN BEFORE THE FIRST PUSH.**
8. **Set `REGISTRY_ADMIN_EMAIL` + `kamal env push`.** Add `REGISTRY_ADMIN_EMAIL: <ADMIN_EMAIL>` to `deploy.yml` env.clear, then
   `kamal env push` (container picks it up without a full redeploy). Setting this before step 7 is the ordering trap.
   Verify: `kamal app exec --reuse 'bin/rails runner "puts User.find_by(email: ENV[\"REGISTRY_ADMIN_EMAIL\"])&.primary_identity.present?"'` → `true`.
9. **Verify the runtime invariants.** Recurring jobs (B17: `SolidQueue::RecurringTask.count == 4`, Supervisor heartbeat fresh);
   storage mount (H2: `df -h /rails/storage`); secret reached the container (`kamal app exec 'bin/rails runner "puts ENV[\"RAILS_MASTER_KEY\"].present?"'` → `true`).
10. **Smoke test (real push/pull).** Mint a PAT at `/settings/tokens`, then from a client that trusts the cert:
    ```bash
    docker login <REGISTRY_DNS_NAME> -u <ADMIN_EMAIL> -p <oprk_token>      # Login Succeeded
    docker pull alpine
    docker tag alpine <REGISTRY_DNS_NAME>/smoke/alpine:1
    docker push <REGISTRY_DNS_NAME>/smoke/alpine:1                         # first push: exercises manifest_processor.rb:18 — must NOT 500
    docker rmi <REGISTRY_DNS_NAME>/smoke/alpine:1
    docker pull <REGISTRY_DNS_NAME>/smoke/alpine:1                         # succeeds from a clean cache
    ```
    Confirm the `smoke/alpine` repo appears at `https://<REGISTRY_DNS_NAME>/` with the admin as owner.
11. **Set up backups + monitoring** (B18 backup + restore drill, H3 disk, H24 uptime) before announcing.

**Three most common failures:** (1) push 500 = `REGISTRY_ADMIN_EMAIL` set before that user signed in; (2) `docker login` hangs/denied =
plain HTTP to a non-localhost host with no TLS/insecure-registries; (3) login redirect mismatch = OAuth redirect URI host != `REGISTRY_HOST`.

---

## Post-deploy smoke test & verification

Run against the REAL host; check each off in this file.

1. **Health & discovery.** `curl -sf https://<REGISTRY_DNS_NAME>/up` → 200; `curl -s https://<REGISTRY_DNS_NAME>/v2/` → 401 with
   `WWW-Authenticate: Basic realm="Registry"` and `Docker-Distribution-API-Version: registry/2.0`.
2. **Admin bootstrap.** Admin signed in BEFORE first push; `/help` shows the real host (not `localhost:3000`).
3. **Login (TLS canary).** `docker login <REGISTRY_DNS_NAME> -u <ADMIN_EMAIL> -p <oprk_token>` → `Login Succeeded`.
4. **Small push.** `docker push <REGISTRY_DNS_NAME>/smoke/alpine:1` → 201/200, no 500.
5. **Large push (>1GB layer).** Exercises `MAX_REQUEST_BODY=0` + upload timeouts → 201/202, no 413/408.
6. **Pull on a clean Docker.** `docker rmi …; docker pull <REGISTRY_DNS_NAME>/smoke/alpine:1` → succeeds; digest matches.
7. **Web UI.** Pushed repo/tag appears at root + tag-history page; `TagEvent` actor = admin email.
8. **Anonymous-pull matches D3.** OFF → `docker logout` then pull → 401; ON → anonymous pull → 200 and a `PullEvent` row only for authenticated pulls (per H6).
9. **Protocol conformance (M12).** `curl -sI` of a manifest returns the correct `vnd.docker.distribution.manifest.v2+json` media type + `Docker-Content-Digest`; upload POST returns 202 with a `Location`. Optionally `skopeo copy`/`crane pull`.
10. **Error sink (H8).** `kamal app exec "bin/rails runner 'Sentry.capture_message(\"smoke\")'"` → event lands in Sentry; the raw `oprk_`/`Authorization` value never appears (H9).
11. **Logs & rotation.** `kamal app logs | head` shows single-line JSON; `docker inspect <container> --format '{{json .HostConfig.LogConfig}}'` shows `max-size`/`max-file`.
12. **Recurring jobs (B17).** `SolidQueue::RecurringTask.count == 4`; Supervisor heartbeat < 1 min; a manual `CleanupOrphanedBlobsJob.perform_now` reaches `finished_at`.
13. **Persistence (H2).** Push a tag, `kamal deploy`, `docker pull` the same tag → succeeds (blobs survived the redeploy).
14. **Throttling (M2).** 31st non-GET `/v2` from one IP within a minute → 429 + `Retry-After: 60`.
15. **Backup + restore drill (B18).** A backup run produces a restorable off-host artifact; the restore drill (fresh volume + separately-stored master.key) serves `docker pull` AND decrypts OAuth.
