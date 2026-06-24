#!/usr/bin/env bash
# agents.sh — read the current state of every yagent-managed agent.
#
# We combine three sources to figure out what's really going on:
#   1. Is the tmux session still alive?  (The ground truth for "running".)
#   2. The state file written by Devin hooks.  (What the agent is doing.)
#   3. The lock file.  (The task title you gave it.)
#
# What we report:
#   working | needs-you | idle | done | error | dead
#
#   - If tmux is alive -> trust the hook state.
#   - If tmux is dead  -> "done" if the hook said done or needs-you,
#                         "dead" otherwise (crashed or abandoned).
#
# Usage:
#   agents.sh list              list every known agent (tab-separated)
#   agents.sh get <dir>         single agent for one folder (empty if none)
#   agents.sh prune             clean up stale locks and ghost state files

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_ROOT="${YAGENT_STATE_ROOT:-${XDG_STATE_HOME:-$HOME/.local/state}/yagent}"

# Turn a folder path into a short tmux session name.
slug_for() { printf 'yagent-%s' "$(printf '%s' "$1" | shasum -a 256 | cut -c1-12)"; }

# Is the tmux session for this folder still alive?
running_for() { tmux has-session -t "$(slug_for "$1")" 2>/dev/null && echo yes || echo no; }

# Pull a top-level JSON field out without needing jq.
jget() { sed -n "s/.*\"$2\"[[:space:]]*:[[:space:]]*\"\{0,1\}\([^\",}]*\)\"\{0,1\}.*/\1/p" <<<"$1" | head -n1; }

# Print one tab-separated row for a given state file.
emit_row() {
  local sf="$1" json dir state action title running eff
  json="$(tr -d '\n' < "$sf")"
  dir="$(jget "$json" workdir)"
  [ -z "$dir" ] && return 0

  # We only care about agents started through yagent (agent.sh writes a lock).
  # Ad-hoc `devin` runs also fire hooks, but they have no lock — ignore them.
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

# Clean up one stale agent: if the tmux session is gone but the lock and/or
# state file still exist, remove them so the UI doesn't show a ghost agent.
prune_one() {
  local sf="$1" json dir state running
  json="$(tr -d '\n' < "$sf")"
  dir="$(jget "$json" workdir)"
  [ -z "$dir" ] && return 0
  [ -f "$dir/.yagent/owner.json" ] || return 0
  running="$(running_for "$dir")"
  [ "$running" = "yes" ] && return 0

  state="$(jget "$json" state)"
  case "$state" in
    done|dead|error|needs-you)
      rm -f "$sf"
      rm -f "$dir/.yagent/owner.json"
      rmdir "$dir/.yagent" 2>/dev/null || true
      ;;
  esac
}

# Walk every state file and prune the stale ones.
prune_all() {
  [ -d "$STATE_ROOT" ] || return 0
  local sf
  for sf in "$STATE_ROOT"/*.json; do
    [ -e "$sf" ] || continue
    prune_one "$sf"
  done
}

# List every agent we know about.
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
