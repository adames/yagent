# devin-agent.yazi

The yazi plugin half of [yagent](../../README.md). It renders agent state over the file tree
and dispatches agent actions to the bundled shell scripts in `scripts/`.

`main.lua` wires the module up in four roles:
- **fetcher** — refreshes the agent state map as directories load (runs `agents.sh list`).
- **Linemode** — renders a colored status glyph on folders that have agents.
- **previewer** — renders the agent panel for a hovered folder (falls back to a plain
  directory listing when there's no agent).
- **functional** — action handlers bound in `keymap.toml`: new / attach / send / kill / clear / refresh.

The plugin is self-contained: the shell scripts live in `scripts/` inside the plugin directory.
`main.lua` discovers them automatically, or respects `$YAGENT_SCRIPTS` if set externally.
