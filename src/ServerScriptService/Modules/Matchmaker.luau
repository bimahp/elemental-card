-- Matchmaker: cross-server queue, match assignment, and teleport delivery.
-- MemoryStore schema v2 avoids global HashMap scans and tokenizes queue entries
-- so cancel/requeue operations cannot affect one another.

local MemoryStoreService = game:GetService("MemoryStoreService")
local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")

local ServerRegistry = require(script.Parent.ServerRegistry)
local TableManager = require(script.Parent.TableManager)

local Matchmaker = {}

local QUEUE_NAME = "MM_Queue_v2"
local QUEUE_STATE_MAP_NAME = "MM_QueueState_v2"
local PENDING_MATCH_MAP_NAME = "MM_PendingMatches_v2"

local ENTRY_EXPIRATION = 300
local INVISIBILITY_TIMEOUT = 30
local PENDING_TTL = 180
local TELEPORT_RETRY_DELAY = 5
local TELEPORT_CONFIRM_DELAY = 10

local queue = MemoryStoreService:GetQueue(QUEUE_NAME, INVISIBILITY_TIMEOUT)
local queueState = MemoryStoreService:GetHashMap(QUEUE_STATE_MAP_NAME)
local pendingMatches = MemoryStoreService:GetHashMap(PENDING_MATCH_MAP_NAME)

-- These tables contain only work owned by this server. Empty servers therefore
-- perform no queue reads and no per-player MemoryStore reads.
local localQueueEntries = {} -- [userId] = { player, entry }
local queueOperations = {} -- [userId] = true while enqueue/dequeue is yielding
local pendingInstructions = {} -- [userId] = { player, instruction }
local localMatchIds = {} -- [matchId] = local expiry timestamp
local teleportAttempts = {} -- [userId] = attempt record
local teleportRetryAt = {} -- [userId] = os.clock timestamp
local joinDataChecked = setmetatable({}, { __mode = "k" })

local function stateKey(userId)
	return tostring(userId)
end

local function queuedState(entry)
	return {
		token = entry.token,
		status = "queued",
		userId = entry.userId,
		jobId = entry.jobId,
		queuedAt = entry.queuedAt,
	}
end

local function sameEntry(state, entry)
	return type(state) == "table"
		and state.token == entry.token
		and state.userId == entry.userId
end

local function updateState(key, expiration, transform)
	local ok, result = pcall(function()
		return queueState:UpdateAsync(key, transform, expiration)
	end)
	if not ok then
		warn("[Matchmaker] queue-state update failed for " .. key .. ": " .. tostring(result))
		return nil, false
	end
	return result, true
end

local function cancelEntry(entry, reason)
	local updated, ok = updateState(stateKey(entry.userId), ENTRY_EXPIRATION, function(current)
		if sameEntry(current, entry) and current.status == "queued" then
			return {
				token = entry.token,
				status = "cancelled",
				userId = entry.userId,
				jobId = entry.jobId,
				queuedAt = entry.queuedAt,
				reason = reason,
			}
		end
		return current
	end)
	return ok and sameEntry(updated, entry) and updated.status == "cancelled"
end

local function claimEntry(entry, matchId, instruction)
	local updated, ok = updateState(stateKey(entry.userId), PENDING_TTL, function(current)
		if sameEntry(current, entry) and current.status == "queued" then
			return {
				token = entry.token,
				status = "matched",
				userId = entry.userId,
				jobId = entry.jobId,
				queuedAt = entry.queuedAt,
				matchId = matchId,
				instruction = instruction,
			}
		end
		if sameEntry(current, entry) and current.status == "matched" and current.matchId == matchId then
			return current
		end
		return current
	end)
	return ok
		and sameEntry(updated, entry)
		and updated.status == "matched"
		and updated.matchId == matchId
end

local function rollbackClaim(entry, matchId)
	updateState(stateKey(entry.userId), ENTRY_EXPIRATION, function(current)
		if sameEntry(current, entry) and current.status == "matched" and current.matchId == matchId then
			return queuedState(entry)
		end
		return current
	end)
end

