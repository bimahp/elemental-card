-- TitleService: pure title unlock/equip rules over profile data.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Cards = require(ReplicatedStorage.Definitions.Cards)
local QuestConfig = require(ReplicatedStorage.Modules.QuestConfig)
local TitleConfig = require(ReplicatedStorage.Modules.TitleConfig)

local TitleService = {}

local TRAINER_ARCHETYPES = { "MIGHTY", "SWIFT", "VITAL" }

local function uniqueCollectibleCount(data)
	local seen = {}
	local total = 0
	for _, cardId in ipairs(type(data.collection) == "table" and data.collection or {}) do
		local card = Cards[cardId]
		if card and card.collectible ~= false and not seen[cardId] then
			seen[cardId] = true
			total += 1
		end
	end
	return total
end

local function totalCollectibleCount()
	local total = 0
	for _, card in pairs(Cards) do
		if type(card) == "table" and card.collectible ~= false then
			total += 1
		end
	end
	return total
end

local function trainerClearCount(data)
	local firstClear = type(data.pveFirstClear) == "table" and data.pveFirstClear or {}
	local total = 0
	for _, archetype in ipairs(TRAINER_ARCHETYPES) do
		if firstClear[archetype] == true then total += 1 end
	end
	return total
end

local function onboardingCompleteFor(data, archetype)
	local quests = type(data.quests) == "table" and data.quests or {}
	local quest = quests[QuestConfig.IDs.ONBOARDING]
	return type(quest) == "table"
		and quest.stage == "complete"
		and (quest.archetype or data.archetype) == archetype
end

local function requirementMet(data, requirement)
	local kind = requirement and requirement.kind
	if kind == "default" then
		return true
	elseif kind == "onboarding_archetype" then
		return onboardingCompleteFor(data, requirement.value)
	elseif kind == "trainer_clears" then
		return trainerClearCount(data) >= (requirement.value or 0)
	elseif kind == "pvp_wins" then
		local pvp = type(data.pvp) == "table" and data.pvp or {}
		return (tonumber(pvp.wins) or 0) >= (requirement.value or 0)
	elseif kind == "unique_collectible" then
		return uniqueCollectibleCount(data) >= (requirement.value or 0)
	end
	return false
end

function TitleService.reconcile(data)
	if type(data) ~= "table" then return false end
	local changed = false
	if type(data.ownedTitles) ~= "table" then
		data.ownedTitles = {}
		changed = true
	end

	for _, title in ipairs(TitleConfig.list()) do
		if data.ownedTitles[title.id] ~= true and requirementMet(data, title.requirement) then
			data.ownedTitles[title.id] = true
			changed = true
		end
	end

	local equipped = data.equippedTitle
	if type(equipped) ~= "string"
		or not TitleConfig.get(equipped)
		or data.ownedTitles[equipped] ~= true then
		data.equippedTitle = TitleConfig.DEFAULT_ID
		data.ownedTitles[TitleConfig.DEFAULT_ID] = true
		changed = true
	end
	return changed
end

function TitleService.equip(data, titleId)
	if type(titleId) ~= "string" or #titleId == 0 or #titleId > 64 then
		return false, "Invalid title"
	end
	if not TitleConfig.get(titleId) then
		return false, "Unknown title"
	end
	TitleService.reconcile(data)
	if data.ownedTitles[titleId] ~= true then
		return false, "Title is locked"
	end
	if data.equippedTitle == titleId then
		return true
	end
	data.equippedTitle = titleId
	return true
end

function TitleService.buildView(data)
	TitleService.reconcile(data)
	local items = table.create(#TitleConfig.list())
	for _, title in ipairs(TitleConfig.list()) do
		local unlocked = data.ownedTitles[title.id] == true
		items[#items + 1] = {
			id = title.id,
			displayName = title.displayName,
			description = title.description,
			unlockText = title.unlockText,
			unlocked = unlocked,
			equipped = data.equippedTitle == title.id,
			order = title.order,
		}
	end
	return {
		equippedId = data.equippedTitle,
		items = items,
	}
end

TitleService.uniqueCollectibleCount = uniqueCollectibleCount
TitleService.totalCollectibleCount = totalCollectibleCount
TitleService.trainerClearCount = trainerClearCount
TitleService.requirementMet = requirementMet

return TitleService
