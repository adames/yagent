#!/usr/bin/env bash
# worktree.sh — isolated-mode support (v0.3): run an agent in a hidden git
# worktree of a folder's repo so parallel agents can't collide, while yagent
# still presents the agent as attached to the original folder.
#
# Usage:
#   worktree.sh add <dir> <branch>   create a worktree for <branch>; print its path
#   worktree.sh remove <path>        remove a worktree (guards a live agent)
#   worktree.sh root <dir>           print the managed worktree root for <dir>'s repo
#
# NOTE: scaffold only — wired up in the v0.3 milestone.

set -euo pipefail

repo_root() { git -C "$1" rev-parse --show-toplevel; }

cmd="${1:-}"; shift || true
case "$cmd" in
  root)
    dir="${1:?dir required}"
    printf '%s.yagent-worktrees\n' "$(repo_root "$dir")"
    ;;
  add)
    echo "worktree.sh: not implemented yet (v0.3)" >&2
    exit 1
    ;;
  remove)
    echo "worktree.sh: not implemented yet (v0.3)" >&2
    exit 1
    ;;
  *)
    echo "usage: worktree.sh {add|remove|root} ..." >&2
    exit 2
    ;;
esac
