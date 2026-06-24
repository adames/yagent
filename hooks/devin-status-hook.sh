#!/usr/bin/env bash
# devin-status-hook.sh — bridge between Devin CLI and yagent.
#
# Devin calls this script for every lifecycle event (see hooks.json).
# We read the event payload, figure out what the agent is doing, and
# write that state to a small JSON file so yazi can display it.
#
# Invocation: devin-status-hook.sh <event>
#   Events: session-start | prompt | pre-tool | post-tool | stop | session-end
#
# What we write (JSON):
#   { state, action, title, workdir, ts }
#   state is one of: working | needs-you | idle | done | error

set -euo pipefail

EVENT="${1:-unknown}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATEDIR_SH="$HERE/../scripts/statedir.sh"

# Devin sets DEVIN_PROJECT_DIR to the project root for every hook; prefer it and
# fall back to the current directory.
WORKDIR="${DEVIN_PROJECT_DIR:-$(pwd -P)}"
WORKDIR="$(cd "$WORKDIR" 2>/dev/null && pwd -P || printf '%s' "$WORKDIR")"

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

# Live update (DDS): if this is a yagent-managed agent (has a lock) and we know
# the yazi client id, push the new state so the UI re-colors instantly without
# waiting for a directory reload or manual refresh. Body is tab-separated:
#   workdir \t state \t action \t title
if [ -f "$WORKDIR/.yagent/owner.json" ] && [ -n "${YAGENT_YAZI_ID:-}" ] && command -v ya >/dev/null 2>&1; then
  printf -v BODY '%s\t%s\t%s\t%s' "$WORKDIR" "$STATE" "$ACTION" "$TITLE"
  ya pub-to "$YAGENT_YAZI_ID" yagent-update --str "$BODY" >/dev/null 2>&1 || true
fi

# Never let a hook failure slow down the agent.
exit 0
