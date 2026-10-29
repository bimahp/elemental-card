-- CameraCardStage: rigid camera-space card models with live SurfaceGui faces.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local CardData = require(ReplicatedStorage.Modules.CardData)

local CameraCardStage = {}
CameraCardStage.__index = CameraCardStage

local CARD_W = 132
local CARD_H = 178
local FRONT_GUTTER_X = 22
local FRONT_GUTTER_Y = 16
local FRONT_CANVAS_W = CARD_W + FRONT_GUTTER_X * 2
local FRONT_CANVAS_H = CARD_H + FRONT_GUTTER_Y * 2
local BASE_DISTANCE = 5
local STACK_OFFSET_PX = 3
local STACK_DEPTH = 0.055
local FLIP_SECONDS = 0.42
local FLY_SECONDS = 0.28
local EMBLEM_NAMES = { "CostBadge", "ChargeCostBadge", "AttackEmblem", "HealthEmblem" }

local function getStroke(frame, CardVisuals, battleType)
	local stroke = frame:FindFirstChildOfClass("UIStroke")
	if not stroke then
		stroke = Instance.new("UIStroke")
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Thickness = 3
		stroke.Parent = frame
	end
	stroke.Color = CardVisuals.TC_type[battleType] or Color3.fromRGB(150, 150, 150)
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

local function captureTransparency(object)
	local values = {}
	if object:IsA("GuiObject") then
		values.BackgroundTransparency = object.BackgroundTransparency
	end
	if object:IsA("ImageLabel") or object:IsA("ImageButton") then
		values.ImageTransparency = object.ImageTransparency
	end
	if object:IsA("TextLabel") or object:IsA("TextButton") or object:IsA("TextBox") then
		values.TextTransparency = object.TextTransparency
		values.TextStrokeTransparency = object.TextStrokeTransparency
	end
	if object:IsA("UIStroke") then
		values.Transparency = object.Transparency
	end
	return values
end

