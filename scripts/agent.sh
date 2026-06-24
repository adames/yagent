#!/usr/bin/env bash
# agent.sh — manage a Devin local agent attached to a folder, via tmux.
#
# One tmux session per agent, named "yagent-<slug>" where <slug> derives from
# the folder path. The agent runs `devin` inside the folder. A lock file at
# <folder>/.yagent/owner.json records the tmux session + task title.
#
# Usage:
#   agent.sh start  <dir> [task...]   create session + launch devin (with task)
#   agent.sh attach <dir>             attach to the agent's REPL (foreground)
#   agent.sh send   <dir> <text...>   send a line to the running REPL
#   agent.sh kill   <dir>             kill the session + clear the lock
#   agent.sh status <dir>             print running|stopped
#   agent.sh slug   <dir>             print the tmux session name

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

slug_for() {
  local dir; dir="$(cd "$1" && pwd -P)"
  printf 'yagent-%s' "$(printf '%s' "$dir" | shasum -a 256 | cut -c1-12)"
}

has_session() { tmux has-session -t "$1" 2>/dev/null; }

require_tmux() {
  command -v tmux >/dev/null || { echo "yagent: tmux is required" >&2; exit 1; }
}

write_lock() {
  local dir="$1" session="$2" title="$3"
  mkdir -p "$dir/.yagent"
  local esc_title; esc_title="$(printf '%s' "$title" | sed 's/\\/\\\\/g; s/"/\\"/g')"
  cat > "$dir/.yagent/owner.json" <<EOF
{
  "session": "$session",
  "title": "$esc_title",
  "started_at": $(date +%s)
}
EOF
}

cmd="${1:-}"; shift || true
case "$cmd" in
  slug)
    slug_for "${1:?dir required}"; echo
    ;;

  status)
    dir="${1:?dir required}"; s="$(slug_for "$dir")"
    if has_session "$s"; then echo running; else echo stopped; fi
    ;;

  start)
    require_tmux
    dir="${1:?dir required}"; shift || true
    task="$*"
    dir="$(cd "$dir" && pwd -P)"
    s="$(slug_for "$dir")"
    if has_session "$s"; then
      echo "yagent: agent already running for $dir ($s)" >&2
      exit 0
    fi
    write_lock "$dir" "$s" "$task"
    # Build the devin command. With a task, start the REPL seeded with it.
    if [ -n "$task" ]; then
      # shellcheck disable=SC2089
      dcmd="devin -- $(printf '%q ' "$task")"
    else
      dcmd="devin"
    fi
    tmux new-session -d -s "$s" -c "$dir" "$dcmd"
    echo "$s"
    ;;

  attach)
    require_tmux
    dir="${1:?dir required}"; s="$(slug_for "$dir")"
    if ! has_session "$s"; then echo "yagent: no agent for $dir" >&2; exit 1; fi
    tmux attach-session -t "$s"
    ;;

  send)
    require_tmux
    dir="${1:?dir required}"; shift || true
    s="$(slug_for "$dir")"
    if ! has_session "$s"; then echo "yagent: no agent for $dir" >&2; exit 1; fi
    tmux send-keys -t "$s" "$*" Enter
    ;;

  kill)
    require_tmux
    dir="${1:?dir required}"; dir="$(cd "$dir" && pwd -P)"; s="$(slug_for "$dir")"
    has_session "$s" && tmux kill-session -t "$s" 2>/dev/null || true
    rm -f "$dir/.yagent/owner.json" 2>/dev/null || true
    echo "killed $s"
    ;;

  *)
    echo "usage: agent.sh {start|attach|send|kill|status|slug} <dir> [args]" >&2
    exit 2
    ;;
esac
