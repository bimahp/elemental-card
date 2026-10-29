-- DialogueController: typewriter dialogue, camera tween, option buttons (client ModuleScript).
local TweenService     = game:GetService("TweenService")
local Players          = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local Lighting         = game:GetService("Lighting")

local LOCAL_PLAYER    = Players.LocalPlayer
local TYPEWRITE_SPEED = 0.04
local CAM_TWEEN_TIME  = 0.5
local CAM_DISTANCE    = 8
local CAM_HEIGHT_OFFSET = 2.0
local CAM_SIDE_OFFSET   = 2.5

local _gui, _panel, _dialogueText, _optionsContainer, _clickCapture, _captureConn, _eConn
local _state = "CLOSED"
local _segmentIdx, _dialogue, _typeThread, _onAction
local _origCamCFrame, _origCamType
local _camTween, _cameraToken = nil, 0
local _origHumanoid, _origWalkSpeed, _origJumpPower, _origJumpHeight, _origJumpEnabled
local _focusState

local function resolveUI()
	if _gui then return true end
	local pg = LOCAL_PLAYER:FindFirstChild("PlayerGui")
	if not pg then return false end
	_gui              = pg:FindFirstChild("DialogueUI"); if not _gui then return false end
	_panel            = _gui:FindFirstChild("DialoguePanel")
	_dialogueText     = _panel and _panel:FindFirstChild("DialogueText")
	_optionsContainer = _panel and _panel:FindFirstChild("OptionsContainer")
	_clickCapture     = _gui:FindFirstChild("ClickCapture")
	return _gui ~= nil
end

local function getTrainerPos(model)
	local head = model:FindFirstChild("Head")
	if head and head:IsA("BasePart") then return head.Position end
	local hrp = model:FindFirstChild("HumanoidRootPart")
		or model:FindFirstChild("UpperTorso")
		or model:FindFirstChild("Torso")
	return hrp and hrp.Position
end

local function clearFocusMode()
	local focus=_focusState
	if not focus then return end
	_focusState=nil
	for _,saved in ipairs(focus.prompts) do
		if saved.instance and saved.instance.Parent then saved.instance.Enabled=saved.enabled end
	end
	for _,saved in ipairs(focus.hiddenParts) do
		if saved.instance and saved.instance.Parent then saved.instance.LocalTransparencyModifier=saved.transparency end
	end
	workspace:SetAttribute("DialogueFocusTarget",nil)
	if focus.questHud and focus.questHud.Parent then focus.questHud.Enabled=focus.questHudEnabled end
	if focus.highlight then focus.highlight:Destroy() end
	if focus.depth then focus.depth:Destroy() end
	if focus.color then focus.color:Destroy() end
end

local function beginFocusMode(model,npcPos)
	clearFocusMode()
	if not model then return end
	local focus={prompts={},hiddenParts={}}
	_focusState=focus
	workspace:SetAttribute("DialogueFocusTarget",model.Name)
	for _,item in ipairs(workspace:GetDescendants()) do
		if item:IsA("ProximityPrompt") and item.Enabled then
			table.insert(focus.prompts,{instance=item,enabled=true})
			item.Enabled=false
		end
	end
	for _,candidate in ipairs(workspace:GetDescendants()) do
		if candidate:IsA("Model") and candidate~=model and candidate:FindFirstChildOfClass("Humanoid") then
			for _,item in ipairs(candidate:GetDescendants()) do
			if item:IsA("BasePart") then
				table.insert(focus.hiddenParts,{instance=item,transparency=item.LocalTransparencyModifier})
				item.LocalTransparencyModifier=1
				end
			end
		end
	end
	local pg=LOCAL_PLAYER:FindFirstChild("PlayerGui")
	focus.questHud=pg and pg:FindFirstChild("QuestHUD")
	if focus.questHud then focus.questHudEnabled=focus.questHud.Enabled;focus.questHud.Enabled=false end
	focus.depth=Instance.new("DepthOfFieldEffect")
	focus.depth.Name="DialogueFocusDepth"
	focus.depth.FarIntensity=0.8;focus.depth.NearIntensity=0.65;focus.depth.InFocusRadius=5
	focus.depth.FocusDistance=npcPos and (workspace.CurrentCamera.CFrame.Position-npcPos).Magnitude or 8
	focus.depth.Parent=Lighting
	focus.color=Instance.new("ColorCorrectionEffect")
	focus.color.Name="DialogueFocusColor"
	focus.color.Brightness=-0.12;focus.color.Contrast=0.1;focus.color.Saturation=-0.25
	focus.color.Parent=Lighting
	focus.highlight=Instance.new("Highlight")
	focus.highlight.Name="DialogueFocusHighlight"
	focus.highlight.Adornee=model
	focus.highlight.DepthMode=Enum.HighlightDepthMode.Occluded
	focus.highlight.FillColor=Color3.fromRGB(255,235,180)
	focus.highlight.FillTransparency=0.82
	focus.highlight.OutlineColor=Color3.fromRGB(255,215,80)
	focus.highlight.OutlineTransparency=0.3
	focus.highlight.Parent=model
	local thisFocus=focus
	task.delay(CAM_TWEEN_TIME,function()
		if _focusState==thisFocus and npcPos and focus.depth.Parent then
			focus.depth.FocusDistance=(workspace.CurrentCamera.CFrame.Position-npcPos).Magnitude
		end
	end)
