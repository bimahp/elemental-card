-- SaveService: ProfileStore wrapper (PLAN_BACKEND Phase 4).
-- Owns the player profile lifecycle: session-locked load on PlayerAdded, release on
-- PlayerRemoving, schema v5 + migration, dirty-flag pooled autosave, reward apply.
-- NPC seats never touch the datastore. Persistence is intentionally only attempted
-- for players still present in the server (locked decision 2026-06-21).

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SSS               = game:GetService("ServerScriptService")

local ProfileStore = require(SSS.Packages.ProfileStore)
local Decks        = require(ReplicatedStorage.Definitions.Decks)
local Cards        = require(ReplicatedStorage.Definitions.Cards)
local LevelConfig  = require(ReplicatedStorage.Modules.LevelConfig)
local QuestConfig  = require(ReplicatedStorage.Modules.QuestConfig)
local RewardConfig = require(ReplicatedStorage.Modules.RewardConfig)
local GachaTransaction  = require(SSS.Modules.GachaTransaction)
local ShopTransaction   = require(SSS.Modules.ShopTransaction)
local VendorTransaction = require(SSS.Modules.VendorTransaction)
local TitleService      = require(SSS.Modules.TitleService)
-- Crystal Core removed (Battle Charge migration): decks no longer store a Core.

local SaveService = {}

-- ── Config ────────────────────────────────────────────────────────────────────
local STORE_NAME           = "PlayerProfiles"  -- stable; data version lives in the data, not the store name
local DEFAULT_ARCHETYPE    = "MIGHTY"           -- new players start MIGHTY (locked)
local DIRTY_FLUSH_INTERVAL = 60                 -- seconds; pooled flush of dirty profiles
local CURRENT_VERSION      = { major = 5, minor = 4 }
local RECEIPT_SAVE_TIMEOUT = 30
local MAX_DECKS            = 12
-- Guard for the destructive major-bump path. A major version increment means the
-- on-disk shape is incompatible and the profile is WIPED to a fresh starter.
local ALLOW_MAJOR_RESET    = true

-- ── Helpers ───────────────────────────────────────────────────────────────────
local function deepCopy(t)
	if type(t) ~= "table" then return t end
	local c = {}
	for k, v in pairs(t) do c[k] = deepCopy(v) end
	return c
end

local function archetypeDeckKey(archetype)
	return string.lower(archetype or DEFAULT_ARCHETYPE)
end

