-- Battle engine (rebuilt for the effects[] system). State + turn flow + combat;
-- all card behavior is delegated to Effects/ (Ops mutations, Triggers bus).
local RS = game:GetService("ReplicatedStorage")
local SSS = game:GetService("ServerScriptService")
local Cards    = require(RS.Definitions.Cards)
local eff      = SSS.Modules.Effects
local Util     = require(eff.Util)
local Ops      = require(eff.Ops)
local Triggers = require(eff.Triggers)
local ChargeState = require(SSS.Modules.ChargeState)

local BattleLogic = {}
local BOARD = Util.BOARD_SIZE
local MAX_CAP, MAX_HAND, HERO_HP = 10, 10, 30

BattleLogic.opp = Util.opp
function BattleLogic.log(state, msg) Ops.log(state, msg) end
function BattleLogic.shuffle(t)
	for i = #t, 2, -1 do local j = math.random(1, i); t[i], t[j] = t[j], t[i] end
end

function BattleLogic.newSide(deckList)
	local deck = {}; for _, id in ipairs(deckList) do table.insert(deck, id) end
	local side = {
		hand = {}, deck = deck, discard = {}, board = {},
		heroHp = HERO_HP, maxHeroHp = HERO_HP, armor = 0,
		energy = 0, energyCap = 0, fatigue = 0,
		cardsPlayedThisTurn = 0, damageTakenThisGame = 0,
		deadAllies = {}, costMods = {}, chargeCostMods = {},
	}
	-- Two-slot hero Charge state (replaces Crystal Core). Independent of Energy/Armor/HP.
	ChargeState.init(side)
	return side
end
function BattleLogic.newBattle(pDeck, nDeck)
	return {
		player = BattleLogic.newSide(pDeck), npc = BattleLogic.newSide(nDeck),
		currentTurn = "player", turnNumber = 1, log = {}, discardHistory = {},
		pendingAnimEvents = {}, animSeq = 0,
	}
end

function BattleLogic.drawCard(state, who) return Ops.drawCard(state, who, {}) end
function BattleLogic.checkWin(state)
	if state.player.heroHp <= 0 then return "npc" end
	if state.npc.heroHp <= 0 then return "player" end
	return nil
end

local function baseCtx(state, who, extra)
	local c = { state = state, who = who, opp = Util.opp(who), Logic = Ops, fireEvent = Triggers.fireEvent }
	if extra then for k, v in pairs(extra) do c[k] = v end end
	return c
end

-- ── turn flow ──
function BattleLogic.startTurn(state, who)
	local side = state[who]
	Ops.recordAnim(state, { action = "turn_start", who = who, turnNumber = state.turnNumber })
	side.energyCap = math.min(MAX_CAP, (side.energyCap or 0) + 1)
	side.energy = side.energyCap
	side.cardsPlayedThisTurn = 0
	Ops.clearTurnCostMods(side)
	for i = 1, BOARD do
		local c = side.board[i]
		if c then c.attackedThisTurn = false; c.summonedThisTurn = false; c.tempAtk = 0 end
	end
	Ops.drawCard(state, who, {})
	Ops.log(state, who .. " starts turn " .. state.turnNumber .. " (" .. side.energy .. "/" .. side.energyCap .. " E, " .. side.heroHp .. " HP)")
end

function BattleLogic.endTurn(state, who)
	local side = state[who]
	for i = 1, BOARD do local c = side.board[i]; if c then c.tempAtk = 0 end end
	Triggers.fireEvent(state, "turn_end", baseCtx(state, who))
	for i = 1, BOARD do
		local cr = side.board[i]
		if cr and cr.battleType and cr.battleType ~= "NEUTRAL" then
			if ChargeState.canGainWithoutReplace(side, cr.battleType) then
				ChargeState.gainCharge(state, who, cr.battleType, 1, { reason = "board_end_turn", sourceSlot = i })
			end
		end
	end
	if state.turnNumber <= 2 then
		for i, id in ipairs(side.hand) do
			if id == "the_coin" then table.remove(side.hand, i); Ops.log(state, who .. "'s Coin vanishes"); break end
		end
	end
	Ops.log(state, "-- " .. who .. " ends turn --")
end

