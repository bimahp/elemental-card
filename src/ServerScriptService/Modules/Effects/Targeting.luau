-- resolveTargets(ctx, entry) -> { target descriptors }. Pure.
-- Player-chosen single targets come from ctx.chosenTarget ({side,slot}).
-- Server-resolved (self/hero/random/all/split) computed here.
local Util = require(script.Parent.Util)
local Targeting = {}

local function validDescriptor(state, t)
	return type(t) == "table"
		and (t.side == "player" or t.side == "npc")
		and type(t.slot) == "number"
		and t.slot % 1 == 0
		and t.slot >= 0
		and t.slot <= Util.BOARD_SIZE
		and state[t.side] ~= nil
end

local function hasCreature(state, t)
	return validDescriptor(state, t) and t.slot ~= 0 and state[t.side].board[t.slot] ~= nil
end

local function chosenCreature(ctx, side)
	local t = ctx.chosenTarget
	if hasCreature(ctx.state, t) and (not side or t.side == side) then
		return t
	end
	return nil
end

local function anyCreatureTargets(state)
	local out = Util.creatureTargets(state, "player")
	for _, t in ipairs(Util.creatureTargets(state, "npc")) do out[#out + 1] = t end
	return out
end

function Targeting.resolve(ctx, entry)
	local state, who, opp = ctx.state, ctx.who, ctx.opp
	local target, area = entry.target, entry.area or "single"
	local res = {}
	if not target then return res end

	if target == "self" then
		if ctx.sourceSlot then res[1] = { side = who, slot = ctx.sourceSlot } end
	elseif target == "own_hero" then
		res[1] = { side = who, slot = 0 }
	elseif target == "all_friendly" then
		res[1] = { side = who, slot = 0 }
		for _, t in ipairs(Util.creatureTargets(state, who)) do res[#res + 1] = t end
	elseif target == "random_friendly" then
		local pool = Util.creatureTargets(state, who)
		if #pool > 0 then res[1] = pool[math.random(1, #pool)] end
	elseif target == "random_enemy" then
		local pool = Util.creatureTargets(state, opp)
		if #pool > 0 then res[1] = pool[math.random(1, #pool)] end
	elseif target == "friendly_creature" then
		if area == "all" then res = Util.creatureTargets(state, who)
		else res[1] = chosenCreature(ctx, who); if not res[1] then local pool = Util.creatureTargets(state, who); if #pool > 0 then res[1] = pool[math.random(1,#pool)] end end end
	elseif target == "enemy_creature" then
		if area == "all" or area == "split" then res = Util.creatureTargets(state, opp)
		else res[1] = chosenCreature(ctx, opp); if not res[1] then local pool = Util.creatureTargets(state, opp); if #pool > 0 then res[1] = pool[math.random(1,#pool)] end end end
	elseif target == "any_creature" then
		res[1] = chosenCreature(ctx)
		if not res[1] then local pool = anyCreatureTargets(state); if #pool > 0 then res[1] = pool[math.random(1,#pool)] end end
	elseif target == "enemy_target" then
		local t = ctx.chosenTarget
		if validDescriptor(state, t) and t.side == opp and (t.slot == 0 or hasCreature(state, t)) then
			res[1] = t
		else
			local pool = Util.creatureTargets(state, opp); res[1] = (#pool > 0) and pool[math.random(1,#pool)] or {side=opp, slot=0}
		end
	end
	-- cost pools / graveyard ("hand","drawn_cards","returned_card","random")
	-- are non-board targets handled by their own actions; return empty here.
	return res
end

return Targeting
