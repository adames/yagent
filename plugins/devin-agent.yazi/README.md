# devin-agent.yazi

The yazi plugin half of [yagent](../../README.md). It renders agent state over the file tree
and dispatches agent actions to the shell scripts under `$YAGENT_SCRIPTS`.

`main.lua` wires the module up in four roles:
- **fetcher** — refreshes the agent state map as directories load (runs `agents.sh list`).
- **Linemode** — renders a colored status glyph on folders that have agents.
- **previewer** — renders the agent panel for a hovered folder (falls back to a plain
  directory listing when there's no agent).
- **functional** — action handlers bound in `keymap.toml`: new / attach / send / kill / refresh.

It's loaded automatically by the isolated yazi profile that `bin/yagent` launches; the plugin
finds its shell helpers via the `YAGENT_SCRIPTS` environment variable.
