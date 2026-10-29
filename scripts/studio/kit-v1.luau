-- kit-v1.luau: creates ReplicatedStorage.Kit, the folder of authored UI templates
-- (UI §10.3, PLAN_UI_FOUNDATIONS step 2). Edit mode; changes the place.
--
-- Tokens are attributes on the folder, copied from UITheme. Templates are drawn
-- from the same token table, so a template's colours always start equal to the
-- tokens. Sizes are at the 1280 x 720 reference: tap targets >= 80 px, text >= 26 px.
--
--   local ARGS = {}                    -- build once; returns early when already applied
--   local ARGS = { rebuild = true }    -- replace a kit-v1 Kit with a fresh build
local ARGS = ARGS or {}

local MIGRATION = "kit-v1"
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local existing = ReplicatedStorage:FindFirstChild("Kit")
if existing then
	local stamp = existing:GetAttribute("Migration")
	if stamp ~= MIGRATION then
		error("ReplicatedStorage.Kit exists with Migration=" .. tostring(stamp) .. "; kit-v1 will not overwrite it", 0)
	end
	if not ARGS.rebuild then
		return "kit-v1 already applied"
	end
end

--------------------------------------------------------------------------------
-- Tokens

local rgb = Color3.fromRGB
local COLORS = {
	Outline = rgb(7, 10, 28),
	Stroke = rgb(53, 70, 116),
	Panel = rgb(24, 27, 44),
	PanelDeep = rgb(13, 18, 31),
	PanelSurface = rgb(18, 26, 43),
	PanelSurface2 = rgb(28, 38, 60),
	TitleNavy = rgb(18, 32, 68),
	TitleBlue = rgb(57, 132, 219),
	TitleGreen = rgb(24, 122, 78),
	TitleOrange = rgb(213, 93, 51),
	Text = rgb(248, 250, 255),
	TextSoft = rgb(197, 211, 238),
	TextMuted = rgb(147, 160, 190),
	Success = rgb(64, 178, 104),
	Warning = rgb(255, 186, 86),
	Danger = rgb(205, 66, 72),
	Disabled = rgb(61, 65, 79),
	Shard = rgb(42, 186, 255),
	Fragment = rgb(255, 196, 60),
	Epic = rgb(141, 93, 255), -- UITheme's "Dust", kept as the Epic rarity accent
	MIGHTY = rgb(165, 14, 14),
	SWIFT = rgb(13, 101, 45),
	VITAL = rgb(23, 78, 166),
	NEUTRAL = rgb(154, 160, 166),
	AccentInventory = rgb(51, 124, 220),
	AccentVending = rgb(31, 154, 105),
	AccentMall = rgb(42, 158, 230),
	AccentDeck = rgb(87, 106, 220),
	AccentMatchmaking = rgb(214, 122, 44),
	AccentPlayerStatus = rgb(37, 145, 139),
	AccentVendor = rgb(178, 122, 56),
}
local NUMBERS = {
	RadiusModal = 20,
	RadiusSurface = 12,
	RadiusButton = 14,
	StrokeThick = 4,
	StrokeThin = 2,
	TitleBarHeight = 96,
	TapMin = 80,
	PanelPadding = 24,
	TextBody = 26,
	TextButton = 28,
	TextTitle = 40,
	PressLockSeconds = 0.4,
	PressScale = 0.96,
	BackdropTransparency = 0.34,
	TextureTransparency = 0.08,
}
local FONTS = {
	FontTitle = Font.fromEnum(Enum.Font.FredokaOne),
	FontButton = Font.fromEnum(Enum.Font.GothamBold),
	FontBody = Font.fromEnum(Enum.Font.Gotham),
	FontBodyBold = Font.fromEnum(Enum.Font.GothamBold),
}
local STRINGS = {
	PanelTexture = "rbxassetid://115366182634060",
}

--------------------------------------------------------------------------------
-- Builders (authoring only: this script is the editor)

local function make(className: string, props, children)
	local inst = Instance.new(className)
	for key, value in pairs(props or {}) do
		if key ~= "Name" then
			(inst :: any)[key] = value
		end
	end
	inst.Name = (props and props.Name) or className
	for _, child in ipairs(children or {}) do
		child.Parent = inst
	end
	return inst
end

