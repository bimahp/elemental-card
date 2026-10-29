-- Shared helpers for the Effects subsystem. Pure; no game mutation.
local Util = {}
Util.BOARD_SIZE = 3

function Util.opp(who) return who == "player" and "npc" or "player" end
function Util.isHero(t) return t ~= nil and t.slot == 0 end

-- target descriptor = { side = "player"|"npc", slot = 0..3 }  (slot 0 = hero)
function Util.getCreature(state, t)
	if not t or t.slot == 0 then return nil end
	local side = state[t.side]
	return side and side.board[t.slot] or nil
end

function Util.creatureTargets(state, side)
	local out = {}
	for i = 1, Util.BOARD_SIZE do
		if state[side].board[i] then out[#out + 1] = { side = side, slot = i } end
	end
	return out
end

function Util.attackOf(m)
	return (m.atk or 0) + (m.tempAtk or 0)
end

-- value of an entry: fixed `value`, or dynamic `valueFrom` resolved from ctx.dynamic
function Util.valueOf(ctx, entry)
	if entry.valueFrom then
		return (ctx.dynamic and ctx.dynamic[entry.valueFrom]) or 0
	end
	return entry.value or 0
end

return Util
