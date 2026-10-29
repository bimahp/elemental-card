-- NameplateController
-- Creates world-space Part+SurfaceGui nameplates for all players and NPCs.
-- Parts are sized in studs so they scale naturally with camera zoom.
-- Rotated toward the camera each frame by RenderStepped.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local Workspace         = game:GetService("Workspace")

local TitleConfig = require(ReplicatedStorage.Modules.TitleConfig)

local localPlayer = Players.LocalPlayer
local camera      = Workspace.CurrentCamera

------------------------------------------------------------------------
-- Config
------------------------------------------------------------------------
local MAX_DIST_SQ   = 40 * 40
local PART_WIDTH    = 8
local PART_HEIGHT        = 3.4  -- NPC nameplates (larger quest mark + title + name)
local PART_HEIGHT_PLAYER = 3.0   -- player nameplates (3 rows: title + name + level)
local GAP_ABOVE     = 0.25
local PX_PER_STUD   = 50

local TITLE_SIZE    = 16
local NAME_SIZE     = 26

local C_NAME         = Color3.fromRGB(255, 255, 255)
local C_TITLE_PLAYER = Color3.fromRGB(255, 210, 50)
local C_TITLE_NPC    = Color3.fromRGB(185, 200, 220)
local C_STROKE       = Color3.fromRGB(0, 0, 0)
local C_LEVEL        = Color3.fromRGB(255, 220, 50)  -- yellow for Level row

------------------------------------------------------------------------
-- NPC static config
------------------------------------------------------------------------
local NPC_DATA = {
    Noob               = { displayName = "Noob",       title = "Card Trainer"    },
    ["Trainer Vital"]  = { displayName = "Catherine",  title = "Vital Collector" },
    ["Trainer Mighty"] = { displayName = "Gronak",     title = "Mighty Collector"},
    ["Trainer Swift"]  = { displayName = "Ziri",       title = "Swift Collector" },
    ["Card Merchant"]  = { displayName = "Rowan",      title = "Card Merchant"   },
}

------------------------------------------------------------------------
-- Registry: { part, sg, head }
------------------------------------------------------------------------
local registry = {}

------------------------------------------------------------------------
-- Build one nameplate Part + SurfaceGui
------------------------------------------------------------------------
local function buildPart(displayName, title, isNpc)
    local partHeight = isNpc and PART_HEIGHT or PART_HEIGHT_PLAYER
    local part = Instance.new("Part")
    part.Name        = "NameplatePart"
    part.Size        = Vector3.new(PART_WIDTH, partHeight, 0.05)
    part.Transparency = 1
    part.CanCollide  = false
    part.CanQuery    = false
    part.CastShadow  = false
    part.Anchored    = true
    part.Locked      = true

    local sg = Instance.new("SurfaceGui")
    sg.Name          = "NameplateSurface"
    sg.Face          = Enum.NormalId.Front
    sg.SizingMode    = Enum.SurfaceGuiSizingMode.PixelsPerStud
    sg.PixelsPerStud = PX_PER_STUD
    sg.AlwaysOnTop   = false
    sg.LightInfluence = 0
    sg.Parent        = part

    -- NPC: quest mark=36%, title=27%, name=37%. Player: title/name/level thirds.
    local titlePos = isNpc and 0.36 or 0
    local titleH   = isNpc and 0.27 or 0.33
    local namePos  = isNpc and 0.63 or 0.33
    local nameH    = isNpc and 0.37 or 0.34

    if isNpc then
        local questMark = Instance.new("TextLabel")
        questMark.Name = "QuestMark"
        questMark.Size = UDim2.new(1, 0, 0.36, 0)
        questMark.Position = UDim2.new(0, 0, 0, 0)
        questMark.BackgroundTransparency = 1
        questMark.Text = "!"
        questMark.TextColor3 = Color3.fromRGB(255, 215, 0)
        questMark.TextSize = 48
        questMark.Font = Enum.Font.GothamBold
        questMark.TextXAlignment = Enum.TextXAlignment.Center
        questMark.TextYAlignment = Enum.TextYAlignment.Bottom
        questMark.TextStrokeTransparency = 0.2
        questMark.TextStrokeColor3 = C_STROKE
        questMark.Visible = false
        questMark.Parent = sg
    end

    local titleLabel = Instance.new("TextLabel")
    titleLabel.Name               = "TitleLabel"
    titleLabel.Size               = UDim2.new(1, 0, titleH, 0)
    titleLabel.Position           = UDim2.new(0, 0, titlePos, 0)
    titleLabel.BackgroundTransparency = 1
    titleLabel.Text               = title
    titleLabel.TextColor3         = isNpc and C_TITLE_NPC or C_TITLE_PLAYER
    titleLabel.TextSize           = TITLE_SIZE
    titleLabel.Font               = Enum.Font.GothamBold
    titleLabel.TextXAlignment     = Enum.TextXAlignment.Center
    titleLabel.TextYAlignment     = Enum.TextYAlignment.Bottom
    titleLabel.TextStrokeTransparency = 0.4
    titleLabel.TextStrokeColor3   = C_STROKE
    titleLabel.Parent             = sg

    local nameLabel = Instance.new("TextLabel")
    nameLabel.Name               = "NameLabel"
    nameLabel.Size               = UDim2.new(1, 0, nameH, 0)
    nameLabel.Position           = UDim2.new(0, 0, namePos, 0)
    nameLabel.BackgroundTransparency = 1
    nameLabel.Text               = displayName
    nameLabel.TextColor3         = C_NAME
    nameLabel.TextSize           = NAME_SIZE
    nameLabel.Font               = Enum.Font.GothamBold
    nameLabel.TextXAlignment     = Enum.TextXAlignment.Center
    nameLabel.TextYAlignment     = isNpc and Enum.TextYAlignment.Top or Enum.TextYAlignment.Center
    nameLabel.TextStrokeTransparency = 0.3
    nameLabel.TextStrokeColor3   = C_STROKE
    nameLabel.Parent             = sg

    if not isNpc then
        local levelLabel = Instance.new("TextLabel")
        levelLabel.Name               = "LevelLabel"
        levelLabel.Size               = UDim2.new(1, 0, 0.33, 0)
        levelLabel.Position           = UDim2.new(0, 0, 0.67, 0)
        levelLabel.BackgroundTransparency = 1
        levelLabel.Text               = "Level 1"
        levelLabel.TextColor3         = C_LEVEL
        levelLabel.TextSize           = TITLE_SIZE
        levelLabel.Font               = Enum.Font.GothamBold
        levelLabel.TextXAlignment     = Enum.TextXAlignment.Center
        levelLabel.TextYAlignment     = Enum.TextYAlignment.Top
        levelLabel.TextStrokeTransparency = 0.4
        levelLabel.TextStrokeColor3   = C_STROKE
        levelLabel.Parent             = sg
    end

    part.Parent = Workspace
    return part, sg
