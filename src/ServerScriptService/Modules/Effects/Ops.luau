-- Game-operations layer: the primitive state mutations Actions (and the
-- reworked BattleLogic) call. Operates on the battle state shape. Fires
-- sub-triggers (shatter/ally_death) via an injected opts.fireEvent to avoid
-- a circular require with Triggers.
local Util = require(script.Parent.Util)
local Cards = require(game:GetService("ReplicatedStorage").Definitions.Cards)
local ChargeState = require(script.Parent.Parent.ChargeState)
local Ops = {}

local HAND = 10
local BOARD = Util.BOARD_SIZE

local function deepcopy(t)
	if type(t) ~= "table" then return t end
	local c = {}
	for k, v in pairs(t) do c[k] = deepcopy(v) end
	return c
end

function Ops.log(state, msg) if state and state.log then table.insert(state.log, msg) end end

-- ---- animatable event log (client presentation Director; PLAN_CARD_BATTLE_REVAMP) ----
-- One flat ordered list on the battle (not per-side): a card resolves, damages
-- an enemy, triggers a death, which triggers an ally-death heal -- all in one
-- causal sequence, so cross-side ordering matters. Mirrors ChargeState.recordEvent.
function Ops.recordAnim(state, ev)
	state.animSeq = (state.animSeq or 0) + 1
	ev.seq = state.animSeq
	state.pendingAnimEvents = state.pendingAnimEvents or {}
	state.pendingAnimEvents[#state.pendingAnimEvents + 1] = ev
	return ev
end

-- ---- keywords ----
function Ops.hasKeyword(m, kw)
	if not (m and m.keywords) then return false end
	for _, k in ipairs(m.keywords) do if k == kw then return true end end
	return false
end
function Ops.addKeyword(m, kw)
	if m and not Ops.hasKeyword(m, kw) then m.keywords = m.keywords or {}; table.insert(m.keywords, kw) end
	-- A granted Charge works like a printed one (newInstance): it lifts summoning sickness.
	if m and kw == "charge" then m.summonedThisTurn = false end
end
function Ops.removeKeyword(m, kw)
	if not (m and m.keywords) then return end
	for i, k in ipairs(m.keywords) do if k == kw then table.remove(m.keywords, i); return end end
end

-- ---- instances ----
function Ops.newInstance(def)
	local kw, hasCharge = {}, false
	if def.keywords then for _, k in ipairs(def.keywords) do kw[#kw+1] = k; if k == "charge" then hasCharge = true end end end
	return {
		cardId = def.id, name = def.name, battleType = def.battleType, race = def.race,
		atk = def.atk or 0, hp = def.hp or 1, maxHp = def.hp or 1, tempAtk = 0,
		keywords = kw, effects = deepcopy(def.effects or {}),
		attackedThisTurn = false, summonedThisTurn = not hasCharge, rebornUsed = false,
	}
end

-- ---- heal / armor ----
function Ops.healHero(state, who, amount)
	if not amount or amount <= 0 then return end
	local s = state[who]; s.heroHp = math.min(s.maxHeroHp or 30, s.heroHp + amount)
	Ops.recordAnim(state, { action = "heal", target = { side = who, slot = 0 }, amount = amount })
end
function Ops.healCreature(state, t, amount)
	local m = Util.getCreature(state, t); if not m or not amount or amount <= 0 then return end
	m.hp = math.min(m.maxHp, m.hp + amount)
	Ops.recordAnim(state, { action = "heal", target = { side = t.side, slot = t.slot }, amount = amount, cardId = m.cardId })
end
function Ops.gainArmor(state, who, amount)
	if not amount or amount <= 0 then return end
	local s = state[who]; s.armor = (s.armor or 0) + amount
	Ops.log(state, who .. " gains " .. amount .. " Armor (" .. s.armor .. ")")
	Ops.recordAnim(state, { action = "gain_armor", target = { side = who, slot = 0 }, amount = amount })
end

-- ---- damage ----
function Ops.damageHero(state, who, amount, opts)
	amount = math.max(0, amount or 0); if amount == 0 then return 0 end
	local s = state[who]
	local absorbed = math.min(s.armor or 0, amount); s.armor = (s.armor or 0) - absorbed
	local toHp = amount - absorbed
	s.heroHp = math.max(0, (s.heroHp or 0) - toHp)
	s.damageTakenThisGame = (s.damageTakenThisGame or 0) + amount
	Ops.recordAnim(state, { action = "damage", target = { side = who, slot = 0 }, amount = amount, lifesteal = opts and opts.lifesteal or nil })
	if opts and opts.lifesteal and opts.sourceWho then Ops.healHero(state, opts.sourceWho, amount) end
	return amount
end
function Ops.damageCreature(state, t, amount, opts)
	amount = math.max(0, amount or 0); if amount == 0 then return 0 end
	local m = Util.getCreature(state, t); if not m then return 0 end
	m.hp = m.hp - amount
	Ops.recordAnim(state, { action = "damage", target = { side = t.side, slot = t.slot }, amount = amount, cardId = m.cardId, lifesteal = opts and opts.lifesteal or nil })
	if opts and opts.lifesteal and opts.sourceWho then Ops.healHero(state, opts.sourceWho, amount) end
	if m.hp > 0 and opts and opts.fireEvent then
		opts.fireEvent(state, "take_damage", { state=state, who=t.side, source=m, sourceSlot=t.slot, Logic=Ops, fireEvent=opts.fireEvent })
	end
	if m.hp <= 0 then Ops.killCreature(state, t, opts) end
	return amount
end

-- ---- death (rebirth + shatter + ally_death) ----
function Ops.killCreature(state, t, opts)
	local side = state[t.side]; local m = side.board[t.slot]; if not m then return end
	local fire = opts and opts.fireEvent
	if fire and not m.shatterDisabled then fire(state, "shatter", { state = state, who = t.side, source = m, sourceSlot = t.slot, Logic = Ops, fireEvent = fire }) end
	if Ops.hasKeyword(m, "rebirth") and not m.rebornUsed then
		m.rebornUsed = true; Ops.removeKeyword(m, "rebirth"); m.hp = m.maxHp; m.tempAtk = 0
		Ops.log(state, m.name .. " is reborn (full)!")
		Ops.recordAnim(state, { action = "rebirth", target = { side = t.side, slot = t.slot }, cardId = m.cardId })
		return
	end
	side.board[t.slot] = nil
	table.insert(side.discard, m.cardId)
	side.deadAllies = side.deadAllies or {}
	table.insert(side.deadAllies, { cardId = m.cardId, name = m.name })
	Ops.log(state, side and (t.side .. "'s " .. m.name .. " dies!"))
	Ops.recordAnim(state, { action = "death", target = { side = t.side, slot = t.slot }, cardId = m.cardId })
	if fire then fire(state, "ally_death", { state = state, who = t.side, Logic = Ops, fireEvent = fire }) end
end

-- ---- buff ----
function Ops.buffCreature(state, t, atk, hp)
	local m = Util.getCreature(state, t); if not m then return end
	if atk then m.atk = m.atk + atk end
	if hp then m.maxHp = m.maxHp + hp; m.hp = m.hp + hp end
	if atk or hp then
		Ops.recordAnim(state, { action = "buff", target = { side = t.side, slot = t.slot }, atk = atk, hp = hp, cardId = m.cardId })
	end
end

-- ---- cards: draw / bounce / summon / graveyard ----
function Ops.drawCard(state, who, opts)
	local side = state[who]
	if #side.deck == 0 then
		side.fatigue = (side.fatigue or 0) + 1
		Ops.damageHero(state, who, side.fatigue, {})
		return nil
	end
	local idx = 1
	if opts and opts.filter and opts.filter.race then
		local matches = {}
		for i, id in ipairs(side.deck) do local d = Cards[id]; if d and d.race == opts.filter.race then matches[#matches+1] = i end end
		if #matches == 0 then return nil end
		idx = matches[math.random(1, #matches)]
	end
	if #side.hand >= HAND then table.remove(side.deck, idx); return nil end
	local id = table.remove(side.deck, idx)
	table.insert(side.hand, id)
	Ops.recordAnim(state, { action = "draw_card", who = who, cardId = id })
	return id
end
function Ops.bounce(state, t)
	local side = state[t.side]; local m = side.board[t.slot]; if not m then return end
	m.shatterDisabled = nil
	side.board[t.slot] = nil
	if #side.hand < HAND then table.insert(side.hand, m.cardId) end
	Ops.log(state, m.name .. " is returned to hand")
	Ops.recordAnim(state, { action = "bounce", target = { side = t.side, slot = t.slot }, cardId = m.cardId })
end
function Ops.summon(state, who, cardId, count)
	local def = Cards[cardId]; if not def then return end
	local side = state[who]
	for _ = 1, (count or 1) do
		local slot
		for i = 1, BOARD do if not side.board[i] then slot = i; break end end
		if not slot then break end
		side.board[slot] = Ops.newInstance(def)
		Ops.log(state, who .. " summons " .. def.name)
		Ops.recordAnim(state, { action = "summon", target = { side = who, slot = slot }, cardId = cardId })
	end
end
function Ops.returnFromGraveyard(state, who, mode)
	local side = state[who]
	if #side.discard == 0 then return nil end
	local i = math.random(1, #side.discard)  -- mode "random"
	local id = table.remove(side.discard, i)
	if #side.hand < HAND then table.insert(side.hand, id) else return nil end
	Ops.recordAnim(state, { action = "return_from_graveyard", who = who, cardId = id })
	return id
end

-- ---- cost modifiers (full system fleshed in Phase 4; mechanic lives here) ----
local function idSetForTarget(state, who, entry, dynamic)
	local ids = {}
	if entry.target == "hand" then
		for _, id in ipairs(state[who].hand) do ids[id] = true end
	elseif entry.target == "drawn_cards" then
		for _, id in ipairs((dynamic and dynamic.drawnCards) or {}) do ids[id] = true end
	elseif entry.target == "returned_card" then
		if dynamic and dynamic.returnedCard then ids[dynamic.returnedCard] = true end
	end
	return ids
end
function Ops.addCostMod(state, who, kind, entry, dynamic)
	local side = state[who]; side.costMods = side.costMods or {}
	table.insert(side.costMods, { kind = kind, value = entry.value, duration = entry.duration, ids = idSetForTarget(state, who, entry, dynamic) })
end
function Ops.effectiveCost(side, cardId, baseCost)
	local cost = baseCost
	for _, mod in ipairs(side.costMods or {}) do
		if mod.ids[cardId] then
			if mod.kind == "set" then cost = mod.value
			elseif mod.kind == "reduce" then cost = cost - (mod.value or 0) end
		end
	end
	return math.max(0, cost)
end
function Ops.clearTurnCostMods(side)
	if not side.costMods then return end
	for i = #side.costMods, 1, -1 do if side.costMods[i].duration == "this_turn" then table.remove(side.costMods, i) end end
end


function Ops.gainEnergy(state, who, amount)
	local s = state[who]; s.energy = (s.energy or 0) + (amount or 0)
	Ops.log(state, who .. " gains " .. (amount or 0) .. " Energy this turn")
end

-- ---- charge (two-slot hero Charge; delegates to ChargeState) ----
function Ops.gainCharge(state, who, battleType, amount, sourceInfo)
	return ChargeState.gainCharge(state, who, battleType, amount, sourceInfo)
end
function Ops.spendCharge(state, who, battleType, amount, sourceInfo)
	return ChargeState.spendCharge(state, who, battleType, amount, sourceInfo)
end
function Ops.canSpendCharge(side, battleType, amount)
	return ChargeState.canSpendCharge(side, battleType, amount)
end
function Ops.destroyChargeSlot(state, who, selector, sourceInfo)
	return ChargeState.destroySlot(state, who, selector, sourceInfo)
end
function Ops.drainCharge(state, who, selector, amount, sourceInfo)
	return ChargeState.drainCharge(state, who, selector, amount, sourceInfo)
end

-- ---- chargeCostMods (hand-tax from add_additional_charge_cost_to_player_hand) ----
function Ops.addChargeCostMod(state, who, cardId, value, remaining)
	local side = state[who]; side.chargeCostMods = side.chargeCostMods or {}
	table.insert(side.chargeCostMods, { cardId = cardId, value = value, remaining = remaining or 1 })
end
function Ops.clearChargeCostMod(side, cardId, opts)
	if not side.chargeCostMods then return end
	for i = #side.chargeCostMods, 1, -1 do
		local mod = side.chargeCostMods[i]
		if mod.cardId == cardId then
			if opts and opts.keepIfStillInHand then
				mod.remaining = (mod.remaining or 1) - 1
				if mod.remaining <= 0 then table.remove(side.chargeCostMods, i) end
			else
				table.remove(side.chargeCostMods, i)
			end
		end
	end
end
function Ops.effectiveChargeCost(side, cardId, rawCc)
	if not rawCc then return nil end
	local bonus = 0
	for _, mod in ipairs(side.chargeCostMods or {}) do
		if mod.cardId == cardId and (mod.remaining or 1) > 0 then bonus += (mod.value or 0) end
	end
	if bonus == 0 then return rawCc end
	return { battleType = rawCc.battleType, amount = rawCc.amount + bonus }
end

return Ops
