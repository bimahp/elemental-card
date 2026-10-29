-- Deterministic title, migration, and progression coverage for Player Status.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SSS = game:GetService("ServerScriptService")

local Cards = require(ReplicatedStorage.Definitions.Cards)
local LevelConfig = require(ReplicatedStorage.Modules.LevelConfig)
local QuestConfig = require(ReplicatedStorage.Modules.QuestConfig)
local SaveService = require(SSS.Modules.SaveService)
local TitleService = require(SSS.Modules.TitleService)

local Spec = {}

local function baseData()
	return {
		_version = { major = 5, minor = 3 },
		archetype = "MIGHTY",
		collection = {},
		exp = 0,
		level = 1,
		pvp = { wins = 0, losses = 0 },
		quests = { [QuestConfig.IDs.ONBOARDING] = { stage = "intro", archetype = nil } },
		pveFirstClear = { MIGHTY = false, SWIFT = false, VITAL = false },
	}
end

local function collectibleIds()
	local ids = {}
	for id, card in pairs(Cards) do
		if card.collectible ~= false then ids[#ids + 1] = id end
	end
	table.sort(ids)
	return ids
end

local function owned(data, titleId)
	return type(data.ownedTitles) == "table" and data.ownedTitles[titleId] == true
end

function Spec.run()
	local ids = collectibleIds()
	assert(#ids == 132, "Expected 132 collectible cards")
	assert(Cards.the_coin.collectible == false, "The Coin must be non-collectible")

	local migrated = baseData()
	migrated.collection = { ids[1], ids[1] }
	migrated.exp = 345
	migrated.pvp.wins = 9
	assert(SaveService.migrate(migrated) == "minor_upgraded", "v5.3 must migrate in place")
	assert(migrated._version.minor == 4, "Migration must bump schema to v5.4")
	assert(migrated.exp == 345 and migrated.pvp.wins == 9 and #migrated.collection == 2,
		"Migration must preserve existing progression")
	assert(owned(migrated, "beta_tester") and migrated.equippedTitle == "beta_tester",
		"Migration must add the default title")

	local fresh = baseData()
	assert(TitleService.reconcile(fresh), "First reconciliation must initialize titles")
	assert(owned(fresh, "beta_tester"), "Beta Tester must be granted")
	assert(not owned(fresh, "mighty_disciple"), "Archetype title requires completed onboarding")
	assert(not TitleService.reconcile(fresh), "Second reconciliation must be idempotent")

	for _, archetype in ipairs({ "MIGHTY", "SWIFT", "VITAL" }) do
		local data = baseData()
		data.archetype = archetype
		data.quests[QuestConfig.IDs.ONBOARDING] = { stage = "complete", archetype = archetype }
		TitleService.reconcile(data)
		assert(owned(data, string.lower(archetype) .. "_disciple"), archetype .. " title must unlock")
	end

	local trainer = baseData()
	trainer.pveFirstClear = { MIGHTY = true, SWIFT = true, VITAL = false }
	TitleService.reconcile(trainer)
	assert(not owned(trainer, "trainer_champion"), "Two trainer clears must remain below threshold")
	trainer.pveFirstClear.VITAL = true
	TitleService.reconcile(trainer)
	assert(owned(trainer, "trainer_champion"), "Three trainer clears must unlock title")

	local pvp = baseData()
	pvp.pvp.wins = 9
	TitleService.reconcile(pvp)
	assert(not owned(pvp, "duelist"), "Nine wins must not unlock Duelist")
	pvp.pvp.wins = 10
	TitleService.reconcile(pvp)
	assert(owned(pvp, "duelist") and not owned(pvp, "battle_veteran"), "Ten wins must unlock only Duelist")
	pvp.pvp.wins = 50
	TitleService.reconcile(pvp)
	assert(owned(pvp, "battle_veteran"), "Fifty wins must unlock Battle Veteran")

	local collection = baseData()
	for i = 1, 49 do collection.collection[#collection.collection + 1] = ids[i] end
	collection.collection[#collection.collection + 1] = ids[1]
	collection.collection[#collection.collection + 1] = "the_coin"
	TitleService.reconcile(collection)
	assert(TitleService.uniqueCollectibleCount(collection) == 49, "Duplicates and The Coin must not count")
	assert(not owned(collection, "crystal_collector"), "49 unique cards must remain below threshold")
	collection.collection[#collection.collection + 1] = ids[50]
	TitleService.reconcile(collection)
	assert(owned(collection, "crystal_collector"), "50 unique cards must unlock Crystal Collector")
	for i = 51, 100 do collection.collection[#collection.collection + 1] = ids[i] end
	TitleService.reconcile(collection)
	assert(owned(collection, "crystal_archivist"), "100 unique cards must unlock Crystal Archivist")
	collection.collection = {}
	TitleService.reconcile(collection)
	assert(owned(collection, "crystal_collector") and owned(collection, "crystal_archivist"),
		"Unlocked collection titles must remain permanent")

	local ok, err = TitleService.equip(collection, "duelist")
	assert(not ok and err == "Title is locked", "Locked title equip must be rejected")
	assert(not TitleService.equip(collection, "not_a_title"), "Unknown title equip must be rejected")
	assert(TitleService.equip(collection, "crystal_archivist"), "Owned title must equip")
	assert(collection.equippedTitle == "crystal_archivist", "Equipped title ID must persist in data")

	local into, needed = LevelConfig.expIntoLevel(math.huge)
	assert(into == 0 and needed == 0 and LevelConfig.levelFromExp(math.huge) == 100,
		"Maximum level progress must have a stable zero denominator")

	return {
		schema = migrated._version,
		titles = #require(ReplicatedStorage.Modules.TitleConfig).list(),
		collectibleCards = TitleService.totalCollectibleCount(),
		statusFieldsVerified = true,
	}
end

return Spec
