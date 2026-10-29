-- Pure, synchronous Card Merchant transactions: Craft (Fragments), Buy (Shards), Destroy (-> Shards).
-- Validates first, then mutates the supplied profile data as one atomic in-memory commit.
-- Mirrors GachaTransaction.lua's shape/conventions exactly.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Cards  = require(ReplicatedStorage.Definitions.Cards)
local Config = require(ReplicatedStorage.Modules.VendorConfig)

local VendorTransaction = {}

local function ownedCounts(data)
	local collection = type(data.collection) == "table" and data.collection or {}
	local counts = {}
	for _, cardId in ipairs(collection) do
		counts[cardId] = (counts[cardId] or 0) + 1
	end
	return counts, collection
end

-- Shared by craft()/buy() -- identical validation/mutation shape, only the currency field differs.
local function directPurchase(data, currencyField, cardId, cost)
	if type(data) ~= "table" then
		return { ok = false, error = "Profile not loaded" }
	end
	if type(cost) ~= "number" or cost < 0 or cost % 1 ~= 0 then
		return { ok = false, error = "Invalid price" }
	end
	local card = type(cardId) == "string" and Cards[cardId]
	if not card or card.collectible == false then
		return { ok = false, error = "Unknown card" }
	end

	local counts = ownedCounts(data)
	if (counts[cardId] or 0) >= Config.MAX_USEFUL_COPIES then
		return { ok = false, error = "Already own the maximum useful copies" }
	end

	local balance = tonumber(data[currencyField]) or 0
	if balance < cost then
		return { ok = false, error = "Not enough currency", balance = balance }
	end

	local collection = type(data.collection) == "table" and data.collection or {}
	collection[#collection + 1] = cardId
	data.collection = collection
	data[currencyField] = balance - cost

	return {
		ok = true,
		cardId = cardId,
		rarity = card.rarity,
		cost = cost,
		balance = data[currencyField],
	}
end

function VendorTransaction.craft(data, cardId, cost)
	return directPurchase(data, "cardFragments", cardId, cost)
end

function VendorTransaction.buy(data, cardId, cost)
	return directPurchase(data, "crystalShards", cardId, cost)
end

-- requests: array of { cardId = string, count = number }. Validates every request before
-- mutating any of them (same all-or-nothing atomicity as GachaTransaction.apply).
function VendorTransaction.destroy(data, requests)
	if type(data) ~= "table" then
		return { ok = false, error = "Profile not loaded" }
	end
	if type(requests) ~= "table" or #requests == 0 then
		return { ok = false, error = "Nothing to recycle" }
	end

	local counts, collection = ownedCounts(data)
	local aggregate = {}
	local order = {}

	for _, req in ipairs(requests) do
		local cardId = type(req) == "table" and req.cardId
		local count = type(req) == "table" and req.count
		if type(cardId) ~= "string" or type(count) ~= "number" or count <= 0 or count % 1 ~= 0 then
			return { ok = false, error = "Invalid recycle request" }
		end
		local card = Cards[cardId]
		if not card or card.collectible == false then
			return { ok = false, error = "Unknown card" }
		end
		if not Config.DESTROY_VALUE_BY_RARITY[card.rarity] then
			return { ok = false, error = "Unsupported rarity" }
		end
		if not aggregate[cardId] then order[#order + 1] = cardId end
		aggregate[cardId] = (aggregate[cardId] or 0) + count
	end

	local function maxDeckCopies(cardId)
		local maxUsed = 0
		for _, deck in ipairs(type(data.decks) == "table" and data.decks or {}) do
			local used = 0
			for _, deckCardId in ipairs(type(deck) == "table" and deck.cards or {}) do
				if deckCardId == cardId then used += 1 end
			end
			if used > maxUsed then maxUsed = used end
		end
		return maxUsed
	end

	local plan = {}
	local totalGained = 0
	for _, cardId in ipairs(order) do
		local count = aggregate[cardId]
		local card = Cards[cardId]
		local owned = counts[cardId] or 0
		if count > owned then
			return { ok = false, error = "Not enough copies to recycle" }
		end

		local remaining = owned - count
		local threshold = Config.RECYCLE_DECK_CHECK_THRESHOLD_BY_RARITY[card.rarity] or Config.MAX_USEFUL_COPIES or 2
		if remaining < threshold and remaining < maxDeckCopies(cardId) then
			return { ok = false, error = "Cant add card, used on deck" }
		end

		local value = Config.DESTROY_VALUE_BY_RARITY[card.rarity]
		plan[#plan + 1] = { cardId = cardId, count = count, value = value }
		totalGained += count * value
	end

	for _, item in ipairs(plan) do
		local remaining = item.count
		for i = #collection, 1, -1 do
			if remaining <= 0 then break end
			if collection[i] == item.cardId then
				table.remove(collection, i)
				remaining -= 1
			end
		end
	end

	data.collection = collection
	local shards = tonumber(data.crystalShards) or 0
	data.crystalShards = shards + totalGained

	return {
		ok = true,
		gained = totalGained,
		balance = data.crystalShards,
		destroyed = plan,
	}
end

return VendorTransaction
