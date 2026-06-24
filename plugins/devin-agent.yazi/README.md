# devin-agent.yazi

The yazi plugin half of [yagent](../../README.md). It renders agent state over the file tree
and dispatches agent actions to `scripts/agent.sh`.

- `main.lua` — plugin entry: glyphs/badges, agent-panel previewer, action handlers.
- `status.lua` — reads a folder's agent state (tmux liveness + hook state file + lock).

Installed (symlinked) into `~/.config/yazi/plugins/devin-agent.yazi` by the top-level
`install.sh`.
