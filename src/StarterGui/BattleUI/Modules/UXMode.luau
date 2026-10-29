-- UXMode: Desktop/Mobile classification based on viewport width and input type.
-- Keyboard input is excluded from the "mouse" set so that WASD in Studio
-- device emulator does not incorrectly switch the mode to Desktop.
local UserInput = game:GetService("UserInputService")
local camera = workspace.CurrentCamera

local UXMode = {}

local SMALL_SCREEN_WIDTH = 800

local MOUSE_INPUT_TYPES = {
	[Enum.UserInputType.MouseMovement] = true,
	[Enum.UserInputType.MouseButton1]  = true,
	[Enum.UserInputType.MouseButton2]  = true,
	[Enum.UserInputType.MouseButton3]  = true,
	[Enum.UserInputType.MouseWheel]    = true,
}

local function computeMode()
	if camera.ViewportSize.X < SMALL_SCREEN_WIDTH then
		return "Mobile"
	end
	if MOUSE_INPUT_TYPES[UserInput:GetLastInputType()] then
		return "Desktop"
	end
	return "Mobile"
end

local changedEvent = Instance.new("BindableEvent")
UXMode.Changed = changedEvent.Event
UXMode.Current = computeMode()

local function recompute()
	local newMode = computeMode()
	if newMode ~= UXMode.Current then
		UXMode.Current = newMode
		changedEvent:Fire(newMode)
	end
end

camera:GetPropertyChangedSignal("ViewportSize"):Connect(recompute)
UserInput.LastInputTypeChanged:Connect(recompute)

return UXMode
