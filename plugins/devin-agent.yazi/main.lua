--- @since 25.2.13
--- devin-agent.yazi — make yazi agent-aware.
---
--- Responsibilities (built incrementally across milestones):
---   * Linemode/entity glyphs + badges on folders that have agents      (ambient layer)
---   * A previewer that renders the agent panel for the hovered folder  (agent axis)
---   * Action handlers invoked from keymap.toml: new / attach / send / kill
---   * A header counter + bell when an agent enters the "needs-you" state
---
--- This file is the plugin entry point. The heavy lifting for reading agent
--- state lives in status.lua.

local M = {}

-- Resolve the directory of this plugin's scripts/ helpers at setup time.
function M:setup(opts)
	opts = opts or {}
	-- opts.scripts_dir: absolute path to yagent's scripts/ (set by install.sh
	-- via init.lua) so action handlers can shell out to agent.sh.
	self.scripts_dir = opts.scripts_dir
end

--- entry: dispatched by `plugin devin-agent -- <action> [args]` keybindings.
--- Actions: new | attach | send | kill | overview  (wired in milestones 6+).
function M:entry(job)
	local action = job.args[1]
	if action == "new" then
		-- TODO(v0.1): prompt for a task, shell out to agent.sh start, then attach.
		ya.notify({ title = "yagent", content = "new agent (todo)", timeout = 2 })
	elseif action == "attach" then
		-- TODO(v0.1): suspend yazi, run agent.sh attach <hovered dir>.
		ya.notify({ title = "yagent", content = "attach (todo)", timeout = 2 })
	elseif action == "kill" then
		ya.notify({ title = "yagent", content = "kill (todo)", timeout = 2 })
	elseif action == "send" then
		ya.notify({ title = "yagent", content = "send (todo)", timeout = 2 })
	elseif action == "overview" then
		ya.notify({ title = "yagent", content = "overview (todo)", timeout = 2 })
	else
		ya.notify({ title = "yagent", content = "unknown action: " .. tostring(action), timeout = 2 })
	end
end

return M
