-- PackRevealController: modal purchase-result flow backed by rigid camera-space 3D cards.
local TweenService = game:GetService("TweenService")
local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local CardVisuals = require(playerGui:WaitForChild("BattleUI"):WaitForChild("Modules"):WaitForChild("CardVisuals"))
local CardData = require(ReplicatedStorage.Modules.CardData)
local AssetIds = require(ReplicatedStorage.Modules.AssetIds)
local AssetPreloader = require(ReplicatedStorage.Modules.AssetPreloader)
local Config = require(ReplicatedStorage.Modules.GachaConfig)
local CameraCardStage = require(script.Parent:WaitForChild("CameraCardStage"))

local PackRevealController = {}
PackRevealController.__index = PackRevealController

local CARD_W = 132
local CARD_H = 178
local SUMMARY_HOLDER_W = 168
local SUMMARY_HOLDER_H = 236
local SUMMARY_TOP_PAD = 16
local SUMMARY_GAP = 8
local SUMMARY_BACKGROUND_TRANSPARENCY = 0.12
local MOVEMENT_ACTIONS = {
	Enum.PlayerActions.CharacterForward,
	Enum.PlayerActions.CharacterBackward,
	Enum.PlayerActions.CharacterLeft,
	Enum.PlayerActions.CharacterRight,
	Enum.PlayerActions.CharacterJump,
}
local modalLockSerial = 0

local function getStroke(frame)
	local stroke = frame:FindFirstChildOfClass("UIStroke")
	if not stroke then
		stroke = Instance.new("UIStroke")
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Thickness = 3
		stroke.Parent = frame
	end
	return stroke
end

local function cardOptsFromInfo(cardInfo)
	local card = cardInfo and CardData.Cards[cardInfo.cardId]
	if not card then return nil end
	local abilityName, abilityBody = CardData.getAbilityDisplay(cardInfo.cardId)
	return {
		battleType = card.battleType,
		cardType = card.cardType,
		cardId = card.id,
		cost = card.cost,
		chargeCost = card.chargeCost,
		corrupted = card.corrupted,
		name = card.name,
		race = card.race,
		atk = card.atk,
		hp = card.hp,
		abilityName = abilityName,
		abilityText = abilityBody,
	}
end

local function clearContainer(container)
	for _, child in ipairs(container:GetChildren()) do
		child:Destroy()
	end
end

function PackRevealController.new(packUI)
	local self = setmetatable({}, PackRevealController)
	self.packUI = packUI
	self.root = packUI:WaitForChild("Root")
	self.burstLayer = self.root:WaitForChild("BurstLayer")
	self.cardStack = self.root:WaitForChild("CardStack")
	self.hintText = self.root:WaitForChild("HintText")
	self.controls = self.root:WaitForChild("Controls")
	self.skipBtn = self.controls:WaitForChild("SkipBtn")
	self.primaryBtn = self.controls:WaitForChild("PrimaryBtn")
	self.summary = self.root:WaitForChild("Summary")
	self.results = self.summary:WaitForChild("Results")
	self.dustLabel = self.summary:WaitForChild("DustLabel")
	self.claimBtn = self.summary:WaitForChild("ClaimBtn")
	self.state = "Idle"
	self.cardStage = nil
	self.currentIndex = 0
	self.result = nil
	self.onClaimed = nil
	self.summaryResizeConnection = nil
	self.openToken = 0
	self.gameplayLock = nil

	self.skipConnection = self.skipBtn.Activated:Connect(function()
		if self.state == "StackReady" or self.state == "FaceUp" then
			self:_showSummary()
		end
	end)
	self.primaryConnection = self.primaryBtn.Activated:Connect(function()
		if self.state == "StackReady" then
			self:_runGuarded(function() self:_flipCurrent() end)
		elseif self.state == "FaceUp" then
			self:_runGuarded(function() self:_dismissAndAdvance() end)
		end
	end)
	self.claimConnection = self.claimBtn.Activated:Connect(function()
		if self.state == "Summary" then self:_claim() end
	end)
	return self
end

function PackRevealController:_setButtonEnabled(button, enabled)
	button.Active = enabled
	button.Selectable = enabled
	button.AutoButtonColor = enabled
	button.BackgroundTransparency = enabled and 0 or 0.4
	button.TextTransparency = enabled and 0 or 0.35
