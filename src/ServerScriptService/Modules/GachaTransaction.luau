-- Pure, synchronous Card Vending Machine transaction.
-- Validates first, then mutates the supplied profile data as one atomic in-memory commit.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Cards  = require(ReplicatedStorage.Definitions.Cards)
local Config = require(ReplicatedStorage.Modules.GachaConfig)

local GachaTransaction = {}

function GachaTransaction.apply(data, cost, rolledEntries)
	if type(data) ~= "table" then
		return { ok = false, error = "Profile not loaded" }
	end
	if type(cost) ~= "number" or cost < 0 or cost % 1 ~= 0 then
		return { ok = false, error = "Invalid pack cost" }
	end
	if type(rolledEntries) ~= "table" or #rolledEntries == 0 then
		return { ok = false, error = "Pack roll failed" }
	end

	for _, entry in ipairs(rolledEntries) do
		local card = type(entry) == "table" and Cards[entry.cardId]
		if not card or card.collectible == false or not Config.RARITY_WEIGHTS[card.rarity] then
			return { ok = false, error = "Pack contained an invalid card" }
		end
	end

	local fragments = tonumber(data.cardFragments) or 0
	if fragments < cost then
		return {
			ok = false,
			error = "Not enough Card Fragments",
			cardFragments = fragments,
		}
	end

	local collection = type(data.collection) == "table" and data.collection or {}
	local ownedCounts = {}
	for _, cardId in ipairs(collection) do
		ownedCounts[cardId] = (ownedCounts[cardId] or 0) + 1
	end

	-- Duplicate protection already happened upstream (GachaService only falls
	-- back to a >=2-owned card once its whole rarity pool is capped --
	-- DESIGN_ECONOMY.md §12.1/§12.4) -- a dupe here is added to the collection
	-- anyway, flagged isDupe for UI display, with no currency compensation.
	-- Manual destroy-for-Shards crafting doesn't exist yet (see DEV_STATUS.md).
	local cards = {}
	for _, entry in ipairs(rolledEntries) do
		local cardId = entry.cardId
		local card = Cards[cardId]
		local ownedBefore = ownedCounts[cardId] or 0
		ownedCounts[cardId] = ownedBefore + 1
		collection[#collection + 1] = cardId
		cards[#cards + 1] = {
			cardId = cardId,
			rarity = card.rarity,
			isNew = ownedBefore == 0,
			isDupe = ownedBefore >= 2,
		}
	end

	data.collection = collection
	data.cardFragments = fragments - cost

	return {
		ok = true,
		cards = cards,
		cardFragments = data.cardFragments,
		cost = cost,
	}
end

return GachaTransaction
