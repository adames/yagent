--- @since 26.5.6
--- devin-agent.yazi — make yazi agent-aware.
---
--- One module wired up in three roles:
---   * fetcher    -> refreshes the agent state map for the current directory
---   * Linemode   -> renders a colored status glyph on folders that have agents
---   * previewer  -> renders the agent panel for the hovered folder
---   * functional -> action handlers (new / attach / send / kill / refresh)
---
--- Heavy logic lives in the (tested) shell scripts under $YAGENT_SCRIPTS:
---   agents.sh  -> read agent status      (list | get)
---   agent.sh   -> manage an agent        (start | attach | send | kill)

local M = {}

-- ── state colors / glyphs ──────────────────────────────────────────────────
-- "needs-you" is the hero state: bold green, the only one that demands action.
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

-- Find the directory containing yagent shell scripts.
-- Order: explicit env var -> plugin-relative -> global install.
local function scripts_dir()
	local explicit = os.getenv("YAGENT_SCRIPTS")
	if explicit then
		return explicit
	end

	-- Try to derive the plugin directory from this file's source path.
	-- yazi loads plugins from ~/.config/yazi/plugins/<name>.yazi/main.lua
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

	-- Global install location (set up by install.sh).
	local home = os.getenv("HOME") or ""
	local global = home .. "/.local/share/yagent/scripts"
	local probe = Command("bash"):arg("-c"):arg("test -f '" .. global .. "/agents.sh' && echo ok")
	local out = probe:output()
	if out and out.stdout:match("ok") then
		return global
	end

	return nil
end

-- Run a yagent shell script and return its stdout (or "" on failure).
-- Notifies the user if the script directory cannot be found.
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

-- Parse one TSV row from agents.sh -> { dir, state, action, running, title }.
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
local set_agents = ya.sync(function(st, agents)
	st.agents = agents
	ui.render()
end)

-- read state from inside the sync Linemode closure
local st_agents = ya.sync(function(st)
	return st.agents
end)

-- Count how many agents currently need the user.
local function count_needs(agents)
	local n = 0
	for _, a in pairs(agents or {}) do
		if a.state == "needs-you" then
			n = n + 1
		end
	end
	return n
end

-- Merge a single live update (from a DDS push) into the agent map. Re-renders
-- the badge, refreshes the preview if this folder is hovered, and "summons" the
-- user (toast + bell) when an agent first transitions into needs-you.
local apply_update = ya.sync(function(st, row)
	st.agents = st.agents or {}
	local prev = st.agents[row.dir]
	local was_needs = prev and prev.state == "needs-you"
	st.agents[row.dir] = row
	ui.render()

	-- Live preview refresh: re-peek if we're hovering this folder right now.
	local h = cx.active.current.hovered
	if h and tostring(h.url) == row.dir then
		ya.emit("peek", { cx.active.preview.skip, only_if = h.url, force = true })
	end

	-- Summon on a fresh needs-you.
	if row.state == "needs-you" and not was_needs then
		local what = (row.title ~= nil and row.title ~= "") and row.title or row.dir
		ya.notify({ title = "yagent — needs you", content = what, timeout = 5 })
		-- Best-effort audible bell; orphan = fire-and-forget, no screen takeover.
		ya.emit("shell", { "printf '\\a' > /dev/tty 2>/dev/null", orphan = true })
	end
end)

local function in_tmux()
	return os.getenv("TMUX") ~= nil and os.getenv("TMUX") ~= ""
end

-- ── fetcher: refresh the agent map for the directory being loaded ───────────
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

-- ── setup (sync): register the per-row status glyph ─────────────────────────
function M:setup(opts)
	opts = opts or {}
	local order = opts.order or 1500

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

	-- Live updates: Devin hooks push the new state here via `ya pub-to`, so the
	-- badge re-colors instantly. The body carries everything we need, keeping
	-- this sync callback cheap (no shelling out).
	ps.sub_remote("yagent-update", function(body)
		if type(body) ~= "string" then
			return
		end
		-- Body is tab-separated: workdir \t state \t action \t title
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
			-- A hook only fires while the process is alive; "done" means it ended.
			running = (f[2] == "done") and "no" or "yes",
		})
	end)

	-- Header counter: an always-visible "N needs you" chip on the right of the
	-- top bar, so the summon is felt even when you're deep in another folder.
	Header:children_add(function()
		local n = count_needs(st_agents())
		if n == 0 then
			return ""
		end
		return ui.Line({ ui.Span(" ◆ " .. n .. " needs you "):fg("green"):bold() })
	end, 9000, Header.RIGHT)
end

-- ── previewer: the agent panel (or a plain dir listing as fallback) ─────────
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
			content = "Scripts not found. Install via `./install.sh` or launch via `yagent`.",
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
			return ya.notify({ title = "yagent", content = "Only done / dead / error agents can be cleared.", timeout = 3 })
		end
		local yes = ya.confirm({
			title = "Clear agent?",
			content = "Remove the finished agent on:\n" .. dir,
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
