#!/usr/bin/env bash
# install.sh — set yagent up on this machine.
#
# What it does:
#   1. Makes the scripts/hooks/bin executable.
#   2. Installs the Devin lifecycle hooks into your user-level Devin config
#      (~/.config/devin/config.json) so every agent reports its state. Your
#      existing config is backed up; existing hooks are never clobbered.
#   3. Prints how to put `yagent` on your PATH.
#
# The yazi side needs no install step: `bin/yagent` launches yazi with an
# isolated config (YAZI_CONFIG_HOME) that wires in the plugin automatically, so
# your normal yazi setup is untouched.
#
# Safe to re-run.

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEVIN_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/devin/config.json"
HOOK_BIN="$REPO/hooks/devin-status-hook.sh"

info() { printf '\033[36m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[33m!!\033[0m  %s\n' "$*" >&2; }

# 1. Permissions -------------------------------------------------------------
chmod +x "$REPO"/scripts/*.sh "$REPO"/hooks/*.sh "$REPO"/bin/* 2>/dev/null || true
info "Marked scripts executable."

# 2. Hooks -------------------------------------------------------------------
RENDERED="$(mktemp)"
sed "s|\$YAGENT_HOOK|$HOOK_BIN|g" "$REPO/hooks/hooks.json" > "$RENDERED"

if command -v python3 >/dev/null && [ -f "$DEVIN_CONFIG" ]; then
  cp "$DEVIN_CONFIG" "$DEVIN_CONFIG.bak"
  info "Backed up $DEVIN_CONFIG -> $DEVIN_CONFIG.bak"
  python3 - "$DEVIN_CONFIG" "$RENDERED" <<'PY'
import json, sys
cfg_path, hooks_path = sys.argv[1], sys.argv[2]
with open(cfg_path) as f: cfg = json.load(f)
with open(hooks_path) as f: new_hooks = json.load(f)
existing = cfg.setdefault("hooks", {})
added = []
for event, entries in new_hooks.items():
    if event not in existing:
        existing[event] = entries
        added.append(event)
if added:
    with open(cfg_path, "w") as f: json.dump(cfg, f, indent=2)
    print("==> Merged yagent hooks into Devin user config:", ", ".join(added))
else:
    print("==> yagent hooks already present in Devin user config — nothing to do.")
PY
else
  mkdir -p "$(dirname "$DEVIN_CONFIG")"
  cp "$RENDERED" "$(dirname "$DEVIN_CONFIG")/yagent-hooks.json"
  warn "Wrote $(dirname "$DEVIN_CONFIG")/yagent-hooks.json — merge its contents under"
  warn "the \"hooks\" key of $DEVIN_CONFIG (see docs.devin.ai hooks)."
fi
rm -f "$RENDERED"

# 3. Scripts (global install) ------------------------------------------------
GLOBAL_SCRIPTS="${XDG_DATA_HOME:-$HOME/.local/share}/yagent/scripts"
mkdir -p "$GLOBAL_SCRIPTS"
cp "$REPO"/scripts/*.sh "$GLOBAL_SCRIPTS/"
chmod +x "$GLOBAL_SCRIPTS"/*.sh
info "Installed scripts to $GLOBAL_SCRIPTS."

# 4. Shell alias -------------------------------------------------------------
ALIAS_LINE="alias yagent='$REPO/bin/yagent'"

# Pick the right shell profile to write into.
if [ -n "${ZSH_VERSION:-}" ] || [[ "${SHELL:-}" == */zsh ]]; then
  PROFILE="$HOME/.zshrc"
elif [ -f "$HOME/.bashrc" ]; then
  PROFILE="$HOME/.bashrc"
else
  PROFILE="$HOME/.profile"
fi

if grep -qF "alias yagent=" "$PROFILE" 2>/dev/null; then
  info "yagent alias already present in $PROFILE — skipping."
else
  printf '\n# yagent\n%s\n' "$ALIAS_LINE" >> "$PROFILE"
  info "Added yagent alias to $PROFILE."
  info "Run:  source $PROFILE   (or open a new terminal) to activate it."
fi

# 5. Usage -------------------------------------------------------------------
cat <<EOF

yagent installed.

  yagent [dir]          open the agent dashboard in that directory
  yagent                open in the current directory

Inside: N new · a attach · s send · K kill · c clear · r refresh · g a overview

Or add the plugin to your existing yazi config:
  ya pkg add adames-cognition/yagent:devin-agent
EOF
