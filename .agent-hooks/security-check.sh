#!/usr/bin/env bash
# Shared PreToolUse hook for Bash commands. It blocks obviously destructive or
# production-facing commands before Claude Code or Codex runs them.

set -euo pipefail

command -v jq >/dev/null 2>&1 || exit 0

payload="$(cat)"
event="$(printf '%s' "$payload" | jq -r '.hook_event_name // .hookEventName // empty' 2>/dev/null || true)"
tool="$(printf '%s' "$payload" | jq -r '.tool_name // .toolName // empty' 2>/dev/null || true)"
cmd="$(printf '%s' "$payload" | jq -r '.tool_input.command // .toolInput.command // empty' 2>/dev/null || true)"

if [[ -n "$tool" && "$tool" != "Bash" ]]; then
  exit 0
fi

if [[ -z "$cmd" ]]; then
  exit 0
fi

deny_reason=""

case "$cmd" in
  *"rm -rf /"*|*"rm -rf ~"*|*"sudo rm -rf"*|*"mkfs."*|*"dd if="*)
    deny_reason="destructive filesystem command blocked"
    ;;
  *"kubectl "*prod*|*"helm "*prod*|*"terraform apply"*prod*|*"terraform destroy"*)
    deny_reason="production infrastructure command blocked"
    ;;
  *"git push --force"*|*"git push -f"*)
    deny_reason="force push blocked"
    ;;
esac

if [[ -n "$deny_reason" ]]; then
  hook_event="${event:-PreToolUse}"
  jq -n --arg event "$hook_event" --arg reason "$deny_reason" \
    '{hookSpecificOutput:{hookEventName:$event,permissionDecision:"deny",permissionDecisionReason:$reason}}'
  printf '%s\n' "$deny_reason" >&2
  exit 2
fi

exit 0
