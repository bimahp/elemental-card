-- PlayerStatusController: thin RemoteFunction wiring for profile status and titles.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SSS = game:GetService("ServerScriptService")

local SaveService = require(SSS.Modules.SaveService)
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local getStatus = remotes:WaitForChild("GetPlayerStatus")
local equipTitle = remotes:WaitForChild("EquipTitle")

local lastRequestAt = {}
local REQUEST_COOLDOWN = 0.15

local function allowed(player)
	local now = os.clock()
	local previous = lastRequestAt[player.UserId] or -math.huge
	if now - previous < REQUEST_COOLDOWN then return false end
	lastRequestAt[player.UserId] = now
	return true
end

getStatus.OnServerInvoke = function(player)
	local data, err = SaveService.getPlayerStatus(player)
	if not data then
		return { ok = false, error = err or "Profile not loaded" }
	end
	return { ok = true, data = data }
end

equipTitle.OnServerInvoke = function(player, titleId)
	if not allowed(player) then
		return { ok = false, error = "Please wait before changing titles" }
	end
	local data, err = SaveService.equipTitle(player, titleId)
	if not data then
		return { ok = false, error = err or "Could not equip title" }
	end
	return { ok = true, data = data }
end

Players.PlayerRemoving:Connect(function(player)
	lastRequestAt[player.UserId] = nil
end)

print("[PlayerStatusController] GetPlayerStatus + EquipTitle wired")
