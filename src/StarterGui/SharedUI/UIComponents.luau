local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Theme = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("UITheme"))

local Components = {}
Components.Theme = Theme

local function corner(parent, radius)
	local c = parent:FindFirstChildOfClass("UICorner") or Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
	return c
end

local function stroke(parent, color, thickness)
	local s = parent:FindFirstChildOfClass("UIStroke") or Instance.new("UIStroke")
	s.Color = color or Theme.Colors.Stroke
	s.Thickness = thickness or Theme.Sizes.StrokeThin
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
	return s
end

local function padding(parent, amount)
	local p = parent:FindFirstChildOfClass("UIPadding") or Instance.new("UIPadding")
	p.PaddingTop = UDim.new(0, amount)
	p.PaddingBottom = UDim.new(0, amount)
	p.PaddingLeft = UDim.new(0, amount)
	p.PaddingRight = UDim.new(0, amount)
	p.Parent = parent
	return p
end

function Components.clear(parent)
	for _, child in ipairs(parent:GetChildren()) do
		child:Destroy()
	end
end

local function withYOffset(position, pixels)
	return UDim2.new(position.X.Scale, position.X.Offset, position.Y.Scale, position.Y.Offset + pixels)
end

local function bindModalEntrance(dialog)
	local screenGui = dialog:FindFirstAncestorOfClass("ScreenGui")
	if not screenGui or dialog:GetAttribute("ModalEntranceBound") then return end
	dialog:SetAttribute("ModalEntranceBound", true)

	local restPosition = dialog.Position
	local activeTween
	local sequence = 0

	local function cancelAnimation()
		sequence += 1
		if activeTween then activeTween:Cancel(); activeTween = nil end
		dialog.Position = restPosition
	end

	local function playAnimation()
		if not screenGui.Enabled then return end
		sequence += 1
		local token = sequence
		if activeTween then activeTween:Cancel() end
		restPosition = dialog.Position
		dialog.Position = withYOffset(restPosition, 30)

		local entrance = TweenService:Create(dialog, TweenInfo.new(0.44, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Position = restPosition,
		})
		activeTween = entrance
		entrance:Play()
		entrance.Completed:Connect(function(playbackState)
			if token ~= sequence or not screenGui.Enabled or playbackState ~= Enum.PlaybackState.Completed then return end
			activeTween = nil
			dialog.Position = restPosition
		end)
	end

	screenGui:GetPropertyChangedSignal("Enabled"):Connect(function()
		if screenGui.Enabled then task.defer(playAnimation) else cancelAnimation() end
	end)
	if screenGui.Enabled then task.defer(playAnimation) end
end

