-- InventoryService: serves a player's saved card collection to the inventory UI
-- (PLAN_BACKEND Phase 5). Read-only; returns the cardId multiset from SaveService.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SSS               = game:GetService("ServerScriptService")

local Save   = require(SSS.Modules.SaveService)
local remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("GetInventory")

remote.OnServerInvoke = function(player)
	local profile = Save.getProfile(player)
	if not profile or not profile:IsActive() then return {} end
	local col = profile.Data.collection or {}
	local out = table.create(#col)
	for i, id in ipairs(col) do out[i] = id end
	return out  -- raw multiset; client collapses to unique + xN
end

print("[InventoryService] GetInventory wired")