end

local function tweenCamera(npcPos)
	local camera = workspace.CurrentCamera
	local char = LOCAL_PLAYER.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end
	_cameraToken += 1
	if _camTween then _camTween:Cancel() end
	_origCamCFrame, _origCamType = camera.CFrame, camera.CameraType
	camera.CameraType = Enum.CameraType.Scriptable
	local pPos = hrp.Position
	local dir = Vector3.new(npcPos.X-pPos.X,0,npcPos.Z-pPos.Z)
	if dir.Magnitude>0.01 then dir=dir.Unit end
	local right=Vector3.new(dir.Z,0,-dir.X)
	local target=npcPos+Vector3.new(0,CAM_HEIGHT_OFFSET,0)
	local camPos=target-dir*CAM_DISTANCE+right*CAM_SIDE_OFFSET+Vector3.new(0,0.5,0)
	_camTween=TweenService:Create(camera,TweenInfo.new(CAM_TWEEN_TIME,Enum.EasingStyle.Quad),{CFrame=CFrame.lookAt(camPos,target)})
	_camTween:Play()
end

local function restoreCamera()
	if not _origCamCFrame then return end
	local camera=workspace.CurrentCamera
	local originalCFrame,originalType=_origCamCFrame,_origCamType
	_cameraToken += 1
	local token=_cameraToken
	if _camTween then _camTween:Cancel() end
	_camTween=TweenService:Create(camera,TweenInfo.new(CAM_TWEEN_TIME,Enum.EasingStyle.Quad),{CFrame=originalCFrame})
	_camTween:Play()
	task.delay(CAM_TWEEN_TIME,function()
		if token==_cameraToken then camera.CameraType=originalType or Enum.CameraType.Custom;_camTween=nil end
	end)
	_origCamCFrame=nil;_origCamType=nil
end

local function freezePlayer()
	local char=LOCAL_PLAYER.Character;if not char then return end
	local hum=char:FindFirstChildOfClass("Humanoid");if not hum then return end
	_origHumanoid=hum
	_origWalkSpeed,_origJumpPower,_origJumpHeight=hum.WalkSpeed,hum.JumpPower,hum.JumpHeight
	_origJumpEnabled=hum:GetStateEnabled(Enum.HumanoidStateType.Jumping)
	hum.WalkSpeed=0;hum.JumpPower=0;hum.JumpHeight=0;hum:SetStateEnabled(Enum.HumanoidStateType.Jumping,false)
end

local function unfreezePlayer()
	local hum=_origHumanoid
	if hum and hum.Parent then
		hum.WalkSpeed=_origWalkSpeed or hum.WalkSpeed;hum.JumpPower=_origJumpPower or hum.JumpPower;hum.JumpHeight=_origJumpHeight or hum.JumpHeight
		hum:SetStateEnabled(Enum.HumanoidStateType.Jumping,_origJumpEnabled~=false)
	end
	_origHumanoid,_origWalkSpeed,_origJumpPower,_origJumpHeight,_origJumpEnabled=nil,nil,nil,nil,nil
end

local function stopTypeThread()
	if _typeThread then task.cancel(_typeThread); _typeThread = nil end
end

local function typewrite(label, text, onDone)
	stopTypeThread()
	label.Text = ""
	_state = "TYPING"
	_typeThread = task.spawn(function()
		for i = 1, #text do
			if _state ~= "TYPING" then return end
			label.Text = string.sub(text, 1, i)
			task.wait(TYPEWRITE_SPEED)
		end
		label.Text = text; _typeThread = nil; _state = "WAITING"
		if onDone then onDone() end
	end)
end

