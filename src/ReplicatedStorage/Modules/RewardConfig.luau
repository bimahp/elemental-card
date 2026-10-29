-- RewardConfig: shared battle-reward economy constants (DESIGN_REWARD.md).
-- Single source of truth for Fragment amounts, daily caps, EXP scaling,
-- validity-gate thresholds, and the forfeit cooldown ladder.
local RewardConfig = {}

RewardConfig.MATCHMAKING = {
	win = 3,
	loss = 1,
	earlyForfeitWin = 2,
	earlyForfeiter = 0,
}

RewardConfig.LOCAL = {
	win = 1,
	loss = 0,
}

RewardConfig.NPC = {
	win = 1,
	loss = 0,
	firstClear = 50,
}

RewardConfig.GLOBAL_DAILY_CAP = 200   -- Matchmaking + Local + repeat-NPC share this
RewardConfig.NPC_DAILY_SUBCAP  = 10   -- repeat-NPC wins only, subset of the global cap

RewardConfig.EXP_PER_FRAGMENT = 15    -- exp = fragmentsGranted * EXP_PER_FRAGMENT

RewardConfig.VALID_TURN    = 4        -- turnNumber >= this = valid regardless of actions
RewardConfig.VALID_ACTIONS = 2        -- meaningful actions >= this = valid regardless of turn

-- Early-forfeit cooldown ladder (seconds), indexed by today's early-forfeit
-- count (1st, 2nd, 3rd, ...). Count beyond the table length clamps to the
-- last entry. Index 1 = warning only (no cooldown).
RewardConfig.FORFEIT_COOLDOWN_LADDER = { 0, 120, 300, 900, 1800 }

function RewardConfig.forfeitCooldownSeconds(forfeitCountToday)
	local ladder = RewardConfig.FORFEIT_COOLDOWN_LADDER
	local index = math.min(math.max(forfeitCountToday, 1), #ladder)
	return ladder[index]
end

return RewardConfig
