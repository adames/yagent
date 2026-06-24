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
with open(hooks_path) as f: hooks = json.load(f)
existing = cfg.get("hooks")
if existing:
    print("!!  Devin config already has a 'hooks' key; not modifying it.", file=sys.stderr)
    print("    Merge these events manually:", ", ".join(hooks), file=sys.stderr)
    sys.exit(3)
cfg["hooks"] = hooks
with open(cfg_path, "w") as f: json.dump(cfg, f, indent=2)
print("==> Installed yagent hooks into Devin user config.")
PY
  rc=$?
  if [ "$rc" = "3" ]; then
    cp "$RENDERED" "$(dirname "$DEVIN_CONFIG")/yagent-hooks.json"
    warn "Wrote $(dirname "$DEVIN_CONFIG")/yagent-hooks.json for manual merge."
  fi
else
  mkdir -p "$(dirname "$DEVIN_CONFIG")"
  cp "$RENDERED" "$(dirname "$DEVIN_CONFIG")/yagent-hooks.json"
  warn "Wrote $(dirname "$DEVIN_CONFIG")/yagent-hooks.json — merge its contents under"
  warn "the \"hooks\" key of $DEVIN_CONFIG (see docs.devin.ai hooks)."
fi
rm -f "$RENDERED"

# 3. PATH --------------------------------------------------------------------
cat <<EOF

yagent installed.

Put the launcher on your PATH (add to your shell rc):
  export PATH="$REPO/bin:\$PATH"

Then run it on any repo:
  yagent ~/code/your-repo

Inside: N new agent · a attach · s send · K kill · r refresh
EOF