local function completeState(userId, matchId)
	updateState(stateKey(userId), PENDING_TTL, function(current)
		if type(current) == "table" and current.status == "matched" and current.matchId == matchId then
			return {
				token = current.token,
				status = "completed",
				userId = current.userId,
				jobId = current.jobId,
				queuedAt = current.queuedAt,
				matchId = matchId,
			}
		end
		return current
	end)
end

local function trackLocalMatch(matchId)
	if type(matchId) == "string" and matchId ~= "" then
		localMatchIds[matchId] = os.time() + PENDING_TTL
	end
end

function Matchmaker.enqueue(player)
	local userId = player.UserId
	if localQueueEntries[userId] or queueOperations[userId] then
		return false, "already_queued"
	end

	queueOperations[userId] = true
	local entry = {
		userId = userId,
		jobId = game.JobId,
		queuedAt = os.time(),
		token = HttpService:GenerateGUID(false),
	}

	local stateOk, stateErr = pcall(function()
		queueState:SetAsync(stateKey(userId), queuedState(entry), ENTRY_EXPIRATION)
	end)
	if not stateOk then
		queueOperations[userId] = nil
		warn("[Matchmaker] enqueue state write failed for " .. player.Name .. ": " .. tostring(stateErr))
		return false, "memory_store"
	end

	local queueOk, queueErr = pcall(function()
		queue:AddAsync(entry, ENTRY_EXPIRATION)
	end)
	if not queueOk then
		cancelEntry(entry, "enqueue_failed")
		queueOperations[userId] = nil
		warn("[Matchmaker] enqueue failed for " .. player.Name .. ": " .. tostring(queueErr))
		return false, "memory_store"
	end

	localQueueEntries[userId] = { player = player, entry = entry }
	queueOperations[userId] = nil
	return true
end

function Matchmaker.isQueued(player)
	return localQueueEntries[player.UserId] ~= nil
end

function Matchmaker.hasLocalQueuedPlayers()
	return next(localQueueEntries) ~= nil
end

function Matchmaker.dequeue(player)
	local userId = player.UserId
	local localEntry = localQueueEntries[userId]
	if not localEntry then
		return false, "not_queued"
	end
	if queueOperations[userId] then
		return false, "busy"
	end

	queueOperations[userId] = true
	local cancelled = cancelEntry(localEntry.entry, "player_cancelled")
	if cancelled then
		localQueueEntries[userId] = nil
	end
	queueOperations[userId] = nil
	return cancelled, cancelled and nil or "already_matched"
end

local function validateEntry(entry)
	if type(entry) ~= "table"
		or type(entry.userId) ~= "number"
		or type(entry.token) ~= "string"
	then
		return false, true
	end

	local ok, state = pcall(function()
		return queueState:GetAsync(stateKey(entry.userId))
	end)
	if not ok then
		warn("[Matchmaker] queue-state read failed for userId=" .. tostring(entry.userId) .. ": " .. tostring(state))
		return false, false
	end
	return sameEntry(state, entry) and state.status == "queued", true
end