local function corner(radius: number, opts)
	local c = make("UICorner", { CornerRadius = UDim.new(0, radius) })
	if opts then
		for key, value in pairs(opts) do
			(c :: any)[key] = UDim.new(0, value)
		end
	end
	return c
end

local function stroke(color: Color3, thickness: number)
	return make("UIStroke", { Color = color, Thickness = thickness, ApplyStrokeMode = Enum.ApplyStrokeMode.Border })
end

local function button(name: string, background: Color3)
	return make("TextButton", {
		Name = name,
		Size = UDim2.fromOffset(320, NUMBERS.TapMin),
		BackgroundColor3 = background,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "Button",
		TextColor3 = COLORS.Text,
		FontFace = FONTS.FontButton,
		TextSize = NUMBERS.TextButton,
		TextWrapped = true,
	}, {
		corner(NUMBERS.RadiusButton),
		stroke(COLORS.Outline, NUMBERS.StrokeThin),
		make("UIScale", { Name = "PressScale" }),
	})
end

--------------------------------------------------------------------------------
-- Templates

local bar = NUMBERS.TitleBarHeight
local pad = NUMBERS.PanelPadding
local slot = NUMBERS.TapMin

-- The shell applyModalShell builds in code today (UI §2.1), authored once.
-- 1040 x 540 fits the smallest phone's Panels room of about 1160 x 549 (UI §10.2).
local panelFrame = make("Frame", {
	Name = "PanelFrame",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(1040, 540),
	BackgroundColor3 = COLORS.Panel,
	BorderSizePixel = 0,
	Active = true,
	ZIndex = 1,
}, {
	corner(NUMBERS.RadiusModal),
	stroke(COLORS.Outline, NUMBERS.StrokeThick),
	make("UIShadow", {
		BlurRadius = UDim.new(0, 18),
		Color = COLORS.Outline,
		Offset = UDim2.fromOffset(0, 8),
		Spread = UDim2.fromOffset(6, 6),
		Transparency = 0.42,
		ZIndex = -1,
	}),
	-- Taps on the header or empty interior land here and never close the panel.
	make("TextButton", {
		Name = "InputBlocker",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
		Selectable = false,
		ZIndex = 1,
	}),
	make("ImageLabel", {
		Name = "Texture",
		Position = UDim2.fromOffset(0, bar),
		Size = UDim2.new(1, 0, 1, -bar),
		BackgroundTransparency = 1,
		Image = STRINGS.PanelTexture,
		ImageTransparency = NUMBERS.TextureTransparency,
		ScaleType = Enum.ScaleType.Tile,
		TileSize = UDim2.fromOffset(640, 640),
		ZIndex = 2,
	}, {
		corner(NUMBERS.RadiusModal, { TopLeftRadius = 0, TopRightRadius = 0 }),
	}),
	make("Frame", {
		Name = "TitleBar",
		Size = UDim2.new(1, 0, 0, bar),
		BackgroundColor3 = COLORS.AccentInventory,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		ZIndex = 3,
	}, {
		corner(NUMBERS.RadiusModal, { BottomLeftRadius = 0, BottomRightRadius = 0 }),
		make("Frame", {
			Name = "Divider",
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromScale(0, 1),
			Size = UDim2.new(1, 0, 0, NUMBERS.StrokeThick),
			BackgroundColor3 = COLORS.Outline,
			BorderSizePixel = 0,
			ZIndex = 4,
		}),
		-- Root pages show the product icon in this slot; deeper pages show Back (UI §2.1).
		make("ImageLabel", {
			Name = "Icon",
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 8, 0.5, 0),
			Size = UDim2.fromOffset(slot, slot),
			BackgroundTransparency = 1,
			ScaleType = Enum.ScaleType.Fit,
			ZIndex = 5,
		}),
		make("TextButton", {
			Name = "BackButton",
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 8, 0.5, 0),
			Size = UDim2.fromOffset(slot, slot),
			BackgroundColor3 = COLORS.PanelSurface2,
			BorderSizePixel = 0,
			AutoButtonColor = false,
			Text = "<",
			TextColor3 = COLORS.Text,
			FontFace = FONTS.FontTitle,
			TextSize = 36,
			Visible = false,
			ZIndex = 5,
		}, {
			corner(NUMBERS.RadiusSurface),
			stroke(COLORS.Outline, NUMBERS.StrokeThin),
			make("UIScale", { Name = "PressScale" }),
		}),
		make("TextLabel", {
			Name = "Title",
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 8 + slot + 16, 0.5, 0),
			Size = UDim2.new(1, -2 * (8 + slot + 16), 1, 0),
			BackgroundTransparency = 1,
			Text = "Panel",
			TextColor3 = COLORS.Text,
			FontFace = FONTS.FontTitle,
			TextSize = NUMBERS.TextTitle,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextStrokeColor3 = COLORS.Outline,
			TextStrokeTransparency = 0.35,
			TextTruncate = Enum.TextTruncate.AtEnd,
			ZIndex = 5,
		}),
		make("TextButton", {
			Name = "CloseButton",
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -8, 0.5, 0),
			Size = UDim2.fromOffset(slot, slot),
			BackgroundColor3 = COLORS.PanelSurface2,
			BorderSizePixel = 0,
			AutoButtonColor = false,
			Text = "X",
			TextColor3 = COLORS.Text,
			FontFace = FONTS.FontTitle,
			TextSize = 36,
			ZIndex = 5,
		}, {
			corner(NUMBERS.RadiusSurface),
			stroke(COLORS.Outline, NUMBERS.StrokeThin),
			make("UIScale", { Name = "PressScale" }),
		}),
	}),
	make("Frame", {
		Name = "Body",
		Position = UDim2.fromOffset(pad, bar + pad),
		Size = UDim2.new(1, -2 * pad, 1, -(bar + 2 * pad)),
		BackgroundTransparency = 1,
		ZIndex = 5,
	}),
})

