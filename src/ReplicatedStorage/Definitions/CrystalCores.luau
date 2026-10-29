-- Crystal Core definitions (alpha). A Core is tied to a deck and acts as the
-- deck's active skill in battle.
local CrystalCores = {}

CrystalCores.THRESHOLDS = { 0, 5, 10, 15 }
CrystalCores.COST = 2

local function core(id, name, types, skillName, description, scaling)
	return {
		id = id,
		name = name,
		types = types,
		cost = CrystalCores.COST,
		skillName = skillName,
		description = description,
		scaling = scaling,
	}
end

CrystalCores.List = {
	core_vanguard = core("core_vanguard", "Core of Vanguard", {"MIGHTY"}, "Raise Shield",
		"Gain Armor based on MIGHTY cards played.",
		{ armor = { type = "MIGHTY", values = {1, 2, 4, 6} } }),

	core_assassin = core("core_assassin", "Core of Assassin", {"SWIFT"}, "Shadow Strike",
		"Deal damage to a creature based on SWIFT cards played. If it dies, draw 1 and reduce that card's cost by 1.",
		{ damage = { type = "SWIFT", values = {1, 2, 2, 3} }, killDraw = true }),

	core_renewal = core("core_renewal", "Core of Renewal", {"VITAL"}, "Renew Life",
		"Restore Health based on VITAL cards played.",
		{ heal = { type = "VITAL", values = {1, 2, 4, 6} } }),

	core_warrior = core("core_warrior", "Core of Warrior", {"MIGHTY", "SWIFT"}, "Battle Rhythm",
		"Gain Armor from MIGHTY cards played and draw from SWIFT cards played.",
		{ armor = { type = "MIGHTY", values = {1, 2, 3, 4} }, draw = { type = "SWIFT", values = {0, 1, 1, 2} } }),

	core_guardian = core("core_guardian", "Core of Guardian", {"MIGHTY", "VITAL"}, "Guarded Renewal",
		"Gain Armor from MIGHTY cards played and restore Health from VITAL cards played.",
		{ armor = { type = "MIGHTY", values = {1, 2, 3, 4} }, heal = { type = "VITAL", values = {0, 1, 2, 3} } }),

	core_sage = core("core_sage", "Core of Sage", {"SWIFT", "VITAL"}, "Flowing Insight",
		"Draw from SWIFT cards played and restore Health from VITAL cards played.",
		{ draw = { type = "SWIFT", values = {0, 1, 1, 2} }, heal = { type = "VITAL", values = {1, 2, 3, 4} } }),
}

CrystalCores.Order = {
	"core_vanguard",
	"core_assassin",
	"core_renewal",
	"core_warrior",
	"core_guardian",
	"core_sage",
}

function CrystalCores.get(coreId)
	return CrystalCores.List[coreId]
end

function CrystalCores.tier(count)
	count = tonumber(count) or 0
	if count >= 15 then return 4 end
	if count >= 10 then return 3 end
	if count >= 5 then return 2 end
	return 1
end

function CrystalCores.scaledValue(core, key, counters)
	local spec = core and core.scaling and core.scaling[key]
	if not spec then return 0 end
	local count = counters and counters[spec.type] or 0
	return spec.values[CrystalCores.tier(count)] or 0
end

function CrystalCores.supports(coreId, battleType)
	if battleType == "NEUTRAL" then return true end
	local core = CrystalCores.get(coreId)
	if not core then return false end
	for _, t in ipairs(core.types) do
		if t == battleType then return true end
	end
	return false
end

function CrystalCores.describe(coreId, counters)
	local core = CrystalCores.get(coreId)
	if not core then return "Unknown Core" end
	local bits = {}
	if core.scaling.armor then bits[#bits+1] = "+" .. CrystalCores.scaledValue(core, "armor", counters) .. " Armor" end
	if core.scaling.damage then bits[#bits+1] = CrystalCores.scaledValue(core, "damage", counters) .. " damage" end
	if core.scaling.heal then bits[#bits+1] = "Heal " .. CrystalCores.scaledValue(core, "heal", counters) end
	if core.scaling.draw then bits[#bits+1] = "Draw " .. CrystalCores.scaledValue(core, "draw", counters) end
	if core.scaling.killDraw then bits[#bits+1] = "kill: draw 1, reduce it by 1" end
	return table.concat(bits, " + ")
end

return CrystalCores