end

function PackRevealController:_setControls(skipVisible, primaryVisible, primaryText, enabled)
	self.controls.Visible = skipVisible or primaryVisible
	self.skipBtn.Visible = skipVisible
	self.primaryBtn.Visible = primaryVisible
	if primaryText then self.primaryBtn.Text = primaryText end
	self:_setButtonEnabled(self.skipBtn, enabled and skipVisible)
	self:_setButtonEnabled(self.primaryBtn, enabled and primaryVisible)
end

function PackRevealController:_destroyStage()
	if self.cardStage then
		self.cardStage:Destroy()
		self.cardStage = nil
	end
end

function PackRevealController:_clearDynamic()
	self:_destroyStage()
	clearContainer(self.burstLayer)
	clearContainer(self.cardStack)
	clearContainer(self.results)
	if self.summaryResizeConnection then
		self.summaryResizeConnection:Disconnect()
		self.summaryResizeConnection = nil
	end
end

function PackRevealController:_releaseGameplayLock()
	local lock = self.gameplayLock
	if not lock then return end
	self.gameplayLock = nil
	lock.active = false

	if lock.descendantConnection then lock.descendantConnection:Disconnect() end
	if lock.characterConnection then lock.characterConnection:Disconnect() end
	if lock.actionName then ContextActionService:UnbindAction(lock.actionName) end

	for prompt, record in pairs(lock.prompts) do
		if record.connection then record.connection:Disconnect() end
		if prompt.Parent then prompt.Enabled = record.enabled end
	end
	for humanoid, jumpEnabled in pairs(lock.humanoids) do
		if humanoid.Parent then
			humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, jumpEnabled)
		end
	end
	if lock.controls then lock.controls:Enable() end
end

function PackRevealController:_acquireGameplayLock()
	self:_releaseGameplayLock()
	modalLockSerial += 1
	local lock = {
		active = true,
		actionName = "PackRevealMovementLock_" .. modalLockSerial,
		prompts = {},
		humanoids = {},
	}
	self.gameplayLock = lock

	local function suppressPrompt(prompt)
		if not prompt:IsA("ProximityPrompt") then return end
		local record = lock.prompts[prompt]
		if not record then
			record = { enabled = prompt.Enabled }
			lock.prompts[prompt] = record
			record.connection = prompt:GetPropertyChangedSignal("Enabled"):Connect(function()
				if lock.active and prompt.Enabled then
					record.enabled = true
					prompt.Enabled = false
				end
			end)
		end
		if prompt.Enabled then prompt.Enabled = false end
	end
	for _, descendant in ipairs(workspace:GetDescendants()) do suppressPrompt(descendant) end
	lock.descendantConnection = workspace.DescendantAdded:Connect(suppressPrompt)

	local function lockCharacter(character)
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not humanoid or lock.humanoids[humanoid] ~= nil then return end
		lock.humanoids[humanoid] = humanoid:GetStateEnabled(Enum.HumanoidStateType.Jumping)
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
	end
	lockCharacter(player.Character)
	lock.characterConnection = player.CharacterAdded:Connect(function(character)
		local humanoid = character:WaitForChild("Humanoid", 5)
		if humanoid and lock.active then lockCharacter(character) end
	end)

	local ok, playerModule = pcall(function()
		return require(player.PlayerScripts:WaitForChild("PlayerModule"))
	end)
	if ok and playerModule then
		lock.controls = playerModule:GetControls()
		lock.controls:Disable()
	end
	ContextActionService:BindActionAtPriority(
		lock.actionName,
		function() return Enum.ContextActionResult.Sink end,
		false,
		Enum.ContextActionPriority.High.Value + 100,
		table.unpack(MOVEMENT_ACTIONS)
	)
end

