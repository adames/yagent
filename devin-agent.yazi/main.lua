--- @since 26.5.6
--- devin-agent.yazi — make yazi agent-aware.
---
--- This plugin turns yazi into a control panel for Devin CLI agents.
--- It wears four hats:
---   * fetcher    -> loads the agent state map as you browse directories
---   * Linemode   -> draws a colored status glyph next to folders that have agents
---   * previewer  -> shows an agent detail panel when you hover a folder
---   * functional -> handles keybindings: new, attach, send, kill, clear, refresh
---
--- The heavy lifting is done by shell scripts in the plugin's scripts/ directory:
---   agents.sh  -> list agents, check if one is running, clean up stale locks
---   agent.sh   -> start, attach, send commands to, or kill an agent

local M = {}

-- ── how each state looks ────────────────────────────────────────────────────
-- needs-you is the "hero" state: bold green, because it's the only one that
-- demands your immediate attention.
local STYLES = {
	["working"]   = ui.Style():fg("cyan"),
	["needs-you"] = ui.Style():fg("green"):bold(),
	["idle"]      = ui.Style():fg("darkgray"),
	["done"]      = ui.Style():fg("gray"),
	["dead"]      = ui.Style():fg("darkgray"),
	["error"]     = ui.Style():fg("red"),
}
local GLYPHS = {
	["working"]   = "●",
	["needs-you"] = "◆",
	["idle"]      = "○",
	["done"]      = "✓",
	["dead"]      = "·",
	["error"]     = "✕",
}

-- ── helpers ────────────────────────────────────────────────────────────────

-- Figure out where the yagent shell scripts live.  We try three places:
--   1. $YAGENT_SCRIPTS (set by the yagent launcher)
--   2. Next to this Lua file (when installed via ya pkg)
--   3. ~/.local/share/yagent/scripts (global install from install.sh)
local function scripts_dir()
	local explicit = os.getenv("YAGENT_SCRIPTS")
	if explicit then
		return explicit
	end

	-- When installed via `ya pkg`, the scripts/ folder sits right next to main.lua.
	-- We can sniff our own source path to find it.
	local info = debug.getinfo(1, "S")
	if info and info.source then
		local src = info.source
		if src:sub(1, 1) == "@" then
			local path = src:sub(2)
			local dir = path:match("(.*/)")
			if dir then
				local candidate = dir .. "scripts"
				local probe = Command("bash"):arg("-c"):arg("test -f '" .. candidate .. "/agents.sh' && echo ok")
				local out = probe:output()
				if out and out.stdout:match("ok") then
					return candidate
				end
			end
		end
	end

	-- Fallback: the global install path used by install.sh.
	local home = os.getenv("HOME") or ""
	local global = home .. "/.local/share/yagent/scripts"
	local probe = Command("bash"):arg("-c"):arg("test -f '" .. global .. "/agents.sh' && echo ok")
	local out = probe:output()
	if out and out.stdout:match("ok") then
		return global
	end

	return nil
end

-- Run a shell script from the yagent scripts directory.
-- Returns stdout as a string, or "" if something went wrong.
local function run(script, args)
	local dir = scripts_dir()
	if not dir then
		return ""
	end
	local cmd = Command("bash"):arg(dir .. "/" .. script)
	for _, a in ipairs(args or {}) do
		cmd = cmd:arg(a)
	end
	local out = cmd:output()
	return out and out.stdout or ""
end

