# yagent

**An agent-aware file manager.** `yagent` turns [yazi](https://yazi-rs.github.io/) into a
control panel for [Devin CLI](https://docs.devin.ai/) local agents: browse your code like
always, but now any folder can have live agents *attached* to it — and you can see at a glance
which are working, which are done, and which need you.

> Status: early development (v0.1 / MVP in progress).

## Why

When you run several local Devin agents, the hard part isn't starting them — it's *knowing
what they're doing without babysitting them*. `yagent` makes agents a first-class, ambient
layer over the file tree you already navigate, so you can fire-and-forget and get pulled back
exactly when an agent needs you.

## Mental model: agents are *attachments*

A folder is the unit. An agent is something **attached** to a folder — like a git status or a
file size. A folder can have **0, 1, or many** agents attached. You never leave the
file-browsing mental model; agents are a second navigable layer over the same tree.

- **Folder axis** (`j`/`k`): normal browsing. Folders with agents get a colored glyph + a `⚑`
  count badge.
- **Agent axis** (`Tab`): the preview column becomes the agent panel; `j`/`k` moves through the
  agents attached to the hovered folder.
- `Enter` always opens the folder (unchanged). Agents are reached via the parallel gesture.

## The signature flow

```
1. Browsing ~/code/myapp, you hover src/auth/
2. Realize it needs work -> press N ("new agent here")
3. Type the task in the prompt overlay
4. yagent launches devin in that folder (its own tmux session) and drops
   you into the live REPL. Detach -> back in yazi instantly.
5. src/auth/ now carries a colored agent badge. Keep browsing.
6. Badge turns GREEN ("needs you") -> press a to jump back into its REPL.
```

## Status model

Five states, optimized for one question — *"does this need me?"*

| State           | Color       | Meaning                                   | Your move          |
|-----------------|-------------|-------------------------------------------|--------------------|
| **Working**     | cyan        | Thinking / building, making progress      | ignore, keep going |
| **Needs you**   | bold green  | Finished a turn, or asking permission     | **jump in**        |
| **Idle**        | dim         | Spinning up, nothing yet                  | wait               |
| **Done**        | gray        | Session ended / detached & complete       | review or clear    |
| **Error**       | red         | Crashed / failed                          | investigate        |

"Needs you" is the hero state — it drives the terminal bell, the header counter, and sort
priority in the Agents Overview.

## Keymap

| Key   | Action                                                            |
|-------|-------------------------------------------------------------------|
| `N`   | New agent on hovered folder -> task prompt -> launch + attach     |
| `a`   | Attach to the agent on the hovered folder (resume its REPL)       |
| `s`   | Send a one-off prompt to a running agent                          |
| `K`   | Kill agent (confirm)                                              |
| `r`   | Refresh agent state                                               |
| `Enter` | Open folder (unchanged)                                         |
| `Tab` | Enter / leave the agent axis — *v0.2*                             |
| `g a` | Agents Overview (sorted by "needs you") — *v0.2*                  |
| `I`   | New **isolated** agent (shadow worktree + sandbox) — *v0.3*       |

## How it works

```
Devin lifecycle hooks (global)  --write-->  state files
                                            ~/.local/state/yagent/<dirhash>.json
scripts/agent.sh  --tmux session per agent-->  lock  .yagent/owner.json (per folder)
                                            |
yazi plugin reads: state file + lock + `tmux has-session` + `git -C` info
   - file list -> glyph + badge        (ambient layer)
   - preview   -> agent panel          (agent axis)
   - header    -> "needs you" counter + bell
```

- **Default mode:** agents run *in-place* on the hovered folder.
- **Isolated mode (opt-in):** a hidden git worktree + `devin --sandbox`, still presented as
  attached to the original folder.
- **Backend:** one tmux session per agent; attach = drop into its REPL.
- **Status:** Devin lifecycle hooks report state; tmux liveness is the authority for "running".

## Requirements

- [yazi](https://yazi-rs.github.io/) (with the BETA plugin/entity API)
- [Devin CLI](https://docs.devin.ai/) (`devin`)
- `tmux`
- `git`

## Install

```sh
./install.sh                      # installs Devin lifecycle hooks (with backup)
export PATH="$PWD/bin:$PATH"       # put the launcher on your PATH
yagent ~/code/your-repo            # open it on a repo
```

`install.sh` installs the Devin lifecycle hooks into your user-level Devin config (backing it
up first, and never clobbering existing hooks). The yazi side needs no install step: `bin/yagent`
launches yazi with an **isolated** `YAZI_CONFIG_HOME` that wires in the plugin automatically, so
your normal yazi config is untouched.

## Layout

```
.
├── install.sh                   # install Devin lifecycle hooks (with backup)
├── bin/yagent                   # launch yazi with an isolated config, rooted at a repo
├── hooks/
│   ├── devin-status-hook.sh     # one dispatcher for all lifecycle events
│   └── hooks.json
├── plugins/devin-agent.yazi/
│   ├── main.lua                 # fetcher + linemode badge + previewer + actions
│   └── README.md
├── config/                      # isolated yazi profile launched by bin/yagent
│   ├── yazi.toml                #   registers the fetcher + previewer
│   ├── keymap.toml              #   N / a / s / K / r bindings
│   ├── init.lua                 #   require("devin-agent"):setup()
│   └── theme.toml               #   color reference (states)
└── scripts/
    ├── agents.sh                # query status: list | get  (read-only)
    ├── agent.sh                 # manage an agent: start / attach / send / kill (tmux + devin)
    ├── worktree.sh              # isolated-mode shadow worktrees (v0.3)
    └── statedir.sh              # dir -> state-file path helper
```

## Roadmap

- **v0.1 (MVP):** in-place agent on hovered folder, glyphs + badges, agent panel, attach/kill,
  hook-driven status, "needs you" bell.
- **v0.2:** `Tab` agent-axis focus, `g a` Agents Overview, `s` send prompt.
- **v0.3:** isolated mode (shadow worktrees), multiple agents per folder, `--sandbox`,
  conflict hints.
- **v0.4:** packaging, themeable colors, desktop notifications, docs.

## License

MIT — see [LICENSE](LICENSE).