function PackRevealController:_playBurst()
	self.state = "Burst"
	self:_setControls(false, false, nil, false)
	self.hintText.Visible = false
	self.cardStack.Visible = true
	self.summary.Visible = false

	local iconAsset = AssetIds.Icons and AssetIds.Icons.CRYSTAL_SHARD or ""
	local viewport = self.burstLayer.AbsoluteSize
	if viewport.X < 1 or viewport.Y < 1 then
		local camera = workspace.CurrentCamera
		viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
	end
	local diagonal = math.sqrt(viewport.X * viewport.X + viewport.Y * viewport.Y)
	local shortSide = math.min(viewport.X, viewport.Y)
	local particleCount = math.clamp(math.floor(diagonal / 34), 36, 58)
	local minRadius = math.max(180, math.floor(diagonal * 0.28))
	local maxRadius = math.max(minRadius + 1, math.floor(diagonal * 0.58))
	local baseSize = math.clamp(math.floor(shortSide * 0.12), 80, 150)

	for i = 1, particleCount do
		local angle = math.rad((i - 1) * (360 / particleCount) + math.random(-7, 7))
		local radius = math.random(minRadius, maxRadius)
		local startSize = math.random(math.floor(baseSize * 0.75), math.floor(baseSize * 1.25))
		local endSize = math.max(28, math.floor(startSize * 0.42))
		local duration = 0.62 + math.random() * 0.22
		local particle = Instance.new("ImageLabel")
		particle.Name = "CrystalBurst"
		particle.AnchorPoint = Vector2.new(0.5, 0.5)
		particle.Position = UDim2.fromScale(0.5, 0.48)
		particle.Size = UDim2.fromOffset(startSize, startSize)
		particle.BackgroundTransparency = 1
		particle.Image = iconAsset
		particle.ImageColor3 = Color3.fromRGB(140, 225, 255)
		particle.Rotation = math.random(0, 359)
		particle.ZIndex = 12
		particle.Parent = self.burstLayer
		TweenService:Create(
			particle,
			TweenInfo.new(duration, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
			{
				Position = UDim2.new(0.5, math.cos(angle) * radius, 0.48, math.sin(angle) * radius),
				Size = UDim2.fromOffset(endSize, endSize),
				ImageTransparency = 1,
				Rotation = particle.Rotation + math.random(-150, 150),
			}
		):Play()
		task.delay(duration + 0.08, function()
			if particle.Parent then particle:Destroy() end
		end)
	end
	-- Do not wait on a tween that may be destroyed during a cold-load frame stall.
	task.wait(0.9)
	clearContainer(self.burstLayer)
end

function PackRevealController:_showStack()
	assert(self.cardStage and self.cardStage.alive, "3D card stage is unavailable")
	self.cardStage:SetVisible(true)
	self.cardStack.Visible = true
	self.summary.Visible = false
	self.currentIndex = 1
	self.state = "StackReady"
	self.hintText.Text = "5 cards ready"
	self.hintText.Visible = true
	self:_setControls(true, true, "Reveal", true)
end

function PackRevealController:_flipCurrent()
	assert(self.cardStage and self.cardStage.alive, "3D card stage is unavailable")
	self.state = "Flipping"
	self.hintText.Text = "Revealing card " .. self.currentIndex .. " of " .. #self.result.cards
	self:_setControls(true, true, self.currentIndex == 1 and "Reveal" or "Next", false)
	assert(self.cardStage:Flip(self.currentIndex), "3D card flip was interrupted")
	self.state = "FaceUp"
	self.hintText.Text = "Card " .. self.currentIndex .. " of " .. #self.result.cards
	local primaryText = self.currentIndex == #self.result.cards and "Done" or "Next"
	self:_setControls(true, true, primaryText, true)
end

function PackRevealController:_dismissAndAdvance()
	assert(self.cardStage and self.cardStage.alive, "3D card stage is unavailable")
	if self.currentIndex >= #self.result.cards then
		self:_showSummary()
		return
	end
	self.state = "Dismissing"
	self:_setControls(true, true, "Next", false)
	assert(self.cardStage:FlyOut(self.currentIndex), "3D card fly-out was interrupted")
	self.currentIndex += 1
	if self.currentIndex > #self.result.cards then
		self:_showSummary()
		return
	end
	self:_flipCurrent()
end

function PackRevealController:_statusFor(cardInfo)
	if cardInfo.isDupe then
		-- Duplicate protection already applied upstream; a dupe here is just an
		-- extra copy added to the collection, no currency conversion (Crystal
		-- Dust is retired -- see DESIGN_ECONOMY.md §12.4).
		return "Duplicate", Color3.fromRGB(130, 220, 255)
	elseif cardInfo.isNew then
		return "New", Color3.fromRGB(120, 245, 150)
	end
	return "Added Copy", Color3.fromRGB(255, 220, 105)
end

function PackRevealController:_buildSummaryCard(parent, cardInfo, index)
	local holder = Instance.new("Frame")
	holder.Name = "Result" .. index
	holder.Size = UDim2.fromOffset(SUMMARY_HOLDER_W, SUMMARY_HOLDER_H)
	holder.BackgroundTransparency = 1
	holder.LayoutOrder = index
	holder.Parent = parent

	local opts = cardOptsFromInfo(cardInfo)
	if not opts then error("Unknown summary card: " .. tostring(cardInfo.cardId)) end
	local frame = CardVisuals.buildCardFrame(CARD_W, CARD_H, "full")
	frame.AnchorPoint = Vector2.new(0.5, 0)
	frame.Position = UDim2.fromOffset(math.floor(SUMMARY_HOLDER_W / 2), SUMMARY_TOP_PAD)
	frame.Parent = holder
	CardVisuals.updateCardFrame(frame, opts)
	getStroke(frame).Color = CardVisuals.TC_type[opts.battleType] or Color3.fromRGB(150, 150, 150)

	local statusText, statusColor = self:_statusFor(cardInfo)
	local status = Instance.new("TextLabel")
	status.Name = "Status"
	status.Position = UDim2.fromOffset(4, SUMMARY_TOP_PAD + 184)
	status.Size = UDim2.fromOffset(SUMMARY_HOLDER_W - 8, 32)
	status.BackgroundColor3 = Color3.fromRGB(18, 23, 34)
	status.BackgroundTransparency = 0.08
	status.BorderSizePixel = 0
	status.Font = Enum.Font.GothamBold
	status.Text = statusText
	status.TextColor3 = statusColor
	status.TextSize = 12
	status.TextWrapped = true
	status.ZIndex = 80
	status.Parent = holder
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 7)
	corner.Parent = status