local function clearOptions()
	if not _optionsContainer then return end
	for _, c in _optionsContainer:GetChildren() do
		if c:IsA("TextButton") then c:Destroy() end
	end
	_optionsContainer.Visible = false
end

local function buildButton(label)
	local btn = Instance.new("TextButton")
	btn.Size                   = UDim2.new(1, 0, 0, 50)
	btn.BackgroundColor3       = Color3.fromRGB(30, 20, 5)
	btn.BackgroundTransparency = 0
	btn.Text                   = label
	btn.TextSize               = 16
	btn.Font                   = Enum.Font.GothamBold
	btn.TextColor3             = Color3.fromRGB(255, 220, 100)
	btn.BorderSizePixel        = 0
	btn.ZIndex                 = 5
	local corner = Instance.new("UICorner", btn); corner.CornerRadius = UDim.new(0, 8)
	local stroke = Instance.new("UIStroke", btn)
	stroke.Color = Color3.fromRGB(255, 220, 100); stroke.Thickness = 1.5
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	local pad = Instance.new("UIPadding", btn)
	pad.PaddingLeft = UDim.new(0, 14); pad.PaddingRight = UDim.new(0, 14)
	return btn
end

local DialogueController   = {}
DialogueController.IsOpen  = false

local function showOptions(options)
	if not _optionsContainer then return end
	clearOptions()
	if #options == 0 then DialogueController:Close(); return end
	_state = "OPTIONS"
	_optionsContainer.Visible = true
	for _, opt in ipairs(options) do
		local btn = buildButton(opt.Label)
		btn.Parent = _optionsContainer
		btn.MouseButton1Click:Connect(function()
			if _state ~= "OPTIONS" then return end
			local action = opt.Action
			local cb = _onAction
			DialogueController:Close()
			if cb and action ~= "CLOSE" then task.delay(CAM_TWEEN_TIME, function() cb(action) end) end
		end)
	end
end

local function nextSegment()
	_segmentIdx += 1
	local seg = _dialogue and _dialogue.Segments and _dialogue.Segments[_segmentIdx]
	if not seg then
		showOptions(_dialogue and _dialogue.Options or {})
		return
	end
	if not _dialogueText then return end
	typewrite(_dialogueText, seg, function() _state = "WAITING" end)
end

function DialogueController:Open(trainerModel, dialogueData, onAction)
	if not resolveUI() then
		warn("[DialogueController] DialogueUI not found in PlayerGui")
		return
	end
	if self.IsOpen then self:Close() end
	_dialogue   = dialogueData
	_onAction   = onAction
	_segmentIdx = 0
	self.IsOpen = true
	freezePlayer()
	local npcPos = getTrainerPos(trainerModel)
	beginFocusMode(trainerModel,npcPos)
	if npcPos then tweenCamera(npcPos) end
	if _dialogueText then _dialogueText.Text = "" end
	clearOptions()
	_gui.Enabled = true
	if _captureConn then _captureConn:Disconnect() end
	_captureConn = _clickCapture and _clickCapture.MouseButton1Click:Connect(function()
		if self.IsOpen then self:Advance() end
	end)
	if _eConn then _eConn:Disconnect() end
	_eConn = UserInputService.InputBegan:Connect(function(input, gpe)
		if gpe or not self.IsOpen then return end
		if input.KeyCode == Enum.KeyCode.E then self:Advance() end
	end)
	nextSegment()
end

function DialogueController:Advance()
	if not self.IsOpen then return end
	if _state == "TYPING" then
		stopTypeThread()
		local seg = _dialogue and _dialogue.Segments and _dialogue.Segments[_segmentIdx]
		if _dialogueText and seg then _dialogueText.Text = seg end
		_state = "WAITING"
	elseif _state == "WAITING" then
		local isLast = _dialogue and _dialogue.Segments[_segmentIdx + 1] == nil
		if isLast then showOptions(_dialogue.Options or {})
		else nextSegment() end
	end
end

function DialogueController:Close()
	if not self.IsOpen then return end
	self.IsOpen = false; _state = "CLOSED"
	stopTypeThread(); clearOptions()
	if _dialogueText then _dialogueText.Text = "" end
	if _captureConn then _captureConn:Disconnect(); _captureConn = nil end
	if _eConn then _eConn:Disconnect(); _eConn = nil end
	if _gui then _gui.Enabled = false end
	clearFocusMode()
	restoreCamera(); unfreezePlayer()
	_dialogue = nil; _segmentIdx = 0; _onAction = nil
end

return DialogueController