-- ── play a card ── opts = { slot = placementSlot (creatures), target = {side,slot} (chosen) }
function BattleLogic.playCard(state, who, cardId, opts)
	opts = opts or {}
	local side = state[who]
	local card = Cards[cardId]
	if not card then return false, "Unknown card" end
	local idx; for i, id in ipairs(side.hand) do if id == cardId then idx = i; break end end
	if not idx then return false, "Card not in hand" end
	local cost = Ops.effectiveCost(side, cardId, card.cost)
	if (side.energy or 0) < cost then return false, "Not enough Energy" end

	-- Charge cost: apply chargeCostMods (hand tax from add_additional_charge_cost_to_player_hand).
	local rawCc = card.chargeCost
	local cc = rawCc and Ops.effectiveChargeCost(side, cardId, rawCc) or nil
	if cc and not ChargeState.canSpendCharge(side, cc.battleType, cc.amount) then
		return false, "Not enough Charge"
	end
	local function payChargeCost()
		if cc then ChargeState.spendCharge(state, who, cc.battleType, cc.amount, { reason = "card_cost", cardId = cardId }) end
	end

	if card.cardType == "creature" then
		local slot = tonumber(opts.slot)
		if not slot or slot < 1 or slot > BOARD then return false, "Invalid slot" end
		if side.board[slot] then return false, "Slot occupied" end
		Ops.recordAnim(state, { action = "cast", who = who, cardId = cardId, cardType = "creature", target = opts.target, zone = opts.chosenZone })
		side.energy -= cost
		payChargeCost()
		table.remove(side.hand, idx)
		Ops.clearChargeCostMod(side, cardId, { keepIfStillInHand = true })
		side.cardsPlayedThisTurn += 1
		local inst = Ops.newInstance(card)
		side.board[slot] = inst
		Ops.recordAnim(state, { action = "summon", target = { side = who, slot = slot }, cardId = cardId })
		Ops.log(state, who .. " summons " .. card.name .. " (slot " .. slot .. ")")
		Triggers.fireEvent(state, "emerge", baseCtx(state, who, { source = inst, sourceSlot = slot, chosenTarget = opts.target, chosenZone = opts.chosenZone }))
		return true
	else
		-- Prerequisite gate: reject a spell that would do nothing before it is
		-- consumed, so the card stays in hand and Energy/Charge are kept.
		local blockReason = Triggers.playBlock(
			baseCtx(state, who, { source = card, chosenTarget = opts.target, chosenZone = opts.chosenZone }), card)
		if blockReason then return false, blockReason end
		Ops.recordAnim(state, { action = "cast", who = who, cardId = cardId, cardType = "spell", target = opts.target, zone = opts.chosenZone })
		side.energy -= cost
		payChargeCost()
		table.remove(side.hand, idx)
		Ops.clearChargeCostMod(side, cardId, { keepIfStillInHand = true })
		side.cardsPlayedThisTurn += 1
		Ops.log(state, who .. " plays " .. card.name)
		Triggers.fireEvent(state, "cast", baseCtx(state, who, { source = card, sourceSlot = nil, chosenTarget = opts.target, chosenZone = opts.chosenZone }))
		table.insert(side.discard, cardId)
		return true
	end
end

-- Crystal Core active skill removed (Phase 3). Hero powers are replaced by the
-- two-slot Charge system (see ChargeState / ChargeConfig). The UseCore remote is
-- left orphaned with no server handler, like other migration-artifact remotes.

-- ── combat ──
local function hasTaunt(side)
	for i = 1, BOARD do local c = side.board[i]; if c and Ops.hasKeyword(c, "taunt") then return true end end
	return false
end

function BattleLogic.attack(state, who, attackerSlot, targetSlot)
	local side = state[who]; local opp = Util.opp(who); local oppSide = state[opp]
	local attacker = side.board[attackerSlot]
	if not attacker then return false, "No attacker" end
	if attacker.attackedThisTurn then return false, "Already attacked" end
	if attacker.summonedThisTurn then return false, "Summoning sick" end
	if Util.attackOf(attacker) <= 0 then return false, "0 Attack" end

	state.lastTauntRedirect = false
	local tauntUp = hasTaunt(oppSide)
	local target
	if targetSlot and targetSlot ~= 0 then
		target = oppSide.board[targetSlot]
		if not target then return false, "No target there" end
		if Ops.hasKeyword(target, "stealth") then return false, "Target Stealthed" end
		if tauntUp and not Ops.hasKeyword(target, "taunt") then return false, "Must attack a Taunt" end
	else
		if tauntUp then return false, "Must attack a Taunt" end
	end

	attacker.attackedThisTurn = true
	if Ops.hasKeyword(attacker, "stealth") then Ops.removeKeyword(attacker, "stealth") end
	local atkVal = Util.attackOf(attacker)
	Ops.recordAnim(state, { action = "attack", who = who, attackerSlot = attackerSlot,
		target = target and { side = opp, slot = targetSlot } or { side = opp, slot = 0 } })

	if target then
		Triggers.fireEvent(state, "attacked", baseCtx(state, opp, { source = target, sourceSlot = targetSlot }))
		target = oppSide.board[targetSlot]
		local defAtk = target and Util.attackOf(target) or 0
		local quickstrike = Ops.hasKeyword(attacker, "quickstrike")
		local defLifesteal = target and Ops.hasKeyword(target, "lifesteal")
		Ops.damageCreature(state, { side = opp, slot = targetSlot }, atkVal,
			{ sourceWho = who, lifesteal = Ops.hasKeyword(attacker, "lifesteal"), fireEvent = Triggers.fireEvent })
		Triggers.fireEvent(state, "deal_damage", baseCtx(state, who, { source = attacker, sourceSlot = attackerSlot }))
		local defenderDead = (oppSide.board[targetSlot] == nil)
		if not (quickstrike and defenderDead) and defAtk > 0 then
			Ops.damageCreature(state, { side = who, slot = attackerSlot }, defAtk,
				{ sourceWho = opp, lifesteal = defLifesteal, fireEvent = Triggers.fireEvent })
		end
		Ops.log(state, who .. "'s " .. attacker.name .. " attacks " .. (target and target.name or "a creature"))
	else
		Ops.damageHero(state, opp, atkVal,
			{ sourceWho = who, lifesteal = Ops.hasKeyword(attacker, "lifesteal"), fireEvent = Triggers.fireEvent })
		Triggers.fireEvent(state, "deal_damage", baseCtx(state, who, { source = attacker, sourceSlot = attackerSlot }))
		Ops.log(state, who .. "'s " .. attacker.name .. " attacks the hero")
	end
	return true
end

return BattleLogic