end

function PackRevealController:_showSummary()
	if self.state == "Summary" or self.state == "Closing" or self.state == "Idle" then return end
	self.state = "Summary"
	self:_destroyStage()
	self.root.BackgroundTransparency = SUMMARY_BACKGROUND_TRANSPARENCY
	self.cardStack.Visible = false
	self.hintText.Visible = false
	self.controls.Visible = false
	self.summary.Visible = true
	clearContainer(self.results)
	if self.summaryResizeConnection then
		self.summaryResizeConnection:Disconnect()
		self.summaryResizeConnection = nil
	end

	local content = Instance.new("Frame")
	content.Name = "ResultsContent"
	content.BackgroundTransparency = 1
	content.Size = UDim2.fromOffset(5 * SUMMARY_HOLDER_W + 4 * SUMMARY_GAP, SUMMARY_HOLDER_H)
	content.Parent = self.results
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	layout.VerticalAlignment = Enum.VerticalAlignment.Top
	layout.Padding = UDim.new(0, SUMMARY_GAP)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = content
	for index, cardInfo in ipairs(self.result.cards) do
		self:_buildSummaryCard(content, cardInfo, index)
	end

	local totalWidth = 5 * SUMMARY_HOLDER_W + 4 * SUMMARY_GAP
	self.results.CanvasPosition = Vector2.zero
	self.results.CanvasSize = UDim2.fromOffset(totalWidth, 0)
	local function updatePosition()
		local extra = math.max(0, self.results.AbsoluteSize.X - totalWidth)
		content.Position = UDim2.fromOffset(math.floor(extra / 2), 0)
		self.results.ScrollingEnabled = extra == 0
	end
	updatePosition()
	self.summaryResizeConnection = self.results:GetPropertyChangedSignal("AbsoluteSize"):Connect(updatePosition)

	local dupeCount = 0
	for _, cardInfo in ipairs(self.result.cards) do
		if cardInfo.isDupe then dupeCount += 1 end
	end
	self.dustLabel.Text = dupeCount > 0
		and (dupeCount .. (dupeCount == 1 and " duplicate card added" or " duplicate cards added"))
		or "No duplicates this pack"
	self.claimBtn.Visible = true
	self:_setButtonEnabled(self.claimBtn, true)