-- Returns:
--   "pair", entryA, entryB, readId
--   "single", entry, readId
--   "none"
-- A read batch is consumed only after assignment persistence succeeds.
function Matchmaker.tryMatch()
	local ok, items, readId = pcall(function()
		return queue:ReadAsync(2, false, 0)
	end)
	if not ok then
		warn("[Matchmaker] tryMatch ReadAsync failed: " .. tostring(items))
		return "none"
	end
	if items == nil or #items == 0 then
		return "none"
	end

	local valid = {}
	for _, entry in ipairs(items) do
		local isValid, checked = validateEntry(entry)
		if not checked then
			return "none"
		end
		if isValid then
			valid[#valid + 1] = entry
		end
	end

	if #valid >= 2 and valid[1].userId ~= valid[2].userId then
		return "pair", valid[1], valid[2], readId
	elseif #valid == 1 then
		return "single", valid[1], readId
	end

	-- The entire batch is stale/cancelled, so removing it cannot discard a
	-- valid waiter.
	local removed, removeErr = pcall(function()
		queue:RemoveAsync(readId)
	end)
	if not removed then
		warn("[Matchmaker] stale queue batch removal failed: " .. tostring(removeErr))
	end
	return "none"
end

function Matchmaker.consume(readId)
	local ok, err = pcall(function()
		queue:RemoveAsync(readId)
	end)
	if not ok then
		-- Claimed entries are already marked matched, so a later re-read is
		-- harmless and will be discarded as stale.
		warn("[Matchmaker] queue consume failed: " .. tostring(err))
	end
	return ok
end

function Matchmaker.selectDestination(entryA, entryB)
	if entryA.jobId == game.JobId and TableManager.countFree() > 0 then
		return entryA.jobId
	end
	if entryB.jobId == game.JobId and TableManager.countFree() > 0 then
		return entryB.jobId
	end

	local candidates = ServerRegistry.getCandidates(50)
	local byJobId = {}
	for _, candidate in ipairs(candidates) do
		byJobId[candidate.JobId] = candidate
	end

	local homeA = byJobId[entryA.jobId]
	if homeA and homeA.FreeTables > 0 then
		return entryA.jobId
	end
	local homeB = byJobId[entryB.jobId]
	if homeB and homeB.FreeTables > 0 then
		return entryB.jobId
	end
	for _, candidate in ipairs(candidates) do
		if candidate.FreeTables > 0 then
			return candidate.JobId
		end
	end
	return nil
end

function Matchmaker.selectDestinationForSingle(entry)
	if entry.jobId == game.JobId and TableManager.countFree() > 0 then
		return entry.jobId
	end
	for _, candidate in ipairs(ServerRegistry.getCandidates(50)) do
		if candidate.FreeTables > 0 then
			return candidate.JobId
		end
	end
	return nil
end

local function instructionFor(matchId, destinationJobId, opponentUserId, npcFallback)
	return {
		matchId = matchId,
		destinationJobId = destinationJobId,
		opponentUserId = opponentUserId,
		npcFallback = npcFallback,
		createdAt = os.time(),
	}
end

local function persistClaimedMatch(matchId, record, claims)
	for index, claim in ipairs(claims) do
		if not claimEntry(claim.entry, matchId, claim.instruction) then
			for rollbackIndex = 1, index - 1 do
				rollbackClaim(claims[rollbackIndex].entry, matchId)
			end
			return false, "participant_not_queued"
		end
	end

	local ok, err = pcall(function()
		pendingMatches:SetAsync(matchId, record, PENDING_TTL)
	end)
	if not ok then
		for _, claim in ipairs(claims) do
			rollbackClaim(claim.entry, matchId)
		end
		warn("[Matchmaker] pending match write failed: " .. tostring(err))
		return false, "memory_store"
	end

	if record.destinationJobId == game.JobId then
		trackLocalMatch(matchId)
	end
	return true
end

function Matchmaker.createMatch(entryA, entryB)
	local destinationJobId = Matchmaker.selectDestination(entryA, entryB)
	if destinationJobId == nil then
		return nil, "no_public_destination"
	end

	local matchId = HttpService:GenerateGUID(false)
	local record = {
		destinationJobId = destinationJobId,
		participantUserIds = { entryA.userId, entryB.userId },
		npcFallback = false,
		createdAt = os.time(),
	}
	local claims = {
		{
			entry = entryA,
			instruction = instructionFor(matchId, destinationJobId, entryB.userId, false),
		},
		{
			entry = entryB,
			instruction = instructionFor(matchId, destinationJobId, entryA.userId, false),
		},
	}
	local ok, err = persistClaimedMatch(matchId, record, claims)
	if not ok then
		return nil, err
	end
	return matchId
end

function Matchmaker.createNpcFallbackMatch(entry)
	local destinationJobId = Matchmaker.selectDestinationForSingle(entry)
	if destinationJobId == nil then
		return nil, "no_public_destination"
	end

	local matchId = HttpService:GenerateGUID(false)
	local record = {
		destinationJobId = destinationJobId,
		participantUserIds = { entry.userId },
		npcFallback = true,
		createdAt = os.time(),
	}
	local claims = {
		{
			entry = entry,
			instruction = instructionFor(matchId, destinationJobId, nil, true),
		},
	}
	local ok, err = persistClaimedMatch(matchId, record, claims)
	if not ok then
		return nil, err
	end
	return matchId
end

local function markArrival(player)
	if joinDataChecked[player] then
		return
	end
	joinDataChecked[player] = true

	local ok, joinData = pcall(function()
		return player:GetJoinData()
	end)
	local teleportData = ok and joinData and joinData.TeleportData
	if type(teleportData) == "table" and type(teleportData.matchId) == "string" then
		trackLocalMatch(teleportData.matchId)
	end
end

local function makeTeleportOptions(instruction)
	local options = Instance.new("TeleportOptions")
	options.ServerInstanceId = instruction.destinationJobId
	options.ShouldReserveServer = false
	options:SetTeleportData({
		matchId = instruction.matchId,
		opponentUserId = instruction.opponentUserId,
		npcFallback = instruction.npcFallback,
	})
	return options
end

TeleportService.TeleportInitFailed:Connect(function(player, teleportResult, errorMessage)
	local userId = player and player.UserId
	local attempt = userId and teleportAttempts[userId]
	if not attempt then
		return
	end
	teleportAttempts[userId] = nil
	teleportRetryAt[userId] = os.clock() + TELEPORT_RETRY_DELAY
	warn(string.format(
		"[Matchmaker] teleport init failed for %s (%s): %s",
		player.Name,
		tostring(teleportResult),
		tostring(errorMessage)
	))
end)

local function refreshPendingInstruction(userId, pending)
	local ok, state = pcall(function()
		return queueState:GetAsync(stateKey(userId))
	end)
	if not ok then
		warn("[Matchmaker] matched-state refresh failed for userId=" .. tostring(userId) .. ": " .. tostring(state))
		return pending
	end
	if type(state) == "table" and state.status == "matched" and state.matchId == pending.instruction.matchId then
		pending.instruction = state.instruction
		return pending
	end
	if type(state) == "table" and state.status == "cancelled" then
		return nil, state.reason or "cancelled"
	end
	return nil, "assignment_expired"
end

local function startTeleport(userId, pending)
	local player = pending.player
	local instruction = pending.instruction
	if player.Parent ~= Players then
		pendingInstructions[userId] = nil
		return
	end

	local attempt = {
		matchId = instruction.matchId,
		startedAt = os.clock(),
	}
	teleportAttempts[userId] = attempt
	local options = makeTeleportOptions(instruction)
	local ok, err = pcall(function()
		TeleportService:TeleportAsync(game.PlaceId, { player }, options)
	end)
	if not ok then
		if teleportAttempts[userId] == attempt then
			teleportAttempts[userId] = nil
		end
		teleportRetryAt[userId] = os.clock() + TELEPORT_RETRY_DELAY
		warn("[Matchmaker] TeleportAsync failed for " .. player.Name .. ": " .. tostring(err))
		return
	end

	task.delay(TELEPORT_CONFIRM_DELAY, function()
		if teleportAttempts[userId] ~= attempt then
			return
		end
		teleportAttempts[userId] = nil
		if player.Parent == Players then
			-- The player did not leave. Retain the instruction and retry.
			teleportRetryAt[userId] = os.clock() + TELEPORT_RETRY_DELAY
		else
			pendingInstructions[userId] = nil
			task.spawn(completeState, userId, instruction.matchId)
		end
	end)
end

-- Returns local client-status updates generated by cancellation/expiry.
function Matchmaker.processPendingTeleportsForPlayers(players)
	local updates = {}
	for _, player in ipairs(players) do
		markArrival(player)
	end

	for userId, localEntry in pairs(localQueueEntries) do
		local player = localEntry.player
		if player.Parent ~= Players then
			continue
		end
		local ok, state = pcall(function()
			return queueState:GetAsync(stateKey(userId))
		end)
		if not ok then
			warn("[Matchmaker] local queue-state read failed for " .. player.Name .. ": " .. tostring(state))
		elseif type(state) == "table"
			and state.status == "matched"
			and type(state.instruction) == "table"
		then
			localQueueEntries[userId] = nil
			pendingInstructions[userId] = {
				player = player,
				instruction = state.instruction,
			}
		elseif type(state) == "table" and state.status == "cancelled" then
			localQueueEntries[userId] = nil
			updates[#updates + 1] = {
				player = player,
				status = "cancelled",
				reason = state.reason,
			}
		end
	end

	for userId, pending in pairs(pendingInstructions) do
		local player = pending.player
		local instruction = pending.instruction
		if player.Parent ~= Players then
			pendingInstructions[userId] = nil
			continue
		end

		local alreadyHome = instruction.destinationJobId == game.JobId
		if alreadyHome then
			trackLocalMatch(instruction.matchId)
			pendingInstructions[userId] = nil
			task.spawn(completeState, userId, instruction.matchId)
			continue
		end

		if teleportAttempts[userId] then
			continue
		end
		if os.clock() < (teleportRetryAt[userId] or 0) then
			continue
		end

		local refreshed, reason = refreshPendingInstruction(userId, pending)
		if not refreshed then
			pendingInstructions[userId] = nil
			updates[#updates + 1] = {
				player = player,
				status = "cancelled",
				reason = reason,
			}
			continue
		end
		startTeleport(userId, refreshed)
	end

	return updates
end

-- Exact matchId lookups only. No ListItemsAsync/global enumeration.
function Matchmaker.getMatchesForThisServer()
	local out = {}
	local now = os.time()
	for matchId, expiresAt in pairs(localMatchIds) do
		if expiresAt <= now then
			localMatchIds[matchId] = nil
			continue
		end

		local ok, record = pcall(function()
			return pendingMatches:GetAsync(matchId)
		end)
		if not ok then
			warn("[Matchmaker] pending match read failed for " .. matchId .. ": " .. tostring(record))
		elseif type(record) ~= "table" then
			localMatchIds[matchId] = nil
		elseif record.destinationJobId ~= game.JobId then
			localMatchIds[matchId] = nil
		else
			out[#out + 1] = { matchId = matchId, record = record }
		end
	end
	return out
end

function Matchmaker.clearMatch(matchId)
	localMatchIds[matchId] = nil
	local ok, err = pcall(function()
		pendingMatches:RemoveAsync(matchId)
	end)
	if not ok then
		warn("[Matchmaker] clearMatch failed for " .. tostring(matchId) .. ": " .. tostring(err))
	end
	return ok
end

function Matchmaker.convertPartialToNpc(matchId, arrivedUserId, missingUserId)
	local ok, updated = pcall(function()
		return pendingMatches:UpdateAsync(matchId, function(current)
			if type(current) ~= "table" then
				return nil
			end
			if current.npcFallback then
				return current
			end
			local containsArrived = false
			local containsMissing = false
			for _, userId in ipairs(current.participantUserIds or {}) do
				containsArrived = containsArrived or userId == arrivedUserId
				containsMissing = containsMissing or userId == missingUserId
			end
			if not containsArrived or not containsMissing then
				return current
			end
			local replacement = {}
			for key, value in pairs(current) do
				replacement[key] = value
			end
			replacement.participantUserIds = { arrivedUserId }
			replacement.npcFallback = true
			replacement.partialFallback = true
			replacement.missingUserId = missingUserId
			return replacement
		end, PENDING_TTL)
	end)
	if not ok then
		warn("[Matchmaker] partial-arrival conversion failed: " .. tostring(updated))
		return false
	end
	if type(updated) ~= "table"
		or not updated.npcFallback
		or updated.participantUserIds[1] ~= arrivedUserId
	then
		return false
	end

	updateState(stateKey(missingUserId), PENDING_TTL, function(current)
		if type(current) == "table"
			and current.status == "matched"
			and current.matchId == matchId
		then
			return {
				token = current.token,
				status = "cancelled",
				userId = current.userId,
				jobId = current.jobId,
				queuedAt = current.queuedAt,
				matchId = matchId,
				reason = "opponent_arrival_timeout",
			}
		end
		return current
	end)
	return true
end

function Matchmaker.onPlayerRemoving(player)
	local userId = player.UserId
	if pendingInstructions[userId] or teleportAttempts[userId] then
		pendingInstructions[userId] = nil
		teleportAttempts[userId] = nil
		teleportRetryAt[userId] = nil
		return
	end
	if localQueueEntries[userId] then
		-- Best-effort cancellation for a true waiter. If an atomic match claim
		-- already won the race, dequeue safely leaves that assignment intact.
		Matchmaker.dequeue(player)
		localQueueEntries[userId] = nil
	end
	queueOperations[userId] = nil
end

return Matchmaker