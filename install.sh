#!/usr/bin/env bash
#
# Open Repo — single-host installer (Docker Compose + Caddy auto-HTTPS).
#
# Idempotent: safe to re-run. It validates prerequisites and configuration,
# builds the image, boots the stack, and smoke-tests the running app. It does
# NOT perform the external steps only an operator can do (DNS, Google OAuth
# console, the admin's first sign-in) — those are printed as next steps.
#
# Usage:
#   ./install.sh              build (if needed), start, smoke-test
#   ./install.sh --no-build   skip the image build (reuse the existing one)
#   ./install.sh --down       stop the stack (keeps the data volume)
#
set -euo pipefail

cd "$(dirname "$0")"

# ── pretty output ────────────────────────────────────────────────────────────
c_red=$'\033[31m'; c_grn=$'\033[32m'; c_yel=$'\033[33m'; c_bld=$'\033[1m'; c_off=$'\033[0m'
info() { printf '%s==>%s %s\n' "$c_bld" "$c_off" "$*"; }
ok()   { printf '%s  ✓%s %s\n' "$c_grn" "$c_off" "$*"; }
warn() { printf '%s  !%s %s\n' "$c_yel" "$c_off" "$*"; }
die()  { printf '%s  ✗ %s%s\n' "$c_red" "$*" "$c_off" >&2; exit 1; }

# ── compose wrapper (v2 plugin or legacy binary) ─────────────────────────────
if docker compose version >/dev/null 2>&1; then
  compose() { docker compose "$@"; }
elif command -v docker-compose >/dev/null 2>&1; then
  compose() { docker-compose "$@"; }
else
  compose() { :; }
fi

# ── subcommands ──────────────────────────────────────────────────────────────
if [[ "${1:-}" == "--down" ]]; then
  info "Stopping the stack (data volume preserved)…"
  compose down
  ok "Stopped. Run ./install.sh to start again; volumes are kept."
  exit 0
fi

do_build=1
[[ "${1:-}" == "--no-build" ]] && do_build=0

# ── 1. prerequisites ─────────────────────────────────────────────────────────
info "Checking prerequisites…"
command -v docker >/dev/null 2>&1 || die "docker is not installed. Install Docker Engine first."
docker info >/dev/null 2>&1 || die "Cannot talk to the Docker daemon (is it running? permissions?)."
docker compose version >/dev/null 2>&1 || command -v docker-compose >/dev/null 2>&1 \
  || die "Docker Compose v2 is not available (need 'docker compose' or 'docker-compose')."
[[ -f Dockerfile && -f docker-compose.yml ]] || die "Run this from the project root (Dockerfile/docker-compose.yml not found)."
ok "Docker $(docker --version | awk '{print $3}' | tr -d ,) + Compose present."

# ── 2. .env ──────────────────────────────────────────────────────────────────
if [[ ! -f .env ]]; then
  cp .env.example .env
  warn ".env created from .env.example."
  die  "Edit .env and set REGISTRY_HOST and REGISTRY_ADMIN_EMAIL, then re-run ./install.sh"
fi

# Read a KEY=value from .env (value as-is, last wins, '=' allowed in value).
env_get() { sed -n "s/^$1=//p" .env | tail -n1; }

# Upsert KEY=value in .env without disturbing other lines.
env_set() {
  local key="$1" val="$2" tmp
  tmp="$(mktemp)"
  if grep -q "^${key}=" .env; then
    # Use a literal replacement that tolerates / and & in the value.
    awk -v k="$key" -v v="$val" 'BEGIN{FS=OFS="="} $1==k{print k"="v; next} {print}' .env >"$tmp"
  else
    cat .env >"$tmp"; printf '%s=%s\n' "$key" "$val" >>"$tmp"
  fi
  mv "$tmp" .env
}

# ── 3. RAILS_MASTER_KEY ──────────────────────────────────────────────────────
master_key="$(env_get RAILS_MASTER_KEY)"
if [[ -z "$master_key" ]]; then
  if [[ -f config/master.key ]]; then
    master_key="$(tr -d '[:space:]' < config/master.key)"
    env_set RAILS_MASTER_KEY "$master_key"
    ok "RAILS_MASTER_KEY loaded from config/master.key into .env."
  else
    die "RAILS_MASTER_KEY is empty and config/master.key is missing. Provide the key
     that decrypts config/credentials.yml.enc (see docs/INSTALL.md)."
  fi