end

function PackRevealController:_fallbackToSummary(message)
	warn("[PackRevealController] " .. tostring(message))
	if self.result and type(self.result.cards) == "table" then
		self.state = "Fallback"
		local ok, summaryError = pcall(function() self:_showSummary() end)
		if ok then return end
		warn("[PackRevealController] summary fallback failed: " .. tostring(summaryError))
	end
	self:_claim()
end

function PackRevealController:_runGuarded(callback)
	task.spawn(function()
		local ok, message = xpcall(callback, debug.traceback)
		if not ok then self:_fallbackToSummary(message) end
	end)
end

function PackRevealController:Open(result, onClaimed)
	if type(result) ~= "table" or type(result.cards) ~= "table" or #result.cards ~= Config.CARDS_PER_PULL then
		return false, "The server returned an invalid pack."
	end
	if self.state ~= "Idle" then
		return false, "A pack reveal is already active."
	end

	self.result = result
	self.onClaimed = onClaimed
	self.currentIndex = 0
	self.openToken += 1
	local openToken = self.openToken
	self:_clearDynamic()
	self:_acquireGameplayLock()
	self.state = "Preparing"
	self.root.BackgroundTransparency = SUMMARY_BACKGROUND_TRANSPARENCY
	self.summary.Visible = false
	self.controls.Visible = false
	self.hintText.Text = "Preparing cards…"
	self.hintText.Visible = true
	self.cardStack.Visible = true
	self.packUI.Enabled = true

	self:_runGuarded(function()
		local preloadSummary = AssetPreloader.preload(AssetIds.revealList(result.cards), {
			attempts = 2,
			assetTimeout = 6,
			concurrency = 4,
			parent = playerGui,
			onProgress = function(done, total)
				if self.openToken == openToken and self.state == "Preparing" and total > 0 then
					self.hintText.Text = ("Preparing cards… %d/%d"):format(done, total)
				end
			end,
		})
		if self.openToken ~= openToken or self.state ~= "Preparing" then return end
		if not preloadSummary.ok then
			warn(("[PackRevealController] %d reveal asset(s) failed after retries: %s")
				:format(#preloadSummary.failed, AssetPreloader.describeFailures(preloadSummary)))
		end

		self.root.BackgroundTransparency = 1
		self.hintText.Visible = false
		self.cardStage = CameraCardStage.new(playerGui, self.cardStack, CardVisuals, function(message)
			if self.openToken == openToken and self.state ~= "Idle" and self.state ~= "Summary" and self.state ~= "Closing" then
				self.cardStage = nil
				self:_fallbackToSummary(message)
			end
		end)
		self.cardStage:SetCards(result.cards)
		self.cardStage:SetVisible(false)
		self:_playBurst()
		if self.openToken ~= openToken then return end
		self:_showStack()
	end)
	return true
end

function PackRevealController:_claim()
	if self.state == "Closing" or self.state == "Idle" then return end
	self.openToken += 1
	self.state = "Closing"
	self:_setButtonEnabled(self.claimBtn, false)
	local callback = self.onClaimed
	self.onClaimed = nil
	self:_clearDynamic()
	self.root.BackgroundTransparency = SUMMARY_BACKGROUND_TRANSPARENCY
	self.summary.Visible = false
	self.controls.Visible = false
	self.hintText.Visible = false
	self.cardStack.Visible = false
	self.packUI.Enabled = false
	self.result = nil
	self.currentIndex = 0
	self.state = "Idle"
	self:_releaseGameplayLock()
	if callback then callback() end
end

function PackRevealController:Destroy()
	self.openToken += 1
	self.state = "Idle"
	if self.skipConnection then self.skipConnection:Disconnect() end
	if self.primaryConnection then self.primaryConnection:Disconnect() end
	if self.claimConnection then self.claimConnection:Disconnect() end
	if self.summaryResizeConnection then self.summaryResizeConnection:Disconnect() end
	self:_clearDynamic()
	self:_releaseGameplayLock()
	self.packUI.Enabled = false
	self.root.BackgroundTransparency = SUMMARY_BACKGROUND_TRANSPARENCY
end

return PackRevealController
