-- QuestService: quest stage CRUD, server-side.
-- Thin wrapper over SaveService quest storage.
-- Fires QuestStateChanged to the client after every write.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SSS               = game:GetService("ServerScriptService")

local QuestConfig = require(ReplicatedStorage.Modules.QuestConfig)
local SaveService = require(SSS.Modules.SaveService)
local Remotes     = ReplicatedStorage:WaitForChild("Remotes")

local QuestService = {}

function QuestService.getStage(player, questId)
	local state = SaveService.getQuestState(player, questId)
	return state and state.stage
end

function QuestService.getArchetype(player, questId)
	local state = SaveService.getQuestState(player, questId)
	return state and state.archetype
end

function QuestService.setStage(player, questId, stage, archetype)
	assert(QuestConfig.Defs[questId], "Unknown questId: " .. tostring(questId))
	local def = QuestConfig.Defs[questId]
	local valid = false
	for _, s in ipairs(def.stages) do if s == stage then valid = true; break end end
	assert(valid, "Invalid stage '" .. tostring(stage) .. "' for quest " .. questId)

	SaveService.setQuestStage(player, questId, stage, archetype)

	local snap = SaveService.getFullSnapshot(player)
	if snap then
		local qEntry = snap.quests[questId] or { stage = stage, archetype = archetype }
		Remotes.QuestStateChanged:FireClient(player, {
			stage           = qEntry.stage,
			chosenArchetype = qEntry.archetype,
			level           = snap.level,
			crystalShards   = snap.crystalShards,
			cardFragments   = snap.cardFragments,
		})
	end
end

return QuestService
