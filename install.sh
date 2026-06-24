#!/usr/bin/env bash
# install.sh — wire yagent into yazi + Devin on this machine.
#
# What it does:
#   1. Symlinks the plugin into ~/.config/yazi/plugins/devin-agent.yazi
#   2. Installs the Devin lifecycle hooks (writes/merges a hooks config) so every
#      agent reports its state.
#   3. Prints next steps (merging keymap, adding bin/ to PATH).
#
# Safe to re-run (idempotent). Nothing is overwritten without a .bak backup.

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

YAZI_CONFIG="${YAZI_CONFIG_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/yazi}"
DEVIN_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/devin"

info() { printf '\033[36m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[33m!!\033[0m  %s\n' "$*" >&2; }

# 1. Plugin symlink ----------------------------------------------------------
info "Linking plugin into $YAZI_CONFIG/plugins/"
mkdir -p "$YAZI_CONFIG/plugins"
ln -sfn "$REPO/plugins/devin-agent.yazi" "$YAZI_CONFIG/plugins/devin-agent.yazi"

# 2. Hooks -------------------------------------------------------------------
# The hook command runs the dispatcher; we export YAGENT_HOOK so hooks.json can
# reference it. Devin reads hooks from its config dir; we drop a ready-to-merge
# file plus a note (auto-merging arbitrary Devin config is left to the user to
# review).
HOOK_BIN="$REPO/hooks/devin-status-hook.sh"
info "Devin hook dispatcher: $HOOK_BIN"
mkdir -p "$DEVIN_CONFIG"
RENDERED="$DEVIN_CONFIG/yagent-hooks.json"
sed "s|\$YAGENT_HOOK|$HOOK_BIN|g" "$REPO/hooks/hooks.json" > "$RENDERED"
info "Wrote rendered hooks to $RENDERED"
warn "Review and merge $RENDERED into your Devin hooks config (see docs:"
warn "  https://docs.devin.ai/cli/extensibility/hooks/overview )."

# 3. Permissions -------------------------------------------------------------
chmod +x "$REPO"/scripts/*.sh "$REPO"/hooks/*.sh "$REPO"/bin/* 2>/dev/null || true

cat <<EOF

yagent installed.

Next steps:
  * Merge keymap:  append $REPO/config/keymap.toml into $YAZI_CONFIG/keymap.toml
  * Add launcher:  put $REPO/bin on your PATH, then run:  yagent ~/code/your-repo
  * Verify hooks:  start a 'devin' session and confirm a state file appears under
                   \$(bash $REPO/scripts/statedir.sh root)
EOF
