-- BattleController v5: thin remote-wiring layer.
-- Battle records: BattleRegistry. Turn loop: DuelSession. Tables/seating: TableManager.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SSS               = game:GetService("ServerScriptService")
local WS                = game:GetService("Workspace")

local Cards    = require(ReplicatedStorage.Definitions.Cards)
local Decks    = require(ReplicatedStorage.Definitions.Decks)
local Logic    = require(SSS.Modules.BattleLogic)
local Registry = require(SSS.Modules.BattleRegistry)
local Session  = require(SSS.Modules.DuelSession)
local Rewards  = require(SSS.Modules.RewardService)
local TblMgr   = require(SSS.Modules.TableManager)
local Save         = require(SSS.Modules.SaveService)
local QuestService = require(SSS.Modules.QuestService)
local QuestConfig  = require(ReplicatedStorage.Modules.QuestConfig)
local ServerRegistry = require(SSS.Modules.ServerRegistry)
local Matchmaker     = require(SSS.Modules.Matchmaker)
local Remotes  = ReplicatedStorage.Remotes

local npcKeys  = {"mighty","swift","vital"}
local BOARD_SIZE = 3

local TRAINER_ARCHETYPE = {
	["Trainer Mighty"] = "MIGHTY",
	["Trainer Swift"]  = "SWIFT",
	["Trainer Vital"]  = "VITAL",
}
local ARCHETYPE_DECK  = { MIGHTY="mighty", SWIFT="swift", VITAL="vital" }
local TUTORIAL_WEAK_DECK = { MIGHTY="vital", SWIFT="mighty", VITAL="swift" }
local tutorialPending = {}  -- [UserId] = true; cleared when startPvE consumes it

local remoteLast = {}
local REMOTE_COOLDOWN = {
	PlayCard         = 0.08,
	DeclareAttack    = 0.08,
	EndTurn          = 0.12,
	Forfeit          = 0.5,
	ReadyUp          = 0.25,
	StandUp          = 0.25,
	StartTrainerBattle = 1.0,
	ConfirmMulligan  = 0.5,
	JoinMatchmaking  = 1.0,
	CancelMatchmaking = 0.5,
}

local function checkRate(player, key)
	local now = os.clock()
	local uid = player.UserId
	local byUser = remoteLast[uid]
	if not byUser then byUser = {}; remoteLast[uid] = byUser end
	local cooldown = REMOTE_COOLDOWN[key] or 0.1
	local last = byUser[key]
	if last and now - last < cooldown then return false end
	byUser[key] = now
	return true
end

local function opp(seat) return seat == "player" and "npc" or "player" end
local function isConnectedPlayer(player)
	return player ~= nil and player.Parent == Players
end

local VALID_ZONES = {own_board=true,enemy_board=true,battle_board=true,own_side=true,enemy_side=true}
local function zoneCanonical(zone, who)
	local ene = opp(who)
	return ({
		own_board    = {scope="board", side=who},
		enemy_board  = {scope="board", side=ene},
		battle_board = {scope="battle"},
		own_side     = {scope="side",  side=who},
		enemy_side   = {scope="side",  side=ene},
	})[zone]
end

local function isBoardSlot(slot)
	return type(slot) == "number" and slot % 1 == 0 and slot >= 1 and slot <= BOARD_SIZE
end

local function isTargetDescriptor(t)
	return type(t) == "table"
		and (t.side == "player" or t.side == "npc")
		and type(t.slot) == "number"
		and t.slot % 1 == 0
		and t.slot >= 0
		and t.slot <= BOARD_SIZE
end

local function hasCreature(state, target)
	return target.slot ~= 0 and state[target.side] and state[target.side].board[target.slot] ~= nil
end

local function targetMatchesEntry(state, who, target, entry)
	local enemy = opp(who)
	local kind = entry.target
	if kind == "friendly_creature" then
		return target.side == who and hasCreature(state, target)
	elseif kind == "enemy_creature" then
		return target.side == enemy and hasCreature(state, target)
	elseif kind == "any_creature" then
		return hasCreature(state, target)
	elseif kind == "enemy_target" then
		return target.side == enemy and (target.slot == 0 or hasCreature(state, target))
	elseif kind == "own_hero" then
		return target.side == who and target.slot == 0
	end
	return false
end

local function cardNeedsChosenTarget(card)
	for _, entry in ipairs(card.effects or {}) do
		if (entry.area or "single") == "single" then
			local target = entry.target
			if target=="friendly_creature" or target=="enemy_creature" or target=="any_creature" or target=="enemy_target" then
				return true
			end
		end
	end
	return false