function Components.applyModalShell(dialog, titleBar, titleLabel, closeButton, backButton, accent)
	accent = accent or Theme.Accents.Inventory
	dialog.BackgroundColor3 = Theme.Colors.Panel
	dialog.BorderSizePixel = 0
	dialog.Active = true
	dialog.Selectable = false
	corner(dialog, Theme.Sizes.ModalRadius)
	stroke(dialog, Theme.Colors.Outline, Theme.Sizes.StrokeThick)
	local shadow = dialog:FindFirstChildOfClass("UIShadow") or Instance.new("UIShadow")
	shadow.BlurRadius = UDim.new(0, 18)
	shadow.Color = Theme.Colors.Outline
	shadow.Offset = UDim2.fromOffset(0, 8)
	shadow.Spread = UDim2.fromOffset(6, 6)
	shadow.Transparency = 0.42
	shadow.ZIndex = -1
	shadow.Parent = dialog
	local dialogPadding = dialog:FindFirstChildOfClass("UIPadding") or Instance.new("UIPadding")
	dialogPadding.PaddingTop = UDim.new(0, 0)
	dialogPadding.PaddingLeft = UDim.new(0, 0)
	dialogPadding.PaddingRight = UDim.new(0, 0)
	dialogPadding.PaddingBottom = UDim.new(0, 0)
	dialogPadding.Parent = dialog

	local inputBlocker = dialog:FindFirstChild("ModalInputBlocker") or Instance.new("TextButton")
	inputBlocker.Name = "ModalInputBlocker"
	inputBlocker.Size = UDim2.fromScale(1, 1)
	inputBlocker.Position = UDim2.fromScale(0, 0)
	inputBlocker.BackgroundTransparency = 1
	inputBlocker.Text = ""
	inputBlocker.AutoButtonColor = false
	inputBlocker.Active = true
	inputBlocker.Selectable = false
	inputBlocker.ZIndex = dialog.ZIndex
	inputBlocker.Parent = dialog

	local contentTexture = dialog:FindFirstChild("ContentTexture") or Instance.new("ImageLabel")
	contentTexture.Name = "ContentTexture"
	contentTexture.Position = UDim2.new(0, 0, 0, Theme.Sizes.TitleBarHeight)
	contentTexture.Size = UDim2.new(1, 0, 1, -Theme.Sizes.TitleBarHeight)
	contentTexture.BackgroundTransparency = 1
	contentTexture.Image = Theme.Assets.PanelTexture
	contentTexture.ImageTransparency = 0.08
	contentTexture.ScaleType = Enum.ScaleType.Tile
	contentTexture.TileSize = UDim2.fromOffset(640, 640)
	contentTexture.Active = false
	contentTexture.ZIndex = dialog.ZIndex + 1
	contentTexture.Parent = dialog
	local textureCorner = corner(contentTexture, Theme.Sizes.ModalRadius)
	textureCorner.TopLeftRadius = UDim.new(0, 0)
	textureCorner.TopRightRadius = UDim.new(0, 0)
	textureCorner.BottomLeftRadius = UDim.new(0, Theme.Sizes.ModalRadius)
	textureCorner.BottomRightRadius = UDim.new(0, Theme.Sizes.ModalRadius)
	local body = dialog:FindFirstChild("Body")
	if body and body:IsA("GuiObject") then body.ZIndex = dialog.ZIndex + 2 end

	titleBar.BackgroundColor3 = accent
	titleBar.BackgroundTransparency = 0
	titleBar.BorderSizePixel = 0
	titleBar.Size = UDim2.new(1, 0, 0, Theme.Sizes.TitleBarHeight)
	titleBar.ZIndex = math.max(dialog.ZIndex + 2, 3)
	titleBar.ClipsDescendants = true
	local titleCorner = corner(titleBar, Theme.Sizes.ModalRadius)
	titleCorner.TopLeftRadius = UDim.new(0, Theme.Sizes.ModalRadius)
	titleCorner.TopRightRadius = UDim.new(0, Theme.Sizes.ModalRadius)
	titleCorner.BottomLeftRadius = UDim.new(0, 0)
	titleCorner.BottomRightRadius = UDim.new(0, 0)
	local oldGradient = titleBar:FindFirstChild("TitleGradient")
	if oldGradient then oldGradient:Destroy() end

	local legacySquareFill = titleBar:FindFirstChild("HeaderSquareFill")
	if legacySquareFill then legacySquareFill:Destroy() end

	local divider = titleBar:FindFirstChild("HeaderDivider") or Instance.new("Frame")
	divider.Name = "HeaderDivider"
	divider.AnchorPoint = Vector2.new(0, 1)
	divider.Position = UDim2.new(0, 0, 1, 0)
	divider.Size = UDim2.new(1, 0, 0, Theme.Sizes.StrokeThick)
	divider.BackgroundColor3 = Theme.Colors.Outline
	divider.BackgroundTransparency = 0
	divider.BorderSizePixel = 0
	divider.ZIndex = titleBar.ZIndex + 1
	divider.Parent = titleBar

	titleLabel.BackgroundTransparency = 1
	titleLabel.ZIndex = titleBar.ZIndex + 2
	titleLabel.TextColor3 = Theme.Colors.Text
	titleLabel.Font = Theme.Fonts.Title
	titleLabel.TextSize = 28
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.TextStrokeTransparency = 0.35
	titleLabel.TextStrokeColor3 = Theme.Colors.Outline
	titleLabel.AnchorPoint = Vector2.new(0, 0.5)
	titleLabel.Position = UDim2.new(0, backButton and 76 or 24, 0.5, 0)
	titleLabel.Size = UDim2.new(1, backButton and -142 or -88, 1, 0)

	closeButton.ZIndex = titleBar.ZIndex + 2
	closeButton.Size = UDim2.fromOffset(Theme.Sizes.CloseButton, Theme.Sizes.CloseButton)
	closeButton.AnchorPoint = Vector2.new(1, 0.5)
	closeButton.Position = UDim2.new(1, -14, 0.5, 0)
	closeButton.BackgroundColor3 = Theme.Colors.PanelSurface2
	closeButton.Text = "X"
	closeButton.TextColor3 = Theme.Colors.Text
	closeButton.Font = Theme.Fonts.Title
	closeButton.TextSize = 24
	closeButton.BorderSizePixel = 0
	corner(closeButton, 10)
	stroke(closeButton, Theme.Colors.Outline, 2)

	if backButton then
		backButton.ZIndex = titleBar.ZIndex + 2
		backButton.Size = UDim2.fromOffset(52, 38)
		backButton.AnchorPoint = Vector2.new(0, 0.5)
		backButton.Position = UDim2.new(0, 14, 0.5, 0)
		backButton.BackgroundColor3 = Theme.Colors.PanelSurface2
		backButton.Text = "<"
		backButton.TextColor3 = Theme.Colors.Text
		backButton.Font = Theme.Fonts.Title
		backButton.TextSize = 24
		backButton.BorderSizePixel = 0
		corner(backButton, 10)
		stroke(backButton, Theme.Colors.Outline, 2)
	end
	bindModalEntrance(dialog)