local function captureEmblems(frame)
	local records = {}
	for _, name in ipairs(EMBLEM_NAMES) do
		local badge = frame:FindFirstChild(name)
		if badge then
			local record = {
				instance = badge,
				originalVisible = badge.Visible,
				parts = {},
			}
			local objects = { badge }
			for _, descendant in ipairs(badge:GetDescendants()) do
				objects[#objects + 1] = descendant
			end
			for _, object in ipairs(objects) do
				local values = captureTransparency(object)
				if next(values) then
					record.parts[#record.parts + 1] = { object = object, values = values }
				end
			end
			badge.Visible = false
			records[#records + 1] = record
		end
	end
	return records
end

local function setEmblemAlpha(records, alpha)
	alpha = math.clamp(alpha or 0, 0, 1)
	for _, record in ipairs(records) do
		record.instance.Visible = record.originalVisible and alpha > 0
		for _, part in ipairs(record.parts) do
			for property, finalValue in pairs(part.values) do
				if alpha >= 1 then
					part.object[property] = finalValue
				else
					part.object[property] = 1 - alpha * (1 - finalValue)
				end
			end
		end
	end
end

local function configurePart(part)
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Massless = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
end

local function newSurface(playerGui, name, adornee, face, canvasSize)
	local surface = Instance.new("SurfaceGui")
	surface.Name = name
	surface.Adornee = adornee
	surface.Face = face
	surface.AlwaysOnTop = true
	surface.LightInfluence = 0
	surface.Brightness = 1
	surface.MaxDistance = 0
	surface.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	surface.CanvasSize = canvasSize
	surface.ClipsDescendants = false
	surface.Enabled = false
	surface.ZOffset = 5
	surface.Parent = playerGui
	return surface
end

function CameraCardStage.new(playerGui, screenAnchor, CardVisuals, onInvalidated)
	local self = setmetatable({}, CameraCardStage)
	self.playerGui = playerGui
	self.screenAnchor = screenAnchor
	self.CardVisuals = CardVisuals
	self.onInvalidated = onInvalidated
	self.id = HttpService:GenerateGUID(false)
	self.renderKey = "PackReveal3D_" .. self.id
	self.camera = Workspace.CurrentCamera
	self.entries = {}
	self.visible = false
	self.alive = true
	self.renderFailed = false

	self.container = Instance.new("Folder")
	self.container.Name = "PackReveal3D_" .. self.id
	self.container.Parent = self.camera or Workspace

	self.dimEffect = Instance.new("ColorCorrectionEffect")
	self.dimEffect.Name = "PackRevealDim_" .. self.id
	self.dimEffect.Brightness = -0.4
	self.dimEffect.Contrast = 0.1
	self.dimEffect.Saturation = -0.15
	self.dimEffect.Parent = self.camera or Workspace

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		self.hiddenHumanoid = humanoid
		self.originalDisplayDistanceType = humanoid.DisplayDistanceType
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	end

	self.cameraConnection = Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		self.camera = Workspace.CurrentCamera
		if self.camera then
			if self.container then self.container.Parent = self.camera end
			if self.dimEffect then self.dimEffect.Parent = self.camera end
		end
	end)
	self.characterConnection = player.CharacterAdded:Connect(function()
		if self.alive then
			self:_invalidate("Character changed during card reveal")
		end
	end)

	RunService:BindToRenderStep(self.renderKey, Enum.RenderPriority.Camera.Value + 1, function()
		if not self.alive or self.renderFailed then return end
		local ok, message = xpcall(function()
			self:_render()
		end, debug.traceback)
		if not ok then
			self.renderFailed = true
			self:_invalidate(message)
		end
	end)
	return self
end

function CameraCardStage:_invalidate(message)
	if not self.alive then return end
	local callback = self.onInvalidated
	self.onInvalidated = nil
	self:Destroy()
	if callback then
		task.defer(callback, message)
	end
end

function CameraCardStage:_destroyEntry(entry)
	if not entry or not entry.alive then return end
	entry.alive = false
	if entry.frontSurface then entry.frontSurface:Destroy() end
	if entry.backSurface then entry.backSurface:Destroy() end
	if entry.model then entry.model:Destroy() end
end

function CameraCardStage:_clearEntries()
	for _, entry in ipairs(self.entries) do
		self:_destroyEntry(entry)
	end
	self.entries = {}
end

function CameraCardStage:_makeEntry(cardInfo, index)
	local opts = cardOptsFromInfo(cardInfo)
	if not opts then error("Unknown card returned by server: " .. tostring(cardInfo and cardInfo.cardId)) end

	local model = Instance.new("Model")
	model.Name = "Card3D_" .. index
	model.Parent = self.container

	local body = Instance.new("Part")
	body.Name = "CardBody"
	configurePart(body)
	body.Material = Enum.Material.SmoothPlastic
	body.Color = Color3.fromRGB(48, 34, 25)
	body.Transparency = 1
	body.Parent = model

	local frontAdorner = Instance.new("Part")
	frontAdorner.Name = "FrontAdorner"
	configurePart(frontAdorner)
	frontAdorner.Transparency = 1
	frontAdorner.Parent = model

	local backSurface = newSurface(
		self.playerGui,
		"PackCardBack_" .. self.id .. "_" .. index,
		body,
		Enum.NormalId.Back,
		Vector2.new(CARD_W, CARD_H)
	)
	local back = self.CardVisuals.mkBack(CARD_W, CARD_H)
	back.Name = "BackFace"
	back.Size = UDim2.fromOffset(CARD_W, CARD_H)
	back.Position = UDim2.fromOffset(0, 0)
	back.Parent = backSurface

	local frontSurface = newSurface(
		self.playerGui,
		"PackCardFront_" .. self.id .. "_" .. index,
		frontAdorner,
		Enum.NormalId.Front,
		Vector2.new(FRONT_CANVAS_W, FRONT_CANVAS_H)
	)
	local front = self.CardVisuals.buildCardFrame(CARD_W, CARD_H, "full")
	front.Name = "FrontFace"
	front.Position = UDim2.fromOffset(FRONT_GUTTER_X, FRONT_GUTTER_Y)
	front.Parent = frontSurface
	self.CardVisuals.updateCardFrame(front, opts)
	getStroke(front, self.CardVisuals, opts.battleType)
	local emblems = captureEmblems(front)
	setEmblemAlpha(emblems, 0)

	return {
		index = index,
		info = cardInfo,
		model = model,
		body = body,
		frontAdorner = frontAdorner,
		backSurface = backSurface,
		frontSurface = frontSurface,
		frontFrame = front,
		emblems = emblems,
		baseOffset = Vector2.new((index - 1) * STACK_OFFSET_PX, -(index - 1) * STACK_OFFSET_PX),
		screenOffset = Vector2.zero,
		yaw = 0,
		roll = 0,
		arc = 0,
		revealProgress = 0,
		faceUp = false,
		alive = true,
	}
end

function CameraCardStage:SetCards(cardResults)
	assert(self.alive, "CameraCardStage is destroyed")
	assert(type(cardResults) == "table" and #cardResults == 5, "Expected five card results")
	self:_clearEntries()
	for index, cardInfo in ipairs(cardResults) do
		self.entries[index] = self:_makeEntry(cardInfo, index)
	end
	self:_render()
end

function CameraCardStage:SetVisible(visible)
	self.visible = visible == true
	if self.alive then self:_render() end
end

function CameraCardStage:_renderEntry(entry, camera, center, viewport)
	if not entry.alive then return end
	local baseDistance = BASE_DISTANCE + (entry.index - 1) * STACK_DEPTH
	local verticalSpan = 2 * baseDistance * math.tan(math.rad(camera.FieldOfView / 2))
	local studsPerPixel = verticalSpan / math.max(1, viewport.Y)
	local worldH = CARD_H * studsPerPixel
	local worldW = CARD_W * studsPerPixel
	local thickness = math.max(0.035, worldH * 0.025)
	local distance = baseDistance - entry.arc * worldH * 0.12

	local screen = center + entry.baseOffset + entry.screenOffset + Vector2.new(0, -entry.arc * 10)
	local x = (screen.X - viewport.X / 2) * studsPerPixel
	local y = -(screen.Y - viewport.Y / 2) * studsPerPixel
	local cardCFrame = camera.CFrame
		* CFrame.new(x, y, -distance)
		* CFrame.Angles(0, math.rad(entry.yaw), math.rad(entry.roll))

	entry.body.Size = Vector3.new(worldW, worldH, thickness)
	entry.body.CFrame = cardCFrame
	entry.frontAdorner.Size = Vector3.new(
		worldW * (FRONT_CANVAS_W / CARD_W),
		worldH * (FRONT_CANVAS_H / CARD_H),
		0.01
	)
	entry.frontAdorner.CFrame = cardCFrame * CFrame.new(0, 0, -thickness / 2 - 0.006)

	local showing = self.visible
	entry.body.Transparency = showing and 0 or 1
	local frontFacing = entry.yaw >= 90
	entry.backSurface.Enabled = showing and not frontFacing
	entry.frontSurface.Enabled = showing and frontFacing

	if entry.revealProgress < 0.8 then
		setEmblemAlpha(entry.emblems, 0)
	else
		setEmblemAlpha(entry.emblems, (entry.revealProgress - 0.8) / 0.2)
	end
end

function CameraCardStage:_render()
	if not self.alive then return end
	local camera = Workspace.CurrentCamera
	if not camera or not self.screenAnchor or not self.screenAnchor.Parent then return end
	self.camera = camera
	local viewport = camera.ViewportSize
	local center = self.screenAnchor.AbsolutePosition + self.screenAnchor.AbsoluteSize / 2
	for _, entry in ipairs(self.entries) do
		self:_renderEntry(entry, camera, center, viewport)
	end
end

function CameraCardStage:_animate(duration, update)
	local started = os.clock()
	while self.alive do
		local raw = math.clamp((os.clock() - started) / duration, 0, 1)
		update(raw)
		if raw >= 1 then return true end
		task.wait()
	end
	return false
end

function CameraCardStage:Flip(index)
	assert(self.alive, "CameraCardStage is destroyed")
	local entry = self.entries[index]
	assert(entry and entry.alive, "Card entry is unavailable")
	if entry.faceUp then return true end

	local completed = self:_animate(FLIP_SECONDS, function(raw)
		local eased = 0.5 - math.cos(math.pi * raw) / 2
		entry.yaw = 180 * eased
		entry.arc = math.sin(math.pi * raw)
		entry.revealProgress = raw
	end)
	if not completed then return false end
	entry.yaw = 180
	entry.arc = 0
	entry.revealProgress = 1
	entry.faceUp = true
	setEmblemAlpha(entry.emblems, 1)
	return true
end

function CameraCardStage:FlyOut(index)
	assert(self.alive, "CameraCardStage is destroyed")
	local entry = self.entries[index]
	assert(entry and entry.alive, "Card entry is unavailable")
	local viewport = (Workspace.CurrentCamera and Workspace.CurrentCamera.ViewportSize) or Vector2.new(1280, 720)
	local startOffset = entry.screenOffset

	local completed = self:_animate(FLY_SECONDS, function(raw)
		local eased = raw * raw * raw * raw
		entry.screenOffset = startOffset + Vector2.new(viewport.X * 0.72 * eased, -24 * eased)
		entry.roll = 16 * eased
		entry.yaw = 180 + 8 * eased
		entry.revealProgress = 1
	end)
	if not completed then return false end
	self:_destroyEntry(entry)
	return true
end

function CameraCardStage:GetEntry(index)
	return self.entries[index]
end

function CameraCardStage:Destroy()
	if not self.alive then return end
	self.alive = false
	RunService:UnbindFromRenderStep(self.renderKey)
	if self.cameraConnection then self.cameraConnection:Disconnect() end
	if self.characterConnection then self.characterConnection:Disconnect() end
	self:_clearEntries()
	if self.dimEffect then self.dimEffect:Destroy(); self.dimEffect = nil end
	if self.container then self.container:Destroy(); self.container = nil end
	if self.hiddenHumanoid and self.hiddenHumanoid.Parent and self.originalDisplayDistanceType then
		self.hiddenHumanoid.DisplayDistanceType = self.originalDisplayDistanceType
	end
	self.onInvalidated = nil
end

return CameraCardStage