end

local function validateChosenTarget(state, who, card, target)
	if not isTargetDescriptor(target) then return false, "Invalid target" end
	if target.side ~= who and target.slot ~= 0 then
		local creature = state[opp(who)] and state[opp(who)].board[target.slot]
		if creature then
			for _, k in ipairs(creature.keywords or {}) do
				if k == "stealth" or k == "stealth_until_attack" then return false, "Target has Stealth" end
			end
		end
	end
	for _, entry in ipairs(card.effects or {}) do
		if (entry.area or "single") == "single" and targetMatchesEntry(state, who, target, entry) then return true end
	end
	return false, "Illegal target"
end

local function validatePlayCard(state, who, cardId, opts)
	if type(cardId) ~= "string" then return false, "Invalid card" end
	local card = Cards[cardId]; if not card then return false, "Unknown card" end
	local side = state[who]
	local inHand = false
	for _, id in ipairs(side.hand) do if id == cardId then inHand=true; break end end
	if not inHand then return false, "Card not in hand" end
	if type(opts) ~= "table" then opts = {slot=opts} end
	if card.cardType == "creature" then
		if not isBoardSlot(tonumber(opts.slot)) then return false, "Invalid slot" end
		if side.board[tonumber(opts.slot)] then return false, "Slot occupied" end
	elseif card.cardType == "spell" then
		if opts.slot ~= nil then return false, "Invalid spell slot" end
	else
		return false, "Invalid card type"
	end
	if opts.zone ~= nil then
		if not VALID_ZONES[opts.zone] then return false, "Invalid zone" end
		if card.playTarget ~= opts.zone then return false, "Zone mismatch" end
		opts.chosenZone = zoneCanonical(opts.zone, who)
	elseif opts.target ~= nil then
		local ok, err = validateChosenTarget(state, who, card, opts.target)
		if not ok then return false, err end
	elseif card.cardType == "spell" and cardNeedsChosenTarget(card) then
		return false, "Target required"
	end
	return true, nil, opts
end

local function validateAttack(state, who, attackerSlot, targetSlot)
	attackerSlot = tonumber(attackerSlot)
	targetSlot   = tonumber(targetSlot) or 0
	if not isBoardSlot(attackerSlot) then return false, "Invalid attacker" end
	if targetSlot % 1 ~= 0 or targetSlot < 0 or targetSlot > BOARD_SIZE then return false, "Invalid target" end
	return true, nil, attackerSlot, targetSlot
end

local function broadcast(battle, lastAction)
	for seatLabel, ref in pairs(battle.seats) do
		if ref.kind == "human" and isConnectedPlayer(ref.player) then
			Remotes.UpdateBattleState:FireClient(ref.player, Registry.viewFor(seatLabel, battle, lastAction))
		end
	end
	battle.state.warnings = nil
	battle.state.player.pendingChargeEvents = {}
	battle.state.npc.pendingChargeEvents = {}
	battle.state.pendingAnimEvents = {}
end

local function endBattle(battle, winner, reason)
	if battle.status == "ending" then return end
	battle.status = "ending"
	Session.cancel(battle)
	reason = reason or "win"

	for seatLabel, ref in pairs(battle.seats) do
		if ref.kind == "human" then
			local player = ref.player
			local ok, err = pcall(function()
				-- TableManager is keyed by UserId, so this also clears a disconnected
				-- player's stale seat mapping.
				TblMgr.unseatPlayer(player)
				local clientWinner = (winner == seatLabel) and "player" or "npc"
				local rewardPlan = Rewards.buildBattleRewards({
					battle = battle,
					winnerSeat = winner,
					recipientSeat = seatLabel,
					reason = reason,
				})
				-- SaveService.applyBattleRewards is the only place a reward plan
				-- turns into an actual currency/EXP mutation -- it owns the daily
				-- caps, the per-archetype NPC first-clear bonus, and EXP scaling,
				-- since those need player-persistent state RewardService never
				-- sees. Returns the *granted* (post-cap) amounts so the client
				-- displays what it actually received, not the pre-cap desired amount.
				local granted = rewardPlan and Save.applyBattleRewards(player, rewardPlan)
				if battle.mode == "pvp" then
					local won = winner == seatLabel
					local rec = Save.recordPvpResult(player, won)
					if granted then
						granted.message = (won and "Victory!" or "Defeat.")
							.. (rec and string.format("  Record: %dW / %dL", rec.wins, rec.losses) or "")
					end
				else
					Save.clearActiveMatch(player)
					if battle.isTutorial and isConnectedPlayer(player) then
						QuestService.setStage(player, QuestConfig.IDs.ONBOARDING, "complete")
					end
				end
				-- Early-forfeit cooldown ladder (Matchmaking category only) --
				-- penalizes only the forfeiting seat (the loser), never the
				-- opponent who benefits from the early-forfeit-win reward.
				-- TODO(DESIGN_REWARD.md §11): abuse-monitoring metrics (forfeiter/
				-- winner suspicious-pattern tracking) are not built yet -- only the
				-- cooldown ladder itself is implemented this pass.
				if reason == "forfeit" and seatLabel ~= winner and rewardPlan and rewardPlan.earlyForfeit and battle.matchmaking then
					Save.registerEarlyForfeit(player)
				end
				if isConnectedPlayer(player) then
					Remotes.BattleOver:FireClient(player, {
						winner = clientWinner,
						rewards = granted,
						exp = Save.getExpProgress(player),
						isTutorialComplete = battle.isTutorial or nil,
					})
				end
			end)
			if not ok then
				warn("[BattleController] player endBattle cleanup failed: " .. tostring(err))
			end
		end
	end

	if battle.tableId then
		local ok, err = pcall(TblMgr.markFree, battle.tableId)
		if not ok then
			warn("[BattleController] table cleanup failed: " .. tostring(err))
		end
	end
	local ok, err = pcall(Registry.destroy, battle)
	if not ok then
		warn("[BattleController] registry cleanup failed: " .. tostring(err))
	end
