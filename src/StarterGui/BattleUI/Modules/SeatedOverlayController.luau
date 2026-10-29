-- SeatedOverlayController: pre-battle table waiting UI extracted from
-- BattleUIController so that the main LocalScript stays below Luau's local
-- register ceiling.
local SeatedOverlayController = {}
SeatedOverlayController.__index = SeatedOverlayController

function SeatedOverlayController.new(deps)
	local self = setmetatable({}, SeatedOverlayController)
	self.player = assert(deps.player, "player required")
	self.remotes = assert(deps.Remotes, "Remotes required")
	self.hideBattleLoading = assert(deps.hideBattleLoading, "hideBattleLoading required")
	self.setBattleControlsLocked = assert(deps.setBattleControlsLocked, "setBattleControlsLocked required")
	self.setTablePromptsSuppressed = assert(deps.setTablePromptsSuppressed, "setTablePromptsSuppressed required")
	self.onSeated = deps.onSeated or function() end
	self.onBattleStarted = deps.onBattleStarted or function() end

	local overlay = Instance.new("ScreenGui")
	overlay.Name = "SeatedOverlay"
	overlay.ResetOnSpawn = false
	overlay.IgnoreGuiInset = true
	overlay.Enabled = false
	overlay.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	overlay.Parent = self.player.PlayerGui
	self.overlay = overlay

	local frame = Instance.new("Frame")
	frame.AnchorPoint = Vector2.new(0.5, 1)
	frame.Position = UDim2.new(0.5, 0, 1, -60)
	frame.Size = UDim2.new(0, 340, 0, 88)
	frame.BackgroundColor3 = Color3.fromRGB(15, 15, 25)
	frame.BackgroundTransparency = 0.1
	frame.BorderSizePixel = 0
	frame.Parent = overlay
	Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 10)
	local stroke = Instance.new("UIStroke", frame)
	stroke.Color = Color3.fromRGB(60, 60, 90)
	stroke.Thickness = 1

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, -16, 0, 28)
	label.Position = UDim2.new(0, 8, 0, 8)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextSize = 13
	label.TextColor3 = Color3.fromRGB(200, 200, 220)
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.Text = "Seated - waiting for opponent..."
	label.Parent = frame
	self.label = label

	local readyButton = Instance.new("TextButton")
	readyButton.Size = UDim2.new(0, 148, 0, 34)
	readyButton.Position = UDim2.new(0, 8, 1, -42)
	readyButton.BackgroundColor3 = Color3.fromRGB(18, 72, 18)
	readyButton.TextColor3 = Color3.fromRGB(160, 230, 160)
	readyButton.Font = Enum.Font.GothamBold
	readyButton.TextSize = 14
	readyButton.Text = "Ready"
	readyButton.BorderSizePixel = 0
	readyButton.Parent = frame
	Instance.new("UICorner", readyButton).CornerRadius = UDim.new(0, 6)
	self.readyButton = readyButton

	local leaveButton = Instance.new("TextButton")
	leaveButton.Size = UDim2.new(0, 148, 0, 34)
	leaveButton.Position = UDim2.new(1, -156, 1, -42)
	leaveButton.BackgroundColor3 = Color3.fromRGB(60, 18, 18)
	leaveButton.TextColor3 = Color3.fromRGB(220, 150, 150)
	leaveButton.Font = Enum.Font.GothamBold
	leaveButton.TextSize = 14
	leaveButton.Text = "Leave Seat"
	leaveButton.BorderSizePixel = 0
	leaveButton.Parent = frame
	Instance.new("UICorner", leaveButton).CornerRadius = UDim.new(0, 6)
	self.leaveButton = leaveButton

	readyButton.Activated:Connect(function()
		self.remotes.ReadyUp:FireServer()
		readyButton.Text = "Ready OK"
		readyButton.Interactable = false
	end)
	leaveButton.Activated:Connect(function()
		self.remotes.StandUp:FireServer()
	end)

	self.remotes.BattleSeated.OnClientEvent:Connect(function(_, chairIdx)
		self.onSeated()
		self.hideBattleLoading()
		overlay.Enabled = true
		label.Text = "Seated (chair " .. tostring(chairIdx) .. ") - waiting for opponent..."
		readyButton.Text = "Ready"
		readyButton.Interactable = true
		self.setBattleControlsLocked(true)
		self.setTablePromptsSuppressed(true)
	end)

	self.remotes.BattleUnseated.OnClientEvent:Connect(function()
		self:hide()
		self.hideBattleLoading()
		self.setBattleControlsLocked(false)
		self.setTablePromptsSuppressed(false)
	end)

	self.remotes.UpdateBattleState.OnClientEvent:Connect(function()
		self.onBattleStarted()
		self:hide()
		self.setBattleControlsLocked(true)
		self.setTablePromptsSuppressed(true)
	end)

	return self
end

function SeatedOverlayController:hide()
	if self.overlay then self.overlay.Enabled = false end
end

return SeatedOverlayController
