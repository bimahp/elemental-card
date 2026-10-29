-- LevelConfig: shared EXP progression table (server + client).
-- EXP_TABLE[n] = EXP needed to advance from level n to n+1.
-- Generated as floor(100 × 1.15^(n-1)) for n = 1..100.
local LevelConfig = {}

local EXP_TABLE = {}
local base = 100
for n = 1, 100 do
	EXP_TABLE[n] = math.floor(base)
	base = base * 1.15
end

function LevelConfig.expForLevel(n)
	return EXP_TABLE[n] or math.huge
end

function LevelConfig.levelFromExp(totalExp)
	local level, cumulative = 1, 0
	for n = 1, 100 do
		local needed = EXP_TABLE[n]
		if cumulative + needed > totalExp then break end
		cumulative = cumulative + needed
		level = n + 1
	end
	return math.min(level, 100)
end

-- Returns (expIntoCurrentLevel, expNeededForNextLevel).
function LevelConfig.expIntoLevel(totalExp)
	local cumulative = 0
	for n = 1, 100 do
		local needed = EXP_TABLE[n]
		if cumulative + needed > totalExp then
			return totalExp - cumulative, needed
		end
		cumulative = cumulative + needed
	end
	return 0, 0
end

return LevelConfig
