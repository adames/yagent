#!/usr/bin/env bash
# statedir.sh — map a working directory to its yagent state-file path.
#
# The same hashing logic is used by the lifecycle hooks (writers) and by the
# yazi plugin (reader), so both sides agree on where a folder's state lives.
#
# Usage:
#   statedir.sh root                # print the state root dir
#   statedir.sh path /abs/dir       # print the state-file path for a folder
#   statedir.sh hash /abs/dir       # print just the hash for a folder

set -euo pipefail

YAGENT_STATE_ROOT="${YAGENT_STATE_ROOT:-${XDG_STATE_HOME:-$HOME/.local/state}/yagent}"

dir_hash() {
  # Resolve to an absolute, symlink-free path so /a and /a/ hash the same.
  local dir="$1"
  dir="$(cd "$dir" 2>/dev/null && pwd -P || printf '%s' "$dir")"
  printf '%s' "$dir" | shasum -a 256 | cut -d' ' -f1
}

cmd="${1:-}"
case "$cmd" in
  root)
    printf '%s\n' "$YAGENT_STATE_ROOT"
    ;;
  hash)
    dir_hash "${2:?usage: statedir.sh hash <dir>}"
    ;;
  path)
    dir="${2:?usage: statedir.sh path <dir>}"
    printf '%s/%s.json\n' "$YAGENT_STATE_ROOT" "$(dir_hash "$dir")"
    ;;
  *)
    echo "usage: statedir.sh {root|path <dir>|hash <dir>}" >&2
    exit 2
    ;;
esac
