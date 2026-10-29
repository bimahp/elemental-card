-- Headless checks for UIKit and the Kit templates (PLAN_UI_FOUNDATIONS step 2).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UIKit = require(ReplicatedStorage.Modules.UIKit)

local Spec = {}

local TEMPLATES = { "PanelFrame", "Button", "ButtonSecondary", "Toast", "Backdrop" }

-- The authoring floors at the 1280 x 720 reference (UI §10.2).
local function checkFloors(kit: Folder)
	local tapMin = kit:GetAttribute("TapMin")
	local textMin = kit:GetAttribute("TextBody")
	for _, item in ipairs(kit:GetDescendants()) do
		if item:IsA("GuiButton") and item.Size.X.Scale == 0 and item.Size.Y.Scale == 0 then
			assert(item.Size.X.Offset >= tapMin and item.Size.Y.Offset >= tapMin,
				item:GetFullName() .. " is under the " .. tapMin .. " px tap floor")
		end
		if (item:IsA("TextLabel") or item:IsA("TextButton")) and item.Text ~= "" then
			assert(item.TextSize >= textMin, item:GetFullName() .. " text is under " .. textMin .. " px")
		end
	end
end

function Spec.run()
	local kit = ReplicatedStorage:FindFirstChild("Kit")
	assert(kit, "ReplicatedStorage.Kit is missing (run kit-v1)")
	for _, name in ipairs(TEMPLATES) do
		assert(kit:FindFirstChild(name), "Kit template missing: " .. name)
	end
	checkFloors(kit)

	local now = 0
	UIKit.clock = function()
		return now
	end
	UIKit.useKit(kit)

	local button = UIKit.clone("Button") :: TextButton
	assert(button:IsA("TextButton") and button.Parent == nil, "clone returns an unparented copy")
	assert(button.BackgroundColor3 == UIKit.token("Success"), "Button starts with the primary colour")

	UIKit.setVariant(button, "danger")
	assert(button.BackgroundColor3 == UIKit.token("Danger") and button:GetAttribute("Variant") == "danger",
		"setVariant paints from the tokens")
	assert(not pcall(UIKit.setVariant, button, "sparkly"), "an unknown variant errors")

	local pressed, whys = 0, 0
	UIKit.bindPress(button, function()
		pressed += 1
	end, function()
		whys += 1
	end)

	now = 1
	assert(UIKit.press(button) == "pressed" and pressed == 1, "a tap after the lock presses")
	now = 1.2
	assert(UIKit.press(button) == "locked" and pressed == 1, "a second tap within 0.4 s is ignored")
	now = 1.5
	assert(UIKit.press(button) == "pressed" and pressed == 2, "a tap after 0.4 s presses again")

	now = 3
	UIKit.setEnabled(button, false)
	assert(button.BackgroundColor3 == UIKit.token("Disabled") and button.Active, "a disabled button greys but stays active")
	now = 3.1
	assert(UIKit.press(button) == "locked", "a tap right after a state change is ignored")
	now = 3.5
	assert(UIKit.press(button) == "why" and whys == 1 and pressed == 2, "a disabled button explains instead of acting")

	now = 5
	UIKit.setEnabled(button, true)
	assert(button:GetAttribute("Variant") == "danger", "enabling restores the variant it had before")
	now = 5.5
	assert(UIKit.press(button) == "pressed" and pressed == 3, "an enabled button presses again")

	button:Destroy()
	UIKit.clock = os.clock
	UIKit.useKit(nil)
	return "UIKitSpec: all checks passed"
end

return Spec