else
  ok "RAILS_MASTER_KEY already set in .env."
fi
[[ -n "$master_key" ]] || die "RAILS_MASTER_KEY resolved empty — refusing to boot a keyless app."

# ── 4. required runtime config ───────────────────────────────────────────────
registry_host="$(env_get REGISTRY_HOST)"
admin_email="$(env_get REGISTRY_ADMIN_EMAIL)"
[[ -n "$registry_host" && "$registry_host" != "registry.example.com" ]] \
  || die "Set REGISTRY_HOST in .env to your real registry FQDN (not the example value)."
[[ -n "$admin_email" && "$admin_email" != "admin@example.com" ]] \
  || die "Set REGISTRY_ADMIN_EMAIL in .env to the admin's real Google account (not the example)."
ok "REGISTRY_HOST=$registry_host  REGISTRY_ADMIN_EMAIL=$admin_email"
[[ -n "$(env_get REGISTRY_ALLOWED_EMAIL_DOMAINS)" ]] \
  || warn "REGISTRY_ALLOWED_EMAIL_DOMAINS is empty — ANY Google-verified email can sign in."

# ── 5. build + boot ──────────────────────────────────────────────────────────
if [[ "$do_build" == "1" ]]; then
  info "Building the application image (first build pulls gems + precompiles assets; this takes a few minutes)…"
  compose build
fi
info "Starting the stack…"
compose up -d

# ── 6. wait for health ───────────────────────────────────────────────────────
info "Waiting for the app to become healthy…"
cid="$(compose ps -q app)"
[[ -n "$cid" ]] || die "app container did not start. Check: docker compose logs app"
for _ in $(seq 1 36); do
  status="$(docker inspect -f '{{.State.Health.Status}}' "$cid" 2>/dev/null || echo starting)"
  [[ "$status" == "healthy" ]] && break
  [[ "$status" == "unhealthy" ]] && { compose logs --tail 40 app; die "app went unhealthy. See logs above."; }
  sleep 5
done
[[ "$status" == "healthy" ]] || { compose logs --tail 40 app; die "app did not become healthy in time. See logs above."; }
ok "app is healthy."

# ── 7. smoke test ────────────────────────────────────────────────────────────
info "Smoke-testing the running app…"
compose exec -T app curl -fsS http://localhost:80/up >/dev/null \
  && ok "GET /up -> 200 (Rails health check)." \
  || die "GET /up failed inside the container."
v2_code="$(compose exec -T app sh -c 'curl -s -o /dev/null -w "%{http_code}" http://localhost:80/v2/' || true)"
case "$v2_code" in
  200) ok "GET /v2/ -> 200 (anonymous pull enabled)." ;;
  401) ok "GET /v2/ -> 401 with auth challenge (anonymous pull disabled)." ;;
  *)   warn "GET /v2/ returned HTTP $v2_code (expected 200 or 401). Check: docker compose logs app" ;;
esac

# ── 8. next steps ────────────────────────────────────────────────────────────
cat <<EOF

${c_grn}${c_bld}✓ Open Repo is up.${c_off}  Web UI / API:  ${c_bld}https://${registry_host}${c_off}

${c_bld}Before the first docker push — do these in order:${c_off}
  1. DNS: point ${registry_host} at this host (A/AAAA). Caddy needs 80 + 443
     open to issue the Let's Encrypt cert. Watch it with:  docker compose logs -f caddy
  2. Google OAuth (GCP console): add redirect URI
       https://${registry_host}/auth/google_oauth2/callback
     and JavaScript origin  https://${registry_host} . Put client_id/secret in
     Rails credentials under google_oauth: (see docs/INSTALL.md).
  3. ${c_yel}Admin first sign-in (ORDERING TRAP):${c_off} have ${admin_email} open
     https://${registry_host}/sign_in and sign in with Google ${c_bld}before${c_off} any push.
     A push to a fresh repo before this 500s.
  4. Create a Personal Access Token at https://${registry_host}/settings/tokens
     then:  docker login ${registry_host} -u ${admin_email} -p <oprk_token>

Useful:
  docker compose logs -f app      docker compose logs -f caddy
  docker compose ps               ./install.sh --down   (stop; keeps data)
EOF