-- Parse a single tab-separated line from agents.sh into a friendly table.
local function parse_row(line)
	local f = {}
	for field in (line .. "\t"):gmatch("(.-)\t") do
		f[#f + 1] = field
	end
	if not f[1] or f[1] == "" then
		return nil
	end
	return { dir = f[1], state = f[2], action = f[3], running = f[4], title = f[5] }
end

-- ── shared state (sync context) ─────────────────────────────────────────────
-- yazi's sync context is where UI updates happen.  We stash the agent map there
-- so Linemode, Header, and preview can all read from the same truth.

local set_agents = ya.sync(function(st, agents)
	st.agents = agents
	ui.render()
end)

-- Peek at the agent map from inside a sync UI callback (e.g. Linemode).
local st_agents = ya.sync(function(st)
	return st.agents
end)

-- How many agents are waiting for the user right now?
local function count_needs(agents)
	local n = 0
	for _, a in pairs(agents or {}) do
		if a.state == "needs-you" then
			n = n + 1
		end
	end
	return n
end

-- Apply a live state update pushed by a Devin hook over DDS.
-- This re-colors the badge, refreshes the preview panel if we're hovering
-- this folder, and rings the bell when an agent first says "needs-you".
local apply_update = ya.sync(function(st, row)
	st.agents = st.agents or {}
	local prev = st.agents[row.dir]
	local was_needs = prev and prev.state == "needs-you"
	st.agents[row.dir] = row
	ui.render()

	-- If this folder is currently hovered, force the preview panel to redraw.
	local h = cx.active.current.hovered
	if h and tostring(h.url) == row.dir then
		ya.emit("peek", { cx.active.preview.skip, only_if = h.url, force = true })
	end

	-- Summon: toast + bell when an agent first transitions to "needs-you".
	if row.state == "needs-you" and not was_needs then
		local what = (row.title ~= nil and row.title ~= "") and row.title or row.dir
		ya.notify({ title = "yagent — needs you", content = what, timeout = 5 })
		-- Orphan shell = fire-and-forget, won't steal the screen.
		ya.emit("shell", { "printf '\\a' > /dev/tty 2>/dev/null", orphan = true })
	end
end)

-- Are we already inside a tmux session?
local function in_tmux()
	return os.getenv("TMUX") ~= nil and os.getenv("TMUX") ~= ""
end

-- ── fetcher: load agent states when yazi opens a directory ──────────────────
function M:fetch(job)
	local agents = {}
	for line in run("agents.sh", { "list" }):gmatch("[^\r\n]+") do
		local row = parse_row(line)
		if row then
			agents[row.dir] = row
		end
	end
	set_agents(agents)
	return false
end

-- ── setup (sync): wire up the UI pieces ────────────────────────────────────
function M:setup(opts)
	opts = opts or {}
	local order = opts.order or 1500

	-- Draw a small colored glyph next to any folder that has an agent attached.
	Linemode:children_add(function(self)
		local file = self._file
		if not file.cha.is_dir or not file.in_current then
			return ""
		end
		local agent = (st_agents() or {})[tostring(file.url)]
		if not agent then
			return ""
		end
		local glyph = GLYPHS[agent.state] or "●"
		local style = STYLES[agent.state] or ui.Style()
		return ui.Line({ " ", ui.Span(glyph):style(style) })
	end, order)

	-- Subscribe to live pushes from Devin hooks (via DDS).
	-- When an agent's state changes, the hook calls `ya pub-to` and we get the
	-- new state here instantly — no need to reload the directory or press `r`.
	ps.sub_remote("yagent-update", function(body)
		if type(body) ~= "string" then
			return
		end
		-- Format: workdir \t state \t action \t title
		local f = {}
		for field in (body .. "\t"):gmatch("(.-)\t") do
			f[#f + 1] = field
		end
		if not f[1] or f[1] == "" then
			return
		end
		apply_update({
			dir = f[1],
			state = f[2],
			action = f[3],
			title = f[4] or "",
			-- "done" means the session ended, so the process is no longer running.
			running = (f[2] == "done") and "no" or "yes",
		})
	end)

	-- Always-visible "N needs you" chip in the top-right corner.
	-- Even when you're deep in another folder, you'll know an agent is waiting.
	Header:children_add(function()
		local n = count_needs(st_agents())
		if n == 0 then
			return ""
		end
		return ui.Line({ ui.Span(" ◆ " .. n .. " needs you "):fg("green"):bold() })
	end, 9000, Header.RIGHT)
end

-- ── previewer: show agent details (or a plain directory listing) ────────────
function M:peek(job)
	local dir = tostring(job.file.url)
	local row = parse_row((run("agents.sh", { "get", dir }):gsub("[\r\n]+$", "")))

	if row then
		return self:peek_agent(job, row)
	end
	return self:peek_dir(job)
end

function M:peek_agent(job, row)
	local glyph = GLYPHS[row.state] or "●"
	local style = STYLES[row.state] or ui.Style()
	local action = (row.action ~= nil and row.action ~= "") and (" — " .. row.action) or ""
	local running = row.running == "yes" and "running" or "stopped"

	local lines = {
		ui.Line("Agent"):bold(),
		ui.Line("─────────────────────────"),
		ui.Line({ ui.Span(" state  "):fg("darkgray"), ui.Span(glyph .. " " .. row.state):style(style), ui.Span(action):fg("gray") }),
		ui.Line({ ui.Span(" proc   "):fg("darkgray"), ui.Span(running) }),
		ui.Line({ ui.Span(" task   "):fg("darkgray"), ui.Span(row.title ~= "" and row.title or "(none)") }),
		ui.Line(""),
		ui.Line({ ui.Span(" a"):fg("green"), ui.Span(" attach   "), ui.Span("s"):fg("green"), ui.Span(" send   "), ui.Span("K"):fg("red"), ui.Span(" kill") }),
	}
	ya.preview_widget(job, ui.Text(lines):area(job.area))
end

function M:peek_dir(job)
	local files, err = fs.read_dir(job.file.url, {})
	if not files then
		return ya.preview_widget(job, ui.Text("Cannot read directory"):area(job.area))
	end
	table.sort(files, function(a, b)
		local ad, bd = a.cha.is_dir, b.cha.is_dir
		if ad ~= bd then
			return ad
		end
		return (a.name or "") < (b.name or "")
	end)

	local lines = {}
	for i = job.skip + 1, math.min(#files, job.skip + job.area.h) do
		local f = files[i]
		local name = f.name or ""
		if f.cha.is_dir then
			lines[#lines + 1] = ui.Line(ui.Span(name .. "/"):fg("blue"))
		else
			lines[#lines + 1] = ui.Line(name)
		end
	end
	ya.preview_widget(job, ui.Text(lines):area(job.area))
end

function M:seek(job)
	local h = cx.active.current.hovered
	if h and h.url == job.file.url then
		ya.emit("peek", {
			math.max(0, cx.active.preview.skip + job.units),
			only_if = job.file.url,
		})
	end
end

-- ── functional entry: actions bound in keymap.toml ──────────────────────────
local hovered_dir = ya.sync(function()
	local h = cx.active.current.hovered
	return h and h.cha.is_dir and tostring(h.url) or nil
end)

local function need_scripts()
	local dir = scripts_dir()
	if not dir then
		ya.notify({
			title = "yagent",
			content = "Can't find yagent scripts. Run ./install.sh or launch with the yagent command.",
			level = "error",
			timeout = 6,
		})
		return false
	end
	return true
end

function M:entry(job)
	if not need_scripts() then
		return
	end
	local action = job.args[1]
	local dir = hovered_dir()

	if action == "new" then
		if not dir then
			return ya.notify({ title = "yagent", content = "Hover a folder first.", timeout = 3 })
		end
		local value, ev = ya.input({
			title = "Task for agent in " .. dir:match("[^/]+$") .. ":",
			pos = { "top-center", y = 3, w = 60 },
		})
		if ev ~= 1 or not value or value == "" then
			return
		end
		if in_tmux() then
			-- yazi runs inside tmux: start detached, then switch the client to
			-- the agent session (attaching would nest and be refused).
			run("agent.sh", { "start", dir, value })
			run("agent.sh", { "switch", dir })
		else
			local agent = scripts_dir() .. "/agent.sh"
			local cmd = string.format(
				"bash %s start %s %s && bash %s attach %s",
				ya.quote(agent), ya.quote(dir), ya.quote(value), ya.quote(agent), ya.quote(dir)
			)
			ya.emit("shell", { cmd, block = true })
			self:refresh()
		end

	elseif action == "attach" then
		if not dir then
			return
		end
		local row = parse_row((run("agents.sh", { "get", dir }):gsub("[\r\n]+$", "")))
		if not row or row.running ~= "yes" then
			return ya.notify({ title = "yagent", content = "No running agent on this folder.", timeout = 3 })
		end
		if in_tmux() then
			run("agent.sh", { "switch", dir })
		else
			ya.emit("shell", { string.format("bash %s attach %s", ya.quote(scripts_dir() .. "/agent.sh"), ya.quote(dir)), block = true })
			self:refresh()
		end

	elseif action == "send" then
		if not dir then
			return
		end
		local value, ev = ya.input({ title = "Send to agent:", pos = { "top-center", y = 3, w = 60 } })
		if ev ~= 1 or not value or value == "" then
			return
		end
		run("agent.sh", { "send", dir, value })

	elseif action == "kill" then
		if not dir then
			return
		end
		local yes = ya.confirm({
			title = "Kill agent?",
			content = "This stops the agent running on:\n" .. dir,
			pos = { "center", w = 60, h = 10 },
		})
		if yes then
			run("agent.sh", { "kill", dir })
			self:refresh()
		end

	elseif action == "clear" then
		if not dir then
			return
		end
		local row = parse_row((run("agents.sh", { "get", dir }):gsub("[\r\n]+$", "")))
		if not row or (row.state ~= "done" and row.state ~= "dead" and row.state ~= "error") then
			return ya.notify({ title = "yagent", content = "You can only clear finished agents (done, dead, or error).", timeout = 3 })
		end
		local yes = ya.confirm({
			title = "Clear this agent?",
			content = "This removes the finished agent from:\n" .. dir,
			pos = { "center", w = 60, h = 10 },
		})
		if yes then
			run("agent.sh", { "kill", dir })
			self:refresh()
		end

	elseif action == "overview" then
		self:overview()

	elseif action == "refresh" then
		self:refresh()
	else
		ya.notify({ title = "yagent", content = "unknown action: " .. tostring(action), timeout = 3 })
	end
end

-- Repo-wide overview: a key menu of all agents, sorted "needs you" first.
-- Picking one reveals (navigates to) its folder so you can act on it.
local OVERVIEW_RANK = { ["needs-you"] = 0, ["working"] = 1, ["idle"] = 2, ["error"] = 3, ["done"] = 4, ["dead"] = 5 }
local OVERVIEW_KEYS = "123456789abcdefghijklmnopqrstuvwxyz"

function M:overview()
	local rows = {}
	for line in run("agents.sh", { "list" }):gmatch("[^\r\n]+") do
		local r = parse_row(line)
		if r then
			rows[#rows + 1] = r
		end
	end
	if #rows == 0 then
		return ya.notify({ title = "yagent", content = "No agents running.", timeout = 3 })
	end
	table.sort(rows, function(a, b)
		return (OVERVIEW_RANK[a.state] or 9) < (OVERVIEW_RANK[b.state] or 9)
	end)

	local cands = {}
	for i, r in ipairs(rows) do
		if i > #OVERVIEW_KEYS then
			break
		end
		local name = r.dir:match("[^/]+$") or r.dir
		local task = (r.title ~= nil and r.title ~= "") and ("  " .. r.title) or ""
		cands[i] = {
			on = OVERVIEW_KEYS:sub(i, i),
			desc = string.format("%s %-10s %s%s", GLYPHS[r.state] or "●", r.state, name, task),
		}
	end

	local idx = ya.which({ cands = cands })
	if idx and rows[idx] then
		ya.emit("reveal", { rows[idx].dir })
	end
end

-- Re-read the agent map, prune stale entries, and trigger a re-render.
function M:refresh()
	run("agents.sh", { "prune" })
	local agents = {}
	for line in run("agents.sh", { "list" }):gmatch("[^\r\n]+") do
		local row = parse_row(line)
		if row then
			agents[row.dir] = row
		end
	end
	set_agents(agents)
end

return M
