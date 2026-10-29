-- HudController: owns the world HUD icon group (TopRightAnchor).
-- Shows it during free-roam; hides the whole group during any battle state
-- (loading, seated, active battle). The inventory dialog open/close + data lives
-- in InventoryController; this script only governs anchor visibility.
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui        = game:GetService("StarterGui")

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local anchor = script.Parent:WaitForChild("TopRightAnchor")
local postBattle = player.PlayerGui:WaitForChild("BattleUI"):WaitForChild("PostBattle")

-- The HUD owns the top-right corner (Inventory + future Card List / Title Collection).
-- Disable Roblox's default player-list pill so it doesn't collide. Reversible: set true.
pcall(function() StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false) end)

local function show() anchor.Visible = true end
local function hide() anchor.Visible = false end

show()

local resultPending = false
local function enterBattle()
	resultPending = false
	hide()
end
local function leaveWithoutResult()
	resultPending = false
	show()
end

-- The result modal is still part of the battle presentation. Keep world-menu
-- buttons hidden until the player explicitly dismisses it.
remotes:WaitForChild("BattleLoading").OnClientEvent:Connect(enterBattle)
remotes:WaitForChild("BattleSeated").OnClientEvent:Connect(enterBattle)
remotes:WaitForChild("UpdateBattleState").OnClientEvent:Connect(enterBattle)
remotes:WaitForChild("BattleOver").OnClientEvent:Connect(function()
	resultPending = true
	hide()
end)
postBattle:GetPropertyChangedSignal("Visible"):Connect(function()
	if postBattle.Visible then return end
	task.defer(function()
		if resultPending and not postBattle.Visible then
			resultPending = false
			show()
		end
	end)
end)
remotes:WaitForChild("BattleUnseated").OnClientEvent:Connect(leaveWithoutResult)
player.CharacterAdded:Connect(leaveWithoutResult)