end

function Components.createHeaderIcon(titleBar, image)
	local icon = titleBar:FindFirstChild("HeaderIcon") or Instance.new("ImageLabel")
	icon.Name = "HeaderIcon"
	icon.AnchorPoint = Vector2.new(0, 0.5)
	icon.Position = UDim2.new(0, 17, 0.5, 0)
	icon.Size = UDim2.fromOffset(46, 46)
	icon.BackgroundTransparency = 1
	icon.Image = image or ""
	icon.ImageColor3 = Color3.new(1, 1, 1)
	icon.ImageTransparency = 0
	icon.ScaleType = Enum.ScaleType.Fit
	icon.ResampleMode = Enum.ResamplerMode.Default
	icon.ZIndex = titleBar.ZIndex + 2
	icon.Active = false
	icon.Parent = titleBar
	return icon
end

function Components.createTitleBar(parent, titleText, accentColor, opts)
	opts = opts or {}
	local bar = Instance.new("Frame")
	bar.Name = opts.name or "TitleBar"
	bar.Size = UDim2.new(1, 0, 0, Theme.Sizes.TitleBarHeight)
	bar.BackgroundColor3 = accentColor or Theme.Accents.Inventory
	bar.BorderSizePixel = 0
	bar.Parent = parent
	corner(bar, Theme.Sizes.ModalRadius)
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Position = UDim2.new(0, opts.backButton and 76 or 24, 0, 0)
	title.Size = UDim2.new(1, opts.backButton and -142 or -88, 1, 0)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = titleText or "Panel"
	title.Font = Theme.Fonts.Title
	title.TextSize = 28
	title.TextColor3 = Theme.Colors.Text
	title.TextStrokeTransparency = 0.35
	title.TextStrokeColor3 = Theme.Colors.Outline
	title.Parent = bar
	local close = Instance.new("TextButton")
	close.Name = "CloseButton"
	close.Parent = bar
	local back = nil
	if opts.backButton then
		back = Instance.new("TextButton")
		back.Name = "BackButton"
		back.Parent = bar
	end
	Components.applyModalShell(parent, bar, title, close, back, accentColor)
	return bar, title, close, back
