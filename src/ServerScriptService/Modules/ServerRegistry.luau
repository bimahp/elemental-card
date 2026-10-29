-- ServerRegistry: cross-server matchmaking HINT layer (PLAN_MATCHMAKING Phase 1).
-- Publishes this server's free-table count/population to a MemoryStoreSortedMap so
-- other servers can pick a likely destination for a matched pair.
--
-- This is a HINT ONLY. Per IDEA_MATCHMAKING.md's locked rule ("Queue = truth,
-- destination server = truth, registry = hint"), the destination server always
-- re-validates real table state at arrival time -- never trust this data alone.

local MemoryStoreService = game:GetService("MemoryStoreService")
local Players            = game:GetService("Players")

local ServerRegistry = {}

local REGISTRY_MAP_NAME = "MM_ServerRegistry"
local PUBLISH_INTERVAL  = 10  -- seconds between heartbeats
local ENTRY_TTL         = 30  -- seconds; a dead/stalled server's entry self-expires

local sortedMap = MemoryStoreService:GetSortedMap(REGISTRY_MAP_NAME)

local countFreeFn -- injected via ServerRegistry.init to avoid a require cycle with TableManager
local started = false
local warnedEmptyJobId = false

-- Writes this server's current {JobId, FreeTables, Players, UpdatedAt} entry.
-- Sort key = FreeTables, so getCandidates() can read back highest-room-first.
--
-- game.JobId is an EMPTY STRING in (non-published) Studio Play/Local Server --
-- confirmed directly, not assumed -- only a real published server gets a real
-- GUID. MemoryStoreSortedMap:SetAsync requires a non-empty key, so publishing
-- would otherwise fail (and spam) every heartbeat during any Studio Play test.
-- Skip with a single one-time warning instead of repeating the failure.
function ServerRegistry.publish()
	if game.JobId == "" then
		if not warnedEmptyJobId then
			warn("[ServerRegistry] game.JobId is empty (Studio Play/Local Server, not a published server) -- skipping publish. Cross-server destination selection is a no-op here by design; see PLAN_MATCHMAKING.md's Testing Constraint section.")
			warnedEmptyJobId = true
		end
		return
	end
	local freeTables = countFreeFn and countFreeFn() or 0
	local ok, err = pcall(function()
		sortedMap:SetAsync(game.JobId, {
			JobId       = game.JobId,
			FreeTables  = freeTables,
			Players     = #Players:GetPlayers(),
			UpdatedAt   = os.time(),
		}, ENTRY_TTL, freeTables)
	end)
	if not ok then
		warn("[ServerRegistry] publish failed: " .. tostring(err))
	end
end

-- Returns up to `count` server entries, most-free-tables first. HINT ONLY --
-- callers must re-validate real table state before relying on this.
function ServerRegistry.getCandidates(count)
	count = count or 20
	local ok, items = pcall(function()
		return sortedMap:GetRangeAsync(Enum.SortDirection.Descending, count)
	end)
	if not ok then
		warn("[ServerRegistry] getCandidates failed: " .. tostring(items))
		return {}
	end
	local out = {}
	for _, item in ipairs(items) do
		if type(item.value) == "table" then
			out[#out + 1] = item.value
		end
	end
	return out
end

-- Starts the periodic heartbeat loop. `getFreeTableCount` is injected (not
-- required directly) so this module has no hard dependency on TableManager.
function ServerRegistry.init(getFreeTableCount)
	if started then return end
	started = true
	countFreeFn = getFreeTableCount
	task.spawn(function()
		while true do
			ServerRegistry.publish()
			task.wait(PUBLISH_INTERVAL)
		end
	end)
end

return ServerRegistry
