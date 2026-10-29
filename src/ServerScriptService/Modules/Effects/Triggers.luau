-- Central trigger bus. fireEvent gathers the relevant cards for an event and
-- runs their matching effects[] entries (condition-gated, targets resolved).
local Util       = require(script.Parent.Util)
local Conditions = require(script.Parent.Conditions)
local Targeting  = require(script.Parent.Targeting)
local Actions    = require(script.Parent.Actions)
local Triggers = {}

-- Player-facing warnings when an effect's condition gates it out, so a wasted
-- card gives feedback in the battle log. `chain` is a bonus gate (a Chain
-- payoff simply not being online), not a misplay, so it is intentionally
-- omitted -- no warning for it.
local CONDITION_FAIL_MSG = {
	friendly_damaged_exists = "No Wounded Ally",
	damaged = "Target not damaged",
	target_undamaged = "Target already at full health",
	attack_gte = "Target's Attack too low",
	attack_lte = "Target's Attack too high",
	two_charge_slots_occupied = "Requires two Charge slots",
}

local function derive(base, overrides)
	local c = {}
	for k, v in pairs(base) do c[k] = v end
	if overrides then for k, v in pairs(overrides) do c[k] = v end end
	return c
end

-- chain entries fire on the play moment (emerge/cast) when chain is active.
local function entryMatches(entry, eventName, base)
	if entry.trigger == eventName then return true end
	if entry.trigger == "chain" and (eventName == "emerge" or eventName == "cast") then
		return Conditions["chain"](base)
	end
	return false
end

-- Run one card's effects[] for an event. `card` = instance or definition.
function Triggers.runCard(base, card, eventName)
	if not (card and card.effects) then return end
	base.dynamic = base.dynamic or {}
	for _, entry in ipairs(card.effects) do
		if entryMatches(entry, eventName, base) then
			local ctx = derive(base, { entry = entry })
			ctx.targets = Targeting.resolve(ctx, entry)
			if Conditions.check(ctx, entry.condition) then
				local fn = Actions[entry.action] or Actions._default
				fn(ctx)
			end
		end
	end
end

-- Cost-pool targets resolve through their own actions, not the board, so an
-- empty board-target result doesn't mean "no target" for them.
local COST_POOL = { hand = true, drawn_cards = true, returned_card = true }

local function hasShatterEffect(creature)
	for _, eff in ipairs((creature and creature.effects) or {}) do
		if eff.trigger == "shatter" then return true end
	end
	return false
end

local function actionTargetOk(ctx, entry)
	if entry.action == "disable_shatter" then
		local t = ctx.targets and ctx.targets[1]
		if not t or t.slot == 0 then return false, "No valid Shatter target" end
		return hasShatterEffect(Util.getCreature(ctx.state, t)), "No valid Shatter target"
	end
	return (entry.target == nil) or COST_POOL[entry.target] or (#ctx.targets > 0), "No valid target"
end

-- Pre-play prerequisite check (spells). Dry-runs the effects WITHOUT executing
-- and returns a player-facing reason if NONE would resolve -- every entry's
-- condition fails or its required target is missing, i.e. the card would be
-- wasted. Returns nil if at least one effect will do something. Mirrors the
-- energy/taunt pre-checks in BattleLogic so a doomed play is rejected up front
-- (card stays in hand, energy unspent) instead of fizzling after the fact.
function Triggers.playBlock(base, card)
	if not (card and card.effects) then return nil end
	base.opp = base.opp or Util.opp(base.who)
	base.dynamic = base.dynamic or {}
	local reason = nil
	for _, entry in ipairs(card.effects) do
		if entryMatches(entry, "cast", base) then
			local ctx = derive(base, { entry = entry })
			ctx.targets = Targeting.resolve(ctx, entry)
			local condOk   = Conditions.check(ctx, entry.condition)
			local targetOk, targetReason = actionTargetOk(ctx, entry)
			if condOk and targetOk then
				return nil -- at least one effect resolves -> playable
			end
			if not reason then
				if not condOk and entry.condition then
					reason = CONDITION_FAIL_MSG[entry.condition.type]
				elseif not targetOk then
					reason = targetReason or "No valid target"
				end
			end
		end
	end
	return reason
end

-- base ctx must carry: state, who; and for source events: source, sourceSlot.
-- opp is derived. Logic/trace/chosenTarget/dynamic are passed through.
function Triggers.fireEvent(state, event, base)
	base.state = base.state or state
	base.opp = base.opp or Util.opp(base.who)

	if event == "emerge" or event == "cast" or event == "shatter" or event == "attacked"
		or event == "deal_damage" or event == "take_damage" then
		Triggers.runCard(base, base.source, event)
	elseif event == "turn_end" or event == "ally_death" then
		local side = state[base.who]
		for i = 1, Util.BOARD_SIZE do
			local m = side.board[i]
			if m then
				Triggers.runCard(derive(base, { source = m, sourceSlot = i }), m, event)
			end
		end
	end
end

return Triggers
