-- Action registry (real behavior). Actions mutate state via ctx.Logic (= Ops,
-- injected) and fire sub-triggers via ctx.fireEvent. ctx fields:
--   state, who, opp, source, sourceSlot, entry, targets, chosenTarget,
--   dynamic (shared scratch across one card's entries), Logic, fireEvent, trace
local Util = require(script.Parent.Util)
local Cards = require(game:GetService("ReplicatedStorage").Definitions.Cards)
local Actions = {}

local function dmgOpts(ctx)
	return { sourceWho = ctx.who, lifesteal = ctx.entry.lifesteal, fireEvent = ctx.fireEvent }
end
local function hit(ctx, t, amount)
	if not t then return end
	if t.slot == 0 then ctx.Logic.damageHero(ctx.state, t.side, amount, dmgOpts(ctx))
	else ctx.Logic.damageCreature(ctx.state, t, amount, dmgOpts(ctx)) end
end

Actions.damage = function(ctx)
	local e = ctx.entry
	local amount = Util.valueOf(ctx, e)
	local area = e.area or "single"
	if area == "all" then
		for _, t in ipairs(ctx.targets) do hit(ctx, t, amount) end
	elseif area == "split" then
		for _ = 1, amount do
			local live = {}
			for _, t in ipairs(ctx.targets) do if Util.getCreature(ctx.state, t) then live[#live+1] = t end end
			if #live == 0 then break end
			hit(ctx, live[math.random(1, #live)], 1)
		end
	else
		hit(ctx, ctx.targets[1], amount)
	end
end

Actions.heal = function(ctx)
	local amount = Util.valueOf(ctx, ctx.entry)
	for _, t in ipairs(ctx.targets) do
		if t.slot == 0 then ctx.Logic.healHero(ctx.state, t.side, amount)
		else ctx.Logic.healCreature(ctx.state, t, amount) end
	end
end

Actions.gain_armor = function(ctx)
	ctx.Logic.gainArmor(ctx.state, ctx.who, Util.valueOf(ctx, ctx.entry))
end

Actions.buff = function(ctx)
	for _, t in ipairs(ctx.targets) do ctx.Logic.buffCreature(ctx.state, t, ctx.entry.atk, ctx.entry.hp) end
end

Actions.draw_card = function(ctx)
	local count = Util.valueOf(ctx, ctx.entry)
	local drawn = {}
	for _ = 1, count do
		local id = ctx.Logic.drawCard(ctx.state, ctx.who, { filter = ctx.entry.filter })
		if id then drawn[#drawn+1] = id end
	end
	ctx.dynamic.drawnCards = drawn
	if #drawn > 0 then ctx.dynamic.drawn_card_cost = (Cards[drawn[1]] and Cards[drawn[1]].cost) or 0 end
end

Actions.destroy = function(ctx)
	local t = ctx.targets[1]
	if t and t.slot ~= 0 then ctx.Logic.killCreature(ctx.state, t, { fireEvent = ctx.fireEvent }) end
end

Actions.grant_keyword = function(ctx)
	for _, t in ipairs(ctx.targets) do
		local crt = Util.getCreature(ctx.state, t)
		if crt then ctx.Logic.addKeyword(crt, ctx.entry.keyword) end
	end
end

Actions.summon = function(ctx)
	ctx.Logic.summon(ctx.state, ctx.who, ctx.entry.cardId, ctx.entry.count)
end

Actions.bounce = function(ctx)
	local t = ctx.targets[1]
	if t and t.slot ~= 0 then ctx.Logic.bounce(ctx.state, t) end
end

Actions.return_from_graveyard = function(ctx)
	local id = ctx.Logic.returnFromGraveyard(ctx.state, ctx.who, ctx.entry.target)
	ctx.dynamic.returnedCard = id
end

Actions.reduce_cost = function(ctx)
	ctx.Logic.addCostMod(ctx.state, ctx.who, "reduce", ctx.entry, ctx.dynamic)
end
Actions.set_cost = function(ctx)
	ctx.Logic.addCostMod(ctx.state, ctx.who, "set", ctx.entry, ctx.dynamic)
end

Actions._default = function(ctx)
	if ctx.state and ctx.state.log then table.insert(ctx.state.log, "UNHANDLED:" .. tostring(ctx.entry and ctx.entry.action)) end
end


Actions.gain_energy = function(ctx)
	ctx.Logic.gainEnergy(ctx.state, ctx.who, Util.valueOf(ctx, ctx.entry))
end

-- Explicit Charge gain from an effect. A no-op for non-producing Battle Types (NEUTRAL).
Actions.gain_charge = function(ctx)
	local e = ctx.entry
	local src = ctx.source
	ctx.Logic.gainCharge(ctx.state, ctx.who, e.battleType, Util.valueOf(ctx, e), {
		reason = "effect_gain",
		cardId = src and (src.cardId or src.id),
		sourceSlot = ctx.sourceSlot,
	})
end

Actions.destroy_charge_slot = function(ctx)
	local e = ctx.entry
	local ownerWho = (e.chargeOwner == "enemy") and ctx.opp or ctx.who
	local src = ctx.source
	ctx.Logic.destroyChargeSlot(ctx.state, ownerWho, e.selector, {
		reason = "destroy_slot",
		cardId = src and (src.cardId or src.id),
	})
end

Actions.drain_charge = function(ctx)
	local e = ctx.entry
	local ownerWho = (e.chargeOwner == "enemy") and ctx.opp or ctx.who
	local src = ctx.source
	ctx.Logic.drainCharge(ctx.state, ownerWho, e.selector, e.value or 1, {
		reason = "drain",
		cardId = src and (src.cardId or src.id),
	})
end

Actions.disable_shatter = function(ctx)
	local t = ctx.targets[1]
	if not t or t.slot == 0 then return end
	local m = Util.getCreature(ctx.state, t)
	if not m then return end
	for _, eff in ipairs(m.effects or {}) do
		if eff.trigger == "shatter" then m.shatterDisabled = true; return end
	end
end

Actions.add_additional_charge_cost_to_player_hand = function(ctx)
	local e = ctx.entry
	local targetWho = (e.targetPlayer == "enemy") and ctx.opp or ctx.who
	local targetSide = ctx.state[targetWho]
	local value = e.value or 1
	local selector = e.selector or "all"
	local candidates = {}
	local counts = {}
	for _, id in ipairs(targetSide.hand) do
		local def = Cards[id]
		if def and def.chargeCost then
			counts[id] = (counts[id] or 0) + 1
			candidates[#candidates+1] = id
		end
	end
	if #candidates == 0 then return end
	if selector == "random" then
		ctx.Logic.addChargeCostMod(ctx.state, targetWho, candidates[math.random(1, #candidates)], value, 1)
	else
		for id, count in pairs(counts) do ctx.Logic.addChargeCostMod(ctx.state, targetWho, id, value, count) end
	end
end

return Actions
