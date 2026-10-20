# devin-agent.yazi

The [yazi](https://yazi-rs.github.io/) plugin behind [yagent](../README.md). It shows a status
glyph next to any folder with a [Devin CLI](https://docs.devin.ai/) agent attached, opens an
agent panel when you hover that folder, and lets you start, attach to, message, or kill agents
without leaving yazi.

Glyphs: `●` working · `◆` needs you · `○` idle · `✓` done · `·` dead · `✕` error

Keys: `N` new · `a` attach · `s` send · `K` kill · `c` clear · `r` refresh · `g a` overview

## Install

Into your own yazi:

```sh
ya pkg add adames/yagent:devin-agent
```

Then wire it into `init.lua`, `yazi.toml`, and `keymap.toml` as shown in the
[main README](../README.md#use-it-inside-your-own-yazi). The Devin hooks are still needed for
status reporting: run `./install.sh` once from a clone of this repo.

Or use the isolated launcher, which comes with the plugin already wired in:

```sh
./install.sh
yagent ~/code/your-repo      # new shell first, or: source ~/.zshrc
```

## Scripts

The shell helpers (`agent.sh`, `agents.sh`, ...) live in `scripts/` here. The plugin looks for
them in `$YAGENT_SCRIPTS`, then next to this file, then `~/.local/share/yagent/scripts`.
