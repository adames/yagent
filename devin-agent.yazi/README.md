# devin-agent.yazi

A [yazi](https://yazi-rs.github.io/) plugin that turns your file manager into a control panel for
[Devin CLI](https://docs.devin.ai/) agents.

It renders a small colored glyph next to any folder that has an active agent,
shows an agent detail panel when you hover that folder, and lets you spawn,
attach to, send commands to, or kill agents without leaving yazi.

## What it does

- **Ambient awareness** — as you browse, folders with agents get a colored badge:
  - `●` cyan = working, `◆` green = needs you, `○` dim = idle, `✓` gray = done, `✕` red = error
- **Live updates** — Devin hooks push state changes over DDS, so badges re-color instantly
- **Agent panel** — hover a folder with an agent to see its state, current action, and task
- **Header counter** — always-visible "N needs you" chip so you never miss an agent waiting for input
- **Actions** — `N` new, `a` attach, `s` send, `K` kill, `c` clear, `r` refresh, `g a` overview

## Install

### Via `ya pkg` (recommended for existing yazi users)

```sh
ya pkg add adames-cognition/yagent:devin-agent
```

Then wire it into your `~/.config/yazi/init.lua`, `keymap.toml`, and `yazi.toml`
(see the [main README](../../README.md) for full snippets).

You also need to run `./install.sh` once to set up the Devin lifecycle hooks.

### Via the isolated launcher

```sh
./install.sh
export PATH="$PWD/bin:$PATH"
yagent ~/code/your-repo
```

This launches yazi in an isolated profile that already has the plugin wired in.

## Self-contained

The shell scripts (`agents.sh`, `agent.sh`, etc.) live in `scripts/` inside this
directory. The plugin discovers them automatically, or respects `$YAGENT_SCRIPTS`
if you want to override the location.
