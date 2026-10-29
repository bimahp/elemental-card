-- UXMode: Desktop/Mobile battle layout from PreferredInput and viewport width (UI §5.3).
-- It never follows the last input, so a key press or chat on a PC cannot flip the layout.
-- The rule itself is UIScaleRules.layoutMode.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Rules = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("UIScaleRules"))

local UXMode = {}

local function currentInput(): string
	local ok, preferred = pcall(function()
		return UserInputService.PreferredInput
	end)
	return Rules.inputKind(ok and preferred or nil, UserInputService.TouchEnabled, UserInputService.MouseEnabled)
end

local function computeMode(): (string, string)
	local camera = workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
	local input = currentInput()
	return Rules.layoutMode(viewport.X, input), string.format("viewport %dx%d, %s", viewport.X, viewport.Y, input)
end

local changedEvent = Instance.new("BindableEvent")
UXMode.Changed = changedEvent.Event
local reason
UXMode.Current, reason = computeMode()
print("[UXMode] " .. UXMode.Current .. " (" .. reason .. ")")

local function recompute()
	local newMode, why = computeMode()
	if newMode ~= UXMode.Current then
		UXMode.Current = newMode
		print("[UXMode] changed to " .. newMode .. " (" .. why .. ")")
		changedEvent:Fire(newMode)
	end
end

local cameraConnection: RBXScriptConnection? = nil
local function watchCamera()
	if cameraConnection then
		cameraConnection:Disconnect()
	end
	local camera = workspace.CurrentCamera
	if camera then
		cameraConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(recompute)
	end
	recompute()
end

workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(watchCamera)
pcall(function()
	UserInputService:GetPropertyChangedSignal("PreferredInput"):Connect(recompute)
end)
watchCamera()

return UXMode
