-- Deterministic duplicate-protection and odds coverage.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SSS = game:GetService("ServerScriptService")
local Cards = require(ReplicatedStorage.Definitions.Cards)
local Config = require(ReplicatedStorage.Modules.GachaConfig)
local GachaService = require(SSS.Modules.GachaService)

local Spec = {}

local function approx(a, b, epsilon)
	return math.abs(a - b) <= (epsilon or 1e-6)
end

function Spec.run()
	local base = GachaService.computeDisplayOdds({})
	local total = 0
	local rarityTotals = { common = 0, rare = 0, epic = 0 }
	local firstCommon
	for _, entry in ipairs(base) do
		total += entry.percent
		rarityTotals[entry.rarity] += entry.percent
		if entry.rarity == "common" and not firstCommon then firstCommon = entry.cardId end
	end
	assert(approx(total, 100), "All raw card odds must total 100%")
	for rarity, weight in pairs(Config.RARITY_WEIGHTS) do
		assert(approx(rarityTotals[rarity], weight), rarity .. " odds must retain configured tier weight")
	end
	assert(firstCommon, "Test requires a Common card")

	local cappedOne = { [firstCommon] = 2 }
	local protected = GachaService.computeDisplayOdds(cappedOne)
	for _, entry in ipairs(protected) do
		assert(entry.cardId ~= firstCommon, "Capped card must be omitted while alternatives exist")
	end
	local generated = GachaService.generateRoll(function(minimum) return minimum end, cappedOne)
	for _, entry in ipairs(generated) do
		assert(entry.cardId ~= firstCommon, "Generator must not return capped card while alternatives exist")
	end

	local allCommonsCapped = {}
	local commonCount = 0
	for cardId, card in pairs(Cards) do
		if card.collectible ~= false and card.rarity == "common" then
			allCommonsCapped[cardId] = 2
			commonCount += 1
		end
	end
	local fallback = GachaService.computeDisplayOdds(allCommonsCapped)
	local fallbackCommons = 0
	for _, entry in ipairs(fallback) do
		if entry.rarity == "common" then
			fallbackCommons += 1
			assert(entry.fallback == true, "All-capped tier entries must be marked fallback")
		end
	end
	assert(fallbackCommons == commonCount, "All-capped tier must show every possible fallback card")

	return {
		totalPercent = total,
		rarityTotals = rarityTotals,
		excludedCard = firstCommon,
		fallbackCommons = fallbackCommons,
	}
end

return Spec
