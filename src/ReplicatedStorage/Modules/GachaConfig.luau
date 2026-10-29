-- Shared Card Vending Machine configuration.
-- Required by both server purchase logic and the client purchase UI.
local GachaConfig = {
	COST_CARD_FRAGMENTS = 200, -- Standard Pack price (aligned with Core Packs, DESIGN_ECONOMY.md §5.2)
	CARDS_PER_PULL = 5,
	MAX_ACTIVATION_DISTANCE = 8,
	SERVER_DISTANCE_TOLERANCE = 3,
	ROLL_COOLDOWN_SECONDS = 0.75,

	RARITY_WEIGHTS = {
		common = 70,
		rare = 25,
		epic = 5,
	},
}

return GachaConfig