local primary = button("Button", COLORS.Success)
primary:SetAttribute("Variant", "primary")
local secondary = button("ButtonSecondary", COLORS.PanelSurface2)
secondary:SetAttribute("Variant", "secondary")

local toast = make("Frame", {
	Name = "Toast",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, pad),
	Size = UDim2.fromOffset(720, 96),
	BackgroundColor3 = COLORS.PanelDeep,
	BorderSizePixel = 0,
	ZIndex = 50,
}, {
	corner(16),
	stroke(COLORS.Outline, 3),
	make("ImageLabel", {
		Name = "Icon",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 20, 0.5, 0),
		Size = UDim2.fromOffset(56, 56),
		BackgroundTransparency = 1,
		ScaleType = Enum.ScaleType.Fit,
		ZIndex = 51,
	}),
	make("TextLabel", {
		Name = "Label",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 92, 0.5, 0),
		Size = UDim2.new(1, -112, 1, -16),
		BackgroundTransparency = 1,
		Text = "Message",
		TextColor3 = COLORS.Text,
		FontFace = FONTS.FontBodyBold,
		TextSize = NUMBERS.TextBody,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 51,
	}),
})

-- The one dim behind panels (UI §2.6); it lives in the PanelBackdrop layer.
local backdrop = make("TextButton", {
	Name = "Backdrop",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = rgb(0, 0, 0),
	BackgroundTransparency = NUMBERS.BackdropTransparency,
	BorderSizePixel = 0,
	AutoButtonColor = false,
	Text = "",
	Modal = true,
	InputSink = Enum.InputSink.All,
	Selectable = false,
})

--------------------------------------------------------------------------------

local kit = Instance.new("Folder")
kit.Name = "Kit"
for name, value in pairs(COLORS) do
	kit:SetAttribute(name, value)
end
for name, value in pairs(NUMBERS) do
	kit:SetAttribute(name, value)
end
for name, value in pairs(FONTS) do
	kit:SetAttribute(name, value)
end
for name, value in pairs(STRINGS) do
	kit:SetAttribute(name, value)
end
kit:SetAttribute("Migration", MIGRATION)
for _, template in ipairs({ panelFrame, primary, secondary, toast, backdrop }) do
	template.Parent = kit
end

if existing then
	existing:Destroy()
end
kit.Parent = ReplicatedStorage
return string.format("kit-v1 applied: %d templates, %d tokens", #kit:GetChildren(), (function()
	local n = 0
	for _ in pairs(kit:GetAttributes()) do
		n += 1
	end
	return n - 1
end)())
