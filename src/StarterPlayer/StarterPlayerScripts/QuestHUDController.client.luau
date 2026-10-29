-- QuestHUDController: directional arrow, exclamation ! marks, Noob dialogue dispatch.
local Players      = game:GetService("Players")
local RunService   = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DialogueController = require(script.Parent.DialogueController)
local QuestConfig        = require(ReplicatedStorage.Modules.QuestConfig)
local Remotes            = ReplicatedStorage:WaitForChild("Remotes")

local localPlayer = Players.LocalPlayer
local camera      = workspace.CurrentCamera

local PlayerGui  = localPlayer:WaitForChild("PlayerGui")
local QuestHUD   = PlayerGui:WaitForChild("QuestHUD", 30)
local QuestArrow = QuestHUD and QuestHUD:WaitForChild("QuestArrow", 5)

local currentStage   = "complete"
local arrowTargets   = {}
local exclMarks      = {}

local QUEST_TARGETS  = {}
local Noob, Trainers, MightyT, SwiftT, VitalT

------------------------------------------------------------------------
-- Quest marks integrated into the NPC nameplate SurfaceGui
------------------------------------------------------------------------
local function getModelAnchor(model)
	return model and (model:FindFirstChild("HumanoidRootPart")
		or model:FindFirstChild("UpperTorso")
		or model:FindFirstChild("Torso")
		or model:FindFirstChild("Head")
		or model.PrimaryPart)
end
local function findNameplateMark(model)
	if not model then return nil end
	for _, part in ipairs(workspace:GetChildren()) do
		if part.Name == "NameplatePart" and part:GetAttribute("TargetModelName") == model.Name then
			local surface = part:FindFirstChild("NameplateSurface")
			local mark = surface and surface:FindFirstChild("QuestMark")
			if mark then return mark end
		end
	end
	return nil
end
local function clearExclMarks()
	for _, part in ipairs(workspace:GetChildren()) do
		if part.Name == "NameplatePart" then
			local surface = part:FindFirstChild("NameplateSurface")
			local mark = surface and surface:FindFirstChild("QuestMark")
			if mark then mark.Visible = false end
		end
	end
	exclMarks = {}
end
local function targetIsActive(model)
	for _, target in ipairs(arrowTargets) do if target == model then return true end end
	return false
end
local function showNameplateMark(model)
	local mark = findNameplateMark(model)
	if mark then mark.Visible = true; exclMarks[model] = mark; return end
	task.spawn(function()
		for _ = 1, 40 do
			if not targetIsActive(model) then return end
			mark = findNameplateMark(model)
			if mark then mark.Visible = true; exclMarks[model] = mark; return end
			task.wait(0.25)
		end
	end)
end

