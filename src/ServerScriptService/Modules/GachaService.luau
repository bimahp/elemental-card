-- GachaService: weighted Card Vending Machine roll generation.
-- Persistence and duplicate conversion commit atomically inside SaveService.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SSS               = game:GetService("ServerScriptService")

local SaveService = require(SSS.Modules.SaveService)
local Cards       = require(ReplicatedStorage.Definitions.Cards)
local Config      = require(ReplicatedStorage.Modules.GachaConfig)

local GachaService = {}

local pool = { common = {}, rare = {}, epic = {} }
for cardId, card in pairs(Cards) do
	if card.collectible ~= false and Config.RARITY_WEIGHTS[card.rarity] then
		pool[card.rarity][#pool[card.rarity] + 1] = cardId
	end
end
for _, bucket in pairs(pool) do table.sort(bucket) end

local RARITY_ORDER = {"common", "rare", "epic"}
local totalWeight = 0
for _, weight in pairs(Config.RARITY_WEIGHTS) do totalWeight += weight end

local function pickRarity(randomInt)
	local roll = randomInt(1, totalWeight)
	local cursor = 0
	for _, rarity in ipairs(RARITY_ORDER) do
		cursor += Config.RARITY_WEIGHTS[rarity]
		if roll <= cursor then return rarity end
	end
	return "common"
end

local function eligibleBucket(rarity, ownedCounts)
	local full = pool[rarity]
	if type(ownedCounts) ~= "table" then return full, false end
	local eligible = {}
	for _, cardId in ipairs(full) do
		if (ownedCounts[cardId] or 0) < 2 then
			eligible[#eligible + 1] = cardId
		end
	end
	if #eligible == 0 then return full, true end
	return eligible, false
end

function GachaService.generateRoll(randomInt, ownedCounts)
	randomInt = randomInt or math.random
	local rolledEntries = {}
	for _ = 1, Config.CARDS_PER_PULL do
		local rarity = pickRarity(randomInt)
		local bucket = eligibleBucket(rarity, ownedCounts)
		if #bucket == 0 then
			return nil, "No collectible cards available for rarity " .. rarity
		end
		local cardId = bucket[randomInt(1, #bucket)]
		rolledEntries[#rolledEntries + 1] = { cardId = cardId }
	end
	return rolledEntries
end

function GachaService.computeDisplayOdds(ownedCounts)
	ownedCounts = type(ownedCounts) == "table" and ownedCounts or {}
	local cards = {}
	for rarityOrder, rarity in ipairs(RARITY_ORDER) do
		local bucket, fallback = eligibleBucket(rarity, ownedCounts)
		local perCardPercent = #bucket > 0
			and (Config.RARITY_WEIGHTS[rarity] / totalWeight * 100) / #bucket
			or 0
		for _, cardId in ipairs(bucket) do
			cards[#cards + 1] = {
				cardId = cardId,
				rarity = rarity,
				owned = ownedCounts[cardId] or 0,
				percent = perCardPercent,
				fallback = fallback,
				_rarityOrder = rarityOrder,
			}
		end
	end
	table.sort(cards, function(a, b)
		if a._rarityOrder ~= b._rarityOrder then return a._rarityOrder < b._rarityOrder end
		local aName = (Cards[a.cardId] and Cards[a.cardId].name) or a.cardId
		local bName = (Cards[b.cardId] and Cards[b.cardId].name) or b.cardId
		if aName ~= bName then return aName < bName end
		return a.cardId < b.cardId
	end)
	for _, entry in ipairs(cards) do entry._rarityOrder = nil end
	return cards
end

function GachaService.roll(player, randomInt)
	local ownedCounts = SaveService.getCollectionCounts(player)
	if not ownedCounts then return { ok = false, error = "Profile not loaded" } end
	local rolledEntries, rollError = GachaService.generateRoll(randomInt, ownedCounts)
	if not rolledEntries then
		return { ok = false, error = rollError or "Pack roll failed" }
	end
	return SaveService.applyCardPackPurchase(player, Config.COST_CARD_FRAGMENTS, rolledEntries)
end

function GachaService.getPoolSummary()
	return {
		common = #pool.common,
		rare = #pool.rare,
		epic = #pool.epic,
		total = #pool.common + #pool.rare + #pool.epic,
	}
end

return GachaService
