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
local function scripts_dir()
	return os.getenv("YAGENT_SCRIPTS")
end

-- Run a yagent shell script and return its stdout (or "" on failure).
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
	if not scripts_dir() then
		ya.notify({ title = "yagent", content = "YAGENT_SCRIPTS is not set; launch via `yagent`.", level = "error", timeout = 4 })
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
		local agent = scripts_dir() .. "/agent.sh"
		local cmd = string.format(
			"bash %s start %s %s && bash %s attach %s",
			ya.quote(agent), ya.quote(dir), ya.quote(value), ya.quote(agent), ya.quote(dir)
		)
		ya.emit("shell", { cmd, block = true })
		self:refresh()

	elseif action == "attach" then
		if not dir then
			return
		end
		local row = parse_row((run("agents.sh", { "get", dir }):gsub("[\r\n]+$", "")))
		if not row or row.running ~= "yes" then
			return ya.notify({ title = "yagent", content = "No running agent on this folder.", timeout = 3 })
		end
		ya.emit("shell", { string.format("bash %s attach %s", ya.quote(scripts_dir() .. "/agent.sh"), ya.quote(dir)), block = true })
		self:refresh()

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

	elseif action == "refresh" then
		self:refresh()
	else
		ya.notify({ title = "yagent", content = "unknown action: " .. tostring(action), timeout = 3 })
	end
end

-- Re-read the agent map and trigger a re-render.
function M:refresh()
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
