--- @since 25.2.13
--- status.lua — read a folder's agent state for the yagent plugin.
---
--- Sources, in priority order:
---   1. tmux liveness  -> is an agent actually running? (authority for "running")
---   2. state file      -> what is it doing? (written by Devin lifecycle hooks)
---   3. lock file       -> task title / session name
---
--- Returns a table: { state, action, title, session, ts } or nil if no agent.

local M = {}

-- Map the raw hook state to a yagent display state.
-- States: working | needs-you | idle | done | error | none
local STATES = {
	["working"] = "working",
	["needs-you"] = "needs-you",
	["idle"] = "idle",
	["done"] = "done",
	["error"] = "error",
}

local function state_root()
	local xdg = os.getenv("XDG_STATE_HOME")
	local home = os.getenv("HOME") or ""
	return (xdg and xdg .. "/yagent") or (home .. "/.local/state/yagent")
end

-- Tiny FNV-1a-ish hash is NOT compatible with sha256 used by the shell side,
-- so the plugin instead resolves the state file by reading the workdir field.
-- For correctness we shell out to the shared statedir.sh helper (cached).
local function state_file_for(dir)
	-- Resolved lazily by the caller via ya.sync/Command; placeholder for now.
	return nil
end

--- Read the lock file at <dir>/.yagent/owner.json, returning {title, session}.
function M.read_lock(dir)
	-- TODO(v0.1): parse owner.json; return nil when absent.
	return nil
end

--- Return the agent status for `dir`, or nil if no agent is attached.
function M.for_dir(dir)
	-- TODO(v0.1): combine tmux liveness + state file + lock.
	-- Wired up in milestone 4 once the hook pipeline is validated.
	return nil
end

--- The color used to render a given state.
function M.color(state)
	if state == "working" then return "cyan" end
	if state == "needs-you" then return "green" end
	if state == "idle" then return "darkgray" end
	if state == "done" then return "gray" end
	if state == "error" then return "red" end
	return nil
end

--- The glyph used to render a given state.
function M.glyph(state)
	if state == "needs-you" then return "" end -- bold marker, themed in main.lua
	if state == "error" then return "" end
	return "" -- generic active dot for working/idle/done
end

M.STATES = STATES
M.state_root = state_root
return M
