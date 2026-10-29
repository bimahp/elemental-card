-- Shared Card Merchant configuration (Craft with Card Fragments, Buy with Crystal Shards, Destroy for Crystal Shards).
-- Required by server purchase/destroy logic and the client Vendor/Inventory UI.
-- See DESIGN_ECONOMY.md §9/§10 and PLAN (Card Merchant NPC) for the source rates.
local VendorConfig = {
	-- Craft: pay Card Fragments for a guaranteed specific card.
	-- Priced off pack cost-per-slot (200 Fragments / 5 cards = 40), rarity-scaled,
	-- NOT off blind-roll EV (see plan doc for why). New table, not documented pre-existing rates.
	CRAFT_COST_BY_RARITY = {
		common = 500,
		rare = 1500,
		epic = 4000,
		legendary = 15000,
	},

	-- Buy: pay Crystal Shards for a guaranteed specific card.
	-- DESIGN_ECONOMY.md §10 rates x2 (user-directed deviation from the documented 10:1-vs-destroy rates).
	BUY_COST_BY_RARITY = {
		common = 40,
		rare = 160,
		epic = 600,
		legendary = 2400,
	},

	-- Destroy: Crystal Shards gained from destroying one duplicate copy. DESIGN_ECONOMY.md §9.2, unscaled.
	DESTROY_VALUE_BY_RARITY = {
		common = 2,
		rare = 8,
		epic = 30,
		legendary = 120,
	},

	-- Recycle deck-check thresholds. Recycle itself has no protected-copy floor;
	-- this threshold only decides when to check saved decks before letting a card
	-- be queued/recycled. Legendary deck max is 1; other rarities remain max 2.
	RECYCLE_DECK_CHECK_THRESHOLD_BY_RARITY = {
		common = 2,
		rare = 2,
		epic = 2,
		legendary = 1,
	},

	-- Craft/Buy max useful copies per card. Deck-building has its own rarity-aware max
	-- in SaveService/InventoryController: Legendary=1, other rarities=2.
	MAX_USEFUL_COPIES = 2,

	-- Rotating stock.
	STOCK_SIZE = 6,
	STOCK_RARITY_SPREAD = { common = 3, rare = 2, epic = 1 },
	ROTATION_INTERVAL_SECONDS = 8 * 3600, -- resets at 00:00 / 08:00 / 16:00 (epoch-aligned)

	-- Proximity gate, mirrors GachaConfig's vending-machine pattern.
	MAX_ACTIVATION_DISTANCE = 8,
	SERVER_DISTANCE_TOLERANCE = 3,
}

return VendorConfig
