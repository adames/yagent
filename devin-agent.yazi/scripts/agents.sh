#!/usr/bin/env bash
# agents.sh — query yagent agent status (read-only).
#
# Combines three sources into one effective state per folder:
#   1. tmux liveness  -> is the agent process actually running?
#   2. state file      -> what is it doing? (written by Devin lifecycle hooks)
#   3. lock file       -> task title
#
# Effective state (what the UI color-codes on):
#   working | needs-you | idle | done | error | dead
#     - if tmux is alive: use the hook state (working/needs-you/idle/error)
#     - if tmux is dead:  "done" when the hook said done/needs-you,
#                         otherwise "dead" (crashed/abandoned)
#
# Usage:
#   agents.sh list            TSV of all known agents: dir \t state \t action \t running \t title
#   agents.sh get <dir>       same single row for one folder (empty if none)

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_ROOT="${YAGENT_STATE_ROOT:-${XDG_STATE_HOME:-$HOME/.local/state}/yagent}"

slug_for() { printf 'yagent-%s' "$(printf '%s' "$1" | shasum -a 256 | cut -c1-12)"; }
running_for() { tmux has-session -t "$(slug_for "$1")" 2>/dev/null && echo yes || echo no; }

# Extract a top-level JSON string/number field (no jq dependency).
jget() { sed -n "s/.*\"$2\"[[:space:]]*:[[:space:]]*\"\{0,1\}\([^\",}]*\)\"\{0,1\}.*/\1/p" <<<"$1" | head -n1; }

emit_row() {
  # $1 = state file path (must exist)
  local sf="$1" json dir state action title running eff
  json="$(tr -d '\n' < "$sf")"
  dir="$(jget "$json" workdir)"
  [ -z "$dir" ] && return 0
  # Only surface yagent-managed agents: those started via agent.sh, which
  # writes a lock. Global Devin hooks also fire for non-yagent sessions
  # (e.g. ad-hoc `devin` runs); those have no lock and are ignored here.
  [ -f "$dir/.yagent/owner.json" ] || return 0
  state="$(jget "$json" state)"
  action="$(jget "$json" action)"
  title="$(jget "$json" title)"
  running="$(running_for "$dir")"

  if [ "$running" = "yes" ]; then
    eff="$state"
  else
    case "$state" in
      done|needs-you) eff="done" ;;
      *)              eff="dead" ;;
    esac
  fi
  [ -z "$eff" ] && eff="idle"
  printf '%s\t%s\t%s\t%s\t%s\n' "$dir" "$eff" "${action:-}" "$running" "${title:-}"
}

prune_one() {
  # $1 = state file path
  local sf="$1" json dir state running
  json="$(tr -d '\n' < "$sf")"
  dir="$(jget "$json" workdir)"
  [ -z "$dir" ] && return 0
  [ -f "$dir/.yagent/owner.json" ] || return 0
  running="$(running_for "$dir")"
  [ "$running" = "yes" ] && return 0

  # Session is dead but lock exists -> stale.  Also remove the state file
  # if the agent ended in a terminal state (done/dead) so it disappears
  # from the UI instead of lingering as a ghost.
  state="$(jget "$json" state)"
  case "$state" in
    done|dead|error|needs-you)
      rm -f "$sf"
      rm -f "$dir/.yagent/owner.json"
      rmdir "$dir/.yagent" 2>/dev/null || true
      ;;
  esac
}

prune_all() {
  [ -d "$STATE_ROOT" ] || return 0
  local sf
  for sf in "$STATE_ROOT"/*.json; do
    [ -e "$sf" ] || continue
    prune_one "$sf"
  done
}

list_all() {
  [ -d "$STATE_ROOT" ] || return 0
  local sf
  for sf in "$STATE_ROOT"/*.json; do
    [ -e "$sf" ] || continue
    emit_row "$sf"
  done
}

cmd="${1:-list}"; shift || true
case "$cmd" in
  list)
    list_all
    ;;
  prune)
    prune_all
    ;;
  get)
    dir="$(cd "${1:?usage: agents.sh get <dir>}" && pwd -P)"
    sf="$STATE_ROOT/$(printf '%s' "$dir" | shasum -a 256 | cut -d' ' -f1).json"
    [ -f "$sf" ] && emit_row "$sf" || true
    ;;
  *)
    echo "usage: agents.sh {list|get <dir>|prune}" >&2
    exit 2
    ;;
esac
