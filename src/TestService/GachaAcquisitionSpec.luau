-- Deterministic verification for PLAN_CARD_ACQUISITION.
local SSS = game:GetService("ServerScriptService")

local Transaction = require(SSS.Modules.GachaTransaction)
local GachaService = require(SSS.Modules.GachaService)

local Spec = {}

local function count(collection, wanted)
	local total = 0
	for _, cardId in ipairs(collection) do
		if cardId == wanted then total += 1 end
	end
	return total
end

function Spec.run()
	local repeated = {}
	for _ = 1, 5 do repeated[#repeated + 1] = { cardId = "fleetpaw" } end

	local data = {
		cardFragments = 200,
		collection = { "fleetpaw" },
	}
	local result = Transaction.apply(data, 160, repeated)
	assert(result.ok, result.error)
	assert(data.cardFragments == 40, "Purchase must deduct exactly 160 Card Fragments")
	-- Duplicate protection (never re-rolling a >=2-owned card until the whole
	-- rarity pool is capped) lives upstream in GachaService -- the transaction
	-- itself just commits whatever it's handed, uncapped, per DESIGN_ECONOMY §12.4.
	assert(count(data.collection, "fleetpaw") == 6, "Every rolled card is added to the collection")
	assert(#result.cards == 5, "Purchase response must preserve all five result slots")
	assert(result.cards[1].isNew == false and result.cards[1].isDupe == false,
		"The first result must report Added Copy when exactly one copy was owned")
	for index = 2, 5 do
		local cardResult = result.cards[index]
		assert(cardResult.isNew == false and cardResult.isDupe == true,
			"Every result beyond the 2-copy threshold must be marked isDupe, with no currency awarded")
	end

	local newCardData = { cardFragments = 100, collection = {} }
	local newCardResult = Transaction.apply(newCardData, 50, {{ cardId = "fleetpaw" }})
	assert(newCardResult.ok, newCardResult.error)
	assert(newCardResult.cards[1].isNew == true and newCardResult.cards[1].isDupe == false,
		"A first copy must be marked New")

	local insufficient = { cardFragments = 49, collection = {} }
	local failed = Transaction.apply(insufficient, 50, repeated)
	assert(not failed.ok and insufficient.cardFragments == 49, "Insufficient funds must not mutate data")
	assert(#insufficient.collection == 0, "Failed purchase must be atomic")

	local invalid = { cardFragments = 100, collection = {} }
	local invalidResult = Transaction.apply(invalid, 50, {{ cardId = "not_a_card" }})
	assert(not invalidResult.ok and invalid.cardFragments == 100, "Invalid roll must not charge")

	local summary = GachaService.getPoolSummary()
	assert(summary.total == 132, "Pool must contain all 132 collectible cards")
	local generated = GachaService.generateRoll(function(minimum) return minimum end)
	assert(type(generated) == "table" and #generated == 5, "Generator must return five cards")

	return {
		pool = summary,
		finalCopies = count(data.collection, "fleetpaw"),
		statusFieldsVerified = true,
	}
end

return Spec