local function setTargets(stage)
	clearExclMarks()
	arrowTargets = {}
	local list = QUEST_TARGETS[stage]
	if not list then
		if QuestArrow then QuestArrow.Visible = false end
		return
	end
	for _, model in ipairs(list) do
		if model and model.Parent then
			arrowTargets[#arrowTargets + 1] = model
			showNameplateMark(model)
		end
	end
	if QuestArrow then QuestArrow.Visible = #arrowTargets > 0 end
end

------------------------------------------------------------------------
-- Directional arrow (RenderStepped)
------------------------------------------------------------------------
local function clampToEdge(cx, cy, dx, dy, margin, vpX, vpY)
	local minX, maxX = margin, vpX - margin
	local minY, maxY = margin, vpY - margin
	local tx = math.huge
	if     dx > 0 then tx = (maxX - cx) / dx
	elseif dx < 0 then tx = (minX - cx) / dx end
	local ty = math.huge
	if     dy > 0 then ty = (maxY - cy) / dy
	elseif dy < 0 then ty = (minY - cy) / dy end
	local t = math.min(math.abs(tx), math.abs(ty))
	return cx + dx * t, cy + dy * t
end

RunService.RenderStepped:Connect(function()
	camera = workspace.CurrentCamera or camera
	if not QuestArrow or #arrowTargets == 0 then
		if QuestArrow then QuestArrow.Visible = false end
		return
	end
	local char = localPlayer.Character
	local pHrp = char and char:FindFirstChild("HumanoidRootPart")

	local nearest, nearestDist = arrowTargets[1], math.huge
	if pHrp then
		for _, target in ipairs(arrowTargets) do
			local tHrp = getModelAnchor(target)
			if tHrp then
				local d = (tHrp.CFrame.Position - pHrp.CFrame.Position).Magnitude
				if d < nearestDist then nearest = target; nearestDist = d end
			end
		end
	end

	local tHrp = getModelAnchor(nearest)
	if not tHrp then QuestArrow.Visible = false; return end

	local targetPos = tHrp.CFrame.Position
	local screenPos, inView = camera:WorldToViewportPoint(targetPos)
	local vp = camera.ViewportSize
	local margin = 80

	-- Hide arrow when NPC is visible on screen and within close range
	local onScreen = inView
		and screenPos.X >= margin and screenPos.X <= vp.X - margin
		and screenPos.Y >= margin and screenPos.Y <= vp.Y - margin
	if onScreen and nearestDist < 35 then
		QuestArrow.Visible = false
		return
	end

	QuestArrow.Visible = true

	local cx, cy = vp.X * 0.5, vp.Y * 0.5
	local dx      = screenPos.X - cx
	local dy      = screenPos.Y - cy
	if screenPos.Z <= 0 then dx, dy = -dx, -dy end
	if math.abs(dx) + math.abs(dy) < 0.001 then dy = 1 end

	-- Rotation: atan2(dy, dx) + 90 maps screen direction to GUI Rotation
	-- (where Rotation=0 means the ▲ glyph points up)
	local angle = math.deg(math.atan2(dy, dx)) + 90
	QuestArrow.Rotation = angle

	local ax, ay = clampToEdge(cx, cy, dx, dy, margin, vp.X, vp.Y)
	QuestArrow.Position = UDim2.new(0, ax, 0, ay)
end)

------------------------------------------------------------------------
-- Noob dialogue by stage
------------------------------------------------------------------------
local NOOB_DIALOGUES = {
	["intro"] = {
		Segments = {
			"Hey! Welcome to the card shop.",
			"Before we can battle you need a deck. The three trainers around the shop will help you choose.",
			"Go talk to Trainer Mighty, Swift, or Vital — then come back!",
		},
	},
	["find_trainer"] = {
		Segments = {
			"You still need a deck! Go pick one of the trainers and choose your path.",
			"Mighty crushes, Swift outruns, Vital outlasts. Your call!",
		},
	},
	["deck_chosen"] = {
		Segments = {
			"You have got your deck. Let us battle!",
		},
		Options = {
			{ Label = "Let's battle!", Action = "START" },
			{ Label = "Not yet.",      Action = "CLOSE" },
		},
	},
}

Remotes.ShowNoobDialogue.OnClientEvent:Connect(function(stage)
	if DialogueController.IsOpen then return end
	local data = NOOB_DIALOGUES[tostring(stage)]
	if not data then return end
	local noobModel = workspace:FindFirstChild("Noob")
	DialogueController:Open(noobModel, data, function(action)
		if action == "START" then
			Remotes.RequestTutorialBattle:FireServer()
		end
	end)
end)

local function applyQuestState(data)
	if type(data) ~= "table" then return end
	currentStage = data.stage or "complete"
	setTargets(currentStage)
end
Remotes.QuestStateChanged.OnClientEvent:Connect(applyQuestState)
task.spawn(function()
	local snapshotRemote=Remotes:WaitForChild("GetQuestSnapshot",10);if not snapshotRemote then return end
	for _=1,20 do
		local ok,data=pcall(function() return snapshotRemote:InvokeServer() end)
		if ok and data then applyQuestState(data);return end
		task.wait(0.5)
	end
	warn("[QuestHUDController] quest snapshot unavailable")
end)

------------------------------------------------------------------------
-- Init: wait for NPCs, build target table, apply initial stage
------------------------------------------------------------------------
task.spawn(function()
	Noob     = workspace:WaitForChild("Noob",     30)
	Trainers = workspace:WaitForChild("Trainers", 30)
	if Trainers then
		MightyT = Trainers:WaitForChild("Trainer Mighty", 10)
		SwiftT  = Trainers:WaitForChild("Trainer Swift",  10)
		VitalT  = Trainers:WaitForChild("Trainer Vital",  10)
	end
	local trainerList = {}
	for _, t in ipairs({ MightyT, SwiftT, VitalT }) do
		if t then trainerList[#trainerList + 1] = t end
	end
	QUEST_TARGETS = {
		["intro"]        = Noob and { Noob } or {},
		["find_trainer"] = trainerList,
		["deck_chosen"]  = Noob and { Noob } or {},
		["complete"]     = {},
	}
	setTargets(currentStage)  -- apply cached stage (from QuestStateChanged on join)
	print("[QuestHUDController] loaded")
end)
