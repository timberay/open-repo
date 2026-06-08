#!/usr/bin/env bash
# UserPromptSubmit hook: when the user references prior decisions, remind the
# AI to consult docs/decisions/ (the ADR index) before answering.
#
# Input (stdin, JSON): { "prompt": "<user message>", ... }
# Output (stdout, JSON, only when keywords match):
#   {"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"..."}}

set -euo pipefail

# Degrade to a silent no-op if jq is unavailable, rather than failing the hook
# on every prompt.
command -v jq >/dev/null 2>&1 || exit 0

payload="$(cat)"
# Tolerate malformed JSON: a non-JSON payload should make this hook a no-op,
# not exit non-zero (which Claude Code interprets as a blocking error).
prompt="$(printf '%s' "$payload" | jq -r '.prompt // empty' 2>/dev/null || true)"

[[ -z "$prompt" ]] && exit 0

# Keywords that suggest the user is asking about prior decisions.
# Conservative — bare "earlier" / "previously" produce too many false positives
# ("I updated this earlier today"), so we require those to co-occur with
# decision-related vocabulary.
pattern='이전에|예전|전에 결정|왜 .{1,30}했|why did we|revisit|past decision|previously decided|previously chose|earlier decision|decided earlier'

if echo "$prompt" | grep -iqE "$pattern"; then
  ctx="→ The user is referencing prior decisions. Read \`docs/decisions/README.md\` index first — decisions live in ADRs (immutable), not in git log. If you intend to change a locked decision, do it via /supersede, not by silently flipping it."
  jq -n --arg ctx "$ctx" '{hookSpecificOutput:{hookEventName:"UserPromptSubmit",additionalContext:$ctx}}'
fi
