#!/usr/bin/env bash
# PreToolUse hook for Edit / Write / NotebookEdit: warn if PROJECT_STATE.md is
# missing or stale (>STATE_STALE_DAYS days old, default 7). Never blocks — the
# script exits 0 in all cases. Warning goes to stderr so it appears in transcript.
#
# Input (stdin, JSON): { "tool_name": "Edit|Write|NotebookEdit|...", ... }

set -euo pipefail

# Degrade to a silent no-op if jq is unavailable, rather than failing the hook
# on every Edit/Write.
command -v jq >/dev/null 2>&1 || exit 0

payload="$(cat)"
tool="$(printf '%s' "$payload" | jq -r '.tool_name // empty' 2>/dev/null || true)"

case "$tool" in
  Edit|Write|NotebookEdit) ;;
  *) exit 0 ;;
esac

state_file="PROJECT_STATE.md"
threshold="${STATE_STALE_DAYS:-7}"

if [[ ! -f "$state_file" ]]; then
  printf '%s\n' "⚠ Orchestrator: PROJECT_STATE.md is missing. Run /state-sync to bootstrap." >&2
  exit 0
fi

# Cross-platform mtime in seconds since epoch (GNU coreutils + BSD/macOS).
mtime=$(stat -c %Y "$state_file" 2>/dev/null || stat -f %m "$state_file" 2>/dev/null || echo 0)
now=$(date +%s)
age_days=$(( (now - mtime) / 86400 ))

if (( age_days >= threshold )); then
  printf '%s\n' "⚠ Orchestrator: PROJECT_STATE.md is ${age_days} days stale (threshold: ${threshold}). Run /state-sync." >&2
fi

exit 0