end

local function register(head, displayName, title, isNpc)
    local part, sg = buildPart(displayName, title, isNpc)
    part:SetAttribute("TargetModelName", head.Parent and head.Parent.Name or displayName)
    table.insert(registry, { part = part, sg = sg, head = head })
    return part, sg
end

------------------------------------------------------------------------
-- Player setup
------------------------------------------------------------------------
local function onCharacterAdded(char, player)
    local head = char:WaitForChild("Head", 10)
    if not head then return end
    local titleId = player:GetAttribute("EquippedTitleId") or TitleConfig.DEFAULT_ID
    local _, sg = register(head, player.DisplayName, TitleConfig.displayName(titleId), false)

    local titleLabel = sg and sg:FindFirstChild("TitleLabel")
    if titleLabel then
        local function refreshTitle()
            titleLabel.Text = TitleConfig.displayName(player:GetAttribute("EquippedTitleId"))
        end
        local titleConnection = player:GetAttributeChangedSignal("EquippedTitleId"):Connect(refreshTitle)
        sg.Destroying:Once(function() titleConnection:Disconnect() end)
        refreshTitle()
    end

    task.spawn(function()
        local levelVal   = player:WaitForChild("Level", 30)
        local levelLabel = sg and sg:FindFirstChild("LevelLabel")
        if not levelVal or not levelLabel then return end
        levelLabel.Text = "Level " .. tostring(levelVal.Value)
        local levelConnection = levelVal.Changed:Connect(function(v)
            levelLabel.Text = "Level " .. tostring(v)
        end)
        sg.Destroying:Once(function() levelConnection:Disconnect() end)
    end)
end

for _, player in ipairs(Players:GetPlayers()) do
    if player.Character then
        task.spawn(onCharacterAdded, player.Character, player)
    end
    player.CharacterAdded:Connect(function(char)
        onCharacterAdded(char, player)
    end)
end
Players.PlayerAdded:Connect(function(player)
    player.CharacterAdded:Connect(function(char)
        onCharacterAdded(char, player)
    end)
end)

------------------------------------------------------------------------
-- NPC setup — use WaitForChild to survive replication lag
------------------------------------------------------------------------
local function setupNpc(model)
    local data = NPC_DATA[model.Name]
    if not data then return end
    -- WaitForChild handles the case where the Head hasn't replicated yet
    local head = model:WaitForChild("Head", 10)
    if not head then
        warn("[NameplateController] Head not found in", model.Name)
        return
    end
    register(head, data.displayName, data.title, true)
end

task.spawn(function()
    -- Wait for Noob, Trainers, and the Card Merchant to be fully replicated before scanning
    local noob     = Workspace:WaitForChild("Noob", 10)
    local trainers = Workspace:WaitForChild("Trainers", 10)
    local vendor   = Workspace:WaitForChild("Card Merchant", 10)

    if noob     then setupNpc(noob) end
    if trainers then
        for _, child in ipairs(trainers:GetChildren()) do
            setupNpc(child)
        end
    end
    if vendor then setupNpc(vendor) end

    print("[NameplateController] NPC nameplates registered:", #registry - 1, "NPCs")
end)

------------------------------------------------------------------------
-- RenderStepped: position, orient, distance-cull
------------------------------------------------------------------------
RunService.RenderStepped:Connect(function()
    local camPos = camera.CFrame.Position

    for i = #registry, 1, -1 do
        local e    = registry[i]
        local head = e.head

        if not head or not head.Parent then
            e.part:Destroy()
            table.remove(registry, i)
            continue
        end

        local focusTarget = Workspace:GetAttribute("DialogueFocusTarget")
        if focusTarget and e.part:GetAttribute("TargetModelName") ~= focusTarget then
            e.sg.Enabled = false
            continue
        end

        local headPos = head.CFrame.Position
        local diff    = headPos - camPos
        local distSq  = diff.X * diff.X + diff.Y * diff.Y + diff.Z * diff.Z

        if distSq > MAX_DIST_SQ then
            e.sg.Enabled = false
            continue
        end

        e.sg.Enabled = true

        local headHalf = head.Size.Y * 0.5
        local cy = headPos.Y + headHalf + GAP_ABOVE + e.part.Size.Y * 0.5
        local npPos = Vector3.new(headPos.X, cy, headPos.Z)

        local camFlat = Vector3.new(camPos.X, npPos.Y, camPos.Z)
        local lookDir = camFlat - npPos
        if lookDir.Magnitude > 0.01 then
            e.part.CFrame = CFrame.lookAt(npPos, camFlat)
        end
    end
end)

print("[NameplateController] loaded")
