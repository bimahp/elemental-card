-- NameplateService
-- Suppresses Roblox default name/health display for NPCs and players.
-- The visual nameplate itself is built client-side by NameplateController.

local Players = game:GetService("Players")

local function suppressDisplay(model)
    local hum = model:FindFirstChildOfClass("Humanoid")
    if hum then
        hum.DisplayDistanceType  = Enum.HumanoidDisplayDistanceType.None
        hum.HealthDisplayType    = Enum.HumanoidHealthDisplayType.AlwaysOff
    end
end

-- Suppress NPC defaults immediately
task.defer(function()
    local noob = workspace:FindFirstChild("Noob")
    if noob then suppressDisplay(noob) end

    local trainers = workspace:FindFirstChild("Trainers")
    if trainers then
        for _, model in ipairs(trainers:GetChildren()) do
            suppressDisplay(model)
        end
    end

    local vendor = workspace:FindFirstChild("Card Merchant")
    if vendor then suppressDisplay(vendor) end
end)

-- Suppress player character defaults (belt-and-suspenders for StarterPlayer settings)
Players.PlayerAdded:Connect(function(player)
    player.CharacterAdded:Connect(function(char)
        local hum = char:WaitForChild("Humanoid", 5)
        if hum then
            hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
            hum.HealthDisplayType   = Enum.HumanoidHealthDisplayType.AlwaysOff
        end
    end)
end)

print("[NameplateService] loaded")
