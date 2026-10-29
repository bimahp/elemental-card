-- Conditions[type](ctx, cond) -> bool. Pure reads of state/targets.
local Util = require(script.Parent.Util)
local Conditions = {}

local function primaryCreature(ctx)
	local t = ctx.targets and ctx.targets[1]
	return Util.getCreature(ctx.state, t)
end

Conditions["damaged"] = function(ctx)
	local m = primaryCreature(ctx); return m ~= nil and m.hp < m.maxHp
end
Conditions["target_undamaged"] = function(ctx)
	local m = primaryCreature(ctx); return m ~= nil and m.hp >= m.maxHp
end
Conditions["attack_gte"] = function(ctx, cond)
	local m = primaryCreature(ctx); return m ~= nil and Util.attackOf(m) >= (cond.value or 0)
end
Conditions["attack_lte"] = function(ctx, cond)
	local m = primaryCreature(ctx); return m ~= nil and Util.attackOf(m) <= (cond.value or 0)
end
Conditions["friendly_damaged_exists"] = function(ctx)
	local side = ctx.state[ctx.who]
	for i = 1, Util.BOARD_SIZE do
		local m = side.board[i]; if m and m.hp < m.maxHp then return true end
	end
	return false
end
Conditions["chain"] = function(ctx)
	return (ctx.state[ctx.who].cardsPlayedThisTurn or 0) >= 2
end
Conditions["two_charge_slots_occupied"] = function(ctx, cond)
	local ownerWho = (cond and cond.chargeOwner == "enemy") and ctx.opp or ctx.who
	local ownerSide = ctx.state[ownerWho]
	local ChargeState = require(game:GetService("ServerScriptService").Modules.ChargeState)
	return ChargeState.bothSlotsOccupied(ownerSide)
end

function Conditions.check(ctx, cond)
	if not cond then return true end
	local fn = Conditions[cond.type]
	if not fn then return false end
	return fn(ctx, cond)
end

return Conditions