end

function Components.createModalShell(parent, titleText, accentColor, opts)
	opts = opts or {}
	local dialog = Instance.new("Frame")
	dialog.Name = opts.name or "Dialog"
	dialog.Size = opts.size or UDim2.fromScale(0.82, 0.76)
	dialog.Position = opts.position or UDim2.fromScale(0.5, 0.5)
	dialog.AnchorPoint = opts.anchorPoint or Vector2.new(0.5, 0.5)
	dialog.Parent = parent
	local bar, title, close, back = Components.createTitleBar(dialog, titleText, accentColor, { backButton = opts.backButton })
	local body = Instance.new("Frame")
	body.Name = "Body"
	body.Position = UDim2.new(0, 18, 0, 76)
	body.Size = UDim2.new(1, -36, 1, -104)
	body.BackgroundTransparency = 1
	body.ZIndex = dialog.ZIndex + 2
	body.Parent = dialog
	return dialog, body, bar, title, close, back
end

function Components.styleScrim(scrim)
	scrim.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	scrim.BackgroundTransparency = 0.34
	scrim.BorderSizePixel = 0
	scrim.Text = ""
	scrim.AutoButtonColor = false
end

function Components.bindFullscreenBackdrop(screenGui, scrim)
	screenGui.IgnoreGuiInset = false
	screenGui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	screenGui.ClipToDeviceSafeArea = true

	local parent = screenGui.Parent
	local backdropName = screenGui.Name .. "Backdrop"
	local backdropGui = parent:FindFirstChild(backdropName)
	if backdropGui and not backdropGui:IsA("ScreenGui") then backdropGui:Destroy(); backdropGui = nil end
	if not backdropGui then
		backdropGui = Instance.new("ScreenGui")
		backdropGui.Name = backdropName
		backdropGui.ResetOnSpawn = screenGui.ResetOnSpawn
		backdropGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
		backdropGui.Parent = parent
	end
	backdropGui.IgnoreGuiInset = true
	backdropGui.ScreenInsets = Enum.ScreenInsets.None
	backdropGui.SafeAreaCompatibility = Enum.SafeAreaCompatibility.None
	backdropGui.ClipToDeviceSafeArea = false
	backdropGui.DisplayOrder = screenGui.DisplayOrder - 1

	local visualTransparency = scrim.BackgroundTransparency
	local backdrop = backdropGui:FindFirstChild("Backdrop")
	if backdrop and not backdrop:IsA("TextButton") then backdrop:Destroy(); backdrop = nil end
	backdrop = backdrop or Instance.new("TextButton")
	backdrop.Name = "Backdrop"
	backdrop.Position = UDim2.fromScale(0, 0)
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = scrim.BackgroundColor3
	backdrop.BackgroundTransparency = visualTransparency
	backdrop.BorderSizePixel = 0
	backdrop.Text = ""
	backdrop.AutoButtonColor = false
	backdrop.Active = true
	backdrop.Interactable = true
	backdrop.Modal = true
	backdrop.InputSink = Enum.InputSink.All
	backdrop.ZIndex = 1
	backdrop.Parent = backdropGui

	-- The Core-safe scrim catches outside clicks; only the full-screen backdrop dims.
	scrim.BackgroundTransparency = 1

	local function syncEnabled()
		backdropGui.Enabled = screenGui.Enabled
	end
	syncEnabled()
	screenGui:GetPropertyChangedSignal("Enabled"):Connect(syncEnabled)
	return backdrop
end

