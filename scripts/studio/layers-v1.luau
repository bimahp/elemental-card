-- layers-v1.luau: creates the PanelBackdrop, Panels and Popups ScreenGuis in StarterGui
-- (UI §10.1, PLAN_UI_FOUNDATIONS step 3). Edit mode; changes the place. Needs kit-v1.
--
--   local ARGS = {}                    -- build once; returns early when already applied
--   local ARGS = { rebuild = true }    -- replace layers-v1 layers with a fresh build
local ARGS = ARGS or {}

local MIGRATION = "layers-v1"
local StarterGui = game:GetService("StarterGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local kit = ReplicatedStorage:FindFirstChild("Kit")
assert(kit and kit:GetAttribute("Migration") == "kit-v1", "layers-v1 needs ReplicatedStorage.Kit from kit-v1")

local NAMES = { "PanelBackdrop", "Panels", "Popups" }
local existing = {}
for _, name in ipairs(NAMES) do
	local gui = StarterGui:FindFirstChild(name)
	if gui then
		if gui:GetAttribute("Migration") ~= MIGRATION then
			error("StarterGui." .. name .. " exists without the layers-v1 stamp; layers-v1 will not overwrite it", 0)
		end
		table.insert(existing, gui)
	end
end
if #existing == #NAMES and not ARGS.rebuild then
	return "layers-v1 already applied"
end

local function screenGui(name: string, insets: Enum.ScreenInsets, displayOrder: number, enabled: boolean)
	local gui = Instance.new("ScreenGui")
	gui.Name = name
	gui.ScreenInsets = insets
	gui.IgnoreGuiInset = insets == Enum.ScreenInsets.None
	gui.DisplayOrder = displayOrder
	gui.Enabled = enabled
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui:SetAttribute("Migration", MIGRATION)
	return gui
end

-- A scaled layer: UIScaleController sizes Root to 1 / scale and sets the UIScale (step 4).
local function scaledLayer(name: string, displayOrder: number)
	local gui = screenGui(name, Enum.ScreenInsets.CoreUISafeInsets, displayOrder, true)
	gui:SetAttribute("AutoScale", true)
	local root = Instance.new("Frame")
	root.Name = "Root"
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundTransparency = 1
	root.BorderSizePixel = 0
	local scale = Instance.new("UIScale")
	scale.Parent = root
	root.Parent = gui
	return gui
end

-- The one dim behind panels (UI §2.6). Off until a panel opens.
local backdropGui = screenGui("PanelBackdrop", Enum.ScreenInsets.None, 19, false)
backdropGui.SafeAreaCompatibility = Enum.SafeAreaCompatibility.None
backdropGui.ClipToDeviceSafeArea = false
kit.Backdrop:Clone().Parent = backdropGui

local panels = scaledLayer("Panels", 20)
local popups = scaledLayer("Popups", 30)

for _, gui in ipairs(existing) do
	gui:Destroy()
end
for _, gui in ipairs({ backdropGui, panels, popups }) do
	gui.Parent = StarterGui
end
return "layers-v1 applied: PanelBackdrop (19), Panels (20), Popups (30)"
