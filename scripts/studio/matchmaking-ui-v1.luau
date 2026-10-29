-- matchmaking-ui-v1.luau: builds the Matchmaking panel in Panels.Root from Kit.PanelFrame
-- and deletes the old StarterGui.MatchmakingUI (PLAN_UI_FOUNDATIONS step 8).
-- Edit mode; changes the place. Needs kit-v1 and layers-v1.
--
--   local ARGS = {}                    -- build once; returns early when already applied
--   local ARGS = { rebuild = true }    -- replace a matchmaking-ui-v1 panel
local ARGS = ARGS or {}

local MIGRATION = "matchmaking-ui-v1"
local StarterGui = game:GetService("StarterGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local kit = ReplicatedStorage:FindFirstChild("Kit")
assert(kit and kit:GetAttribute("Migration") == "kit-v1", "needs ReplicatedStorage.Kit from kit-v1")
local panels = StarterGui:FindFirstChild("Panels")
assert(panels and panels:GetAttribute("Migration") == "layers-v1", "needs StarterGui.Panels from layers-v1")
local root = panels:FindFirstChild("Root")

local existing = root:FindFirstChild("Matchmaking")
if existing then
	if existing:GetAttribute("Migration") ~= MIGRATION then
		error("Panels.Root.Matchmaking exists without the matchmaking-ui-v1 stamp", 0)
	end
	if not ARGS.rebuild then
		return "matchmaking-ui-v1 already applied"
	end
end

local function token(name)
	local value = kit:GetAttribute(name)
	assert(value ~= nil, "missing Kit token " .. name)
	return value
end

local MATCHMAKING_ICON = "rbxassetid://105294857091338" -- AssetIds.Icons.MATCHMAKING

local panel = kit.PanelFrame:Clone()
panel.Name = "Matchmaking"
panel.Size = UDim2.fromOffset(640, 400)
panel.Visible = false
panel:SetAttribute("Migration", MIGRATION)

local titleBar = panel.TitleBar
titleBar.BackgroundColor3 = token("AccentMatchmaking")
titleBar.Title.Text = "Matchmaking"
titleBar.Icon.Image = MATCHMAKING_ICON

local body = panel.Body

local function label(name: string, text: string, y: number, color: Color3, font: Font)
	local l = Instance.new("TextLabel")
	l.Name = name
	l.Position = UDim2.fromOffset(0, y)
	l.Size = UDim2.new(1, 0, 0, 40)
	l.BackgroundTransparency = 1
	l.Text = text
	l.TextColor3 = color
	l.FontFace = font
	l.TextSize = token("TextBody")
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextTruncate = Enum.TextTruncate.AtEnd
	l.ZIndex = 6
	l.Parent = body
	return l
end

label("LevelLabel", "Level 1", 0, token("TextSoft"), token("FontBodyBold"))
local status = label("StatusLabel", "Searching for an opponent...", 48, token("TextMuted"), token("FontBody"))
status.Visible = false

local function bottomButton(name: string, text: string)
	local b = kit.Button:Clone()
	b.Name = name
	b.Text = text
	b.AnchorPoint = Vector2.new(0.5, 1)
	b.Position = UDim2.fromScale(0.5, 1)
	b.Size = UDim2.fromOffset(360, token("TapMin"))
	b.ZIndex = 6
	b.Parent = body
	return b
end

bottomButton("FindButton", "Find Opponent")
local cancel = bottomButton("CancelButton", "Cancel Matchmaking")
cancel.BackgroundColor3 = token("Danger")
cancel:SetAttribute("Variant", "danger")
cancel.Visible = false

local old = StarterGui:FindFirstChild("MatchmakingUI")
if existing then
	existing:Destroy()
end
panel.Parent = root
if old then
	old:Destroy()
end
return "matchmaking-ui-v1 applied" .. (old and "; StarterGui.MatchmakingUI deleted" or "")
