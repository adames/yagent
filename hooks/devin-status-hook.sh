#!/usr/bin/env bash
# devin-status-hook.sh — Devin CLI lifecycle hook dispatcher for yagent.
#
# Invoked by Devin for each lifecycle event (see hooks.json). It reads the hook
# payload on stdin, derives a yagent state for the agent's working directory,
# and writes it atomically to the folder's state file.
#
# Invocation: devin-status-hook.sh <event>
#   where <event> is one of:
#     session-start | prompt | pre-tool | post-tool | stop | session-end
#
# State written (JSON): { state, action, title, session_id, ts }
#   state: working | needs-you | idle | done | error

set -euo pipefail

EVENT="${1:-unknown}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATEDIR_SH="$HERE/../scripts/statedir.sh"

# The hook runs inside the agent's working directory.
WORKDIR="$(pwd -P)"

# Slurp stdin (may be empty for some events). Keep it small/safe.
PAYLOAD="$(cat 2>/dev/null || true)"

json_get() {
  # Best-effort extract a top-level string field from PAYLOAD without jq.
  # $1 = field name
  printf '%s' "$PAYLOAD" | sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" | head -n1
}

now() { date +%s; }

# Map the lifecycle event to a yagent state + a short action label.
case "$EVENT" in
  session-start) STATE="idle";      ACTION="starting" ;;
  prompt)        STATE="working";   ACTION="thinking" ;;
  pre-tool)      STATE="working";   ACTION="$(json_get tool_name)" ;;
  post-tool)     STATE="working";   ACTION="$(json_get tool_name)" ;;
  stop)          STATE="needs-you"; ACTION="awaiting input" ;;
  session-end)   STATE="done";      ACTION="ended" ;;
  *)             STATE="idle";      ACTION="$EVENT" ;;
esac

STATE_FILE="$(bash "$STATEDIR_SH" path "$WORKDIR")"
mkdir -p "$(dirname "$STATE_FILE")"

# Carry over a human title from the lock file if present.
TITLE=""
if [ -f "$WORKDIR/.yagent/owner.json" ]; then
  TITLE="$(sed -n 's/.*"title"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$WORKDIR/.yagent/owner.json" | head -n1)"
fi

esc() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }

TMP="$(mktemp "${STATE_FILE}.XXXXXX")"
cat > "$TMP" <<EOF
{
  "state": "$(esc "$STATE")",
  "action": "$(esc "$ACTION")",
  "title": "$(esc "$TITLE")",
  "workdir": "$(esc "$WORKDIR")",
  "ts": $(now)
}
EOF
mv -f "$TMP" "$STATE_FILE"

# Hooks must not block the agent; always succeed.
exit 0