end

local function onBroadcast(battle, lastAction) broadcast(battle, lastAction) end
local function onBattleEnd(battle, winner, reason) endBattle(battle, winner, reason) end
local function onMulliganOffer(battle, seat, hand)
	local ref = battle.seats[seat]
	if ref and ref.kind == "human" and isConnectedPlayer(ref.player) then
		Remotes.OfferMulligan:FireClient(ref.player, hand)
	end
end

-- PLAN_MATCHMAKING Phase 4a: fires once mulligan begins -- the reconnect-
-- eligible point. Only local PvP (battle.mode=="pvp") and matchmaking-
-- originated battles (battle.matchmaking==true, covers both matchmaking PvP
-- and NPC-fallback PvE) get activeMatch/reconnect tracking; a normal
-- standing-Noob PvE battle never touches it, matching today's behavior.
local function onMatchStart(battle)
	if not (battle.mode == "pvp" or battle.matchmaking) then return end
	for _, ref in pairs(battle.seats) do
		if ref.kind == "human" then
			Save.beginMatch(ref.player, battle.id, game.JobId, battle.mode)
		end
	end
end

-- PLAN_MATCHMAKING Phase 4c: attempts to resume a still-live battle for a
-- player whose profile loaded with a stale activeMatch flag (they left
-- unresolved last session). Returns true if reconnect was attempted/handled
-- (SaveService then skips the abandonment penalty); false to fall through to
-- abandonment. Injected into SaveService.init below.
local function attemptReconnect(player, activeMatch)
	if activeMatch.jobId == game.JobId then
		-- Same server: the battle record may still be alive right here.
		local battle = Registry.get(activeMatch.battleId)
		if not battle or battle.status == "ending" then return false end
		local seat = Registry.canonicalSeatByUserId(battle, player.UserId)
		if not seat then return false end
		Registry.reconnectSeat(battle, seat, player)
		if battle.disconnectedSeats then battle.disconnectedSeats[seat] = nil end
		-- Re-seat physically. TableManager's playerTable/playerChair are keyed
		-- by UserId (survive the disconnect unchanged, per Phase 4b never
		-- calling unseatPlayer for a paused matchmaking battle), so the
		-- original chair is still authoritatively known.
		local chairIdx = TblMgr.getChairForPlayer(player)
		local tbl = battle.tableId and TblMgr.getTableById(battle.tableId)
		if tbl and chairIdx then TblMgr.seatPlayerAt(player, tbl, chairIdx) end
		-- Prime the client directly into the live battle -- BattleUIController
		-- has no existing entry point for "join mid-turn"; this bypasses the
		-- normal BattleSeated -> mulligan -> first UpdateBattleState sequence.
		Remotes.BattleReconnected:FireClient(player, Registry.viewFor(seat, battle, "other"))
		return true
	else
		-- Different server: attempt to teleport back. A stale/dead jobId
		-- doesn't error here (Roblox silently routes to a different/new public
		-- server instead) -- the destination server's own onPlayerAdded will
		-- see game.JobId ~= activeMatch.jobId in that case and correctly fall
		-- through to abandonment there instead. Returning true here just means
		-- "a reconnect attempt was made", not "it definitely succeeded".
		local teleportOptions = Instance.new("TeleportOptions")
		teleportOptions.ServerInstanceId = activeMatch.jobId
		teleportOptions.ShouldReserveServer = false
		local ok, err = pcall(function()
			game:GetService("TeleportService"):TeleportAsync(game.PlaceId, { player }, teleportOptions)
		end)
		if not ok then
			warn("[BattleController] attemptReconnect: TeleportAsync failed for " .. player.Name .. ": " .. tostring(err))
			return false
		end
		return true
	end
