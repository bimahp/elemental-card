local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player  = Players.LocalPlayer
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local inChairGui = false
local inBattle   = false

-- ── Find seat positions ───────────────────────────────────────────────────────
local function findSeatByAttr(attr)
	for _, obj in ipairs(workspace:GetChildren()) do
		if obj:IsA("Model") and obj:GetAttribute(attr) then
			for _, d in ipairs(obj:GetDescendants()) do
				if d:IsA("Seat") then return d end
			end
		end
	end
end

-- ── Challenge / Leave GUI ─────────────────────────────────────────────────────
local gui = Instance.new("ScreenGui")
gui.Name        = "ChairGui"
gui.ResetOnSpawn = false
gui.Enabled     = false
gui.Parent      = player.PlayerGui

local frame = Instance.new("Frame")
frame.Size            = UDim2.new(0, 260, 0, 110)
frame.Position        = UDim2.new(0.5,-130, 0.72,-55)
frame.BackgroundColor3 = Color3.fromRGB(18,18,28)
frame.BorderSizePixel = 0
Instance.new("UICorner", frame).CornerRadius = UDim.new(0,10)
frame.Parent = gui

local lbl = Instance.new("TextLabel")
lbl.Size = UDim2.new(1,0,0.33,0)
lbl.BackgroundTransparency = 1
lbl.Text = "Noob challenges you to a card duel!"
lbl.TextColor3 = Color3.fromRGB(220,220,220)
lbl.TextScaled = true
lbl.Font = Enum.Font.GothamMedium
lbl.Parent = frame

local challengeBtn = Instance.new("TextButton")
challengeBtn.Size = UDim2.new(0.47,0, 0.44,0)
challengeBtn.Position = UDim2.new(0.02,0, 0.53,0)
challengeBtn.BackgroundColor3 = Color3.fromRGB(180,40,40)
challengeBtn.Text = "⚔ Challenge"
challengeBtn.TextColor3 = Color3.new(1,1,1)
challengeBtn.TextScaled = true
challengeBtn.Font = Enum.Font.GothamBold
Instance.new("UICorner", challengeBtn).CornerRadius = UDim.new(0,6)
challengeBtn.Parent = frame

local leaveBtn = Instance.new("TextButton")
leaveBtn.Size = UDim2.new(0.47,0, 0.44,0)
leaveBtn.Position = UDim2.new(0.51,0, 0.53,0)
leaveBtn.BackgroundColor3 = Color3.fromRGB(55,55,65)
leaveBtn.Text = "Leave"
leaveBtn.TextColor3 = Color3.fromRGB(200,200,200)
leaveBtn.TextScaled = true
leaveBtn.Font = Enum.Font.Gotham
Instance.new("UICorner", leaveBtn).CornerRadius = UDim.new(0,6)
leaveBtn.Parent = frame

-- ── Teleport player to player seat ───────────────────────────────────────────
local function teleportToChair()
	local seat = findSeatByAttr("IsPlayerSeat")
	if not seat then return end
	local char = player.Character
	if not char then return end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end
	-- Teleport to above the seat
	hrp.CFrame = seat.CFrame * CFrame.new(0, seat.Size.Y / 2 + hrp.Size.Y / 2 + 0.5, 0)
end

local function lockPlayer()
	local char = player.Character
	if not char then return end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if hum then hum.WalkSpeed = 0 hum.JumpPower = 0 end
end

local function unlockPlayer()
	local char = player.Character
	if not char then return end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if hum then hum.WalkSpeed = 16 hum.JumpPower = 50 end
end

local function showGui()
	if inBattle or inChairGui then return end
	inChairGui = true
	teleportToChair()
	lockPlayer()
	gui.Enabled = true
end

local function hideGui()
	inChairGui = false
	gui.Enabled = false
	unlockPlayer()
end

-- ── Hook ProximityPrompt on DuelTable ─────────────────────────────────────────
local function findTablePrompt()
	local tbl = workspace:FindFirstChild("DuelTable")
	if not tbl then return nil end
	for _, d in ipairs(tbl:GetDescendants()) do
		if d:IsA("ProximityPrompt") then return d end
	end
	return nil
end

local prompt = findTablePrompt()
if not prompt then
	-- Wait for it to exist (table might load late)
	workspace.DescendantAdded:Connect(function(d)
		if d:IsA("ProximityPrompt") and d.Name == "DuelTablePrompt" and not prompt then
			prompt = d
			prompt.Triggered:Connect(function() showGui() end)
		end
	end)
else
	prompt.Triggered:Connect(function() showGui() end)
end

-- ── Buttons ───────────────────────────────────────────────────────────────────
challengeBtn.Activated:Connect(function()
	if not inChairGui then return end
	gui.Enabled = false
	inBattle = true
	Remotes.StartDuel:FireServer()
end)

leaveBtn.Activated:Connect(function()
	hideGui()
end)

-- ── BattleOver: release player ────────────────────────────────────────────────
Remotes.BattleOver.OnClientEvent:Connect(function()
	-- Movement unlock handled by BattleUI ContinueBtn
	inBattle=false; inChairGui=false; gui.Enabled=false
end)

-- ── Respawn cleanup ───────────────────────────────────────────────────────────
player.CharacterAdded:Connect(function()
	inBattle   = false
	inChairGui = false
	gui.Enabled = false
end)
