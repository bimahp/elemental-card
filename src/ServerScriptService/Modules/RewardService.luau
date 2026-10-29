-- RewardService: pure battle-reward classifier (DESIGN_REWARD.md).
-- Never touches profile data -- SaveService.applyBattleRewards is the only
-- place a RewardService payload turns into an actual currency/EXP mutation
-- (daily caps, per-archetype first-clear bonus, and EXP scaling all live
-- there, since they require player-persistent state this module never sees).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RewardConfig = require(ReplicatedStorage.Modules.RewardConfig)

local RewardService = {}

local function seatHasHuman(battle, seat)
	local ref = battle.seats and battle.seats[seat]
	return ref and ref.kind == "human"
end

local function opp(seat)
	return seat == "player" and "npc" or "player"
end

-- Matchmaking (real matchmaking PvP or NPC-fallback) / Local (non-
-- matchmaking PvP) / NPC (Trainer or standing-Noob PvE). See
-- DESIGN_REWARD.md's Battle Mode Categories table. Confirmed with the user:
-- NPC-fallback pays Matchmaking rate, not NPC rate, since it went through
-- the real matchmaking flow.
local function category(battle)
	if battle.matchmaking then return "matchmaking" end
	if battle.mode == "pvp" then return "local" end
	return "npc"
end

local function isValid(battle, seat)
	local turnNumber = (battle.state and battle.state.turnNumber) or 1
	local actions = (battle.meaningfulActions and battle.meaningfulActions[seat]) or 0
	return turnNumber >= RewardConfig.VALID_TURN or actions >= RewardConfig.VALID_ACTIONS
end

-- Opponent's deck archetype (MIGHTY/SWIFT/VITAL), used for the NPC
-- category's per-archetype first-clear bonus. Works uniformly for the
-- standing Noob (random deckKey), Trainer battles (fixed deckKey), and the
-- tutorial (TUTORIAL_WEAK_DECK) -- all three set seats.npc.deckKey via
-- BattleController.startPvE.
local function npcArchetype(battle)
	for _, ref in pairs(battle.seats or {}) do
		if ref.kind == "npc" and ref.deckKey then
			return string.upper(ref.deckKey)
		end
	end
	return nil
end

-- ctx = { battle, winnerSeat, recipientSeat, reason }
-- reason: "win" (default, a normal decisive end) or "forfeit" (explicit
-- Forfeit press, or a 2-consecutive-timeout AFK-forfeit -- see DuelSession's
-- scheduleHumanTimer, which is functionally identical for reward purposes).
-- Returns nil if the recipient seat isn't a present human (nothing to
-- reward), otherwise an unpersisted plan for SaveService.applyBattleRewards:
-- { mode, category, outcome, forfeited, earlyForfeit, valid,
--   baseCardFragments, archetype }
function RewardService.buildBattleRewards(ctx)
	local battle = ctx.battle
	local winnerSeat = ctx.winnerSeat
	local recipientSeat = ctx.recipientSeat
	local reason = ctx.reason or "win"

	if not seatHasHuman(battle, recipientSeat) then return nil end

	local cat = category(battle)
	local isWinner = recipientSeat == winnerSeat

	if cat == "matchmaking" then
		if reason == "forfeit" then
			-- Forfeiter is always the losing seat. Early vs. late is judged by
			-- whether *the forfeiter* had reached validity yet -- both
			-- recipients (forfeiter and opponent) share this one flag, per
			-- DESIGN_REWARD.md §9.
			local forfeiterSeat = opp(winnerSeat)
			local earlyForfeit = not isValid(battle, forfeiterSeat)
			local isForfeiter = recipientSeat == forfeiterSeat
			local base
			if isForfeiter then
				base = earlyForfeit and RewardConfig.MATCHMAKING.earlyForfeiter or RewardConfig.MATCHMAKING.loss
			else
				base = earlyForfeit and RewardConfig.MATCHMAKING.earlyForfeitWin or RewardConfig.MATCHMAKING.win
			end
			return {
				mode = battle.mode, category = cat,
				outcome = isForfeiter and "loss" or "win",
				forfeited = true, earlyForfeit = earlyForfeit, valid = true,
				baseCardFragments = base,
			}
		end

		-- Normal (non-forfeit) end: each recipient's own validity gates their
		-- own reward independently (DESIGN_REWARD.md §8) -- a decisive win/loss
		-- that resolves before turn 4 with too few actions from this recipient
		-- grants nothing, regardless of who actually won.
		local valid = isValid(battle, recipientSeat)
		local base = 0
		if valid then
			base = isWinner and RewardConfig.MATCHMAKING.win or RewardConfig.MATCHMAKING.loss
		end
		return {
			mode = battle.mode, category = cat,
			outcome = isWinner and "win" or "loss",
			forfeited = false, valid = valid,
			baseCardFragments = base,
		}
	end

	if cat == "local" then
		local base = isWinner and RewardConfig.LOCAL.win or RewardConfig.LOCAL.loss
		return {
			mode = battle.mode, category = cat,
			outcome = isWinner and "win" or "loss",
			forfeited = (reason == "forfeit"), valid = true,
			baseCardFragments = base,
		}
	end

	-- cat == "npc"
	local base = isWinner and RewardConfig.NPC.win or RewardConfig.NPC.loss
	return {
		mode = battle.mode, category = cat,
		outcome = isWinner and "win" or "loss",
		forfeited = (reason == "forfeit"), valid = true,
		baseCardFragments = base,
		archetype = isWinner and npcArchetype(battle) or nil,
	}
end

return RewardService