function Components.createSectionSurface(parent, name, opts)
	opts = opts or {}
	local frame = Instance.new("Frame")
	frame.Name = name or "SectionSurface"
	frame.BackgroundColor3 = opts.light and Color3.fromRGB(224, 228, 236) or (opts.color or Theme.Colors.PanelSurface)
	frame.BorderSizePixel = 0
	frame.Parent = parent
	corner(frame, opts.radius or Theme.Sizes.SurfaceRadius)
	stroke(frame, opts.strokeColor or Theme.Colors.Stroke, opts.strokeThickness or Theme.Sizes.StrokeThin)
	if opts.padding ~= false then padding(frame, opts.padding or 12) end
	return frame
end

function Components.createPrimaryButton(parent, text, icon, state)
	state = state or {}
	local b = Instance.new("TextButton")
	b.Name = state.name or "Button"
	b.Size = state.size or UDim2.fromOffset(220, 48)
	b.BackgroundColor3 = state.disabled and Theme.Colors.Disabled or (state.color or Theme.Colors.Success)
	b.Text = text
	b.TextColor3 = Theme.Colors.Text
	b.Font = state.font or Theme.Fonts.Button
	b.TextSize = state.textSize or 16
	b.TextWrapped = true
	b.BorderSizePixel = 0
	b.AutoButtonColor = not state.disabled
	b.Active = not state.disabled
	b.Parent = parent
	corner(b, state.radius or Theme.Sizes.ButtonRadius)
	stroke(b, state.strokeColor or Theme.Colors.Outline, state.strokeThickness or 2)
	local oldGradient = b:FindFirstChild("ButtonGradient")
	if oldGradient then oldGradient:Destroy() end
	if icon then
		local image = Instance.new("ImageLabel")
		image.Name = "Icon"
		image.BackgroundTransparency = 1
		image.AnchorPoint = Vector2.new(0, 0.5)
		image.Position = UDim2.new(0, 12, 0.5, 0)
		image.Size = UDim2.fromOffset(28, 28)
		image.Image = icon
		image.ScaleType = Enum.ScaleType.Fit
		image.Parent = b
	end
	return b
end

function Components.createCurrencyPill(parent, icon, amount, label, color)
	local pill = Instance.new("Frame")
	pill.Name = label and (label .. "Pill") or "CurrencyPill"
	pill.Size = UDim2.fromOffset(174, 42)
	pill.BackgroundColor3 = Theme.Colors.PanelDeep
	pill.BorderSizePixel = 0
	pill.Parent = parent
	corner(pill, 18)
	stroke(pill, color or Theme.Colors.Stroke, 2)
	local img = Instance.new("ImageLabel")
	img.Name = "Icon"
	img.BackgroundTransparency = 1
	img.Position = UDim2.fromOffset(10, 5)
	img.Size = UDim2.fromOffset(32, 32)
	img.Image = icon or ""
	img.ScaleType = Enum.ScaleType.Fit
	img.Parent = pill
	local txt = Instance.new("TextLabel")
	txt.Name = "Count"
	txt.BackgroundTransparency = 1
	txt.Position = UDim2.fromOffset(48, 0)
	txt.Size = UDim2.new(1, -56, 1, 0)
	txt.TextXAlignment = Enum.TextXAlignment.Left
	txt.Text = tostring(amount or 0) .. (label and (" " .. label) or "")
	txt.TextColor3 = Theme.Colors.TextSoft
	txt.Font = Theme.Fonts.BodyBold
	txt.TextSize = 15
	txt.TextTruncate = Enum.TextTruncate.AtEnd
	txt.Parent = pill
	return pill, txt
end