-- The starter collection is the archetype's 30-card starter deck as a multiset
-- (duplicates kept; Phase 5 inventory stacks them with an xN badge).
local function buildStarterCollection(archetype)
	local deck = Decks[archetypeDeckKey(archetype)]
	local collection = {}
	if deck and deck.cards then
		for _, id in ipairs(deck.cards) do
			collection[#collection + 1] = id
		end
	end
	return collection
end

local function buildDefaultDeck()
	local cards = {}
	for _, id in ipairs((Decks.mighty and Decks.mighty.cards) or {}) do cards[#cards + 1] = id end
	local now = os.time()
	return {
		id = "deck_mighty_starter",
		name = "Mighty Starter",
		cards = cards,
		createdAt = now,
		updatedAt = now,
	}
end

local function ensureCollectionCoversDeck(data, deck)
	if type(data.collection) ~= "table" then data.collection = {} end
	local available = {}
	for _, id in ipairs(data.collection) do available[id] = (available[id] or 0) + 1 end
	for _, id in ipairs(deck.cards or {}) do
		if (available[id] or 0) > 0 then available[id] -= 1
		else data.collection[#data.collection + 1] = id end
	end
end

local function ensureDeckDefaults(data)
	local q = type(data.quests) == "table" and data.quests[QuestConfig.IDs.ONBOARDING]
	local onboardingIncomplete = type(q) == "table" and q.stage ~= "complete"
	if data.activeDeckId == false and onboardingIncomplete then return end
	if data.activeDeckId == false then data.activeDeckId = nil end
	if type(data.decks) ~= "table" or #data.decks == 0 then
		local deck = buildDefaultDeck()
		data.decks = { deck }
		data.activeDeckId = deck.id
		ensureCollectionCoversDeck(data, deck)
		return
	end
	local active
	if type(data.activeDeckId) == "string" then
		for _, deck in ipairs(data.decks) do if deck.id == data.activeDeckId then active = deck; break end end
	end
	if not active then active = data.decks[1]; data.activeDeckId = active and active.id or nil end
	if active and not onboardingIncomplete then ensureCollectionCoversDeck(data, active) end
end

-- Schema v5.0 template. ProfileStore deep-copies this for first-time keys, so the
-- template IS the new-player grant: archetype MIGHTY + the MIGHTY starter collection.
local TEMPLATE = {
	_version      = { major = CURRENT_VERSION.major, minor = CURRENT_VERSION.minor },
	archetype     = DEFAULT_ARCHETYPE,
	collection    = {},                       -- v3.1: empty until grantStarterDeck
	crystalShards = 0,                        -- v3.1: replaces gold; paid+destroy+quest only (DESIGN_ECONOMY)
	cardFragments = 0,                        -- v5.3: free gameplay currency, random packs only (DESIGN_ECONOMY)
	purchaseHistory = {},                    -- v5.1: granted Developer Product receipt IDs
	exp           = 0,
	level         = 1,                        -- v3.1
	pvp           = { wins = 0, losses = 0 }, -- v1.1
	activeMatch   = false,                    -- v1.1: set while in a match (abandon detection); v5.2 adds jobId+mode for reconnect
	decks         = {},                       -- v3.1: empty until grantStarterDeck
	activeDeckId  = false,                    -- v3.1: false = quest-gated (no deck until onboarding)
	quests        = { [QuestConfig.IDs.ONBOARDING] = { stage = "intro", archetype = nil } }, -- v3.1
	-- v5.3 (DESIGN_REWARD.md battle-reward revamp):
	dailyRewards  = { day = 0, battleFragments = 0, npcFragments = 0, forfeitCount = 0 },
	matchmakingCooldownUntil = 0,              -- epoch seconds; early-forfeit cooldown ladder
	pveFirstClear = { MIGHTY = false, SWIFT = false, VITAL = false }, -- per-archetype NPC first-clear bonus
	ownedTitles   = { beta_tester = true },  -- v5.4: permanent cosmetic title unlocks
	equippedTitle = "beta_tester",           -- v5.4: publicly replicated title selection
}

-- A fresh data table (used by new-player grant and the major-bump hard reset).
local function buildFreshData()
	return deepCopy(TEMPLATE)
end
SaveService.buildFreshData = buildFreshData  -- exposed for headless tests

-- ── Migration ─────────────────────────────────────────────────────────────────
-- Run BEFORE Reconcile so a missing/old _version is still visible. Reconcile
-- afterward backfills any keys added in a minor bump.
--   major < current  -> hard reset (guarded, destructive)
--   minor < current  -> ordered in-place minor migrations, then bump minor
--   version > current -> warn (server older than data); serve as-is
-- Returns a status string for logging/tests.
-- Minor migrations only run when major == CURRENT_VERSION.major.
-- Any profile with major < 5 is hard-reset before reaching this table.
local MINOR_MIGRATIONS = {
	["5.3->5.4"] = function(data)
		if type(data.ownedTitles) ~= "table" then data.ownedTitles = { beta_tester = true } end
		data.ownedTitles.beta_tester = true
		if type(data.equippedTitle) ~= "string" then data.equippedTitle = "beta_tester" end
	end,
	["5.2->5.3"] = function(data)
		-- Battle-reward economy revamp (DESIGN_REWARD.md/DESIGN_ECONOMY.md):
		-- Card Fragments replace Crystal Dust; add daily reward-cap tracking,
		-- the forfeit-cooldown timestamp, and per-archetype NPC first-clear flags.
		if data.cardFragments == nil then data.cardFragments = 0 end
		if type(data.dailyRewards) ~= "table" then
			data.dailyRewards = { day = 0, battleFragments = 0, npcFragments = 0, forfeitCount = 0 }
		end
		if data.matchmakingCooldownUntil == nil then data.matchmakingCooldownUntil = 0 end
		if type(data.pveFirstClear) ~= "table" then
			data.pveFirstClear = { MIGHTY = false, SWIFT = false, VITAL = false }
		end
		data.crystalDust = nil
	end,
	["5.1->5.2"] = function(data)
		-- PLAN_MATCHMAKING Phase 4a: activeMatch gains jobId (reconnect target)
		-- and mode ("pvp"|"pve", so an abandoned NPC-fallback match never
		-- records a PVP loss). Only a genuinely in-flight match written by the
		-- pre-Phase-4a code (an extremely narrow window) would be missing
		-- these -- default jobId=nil (treated as "different server", which
		-- safely falls through to the existing abandonment path since no real
		-- reconnect target is known) and mode="pvp" (matches the only mode
		-- that ever called beginPvpMatch before this migration existed).
		if type(data.activeMatch) == "table" and data.activeMatch.mode == nil then
			data.activeMatch.mode = "pvp"
			-- jobId is left nil -- correctly falls through to the abandonment path
			-- (no real reconnect target is known for a pre-migration record).
		end
	end,
	["5.0->5.1"] = function(data)
		if type(data.purchaseHistory) ~= "table" then data.purchaseHistory = {} end
	end,
	["4.0->4.1"] = function(data)
		if data.crystalDust == nil then data.crystalDust = 0 end
	end,
	["3.0->3.1"] = function(data)
		if data.gold ~= nil then
			data.crystalShards = (tonumber(data.crystalShards) or 0) + (tonumber(data.gold) or 0)
			data.gold = nil
		end
		data.level = LevelConfig.levelFromExp(data.exp or 0)
		if type(data.quests) ~= "table" then data.quests = {} end
		local questId = QuestConfig.IDs.ONBOARDING
		local q = data.quests[questId]
		local hasDeckData = type(data.activeDeckId) == "string"
			or (type(data.decks) == "table" and #data.decks > 0)
			or (type(data.collection) == "table" and #data.collection > 0)
		if type(q) ~= "table" then
			data.quests[questId] = { stage = "complete", archetype = data.archetype }
		elseif hasDeckData and q.stage ~= "deck_chosen" and q.stage ~= "complete" then
			data.quests[questId] = { stage = "complete", archetype = q.archetype or data.archetype }
		else
			q.stage = q.stage or "intro"
		end
	end,
}

local function hardReset(data)
	for k in pairs(data) do data[k] = nil end
	for k, v in pairs(buildFreshData()) do data[k] = v end
end

local function migrate(data)
	local v = data._version
	local major = (type(v) == "table" and tonumber(v.major)) or 0
	local minor = (type(v) == "table" and tonumber(v.minor)) or 0

	if major < CURRENT_VERSION.major then
		if ALLOW_MAJOR_RESET then
			hardReset(data)
			return "major_reset"
		end
		return "blocked"  -- caller decides; we still serve reconciled data
	end

	if major == CURRENT_VERSION.major and minor < CURRENT_VERSION.minor then
		for step = minor, CURRENT_VERSION.minor - 1 do
			local key = string.format("%d.%d->%d.%d", major, step, major, step + 1)
			local fn = MINOR_MIGRATIONS[key]
			if fn then fn(data) end
		end
		data._version = { major = CURRENT_VERSION.major, minor = CURRENT_VERSION.minor }
		return "minor_upgraded"
	end

	if major > CURRENT_VERSION.major or (major == CURRENT_VERSION.major and minor > CURRENT_VERSION.minor) then
		return "ahead"  -- data written by newer server code; serve cautiously
	end

	return "current"
end
SaveService.migrate = migrate  -- exposed for headless tests

-- ── Runtime state ──────────────────────────────────────────────────────────────
local Remotes       -- set in SaveService.init after WaitForChild resolves
local Store         -- the active ProfileStore store object (real or .Mock)
local Profiles = {} -- [Player] = profile
local Dirty    = {} -- [Player] = true
local Loading  = {} -- [Player] = true  (in-flight load guard; prevents double-load)
local ReceiptSaving = {} -- [Player] = PurchaseId while persistence confirmation is pending
local started  = false
local attemptReconnectFn -- injected via SaveService.init; PLAN_MATCHMAKING Phase 4c

local function dayBucket()
	return math.floor(os.time() / 86400)
end
SaveService.dayBucket = dayBucket -- exposed for headless tests

-- Resets the three daily reward counters when the UTC day bucket has rolled
-- over. Called at the top of every function that reads/writes them so a
-- stale bucket never has to be handled by call sites individually.
local function ensureDailyReset(data)
	if type(data.dailyRewards) ~= "table" then
		data.dailyRewards = { day = 0, battleFragments = 0, npcFragments = 0, forfeitCount = 0 }
	end
	local today = dayBucket()
	if data.dailyRewards.day ~= today then
		data.dailyRewards.day = today
		data.dailyRewards.battleFragments = 0
		data.dailyRewards.npcFragments = 0
		data.dailyRewards.forfeitCount = 0
	end
end

local function checkLevelUp(player, data)
	local newLevel = LevelConfig.levelFromExp(data.exp or 0)
	if newLevel > (data.level or 1) then
		data.level = newLevel
		local levelVal = player:FindFirstChild("Level")
		if levelVal then levelVal.Value = newLevel end
		if Remotes then Remotes.LevelUp:FireClient(player, { newLevel = newLevel }) end
	end
end

local function syncTitles(player, data)
	if not data then
		local profile = Profiles[player]
		if not profile or not profile:IsActive() then return false end
		data = profile.Data
	end
	local changed = TitleService.reconcile(data)
	player:SetAttribute("EquippedTitleId", data.equippedTitle)
	if changed and Profiles[player] then Dirty[player] = true end
	return changed
end

-- ── Profile lifecycle ──────────────────────────────────────────────────────────
local function onPlayerAdded(player)
	-- Re-entrancy guard: a player present at init can be caught by both the
	-- PlayerAdded connection and the GetPlayers() sweep. Double StartSessionAsync
	-- on one key throws ("already loaded in this session"), so load each once.
	if Profiles[player] or Loading[player] then return end
	Loading[player] = true

	local profile = Store:StartSessionAsync("Player_" .. player.UserId, {
		Cancel = function() return player.Parent ~= Players end,
	})
	Loading[player] = nil

	if profile == nil then
		player:Kick("Data could not be loaded. Please rejoin.")
		return
	end

	profile:AddUserId(player.UserId)
	local status = migrate(profile.Data)   -- before Reconcile (see migrate notes)
	profile:Reconcile()                    -- backfill any missing keys from TEMPLATE
	ensureDeckDefaults(profile.Data)
	local titlesChanged = syncTitles(player, profile.Data)
	profile.Data._version = { major = CURRENT_VERSION.major, minor = CURRENT_VERSION.minor }
	if status ~= "current" or titlesChanged then Dirty[player] = true end

	-- Reconnect-or-abandon (PLAN_MATCHMAKING Phase 4c): an activeMatch flag
	-- still set on load means the player left a match unresolved last session
	-- (disconnect/crash). Try to reconnect them into the still-live battle
	-- first (same-server: direct lookup; different-server: TeleportAsync
	-- toward the stored jobId) via the injected attemptReconnect callback --
	-- only fall back to recording abandonment if that isn't possible/fails.
	-- A generous sanity ceiling guards against a future bug leaving a player
	-- stuck in reconnect-limbo forever. The flag was force-saved at match
	-- start, so this survives any exit.
	if profile.Data.activeMatch then
		local activeMatch = profile.Data.activeMatch
		local RECONNECT_SANITY_CEILING = 3600 -- seconds; far longer than any real match
		local tooOld = (os.time() - (activeMatch.startedAt or 0)) > RECONNECT_SANITY_CEILING
		local reconnected = false
		if not tooOld and attemptReconnectFn then
			local ok, handled = pcall(attemptReconnectFn, player, activeMatch)
			reconnected = ok and handled == true
		end
		if not reconnected then
			profile.Data.activeMatch = false
			if activeMatch.mode == "pve" then
				warn(string.format("[SaveService] %s abandoned a prior matchmaking NPC-fallback match -> no penalty recorded (a PvE loss carries none)",
					player.Name))
			else
				profile.Data.pvp.losses += 1
				warn(string.format("[SaveService] %s abandoned a prior PVP match -> loss recorded (%dW/%dL)",
					player.Name, profile.Data.pvp.wins, profile.Data.pvp.losses))
			end
			task.spawn(function() if profile:IsActive() then profile:Save() end end)
		end
	end

	profile.OnSessionEnd:Connect(function()
		Profiles[player] = nil
		Dirty[player] = nil
		ReceiptSaving[player] = nil
		if player.Parent == Players then
			player:Kick("Your data session ended (you may have joined another server). Please rejoin.")
		end
	end)

	if player.Parent == Players then
		Profiles[player] = profile
		if status ~= "current" then
			warn(string.format("[SaveService] %s profile migration: %s", player.Name, status))
		end
		-- Create Level IntValue so all clients can read player level from the Player object
		local levelVal = Instance.new("IntValue")
		levelVal.Name   = "Level"
		levelVal.Value  = profile.Data.level or 1
		levelVal.Parent = player
		player:SetAttribute("EquippedTitleId", profile.Data.equippedTitle)
		-- Broadcast initial quest state to the joining client
		if Remotes then
			local qEntry = (profile.Data.quests and profile.Data.quests[QuestConfig.IDs.ONBOARDING])
			               or { stage = "complete", archetype = nil }
			Remotes.QuestStateChanged:FireClient(player, {
				stage           = qEntry.stage,
				chosenArchetype = qEntry.archetype,
				level           = profile.Data.level or 1,
				crystalShards   = profile.Data.crystalShards or 0,
				cardFragments   = profile.Data.cardFragments or 0,
			})
		end
	else
		-- player left while loading
		profile:EndSession()
	end
end

local function onPlayerRemoving(player)
	local profile = Profiles[player]
	if profile then profile:EndSession() end
	Profiles[player] = nil
	Dirty[player] = nil
	Loading[player] = nil
	ReceiptSaving[player] = nil
end

-- ── Public API ──────────────────────────────────────────────────────────────────
function SaveService.getProfile(player)
	return Profiles[player]
end

-- Archetype for battle deck selection. Falls back to the default if the profile
-- isn't loaded yet so battle entry never hard-fails on a data hiccup.
function SaveService.getArchetype(player)
	local profile = Profiles[player]
	if profile and profile:IsActive() and profile.Data.archetype then
		return profile.Data.archetype
	end
	return DEFAULT_ARCHETYPE
end

function SaveService.markDirty(player)
	if Profiles[player] then Dirty[player] = true end
end

function SaveService.getCollectionCounts(player)
	local profile = Profiles[player]
	if not profile or not profile:IsActive() then return nil end
	local counts = {}
	for _, cardId in ipairs(profile.Data.collection or {}) do
		counts[cardId] = (counts[cardId] or 0) + 1
	end
	return counts
end

-- exp-into-current-level / exp-needed-for-next-level, for the post-battle
-- Result screen's EXP progress bar.
function SaveService.getExpProgress(player)
	local profile = Profiles[player]
	if not profile or not profile:IsActive() then return nil end
	local data = profile.Data
	local into, needed = LevelConfig.expIntoLevel(data.exp or 0)
	return { level = data.level or 1, into = into, needed = needed }
end

function SaveService.getPlayerStatus(player)
	local profile = Profiles[player]
	if not profile or not profile:IsActive() then return nil, "Profile not loaded" end
	local data = profile.Data
	syncTitles(player, data)
	local into, needed = LevelConfig.expIntoLevel(data.exp or 0)
	local currentLevel = data.level or LevelConfig.levelFromExp(data.exp or 0)
	local pvp = type(data.pvp) == "table" and data.pvp or {}
	return {
		level = {
			current = currentLevel,
			expInto = into,
			expNeeded = needed,
			maxed = currentLevel >= 100 or needed <= 0,
		},
		archetype = data.archetype,
		pvp = { wins = tonumber(pvp.wins) or 0, losses = tonumber(pvp.losses) or 0 },
		collection = {
			uniqueOwned = TitleService.uniqueCollectibleCount(data),
			totalCollectible = TitleService.totalCollectibleCount(),
		},
		trainers = { cleared = TitleService.trainerClearCount(data), total = 3 },
		titles = TitleService.buildView(data),
	}
end

function SaveService.equipTitle(player, titleId)
	local profile = Profiles[player]
	if not profile or not profile:IsActive() then return nil, "Profile not loaded" end
	local data = profile.Data
	local ok, err = TitleService.equip(data, titleId)
	if not ok then return nil, err end
	Dirty[player] = true
	player:SetAttribute("EquippedTitleId", data.equippedTitle)
	task.spawn(function()
		if profile:IsActive() then profile:Save() end
	end)
	return SaveService.getPlayerStatus(player)
end

-- Remaining seconds on the early-forfeit matchmaking cooldown ladder, or 0
-- if none is active. Checked by JoinMatchmaking before enqueueing.
function SaveService.getMatchmakingCooldownRemaining(player)
	local profile = Profiles[player]
	if not profile or not profile:IsActive() then return 0 end
	local remaining = (profile.Data.matchmakingCooldownUntil or 0) - os.time()
	return remaining > 0 and remaining or 0
end

-- Consumes a RewardService reward plan and persists it -- the only place a
-- plan turns into an actual cardFragments/exp mutation. Owns everything that
-- needs player-persistent state RewardService deliberately never touches:
-- the daily caps (global 200/day across Matchmaking+Local+repeat-NPC, plus
-- NPC's own 10/day sub-cap), the per-archetype NPC first-clear bonus (which
-- bypasses both caps), and EXP scaling (exp = granted * EXP_PER_FRAGMENT,
-- computed from what was *actually* granted, not the pre-cap desired amount).
-- Returns the granted amounts (for client display), or nil if the profile
-- isn't loaded/active (e.g. a disconnected recipient) -- matching every
-- other SaveService function's present-player-only convention.
function SaveService.applyBattleRewards(player, rewardPlan)
	if type(rewardPlan) ~= "table" then return nil end
	local profile = Profiles[player]
	if not profile or not profile:IsActive() then return nil end
	local data = profile.Data
	ensureDailyReset(data)

	local cat = rewardPlan.category
	local granted = rewardPlan.baseCardFragments or 0
	local firstClear = false

	if cat == "npc" and rewardPlan.outcome == "win" and rewardPlan.archetype
		and data.pveFirstClear[rewardPlan.archetype] == false then
		data.pveFirstClear[rewardPlan.archetype] = true
		granted = RewardConfig.NPC.firstClear
		firstClear = true
	end

	if not firstClear then
		local globalRoom = math.max(0, RewardConfig.GLOBAL_DAILY_CAP - data.dailyRewards.battleFragments)
		granted = math.min(granted, globalRoom)
		if cat == "npc" then
			local npcRoom = math.max(0, RewardConfig.NPC_DAILY_SUBCAP - data.dailyRewards.npcFragments)
			granted = math.min(granted, npcRoom)
		end
		data.dailyRewards.battleFragments += granted
		if cat == "npc" then data.dailyRewards.npcFragments += granted end
	end

	data.cardFragments = (data.cardFragments or 0) + granted
	local expGained = granted * RewardConfig.EXP_PER_FRAGMENT
	if expGained > 0 then
		data.exp = (data.exp or 0) + expGained
		checkLevelUp(player, data)
	end
	syncTitles(player, data)

	if Remotes then
		local qEntry = (data.quests and data.quests[QuestConfig.IDs.ONBOARDING])
			or { stage = "complete", archetype = nil }
		Remotes.QuestStateChanged:FireClient(player, {
			stage = qEntry.stage,
			chosenArchetype = qEntry.archetype,
			level = data.level or 1,
			crystalShards = data.crystalShards or 0,
			cardFragments = data.cardFragments or 0,
		})
	end

	-- Important event (currency granted): force an immediate flush, same
	-- convention the old cardDrop path used.
	Dirty[player] = nil
	task.spawn(function()
		if profile:IsActive() then profile:Save() end
	end)

	return {
		category = cat,
		outcome = rewardPlan.outcome,
		forfeited = rewardPlan.forfeited,
		earlyForfeit = rewardPlan.earlyForfeit,
		valid = rewardPlan.valid,
		firstClear = firstClear,
		cardFragments = granted,
		exp = expGained,
	}
end

-- Increments today's early-forfeit count (Matchmaking category only) and, if
-- the ladder calls for it, sets the matchmaking-queue cooldown timestamp.
-- See RewardConfig.FORFEIT_COOLDOWN_LADDER.
function SaveService.registerEarlyForfeit(player)
	local profile = Profiles[player]
	if not profile or not profile:IsActive() then return end
	local data = profile.Data
	ensureDailyReset(data)
	data.dailyRewards.forfeitCount += 1
	local cooldown = RewardConfig.forfeitCooldownSeconds(data.dailyRewards.forfeitCount)
	if cooldown > 0 then
		data.matchmakingCooldownUntil = os.time() + cooldown
	end
	Dirty[player] = true
end

-- ── Match result tracking (PLAN_BACKEND issue: anti rage-quit; generalized
-- for PLAN_MATCHMAKING Phase 4 reconnect) ────────────────────────────────────
-- beginMatch: flag a player "in a match" at start and force-save, so an
-- unclean exit is detectable on next load -- resolved there either as a
-- reconnect (same/different server, Phase 4c) or, failing that, an
-- abandonment (a PVP loss for mode="pvp"; no penalty for mode="pve", matching
-- how a normal PvE loss already carries no penalty). `jobId` is the server
-- instance a reconnect should target -- nil for battles that don't need
-- cross-server reconnect (a non-matchmaking local battle only ever needs
-- same-process resolution, but storing it uniformly is harmless).
-- Renamed from the PLAN_BACKEND-era beginPvpMatch -- this is no longer
-- PVP-only (NPC-fallback matchmaking matches need reconnect tracking too,
-- per PLAN_MATCHMAKING.md's Phase 3 scoping decision), so a mode-agnostic
-- name matches what it now actually does.
function SaveService.beginMatch(player, battleId, jobId, mode)
	local profile = Profiles[player]
	if not profile or not profile:IsActive() then return false end
	profile.Data.activeMatch = { battleId = battleId, jobId = jobId, mode = mode, startedAt = os.time() }
	task.spawn(function() if profile:IsActive() then profile:Save() end end)
	return true
end

-- Clears activeMatch without touching pvp.wins/losses -- used both by
-- recordPvpResult's existing PVP-result path (unchanged) and by a
-- matchmaking-originated PvE (NPC-fallback) battle's normal end, which has
-- no W/L record to update but still needs the reconnect flag cleared.
function SaveService.clearActiveMatch(player)
	local profile = Profiles[player]
	if not profile or not profile:IsActive() then return false end
	if profile.Data.activeMatch then
		profile.Data.activeMatch = false
		task.spawn(function() if profile:IsActive() then profile:Save() end end)
	end
	return true
end

-- recordPvpResult: clean finish (win/loss/forfeit while present). Records W/L,
-- clears the activeMatch flag (so next login won't double-count), force-saves.
-- Returns the new {wins,losses} for display, or nil if the profile is gone
-- (disconnected) -- in which case the activeMatch flag resolves it on next load.
function SaveService.recordPvpResult(player, won)
	local profile = Profiles[player]
	if not profile or not profile:IsActive() then return nil end
	local pvp = profile.Data.pvp
	if won then pvp.wins += 1 else pvp.losses += 1 end
	profile.Data.activeMatch = false
	syncTitles(player, profile.Data)
	task.spawn(function() if profile:IsActive() then profile:Save() end end)
	return { wins = pvp.wins, losses = pvp.losses }
end

function SaveService.getPvpRecord(player)
	local profile = Profiles[player]
	if profile and profile:IsActive() then
		return { wins = profile.Data.pvp.wins, losses = profile.Data.pvp.losses }
	end
	return { wins = 0, losses = 0 }
end

-- ── Deck builder / active battle deck (schema v1.2) ───────────────────────────
local function collectionCounts(collection)
	local counts = {}
	for _, id in ipairs(collection or {}) do counts[id] = (counts[id] or 0) + 1 end
	return counts
end

local function findDeck(data, deckId)
	for _, deck in ipairs(data.decks or {}) do
		if deck.id == deckId then return deck end
	end
	return nil
end

local function maxDeckCopiesForCard(card)
	if card and card.rarity == "legendary" then return 1 end
	return 2
end

local function validateDeckData(data, deck)
	local errors = {}
	if type(deck) ~= "table" then return false, {"Missing deck"} end
	local cards = deck.cards or {}
	if #cards ~= 30 then errors[#errors+1] = "Deck must contain exactly 30 cards" end
	local owned = collectionCounts(data.collection)
	local used = {}
	for _, id in ipairs(cards) do
		local card = Cards[id]
		used[id] = (used[id] or 0) + 1
		if not card then
			errors[#errors+1] = "Unknown card: " .. tostring(id)
		end
		local maxCopies = maxDeckCopiesForCard(card)
		if used[id] > maxCopies then errors[#errors+1] = "Max " .. maxCopies .. " copies: " .. tostring(id) end
		if used[id] > (owned[id] or 0) then errors[#errors+1] = "Not owned: " .. tostring(id) end
	end
	return #errors == 0, errors
end
SaveService.validateDeckData = validateDeckData

local function validateDraftCards(data, cards)
	local errors = {}
	if type(cards) ~= "table" then return false, {"Invalid cards"} end
	if #cards > 30 then errors[#errors+1] = "Deck cannot exceed 30 cards" end
	local owned = collectionCounts(data.collection)
	local used = {}
	for _, id in ipairs(cards) do
		local card = Cards[id]
		used[id] = (used[id] or 0) + 1
		if not card then
			errors[#errors+1] = "Unknown card: " .. tostring(id)
		end
		local maxCopies = maxDeckCopiesForCard(card)
		if used[id] > maxCopies then errors[#errors+1] = "Max " .. maxCopies .. " copies: " .. tostring(id) end
		if used[id] > (owned[id] or 0) then errors[#errors+1] = "Not owned: " .. tostring(id) end
	end
	return #errors == 0, errors
end

local function deckSummary(data, deck)
	local copy = deepCopy(deck)
	local valid, errors = validateDeckData(data, deck)
	copy.valid = valid
	copy.errors = errors
	copy.cardCount = #(deck.cards or {})
	copy.isActive = (data.activeDeckId == deck.id)
	return copy
end

function SaveService.getDecks(player)
	local profile = Profiles[player]
	if not profile or not profile:IsActive() then return { decks = {}, activeDeckId = nil } end
	ensureDeckDefaults(profile.Data)
	local out = {}
	for _, deck in ipairs(profile.Data.decks or {}) do out[#out+1] = deckSummary(profile.Data, deck) end
	return { decks = out, activeDeckId = profile.Data.activeDeckId, maxDecks = MAX_DECKS }
end

function SaveService.createDeck(player, name)
	local profile = Profiles[player]
	if not profile or not profile:IsActive() then return false, "Profile not loaded" end
	local data = profile.Data; ensureDeckDefaults(data)
	if #data.decks >= MAX_DECKS then return false, "Deck limit reached" end
	local now = os.time()
	local deck = { id = "deck_" .. player.UserId .. "_" .. now .. "_" .. math.random(1000,9999), name = tostring(name or "New Deck"):sub(1, 32), cards = {}, createdAt = now, updatedAt = now }
	table.insert(data.decks, deck)
	Dirty[player] = true
	return true, deckSummary(data, deck)
end

function SaveService.saveDeckCards(player, deckId, cards)
	local profile = Profiles[player]
	if not profile or not profile:IsActive() then return false, "Profile not loaded" end
	local data = profile.Data; ensureDeckDefaults(data)
	local deck = findDeck(data, deckId); if not deck then return false, "Deck not found" end
	local ok, errors = validateDraftCards(data, cards)
	if not ok then return false, table.concat(errors, "; ") end
	deck.cards = deepCopy(cards)
	deck.updatedAt = os.time()
	Dirty[player] = true
	return true, deckSummary(data, deck)
end

function SaveService.renameDeck(player, deckId, name)
	local profile = Profiles[player]
	if not profile or not profile:IsActive() then return false, "Profile not loaded" end
	local deck = findDeck(profile.Data, deckId); if not deck then return false, "Deck not found" end
	deck.name = tostring(name or deck.name):sub(1, 32)
	deck.updatedAt = os.time()
	Dirty[player] = true
	return true, deckSummary(profile.Data, deck)
end

function SaveService.deleteDeck(player, deckId)
	local profile = Profiles[player]
	if not profile or not profile:IsActive() then return false, "Profile not loaded" end
	local data = profile.Data; ensureDeckDefaults(data)
	if data.activeDeckId == deckId then return false, "Choose another active deck before deleting this one" end
	for i, deck in ipairs(data.decks) do
		if deck.id == deckId then
			table.remove(data.decks, i)
			Dirty[player] = true
			return true, SaveService.getDecks(player)
		end
	end
	return false, "Deck not found"
end

function SaveService.setActiveDeck(player, deckId)
	local profile = Profiles[player]
	if not profile or not profile:IsActive() then return false, "Profile not loaded" end
	local data = profile.Data; ensureDeckDefaults(data)
	local deck = findDeck(data, deckId); if not deck then return false, "Deck not found" end
	local valid, errors = validateDeckData(data, deck)
	if not valid then return false, table.concat(errors, "; ") end
	data.activeDeckId = deckId
	Dirty[player] = true
	return true, deckSummary(data, deck)
end

function SaveService.getActiveBattleDeck(player)
	local profile = Profiles[player]
	if not profile or not profile:IsActive() then
		local deck = buildDefaultDeck()
		return { cards = deepCopy(deck.cards), name = deck.name }
	end
	local data = profile.Data; ensureDeckDefaults(data)
	local deck = findDeck(data, data.activeDeckId)
	local valid = deck and validateDeckData(data, deck)
	if not valid then return nil, "No valid active deck" end
	return { cards = deepCopy(deck.cards), name = deck.name }
end

-- ── Quest & currency (v3.1) ──────────────────────────────────────────────────
function SaveService.grantStarterDeck(player, archetype)
	local profile = Profiles[player]
	if not profile or not profile:IsActive() then return false, "Profile not loaded" end
	local key = string.lower(archetype or "")
	local deckDef = Decks[key]
	if not deckDef then return false, "Unknown archetype: " .. tostring(archetype) end
	local data = profile.Data
	local hasOwnedData = type(data.activeDeckId) == "string"
		or (type(data.decks) == "table" and #data.decks > 0)
		or (type(data.collection) == "table" and #data.collection > 0)
	if data.activeDeckId ~= false or hasOwnedData then
		return false, "Starter deck grant refused: profile already owns cards or decks"
	end
	data.collection = {}
	for _, id in ipairs(deckDef.cards) do data.collection[#data.collection + 1] = id end
	local now    = os.time()
	local deckId = "deck_" .. key .. "_starter"
	local deck   = { id = deckId, name = deckDef.name, cards = deepCopy(deckDef.cards), createdAt = now, updatedAt = now }
	data.decks        = { deck }
	data.activeDeckId = deckId
	data.archetype    = string.upper(archetype)
	syncTitles(player, data)
	Dirty[player] = true
	return true
end

function SaveService.getQuestState(player, questId)
	local profile = Profiles[player]
	if not profile or not profile:IsActive() then return nil end
	local quests = profile.Data.quests
	if type(quests) ~= "table" then return nil end
	return quests[questId]
end

function SaveService.setQuestStage(player, questId, stage, archetype)
	local profile = Profiles[player]
	if not profile or not profile:IsActive() then return false, "Profile not loaded" end
	local data = profile.Data
	if type(data.quests) ~= "table" then data.quests = {} end
	local previous = data.quests[questId]
	local nextArchetype = archetype
	if nextArchetype == nil and type(previous) == "table" then nextArchetype = previous.archetype end
	data.quests[questId] = { stage = stage, archetype = nextArchetype }
	syncTitles(player, data)
	Dirty[player] = true
	return true
end

function SaveService.getFullSnapshot(player)
	local profile = Profiles[player]
	if not profile or not profile:IsActive() then return nil end
	local data = profile.Data
	return {
		level         = data.level or 1,
		crystalShards = data.crystalShards or 0,
		cardFragments = data.cardFragments or 0,
		quests        = deepCopy(data.quests or {}),
	}
end

-- ── Atomic Card Vending Machine purchase (v5.0) ───────────────────────────────
function SaveService.applyCardPackPurchase(player, cost, rolledEntries)
	local profile = Profiles[player]
	if not profile or not profile:IsActive() then
		return { ok = false, error = "Profile not loaded" }
	end

	local result = GachaTransaction.apply(profile.Data, cost, rolledEntries)
	if not result.ok then return result end

	syncTitles(player, profile.Data)
	Dirty[player] = true
	if Remotes then
		local qEntry = (profile.Data.quests and profile.Data.quests[QuestConfig.IDs.ONBOARDING])
			or { stage = "complete", archetype = nil }
		Remotes.QuestStateChanged:FireClient(player, {
			stage = qEntry.stage,
			chosenArchetype = qEntry.archetype,
			level = profile.Data.level or 1,
			crystalShards = profile.Data.crystalShards or 0,
			cardFragments = profile.Data.cardFragments or 0,
		})
	end
	-- Prompt persistence immediately; Dirty remains set as an autosave backstop.
	task.spawn(function()
		if profile:IsActive() then profile:Save() end
	end)
	return result
end

-- ── Atomic Card Merchant Craft/Buy/Destroy (Card Merchant NPC) ───────────────────────
local function fireCurrencyRefresh(player, profile)
	if not Remotes then return end
	local qEntry = (profile.Data.quests and profile.Data.quests[QuestConfig.IDs.ONBOARDING])
		or { stage = "complete", archetype = nil }
	Remotes.QuestStateChanged:FireClient(player, {
		stage = qEntry.stage,
		chosenArchetype = qEntry.archetype,
		level = profile.Data.level or 1,
		crystalShards = profile.Data.crystalShards or 0,
		cardFragments = profile.Data.cardFragments or 0,
	})
end

local function commitVendorResult(player, profile, result)
	if not result.ok then return result end
	syncTitles(player, profile.Data)
	Dirty[player] = true
	fireCurrencyRefresh(player, profile)
	task.spawn(function()
		if profile:IsActive() then profile:Save() end
	end)
	return result
end

function SaveService.applyCardCraft(player, cardId, cost)
	local profile = Profiles[player]
	if not profile or not profile:IsActive() then
		return { ok = false, error = "Profile not loaded" }
	end
	local result = VendorTransaction.craft(profile.Data, cardId, cost)
	return commitVendorResult(player, profile, result)
end

function SaveService.applyCardBuy(player, cardId, cost)
	local profile = Profiles[player]
	if not profile or not profile:IsActive() then
		return { ok = false, error = "Profile not loaded" }
	end
	local result = VendorTransaction.buy(profile.Data, cardId, cost)
	return commitVendorResult(player, profile, result)
end

function SaveService.applyCardDestroy(player, requests)
	local profile = Profiles[player]
	if not profile or not profile:IsActive() then
		return { ok = false, error = "Profile not loaded" }
	end
	local result = VendorTransaction.destroy(profile.Data, requests)
	return commitVendorResult(player, profile, result)
end

-- ── Persisted Developer Product receipt grant (v5.1) ────────────────────────────
local function receiptWasPersisted(profile, purchaseId)
	local saved = profile.LastSavedData
	return type(saved) == "table"
		and type(saved.purchaseHistory) == "table"
		and saved.purchaseHistory[purchaseId] == true
end

local function waitForReceiptSave(profile, purchaseId)
	if receiptWasPersisted(profile, purchaseId) then return true end
	local gate = Instance.new("BindableEvent")
	local completed = false
	local confirmed = false
	local connection
	connection = profile.OnAfterSave:Connect(function(lastSavedData)
		local history = type(lastSavedData) == "table" and lastSavedData.purchaseHistory
		if not completed and type(history) == "table" and history[purchaseId] == true then
			confirmed = true
			completed = true
			gate:Fire()
		end
	end)
	task.delay(RECEIPT_SAVE_TIMEOUT, function()
		if not completed then
			completed = true
			gate:Fire()
		end
	end)
	local called = pcall(function() profile:Save() end)
	if called and not completed then gate.Event:Wait() end
	connection:Disconnect()
	gate:Destroy()
	return confirmed or receiptWasPersisted(profile, purchaseId)
end

function SaveService.applyDeveloperProductReceipt(player, purchaseId, productId, shardAmount)
	local profile = Profiles[player]
	if not profile or not profile:IsActive() then
		return { ok = false, error = "Profile not loaded", retry = true }
	end
	if ReceiptSaving[player] then
		return { ok = false, error = "Another receipt is being saved", retry = true }
	end
	ReceiptSaving[player] = purchaseId

	local result = ShopTransaction.grant(profile.Data, purchaseId, productId, shardAmount)
	if not result.ok then
		ReceiptSaving[player] = nil
		return result
	end

	Dirty[player] = true
	local persisted = waitForReceiptSave(profile, purchaseId)
	ReceiptSaving[player] = nil
	if not persisted then
		return {
			ok = false,
			error = "Receipt save was not confirmed",
			retry = true,
			crystalShards = profile.Data.crystalShards or 0,
		}
	end
	result.persisted = true
	return result
end

-- ── Init ────────────────────────────────────────────────────────────────────────
-- opts.mock = true binds to ProfileStore.Mock (headless tests; no real DataStore).
function SaveService.init(opts)
	if started then return SaveService end
	started = true
	opts = opts or {}
	attemptReconnectFn = opts.attemptReconnect

	Remotes = ReplicatedStorage:WaitForChild("Remotes")
	local store = ProfileStore.New(STORE_NAME, TEMPLATE)
	Store = opts.mock and store.Mock or store

	-- Connect FIRST, then sweep existing players, so a player joining during init
	-- is never missed (the load guard dedupes anyone caught by both paths).
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(onPlayerAdded, player)
	end

	-- Dirty-flag pooled autosave. ProfileStore's circular AUTO_SAVE_PERIOD (~300s)
	-- is the backstop; this flushes only profiles marked dirty, more responsively.
	task.spawn(function()
		while true do
			task.wait(DIRTY_FLUSH_INTERVAL)
			for player, profile in pairs(Profiles) do
				if Dirty[player] and profile:IsActive() then
					Dirty[player] = nil
					task.spawn(function()
						if profile:IsActive() then profile:Save() end
					end)
				end
			end
		end
	end)

	print(string.format("[SaveService] init (store=%s, schema v%d.%d)",
		opts.mock and "MOCK" or STORE_NAME, CURRENT_VERSION.major, CURRENT_VERSION.minor))
	return SaveService
end

return SaveService
