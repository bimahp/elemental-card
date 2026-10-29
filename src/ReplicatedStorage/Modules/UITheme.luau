local UITheme = {}

UITheme.Colors = {
	Outline = Color3.fromRGB(7, 10, 28),
	Stroke = Color3.fromRGB(53, 70, 116),
	Panel = Color3.fromRGB(24, 27, 44),
	PanelDeep = Color3.fromRGB(13, 18, 31),
	PanelSurface = Color3.fromRGB(18, 26, 43),
	PanelSurface2 = Color3.fromRGB(28, 38, 60),
	TitleNavy = Color3.fromRGB(18, 32, 68),
	TitleBlue = Color3.fromRGB(57, 132, 219),
	TitleGreen = Color3.fromRGB(24, 122, 78),
	TitleOrange = Color3.fromRGB(213, 93, 51),
	Text = Color3.fromRGB(248, 250, 255),
	TextSoft = Color3.fromRGB(197, 211, 238),
	TextMuted = Color3.fromRGB(147, 160, 190),
	Success = Color3.fromRGB(64, 178, 104),
	Warning = Color3.fromRGB(255, 186, 86),
	Danger = Color3.fromRGB(205, 66, 72),
	Disabled = Color3.fromRGB(61, 65, 79),
	Shard = Color3.fromRGB(42, 186, 255),
	Dust = Color3.fromRGB(141, 93, 255), -- retained: still used as the epic-rarity accent color
	Fragment = Color3.fromRGB(255, 196, 60), -- Card Fragments: warm gold (DESIGN_UI.md)
	MIGHTY = Color3.fromRGB(165, 14, 14),
	SWIFT = Color3.fromRGB(13, 101, 45),
	VITAL = Color3.fromRGB(23, 78, 166),
	NEUTRAL = Color3.fromRGB(154, 160, 166),
}

UITheme.Assets = {
	PanelTexture = "rbxassetid://115366182634060",
}

UITheme.Sizes = {
	ModalRadius = 20,
	SurfaceRadius = 12,
	ButtonRadius = 10,
	TitleBarHeight = 64,
	PanelPadding = 18,
	TileGap = 12,
	StrokeThick = 4,
	StrokeThin = 2,
	CloseButton = 42,
	MobileBreakpoint = 800,
}

UITheme.Fonts = {
	Title = Enum.Font.FredokaOne,
	Display = Enum.Font.FredokaOne,
	Button = Enum.Font.GothamBold,
	Body = Enum.Font.Gotham,
	BodyBold = Enum.Font.GothamBold,
}

UITheme.Accents = {
	Inventory = Color3.fromRGB(51, 124, 220),
	Vending = Color3.fromRGB(31, 154, 105),
	Mall = Color3.fromRGB(42, 158, 230),
	Deck = Color3.fromRGB(87, 106, 220),
	Matchmaking = Color3.fromRGB(214, 122, 44),
	PlayerStatus = Color3.fromRGB(37, 145, 139),
	Vendor = Color3.fromRGB(178, 122, 56),
}

return UITheme
