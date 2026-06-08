#!/usr/bin/env bash
# UserPromptSubmit hook: when the user asks for NEW FEATURE work, inject the
# six-phase pipeline reminder (pipeline-reminder.txt).
#
# Two guardrails keep this from becoming context noise:
#   1. Narrow keywords — bare "추가/만들/build/add" fire on trivial edits
#      ("이 줄 추가해줘"), so we require new-feature framing.
#   2. Once per session — the reminder is injected at most once per session_id,
#      not on every matching prompt.
#
# Input (stdin, JSON): { "prompt": "<user message>", "session_id": "...", ... }
# Output (stdout, JSON, only when it fires):
#   {"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"..."}}

set -euo pipefail

# Degrade to a silent no-op if jq is unavailable, rather than erroring on every
# prompt (a missing jq must never turn into a blocking hook failure).
command -v jq >/dev/null 2>&1 || exit 0

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
reminder="$HERE/pipeline-reminder.txt"
[[ -f "$reminder" ]] || exit 0

payload="$(cat)"
prompt="$(printf '%s' "$payload" | jq -r '.prompt // empty' 2>/dev/null || true)"
[[ -z "$prompt" ]] && exit 0

# Narrow feature-intent keywords. We deliberately do NOT match bare
# "추가 / 만들 / build / add" — those dominate ordinary dev conversation and
# would re-inject this reminder on nearly every prompt.
pattern='새 기능|새로운 기능|기능 추가|기능을 추가|기능 구현|기능을 구현|신규 기능|새 페이지|새 화면|새 엔드포인트|new feature|implement (a |an |the |new )|build (a |an |the )?(new )?(feature|page|screen|endpoint|api)|add (a |an |the )?(new )?(feature|page|screen|endpoint|api)'

echo "$prompt" | grep -iqE "$pattern" || exit 0

# Once per session: skip if we already reminded in this session.
session="$(printf '%s' "$payload" | jq -r '.session_id // empty' 2>/dev/null || true)"
if [[ -n "$session" ]]; then
  # Keep the marker name filesystem-safe regardless of the session_id format.
  safe="$(printf '%s' "$session" | tr -c 'A-Za-z0-9._-' '_')"
  marker="${TMPDIR:-/tmp}/.pipeline-reminder.${safe}"
  [[ -f "$marker" ]] && exit 0
  : > "$marker" 2>/dev/null || true
fi

jq -n --rawfile ctx "$reminder" \
  '{hookSpecificOutput:{hookEventName:"UserPromptSubmit",additionalContext:$ctx}}'
