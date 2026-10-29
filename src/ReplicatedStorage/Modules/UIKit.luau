-- UIKit: the runtime half of ReplicatedStorage.Kit (UI §10.3, ARCHITECTURE §12.2).
-- It clones authored templates and switches their state. It never builds a visual tree.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UIKit = {}

-- Each variant names the Kit tokens it paints with.
local VARIANTS = {
	primary = { background = "Success", text = "Text" },
	secondary = { background = "PanelSurface2", text = "Text" },
	danger = { background = "Danger", text = "Text" },
	disabled = { background = "Disabled", text = "TextMuted" },
}

local kitFolder: Folder? = nil
-- Specs swap the clock to step time by hand.
UIKit.clock = os.clock

-- Per button: when its state last changed or a press was accepted, and its handlers.
local buttons = setmetatable({}, { __mode = "k" })

local function stateOf(button: GuiButton)
	local state = buttons[button]
	if not state then
		state = { lockedAt = -math.huge }
		buttons[button] = state
	end
	return state
end

function UIKit.kit(): Folder
	if not kitFolder then
		kitFolder = ReplicatedStorage:WaitForChild("Kit") :: Folder
	end
	return kitFolder :: Folder
end

-- Specs point UIKit at a copy of the Kit; nil goes back to ReplicatedStorage.Kit.
function UIKit.useKit(folder: Folder?)
	kitFolder = folder
end

function UIKit.token(name: string): any
	local value = UIKit.kit():GetAttribute(name)
	assert(value ~= nil, "UIKit: no Kit token " .. name)
	return value
end

function UIKit.clone(templateName: string): Instance
	local template = UIKit.kit():FindFirstChild(templateName)
	assert(template, "UIKit: no Kit template " .. templateName)
	return template:Clone()
end

function UIKit.setVariant(button: GuiButton, variant: string)
	local spec = VARIANTS[variant]
	assert(spec, "UIKit: unknown variant " .. tostring(variant))
	button.BackgroundColor3 = UIKit.token(spec.background)
	if button:IsA("TextButton") then
		button.TextColor3 = UIKit.token(spec.text)
	end
	button:SetAttribute("Variant", variant)
	stateOf(button).lockedAt = UIKit.clock()
end

-- A disabled button still takes taps, so its why handler can say what is missing.
function UIKit.setEnabled(button: GuiButton, enabled: boolean)
	local current = button:GetAttribute("Variant")
	if enabled then
		if current == "disabled" then
			UIKit.setVariant(button, button:GetAttribute("EnabledVariant") or "primary")
		end
	elseif current ~= "disabled" then
		button:SetAttribute("EnabledVariant", current or "primary")
		UIKit.setVariant(button, "disabled")
	end
end

function UIKit.isEnabled(button: GuiButton): boolean
	return button:GetAttribute("Variant") ~= "disabled"
end

-- Runs one tap through the press rules. bindPress calls it on Activated; specs call it directly.
-- Returns "pressed", "why" or "locked".
function UIKit.press(button: GuiButton): string
	local state = stateOf(button)
	local now = UIKit.clock()
	if now - state.lockedAt < UIKit.token("PressLockSeconds") then
		return "locked"
	end
	state.lockedAt = now
	if not UIKit.isEnabled(button) then
		if state.onWhy then
			state.onWhy(button)
		end
		return "why"
	end
	if state.onPress then
		state.onPress(button)
	end
	return "pressed"
end

-- Taps within PressLockSeconds of a state change or an accepted tap are ignored,
-- so a double tap cannot fire twice or undo the order it just gave.
function UIKit.bindPress(button: GuiButton, onPress: (GuiButton) -> (), onWhy: ((GuiButton) -> ())?)
	local state = stateOf(button)
	state.onPress = onPress
	state.onWhy = onWhy
	local pressScale = button:FindFirstChild("PressScale") :: UIScale?
	local connections = {
		button.Activated:Connect(function()
			UIKit.press(button)
		end),
	}
	if pressScale then
		table.insert(connections, button.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				pressScale.Scale = UIKit.token("PressScale")
			end
		end))
		table.insert(connections, button.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				pressScale.Scale = 1
			end
		end))
	end
	return function()
		for _, connection in ipairs(connections) do
			connection:Disconnect()
		end
		state.onPress = nil
		state.onWhy = nil
		if pressScale then
			pressScale.Scale = 1
		end
	end
end

return UIKit