end

-- ── PvE start ─────────────────────────────────────────────────────────────────
local function startPvE(tbl)
	local human = tbl.chairs[1].player; if not human then return end
	local activeDeck, deckErr = Save.getActiveBattleDeck(human)
	if not activeDeck then
		warn("[BattleController] PvE blocked: " .. tostring(deckErr))
		Remotes.BattleUnseated:FireClient(human)
		TblMgr.unseatPlayer(human)
		return
	end
	local playerDeck = {}
	for _, id in ipairs(activeDeck.cards) do table.insert(playerDeck, id) end
	local npcDeckKey  = tbl._npcDeckKey or npcKeys[math.random(#npcKeys)]
	local isTutorial  = tutorialPending[human.UserId] == true
	tbl._npcDeckKey   = nil
	tutorialPending[human.UserId] = nil
	local npcDeck = {}
	for _, id in ipairs(Decks[npcDeckKey].cards) do table.insert(npcDeck, id) end
	local state  = Logic.newBattle(playerDeck, npcDeck)
	local seats  = {
		player = {kind="human", player=human, deckName=activeDeck.name},
		npc    = {kind="npc",   deckKey=npcDeckKey},
	}
	local battle = Registry.create(state, seats, tbl.tableId)
	battle.meaningfulActions = { player = 0, npc = 0 } -- DESIGN_REWARD.md validity gate (turn 4 OR 2+ actions)
	battle.mode       = "pve"
	battle.difficulty = "noob"
	battle.isTutorial = isTutorial
	-- PLAN_MATCHMAKING: NPC-fallback matches (Phase 3) are structurally a PvE
	-- battle, but still matchmaking-originated -- Phase 4 reconnect gating
	-- checks this flag the same way it does on startPvP.
	battle.matchmaking = tbl._matchmaking or false
	tbl._matchmaking = nil
	TblMgr.markOccupied(tbl, battle.id)
	Session.start(battle, onBroadcast, onBattleEnd, onMulliganOffer, onMatchStart)
end

-- ── PvP start ─────────────────────────────────────────────────────────────────
local function startPvP(tbl)
	local p1 = tbl.chairs[1].player; local p2 = tbl.chairs[2].player
	if not p1 or not p2 then return end
	local active1, err1 = Save.getActiveBattleDeck(p1)
	local active2, err2 = Save.getActiveBattleDeck(p2)
	if not active1 or not active2 then
		warn("[BattleController] PvP blocked: " .. tostring(err1 or err2))
		if p1 then Remotes.BattleUnseated:FireClient(p1); TblMgr.unseatPlayer(p1) end
		if p2 then Remotes.BattleUnseated:FireClient(p2); TblMgr.unseatPlayer(p2) end
		return
	end
	local function deckFor(active) local out={} for _,id in ipairs(active.cards) do table.insert(out,id) end return out end
	local deck1, deck2 = deckFor(active1), deckFor(active2)
	local state  = Logic.newBattle(deck1, deck2)
	local seats  = {
		player = {kind="human", player=p1, deckName=active1.name},
		npc    = {kind="human", player=p2, deckName=active2.name},
	}
	local battle = Registry.create(state, seats, tbl.tableId)
	battle.meaningfulActions = { player = 0, npc = 0 } -- DESIGN_REWARD.md validity gate (turn 4 OR 2+ actions)
	battle.mode = "pvp"
	-- PLAN_MATCHMAKING: distinguishes a matchmaking-originated battle from a
	-- local same-server ReadyUp battle -- Phase 4 gates reconnect eligibility
	-- on this flag, not on battle.mode alone (which covers both).
	battle.matchmaking = tbl._matchmaking or false
	tbl._matchmaking = nil
	-- activeMatch/jobId persistence moved to onMatchStart (mulligan-start time,
	-- PLAN_MATCHMAKING Phase 4a) -- no longer called here at Registry.create time.
	TblMgr.markOccupied(tbl, battle.id)
	Session.start(battle, onBroadcast, onBattleEnd, onMulliganOffer, onMatchStart)
end

-- ── Matchmaking: destination-side seating (PLAN_MATCHMAKING Phase 2) ─────────────
-- Called every poll tick. For each match record this server is the
-- destination for, seats any currently-present participants and starts the
-- battle once both are here. NPC-fallback records (Phase 3) are skipped here.
local PARTIAL_ARRIVAL_TIMEOUT = 30
local partialArrivalStarted = {} -- [matchId] = os.clock()

local function seatNpcFallbackMatch(matchId, player)
	if Registry.getForPlayer(player) or TblMgr.getTableForPlayer(player) then
		partialArrivalStarted[matchId] = nil
		Matchmaker.clearMatch(matchId)
		return true
	end

	local tbl = TblMgr.findFreeTable()
	if not tbl then
		return false
	end

	tbl._matchmaking = true
	local seated = TblMgr.seatPlayerAt(player, tbl, 1)
	if not seated then
		tbl._matchmaking = nil
		if TblMgr.getTableForPlayer(player) then
			TblMgr.unseatPlayer(player)
		end
		return false
	end

	partialArrivalStarted[matchId] = nil
	Matchmaker.clearMatch(matchId)
	if isConnectedPlayer(player) then
		Remotes.MatchmakingUpdate:FireClient(player, "matched")
	end
	TblMgr.spawnNpcAt(tbl, 2)
	startPvE(tbl)
	return true
end

local function attemptSeatPendingMatches()
	for _, entry in ipairs(Matchmaker.getMatchesForThisServer()) do
		local matchId, record = entry.matchId, entry.record
		if record.npcFallback then
			local player = Players:GetPlayerByUserId(record.participantUserIds[1])
			if player then
				seatNpcFallbackMatch(matchId, player)
			end
			continue
		end

		local userId1 = record.participantUserIds[1]
		local userId2 = record.participantUserIds[2]
		local player1 = userId1 and Players:GetPlayerByUserId(userId1)
		local player2 = userId2 and Players:GetPlayerByUserId(userId2)

		if player1 and player2 then
			partialArrivalStarted[matchId] = nil
			if Registry.getForPlayer(player1) or Registry.getForPlayer(player2)
				or TblMgr.getTableForPlayer(player1) or TblMgr.getTableForPlayer(player2)
			then
				Matchmaker.clearMatch(matchId)
				continue
			end

			local tbl = TblMgr.findFreeTable()
			if not tbl then
				continue
			end

			tbl._matchmaking = true
			local seated1 = TblMgr.seatPlayerAt(player1, tbl, 1)
			local seated2 = seated1 and TblMgr.seatPlayerAt(player2, tbl, 2)
			if seated1 and seated2 then
				Matchmaker.clearMatch(matchId)
				Remotes.MatchmakingUpdate:FireClient(player1, "matched")
				Remotes.MatchmakingUpdate:FireClient(player2, "matched")
				startPvP(tbl)
			else
				tbl._matchmaking = nil
				if TblMgr.getTableForPlayer(player1) then TblMgr.unseatPlayer(player1) end
				if TblMgr.getTableForPlayer(player2) then TblMgr.unseatPlayer(player2) end
			end
		elseif player1 or player2 then
			local arrived = player1 or player2
			local missingUserId = player1 and userId2 or userId1
			local startedAt = partialArrivalStarted[matchId]
			if not startedAt then
				partialArrivalStarted[matchId] = os.clock()
			elseif os.clock() - startedAt >= PARTIAL_ARRIVAL_TIMEOUT then
				local converted = Matchmaker.convertPartialToNpc(
					matchId,
					arrived.UserId,
					missingUserId
				)
				if converted then
					seatNpcFallbackMatch(matchId, arrived)
				end
			end
		else
			partialArrivalStarted[matchId] = nil
		end
	end
end

-- ── StartTrainerBattle ────────────────────────────────────────────────────────
Remotes.StartTrainerBattle.OnServerEvent:Connect(function(player, trainerName)
	if not checkRate(player, "StartTrainerBattle") then return end
	if type(trainerName) ~= "string" then return end
	if QuestService.getStage(player, QuestConfig.IDs.ONBOARDING) ~= "complete" then return end
	local archetype = TRAINER_ARCHETYPE[trainerName]; if not archetype then return end
	if Registry.getForPlayer(player) then return end
	if TblMgr.getTableForPlayer(player) then return end
	TblMgr.handleTalkToNpc(player, ARCHETYPE_DECK[archetype], trainerName)
end)

-- ── ChooseStarterDeck ────────────────────────────────────────────────────────
Remotes.ChooseStarterDeck.OnServerEvent:Connect(function(player, trainerModelName)
	if type(trainerModelName) ~= "string" then return end
	if QuestService.getStage(player, QuestConfig.IDs.ONBOARDING) ~= "find_trainer" then return end
	local archetype = trainerModelName:match("Trainer (%a+)")
	if not archetype then return end
	archetype = archetype:upper()
	if not TUTORIAL_WEAK_DECK[archetype] then return end
	local ok, err = Save.grantStarterDeck(player, archetype)
	if not ok then warn("[BattleController] grantStarterDeck: " .. tostring(err)); return end
	local activeDeck, deckErr = Save.getActiveBattleDeck(player)
	if not activeDeck then warn("[BattleController] starter deck activation failed: " .. tostring(deckErr)); return end
	QuestService.setStage(player, QuestConfig.IDs.ONBOARDING, "deck_chosen", archetype)
end)

-- ── RequestTutorialBattle ─────────────────────────────────────────────────────
-- JoinMatchmaking / CancelMatchmaking (PLAN_MATCHMAKING Phase 5)
Remotes.JoinMatchmaking.OnServerEvent:Connect(function(player)
	if not checkRate(player, "JoinMatchmaking") then return end
	if Registry.getForPlayer(player) or TblMgr.getTableForPlayer(player) then return end
	local cooldownRemaining = Save.getMatchmakingCooldownRemaining(player)
	if cooldownRemaining > 0 then
		Remotes.Notify:FireClient(player, string.format(
			"Matchmaking cooldown: %dm %ds remaining (too many early forfeits today).",
			math.floor(cooldownRemaining / 60), math.floor(cooldownRemaining % 60)))
		return
	end
	if Matchmaker.isQueued(player) then
		Remotes.MatchmakingUpdate:FireClient(player, "queued")
		return
	end
	local enqueued = Matchmaker.enqueue(player)
	if enqueued then
		Remotes.MatchmakingUpdate:FireClient(player, "queued")
	end
end)

Remotes.CancelMatchmaking.OnServerEvent:Connect(function(player)
	if not checkRate(player, "CancelMatchmaking") then return end
	local cancelled = Matchmaker.dequeue(player)
	if cancelled then
		Remotes.MatchmakingUpdate:FireClient(player, "cancelled")
	end
end)

Remotes.RequestTutorialBattle.OnServerEvent:Connect(function(player)
	if QuestService.getStage(player, QuestConfig.IDs.ONBOARDING) ~= "deck_chosen" then return end
	if Registry.getForPlayer(player) then return end
	if TblMgr.getTableForPlayer(player) then return end
	local archetype = QuestService.getArchetype(player, QuestConfig.IDs.ONBOARDING)
	if not archetype then return end
	local npcDeckKey = TUTORIAL_WEAK_DECK[archetype]
	if not npcDeckKey then return end
	tutorialPending[player.UserId] = true
	local started = TblMgr.handleTalkToNpc(player, npcDeckKey)
	if not started then tutorialPending[player.UserId] = nil end
end)

-- ── Init SaveService ──────────────────────────────────────────────────────────
Save.init({ attemptReconnect = attemptReconnect })

-- Initialize physical tables before publishing capacity or starting matchmaking.
TblMgr.init({
	Remotes = Remotes,
	onStartPvE = startPvE,
	onStartPvP = startPvP,
	getBattleForPlayer = function(player)
		return Registry.getForPlayer(player)
	end,
})

-- Server registry is a hint; destination seating still re-validates real state.
ServerRegistry.init(TblMgr.countFree)

-- Empty servers perform no queue reads. The protected loop survives transient
-- MemoryStore/teleport failures, and jitter avoids synchronized universe-wide bursts.
task.spawn(function()
	while true do
		task.wait(4 + math.random() * 2)
		local ok, err = pcall(function()
			local updates = Matchmaker.processPendingTeleportsForPlayers(Players:GetPlayers())
			for _, update in ipairs(updates) do
				if isConnectedPlayer(update.player) then
					Remotes.MatchmakingUpdate:FireClient(update.player, update.status)
				end
			end

			if Matchmaker.hasLocalQueuedPlayers() then
				local result, entryA, entryBOrReadId, pairReadId = Matchmaker.tryMatch()
				if result == "pair" then
					local entryB = entryBOrReadId
					local matchId, reason = Matchmaker.createMatch(entryA, entryB)
					if matchId then
						Matchmaker.consume(pairReadId)
					elseif reason ~= "no_public_destination" and reason ~= "participant_not_queued" then
						warn(string.format(
							"[Matchmaker] createMatch failed for userId=%d / userId=%d: %s",
							entryA.userId,
							entryB.userId,
							tostring(reason)
						))
					end
				elseif result == "single" then
					local readId = entryBOrReadId
					local waited = os.time() - (entryA.queuedAt or os.time())
					if waited >= 60 then
						local matchId, reason = Matchmaker.createNpcFallbackMatch(entryA)
						if matchId then
							Matchmaker.consume(readId)
						elseif reason ~= "no_public_destination" and reason ~= "participant_not_queued" then
							warn(string.format(
								"[Matchmaker] NPC fallback failed for userId=%d: %s",
								entryA.userId,
								tostring(reason)
							))
						end
					end
				end
			end

			attemptSeatPendingMatches()
		end)
		if not ok then
			warn("[Matchmaker] poll iteration failed: " .. tostring(err))
		end
	end
end)

Remotes.GetQuestSnapshot.OnServerInvoke = function(player)
	local snap = Save.getFullSnapshot(player)
	if not snap then return nil end
	local q = snap.quests[QuestConfig.IDs.ONBOARDING] or { stage = "complete" }
	return { stage = q.stage, chosenArchetype = q.archetype, level = snap.level, crystalShards = snap.crystalShards, cardFragments = snap.cardFragments }
end

-- ── Wire Noob TalkPrompt ──────────────────────────────────────────────────────
task.defer(function()
	local noob = WS:FindFirstChild("Noob")
	local hrp  = noob and noob:FindFirstChild("HumanoidRootPart")
	local pp   = hrp  and hrp:FindFirstChild("TalkPrompt")
	if pp then
		pp.Triggered:Connect(function(player)
			local stage = QuestService.getStage(player, QuestConfig.IDs.ONBOARDING)
			if stage ~= "complete" then
				Remotes.ShowNoobDialogue:FireClient(player, stage)
				-- Advance intro → find_trainer on first Noob contact
				if stage == "intro" then
					QuestService.setStage(player, QuestConfig.IDs.ONBOARDING, "find_trainer")
				end
				return
			end
			TblMgr.handleTalkToNpc(player)
		end)
		print("[BattleController] Noob TalkPrompt wired")
	else
		warn("[BattleController] Noob TalkPrompt not found — PvE entry unavailable")
	end
end)

-- ── StandUp ───────────────────────────────────────────────────────────────────
Remotes.StandUp.OnServerEvent:Connect(function(player)
	if not checkRate(player, "StandUp") then return end
	TblMgr.handleStandUp(player)
end)

-- ── ReadyUp ───────────────────────────────────────────────────────────────────
Remotes.ReadyUp.OnServerEvent:Connect(function(player)
	if not checkRate(player, "ReadyUp") then return end
	TblMgr.handleReadyUp(player)
end)

-- ── ConfirmMulligan ───────────────────────────────────────────────────────────
Remotes.ConfirmMulligan.OnServerEvent:Connect(function(player)
	if not checkRate(player, "ConfirmMulligan") then return end
	local battle = Registry.getForPlayer(player)
	if not battle or battle.status ~= "mulligan" then return end
	local seat = Registry.canonicalSeat(player, battle)
	if not seat then return end
	Session.confirmMulligan(battle, seat, onBroadcast, onBattleEnd)
end)

-- ── RedrawMulliganCard ────────────────────────────────────────────────────────
Remotes.RedrawMulliganCard.OnServerInvoke = function(player, idx)
	local battle = Registry.getForPlayer(player)
	if not battle or battle.status ~= "mulligan" then return false, "Not in mulligan" end
	local seat = Registry.canonicalSeat(player, battle)
	if not seat then return false, "No seat" end
	return Session.redrawMulliganCard(battle, seat, idx)
end

-- ── PlayCard ──────────────────────────────────────────────────────────────────
Remotes.PlayCard.OnServerEvent:Connect(function(player, cardId, opts)
	if not checkRate(player, "PlayCard") then return end
	local battle = Registry.getForPlayer(player)
	if not battle or battle.status ~= "active" then return end
	local seat = Registry.canonicalSeat(player, battle)
	if not seat or battle.state.currentTurn ~= seat then return end
	if type(opts) ~= "table" then opts = {slot=opts} end
	opts = Registry.remapOpts(seat, opts)
	local valid, validationErr, cleanOpts = validatePlayCard(battle.state, seat, cardId, opts)
	if not valid then
		local w = battle.state.warnings or {}; w[#w+1]=tostring(validationErr or "Invalid action")
		battle.state.warnings = w; broadcast(battle, "other"); return
	end
	local ok, err = Logic.playCard(battle.state, seat, cardId, cleanOpts)
	if not ok then local w = battle.state.warnings or {}; w[#w+1]=tostring(err); battle.state.warnings = w
	else battle.meaningfulActions[seat] = (battle.meaningfulActions[seat] or 0) + 1 end
	Session.afterHumanAction(battle, "play_card", onBroadcast, onBattleEnd)
end)

-- ── DeclareAttack ─────────────────────────────────────────────────────────────
Remotes.DeclareAttack.OnServerEvent:Connect(function(player, attackerSlot, targetSlot)
	if not checkRate(player, "DeclareAttack") then return end
	local battle = Registry.getForPlayer(player)
	if not battle or battle.status ~= "active" then return end
	local seat = Registry.canonicalSeat(player, battle)
	if not seat or battle.state.currentTurn ~= seat then return end
	local valid, validationErr, cleanAttackerSlot, cleanTargetSlot = validateAttack(battle.state, seat, attackerSlot, targetSlot)
	if not valid then
		local w = battle.state.warnings or {}; w[#w+1]=tostring(validationErr or "Invalid attack")
		battle.state.warnings = w; broadcast(battle, "other"); return
	end
	local ok, err = Logic.attack(battle.state, seat, cleanAttackerSlot, cleanTargetSlot)
	if not ok then local w = battle.state.warnings or {}; w[#w+1]=tostring(err); battle.state.warnings = w
	else battle.meaningfulActions[seat] = (battle.meaningfulActions[seat] or 0) + 1 end
	Session.afterHumanAction(battle, "attack", onBroadcast, onBattleEnd)
end)

-- ── EndTurn ───────────────────────────────────────────────────────────────────
Remotes.EndTurn.OnServerEvent:Connect(function(player)
	if not checkRate(player, "EndTurn") then return end
	local battle = Registry.getForPlayer(player)
	if not battle or battle.status ~= "active" then return end
	local seat = Registry.canonicalSeat(player, battle)
	if not seat or battle.state.currentTurn ~= seat then return end
	Session.humanEndTurn(battle, seat, onBroadcast, onBattleEnd)
end)

-- ── Forfeit ───────────────────────────────────────────────────────────────────
Remotes.Forfeit.OnServerEvent:Connect(function(player)
	if not checkRate(player, "Forfeit") then return end
	local battle = Registry.getForPlayer(player); if not battle then return end
	local seat = Registry.canonicalSeat(player, battle); if not seat then return end
	endBattle(battle, (seat == "player") and "npc" or "player", "forfeit")
end)

-- ── Cleanup on disconnect ─────────────────────────────────────────────────────
-- PLAN_MATCHMAKING Phase 4b: a matchmaking-originated battle (real match or
-- NPC-fallback) no longer forfeits on disconnect -- it's PAUSED instead. The
-- existing turn-timeout/streak machinery (DuelSession, unchanged) becomes the
-- only forfeit trigger; a reconnect (SaveService.onPlayerAdded -> attemptReconnect,
-- Phase 4c) can resume this exact battle. Crucially, Registry.removePlayer is
-- skipped for the paused case -- it would wipe PlayerBattle[userId], which the
-- reconnect lookup depends on staying intact.
-- Local (non-matchmaking) PvP and normal PvE keep today's exact behavior:
-- instant forfeit, immediate cleanup.
Players.PlayerRemoving:Connect(function(player)
	Matchmaker.onPlayerRemoving(player)
	local battle = Registry.getForPlayer(player)
	if battle then
		if battle.matchmaking and battle.status ~= "ending" then
			local seat = Registry.canonicalSeat(player, battle)
			if seat then
				battle.disconnectedSeats = battle.disconnectedSeats or {}
				battle.disconnectedSeats[seat] = true
			end
			-- Deliberately no endBattle/Registry.removePlayer here -- see comment above.
		else
			local seat = Registry.canonicalSeat(player, battle)
			endBattle(battle, seat and ((seat=="player") and "npc" or "player") or "npc", "forfeit")
			Registry.removePlayer(player)
		end
	elseif TblMgr.getTableForPlayer(player) then
		TblMgr.unseatPlayer(player)
		Registry.removePlayer(player)
	else
		Registry.removePlayer(player)
	end
	remoteLast[player.UserId]     = nil
	tutorialPending[player.UserId] = nil
end)

print("[BattleController v5] Loaded — TableManager wired, Noob PvE + table PvP + Trainer PvE active.")
