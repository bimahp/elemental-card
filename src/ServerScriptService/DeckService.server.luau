-- DeckService: RemoteFunction wrapper for the deck builder (Core-free).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SSS = game:GetService("ServerScriptService")

local Save = require(SSS.Modules.SaveService)
local remotes = ReplicatedStorage:WaitForChild("Remotes")

local function response(ok, payload)
	if ok then return { ok = true, data = payload } end
	return { ok = false, error = tostring(payload or "Request failed") }
end

remotes:WaitForChild("GetDecks").OnServerInvoke = function(player)
	return response(true, Save.getDecks(player))
end

remotes:WaitForChild("CreateDeck").OnServerInvoke = function(player, name)
	return response(Save.createDeck(player, name))
end

remotes:WaitForChild("SaveDeckCards").OnServerInvoke = function(player, deckId, cards)
	return response(Save.saveDeckCards(player, deckId, cards))
end

remotes:WaitForChild("RenameDeck").OnServerInvoke = function(player, deckId, name)
	return response(Save.renameDeck(player, deckId, name))
end

remotes:WaitForChild("DeleteDeck").OnServerInvoke = function(player, deckId)
	return response(Save.deleteDeck(player, deckId))
end

remotes:WaitForChild("SetActiveDeck").OnServerInvoke = function(player, deckId)
	return response(Save.setActiveDeck(player, deckId))
end

print("[DeckService] deck remotes wired")
