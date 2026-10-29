-- UIScaleController: scales every AutoScale layer in PlayerGui (UI §10.2, ARCHITECTURE §12.3).
-- A layer's Root is sized 1 / scale and its UIScale set to scale, so children always
-- see at least the reference canvas. Each layer publishes AppliedScale and AppliedInput.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Rules = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("UIScaleRules"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local function currentInput(): string
	local ok, preferred = pcall(function()
		return UserInputService.PreferredInput
	end)
	return Rules.inputKind(ok and preferred or nil, UserInputService.TouchEnabled, UserInputService.MouseEnabled)
end

local function applyTo(gui: Instance, scale: number, input: string)
	if not (gui:IsA("ScreenGui") and gui:GetAttribute("AutoScale")) then
		return
	end
	local root = gui:FindFirstChild("Root")
	local uiScale = root and root:FindFirstChildOfClass("UIScale")
	if not (root and root:IsA("GuiObject") and uiScale) then
		warn("[UIScaleController] " .. gui.Name .. " has AutoScale but no Root with a UIScale")
		return
	end
	root.Size = UDim2.fromScale(1 / scale, 1 / scale)
	uiScale.Scale = scale
	gui:SetAttribute("AppliedScale", scale)
	gui:SetAttribute("AppliedInput", input)
end

local function applyAll()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local viewport = camera.ViewportSize
	local input = currentInput()
	local scale = Rules.scaleFor(viewport.X, viewport.Y, input, player:GetAttribute("UISize"))
	for _, gui in ipairs(playerGui:GetChildren()) do
		applyTo(gui, scale, input)
	end
end

local cameraConnection: RBXScriptConnection? = nil
local function watchCamera()
	if cameraConnection then
		cameraConnection:Disconnect()
	end
	local camera = workspace.CurrentCamera
	if camera then
		cameraConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(applyAll)
	end
	applyAll()
end

workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(watchCamera)
pcall(function()
	UserInputService:GetPropertyChangedSignal("PreferredInput"):Connect(applyAll)
end)
player:GetAttributeChangedSignal("UISize"):Connect(applyAll)
playerGui.ChildAdded:Connect(function(gui)
	if gui:IsA("ScreenGui") and gui:GetAttribute("AutoScale") then
		applyAll()
	end
end)
watchCamera()
