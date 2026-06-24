# Changelog

## v0.2.x — Robustness & Packaging

### Added

- **Stale-lock pruning.** `agents.sh prune` detects dead tmux sessions that still have lock files and cleans them up. Called automatically on every refresh (`r`).
- **`c` clear action.** Remove a finished (done / dead / error) agent after confirmation, so your UI stays tidy.
- **`require_devin` check.** Starting an agent now fails fast with a helpful message if `devin` is not installed.
- **Script auto-discovery.** The plugin finds its shell helpers in three places: `$YAGENT_SCRIPTS`, the plugin's own `scripts/` directory, or `~/.local/share/yagent/scripts`.
- **`ya pkg` support.** The plugin is now self-contained at `devin-agent.yazi/` and installable via `ya pkg add adames-cognition/yagent:devin-agent`.
- **Global script install.** `install.sh` now copies scripts to `~/.local/share/yagent/scripts` so `ya pkg` users don't need the launcher.
- **Troubleshooting table** in the README.

### Changed

- Restructured repo: plugin moved to repo root (`devin-agent.yazi/`) for `ya pkg` compatibility.
- Root `scripts` is now a symlink for backward compatibility with `bin/yagent`.
- All error messages are more human-friendly.
- Comments throughout the codebase explain the "why", not just the "what".

## v0.2 — Real-Time Updates

### Added

- **Live badge updates via DDS.** Devin hooks push state changes directly to yazi using `ya pub-to`, so badges re-color instantly.
- **Nested-tmux attach awareness.** When yazi runs inside tmux, `a`/`N` use `switch-client` instead of `attach` to avoid nesting.
- **"Needs you" summon.** Terminal bell + toast notification + header counter when an agent first transitions to `needs-you`.
- **Live preview refresh.** The agent panel updates in real time when the hovered folder's agent changes state.
- **`g a` Agents Overview.** A key menu of all agents sorted by urgency; pick one to navigate to its folder.

## v0.1 — MVP

### Added

- Agent badges on folders (glyph + color-coded state).
- Agent preview panel on hover.
- `N` new agent, `a` attach, `s` send, `K` kill, `r` refresh.
- Hook-driven status model (working, needs-you, idle, done, error).
- Isolated yazi profile via `bin/yagent`.