function Components.createEmptyState(parent, kind, message)
	local frame = Components.createSectionSurface(parent, "EmptyState", { padding = false, strokeColor = Theme.Colors.Stroke })
	frame.Size = UDim2.fromScale(1, 1)
	local silhouette = Instance.new("Frame")
	silhouette.Name = "CardSilhouette"
	silhouette.AnchorPoint = Vector2.new(0.5, 0.5)
	silhouette.Position = UDim2.fromScale(0.5, 0.42)
	silhouette.Size = UDim2.fromOffset(kind == "wide" and 120 or 104, kind == "wide" and 160 or 142)
	silhouette.BackgroundColor3 = Theme.Colors.PanelSurface2
	silhouette.BackgroundTransparency = 0.35
	silhouette.BorderSizePixel = 0
	silhouette.Parent = frame
	corner(silhouette, 12)
	stroke(silhouette, Theme.Colors.Stroke, 2)
	local diamond = Instance.new("TextLabel")
	diamond.BackgroundTransparency = 1
	diamond.AnchorPoint = Vector2.new(0.5, 0.5)
	diamond.Position = UDim2.fromScale(0.5, 0.5)
	diamond.Size = UDim2.fromScale(1, 1)
	diamond.Text = "◇"
	diamond.TextColor3 = Theme.Colors.Shard
	diamond.TextTransparency = 0.28
	diamond.Font = Theme.Fonts.Title
	diamond.TextSize = 54
	diamond.Parent = silhouette
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.AnchorPoint = Vector2.new(0.5, 1)
	label.Position = UDim2.new(0.5, 0, 1, -34)
	label.Size = UDim2.new(1, -40, 0, 56)
	label.Text = message or "Select an item"
	label.TextColor3 = Theme.Colors.TextSoft
	label.Font = Theme.Fonts.BodyBold
	label.TextSize = 17
	label.TextWrapped = true
	label.Parent = frame
	return frame
end

-- Generic rounded/stroked progress-bar primitive (track + fill), reusable by
-- any future meter (EXP, quest progress, loading, etc.) -- not tied to any
-- one panel. Returns track, fill, setProgress(fraction, tweenTime?).
function Components.createProgressBar(parent, opts)
	opts = opts or {}
	local barHeight = (opts.size and opts.size.Y.Offset) or 18
	local radius = opts.radius or math.floor(barHeight / 2)

	local track = Instance.new("Frame")
	track.Name = opts.name or "ProgressBar"
	track.Size = opts.size or UDim2.new(1, 0, 0, barHeight)
	track.BackgroundColor3 = opts.trackColor or Theme.Colors.PanelDeep
	track.BorderSizePixel = 0
	track.ClipsDescendants = true
	track.Parent = parent
	corner(track, radius)
	stroke(track, opts.strokeColor or Theme.Colors.Stroke, opts.strokeThickness or Theme.Sizes.StrokeThin)

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.new(math.clamp(opts.initial or 0, 0, 1), 0, 1, 0)
	fill.BackgroundColor3 = opts.fillColor or Theme.Colors.Success
	fill.BorderSizePixel = 0
	fill.ZIndex = track.ZIndex + 1
	fill.Parent = track
	corner(fill, radius)

	local function setProgress(fraction, tweenTime)
		fraction = math.clamp(fraction or 0, 0, 1)
		local goalSize = UDim2.new(fraction, 0, 1, 0)
		if tweenTime and tweenTime > 0 then
			TweenService:Create(fill, TweenInfo.new(tweenTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = goalSize }):Play()
		else
			fill.Size = goalSize
		end
	end

	return track, fill, setProgress
end

function Components.addCanvasPattern(parent, transparency)
	local texture = Instance.new("ImageLabel")
	texture.Name = "PanelTexture"
	texture.BackgroundTransparency = 1
	texture.Size = UDim2.fromScale(1, 1)
	texture.Image = Theme.Assets.PanelTexture
	texture.ImageTransparency = transparency or 0.08
	texture.ScaleType = Enum.ScaleType.Tile
	texture.TileSize = UDim2.fromOffset(640, 640)
	texture.ZIndex = 0
	texture.Active = false
	texture.Parent = parent
	return texture
end

return Components
