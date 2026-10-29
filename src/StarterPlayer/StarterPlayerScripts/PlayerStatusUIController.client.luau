-- PlayerStatusUIController: responsive account overview and cosmetic title equip UI.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local gui = playerGui:WaitForChild("PlayerStatusUI")
local hud = playerGui:WaitForChild("Hud")
local profileButton = hud:WaitForChild("TopRightAnchor"):WaitForChild("ProfileButton")
local profileIcon = profileButton:WaitForChild("Icon")
profileIcon.Image = "rbxassetid://134348501295873"
profileIcon.ScaleType = Enum.ScaleType.Fit
local avatarCorner = profileIcon:FindFirstChildOfClass("UICorner")
if avatarCorner then avatarCorner:Destroy() end
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local getStatus = remotes:WaitForChild("GetPlayerStatus")
local equipTitle = remotes:WaitForChild("EquipTitle")

local UI = require(playerGui:WaitForChild("SharedUI"):WaitForChild("UIComponents"))
local Theme = UI.Theme
local TitleConfig = require(ReplicatedStorage.Modules.TitleConfig)
local PanelCoordinator = require(ReplicatedStorage.Modules.PanelCoordinator)

local dialog = gui:WaitForChild("Dialog")
local scrim = gui:WaitForChild("Scrim")
local titleBar = dialog:WaitForChild("TitleBar")
local title = titleBar:WaitForChild("Title")
local closeButton = titleBar:WaitForChild("CloseButton")
local body = dialog:WaitForChild("Body")

UI.styleScrim(scrim)
local fullscreenBackdrop = UI.bindFullscreenBackdrop(gui, scrim)
UI.applyModalShell(dialog, titleBar, title, closeButton, nil, Theme.Accents.PlayerStatus)
local headerIcon = UI.createHeaderIcon(titleBar, "")
headerIcon.ScaleType = Enum.ScaleType.Crop
title.Text = "Player Status"
title.Position = UDim2.new(0, 76, 0.5, 0)
title.Size = UDim2.new(1, -142, 1, 0)
body.Position = UDim2.new(0, 18, 0, 76)
body.Size = UDim2.new(1, -36, 1, -104)
body.BackgroundTransparency = 1
body.ClipsDescendants = true

for _, child in ipairs(body:GetChildren()) do child:Destroy() end

local function corner(instance, radius)
	local value = instance:FindFirstChildOfClass("UICorner") or Instance.new("UICorner")
	value.CornerRadius = type(radius) == "number" and UDim.new(0, radius) or radius
	value.Parent = instance
	return value
end

local function stroke(instance, color, thickness, transparency)
	local value = instance:FindFirstChildOfClass("UIStroke") or Instance.new("UIStroke")
	value.Color = color or Theme.Colors.Stroke
	value.Thickness = thickness or 1
	value.Transparency = transparency or 0
	value.Parent = instance
	return value
end

local function label(parent, name, text, size, position, font, textSize, color, alignment)
	local value = Instance.new("TextLabel")
	value.Name = name
	value.BackgroundTransparency = 1
	value.Size = size
	value.Position = position or UDim2.fromOffset(0, 0)
	value.Text = text or ""
	value.TextColor3 = color or Theme.Colors.Text
	value.Font = font or Theme.Fonts.Body
	value.TextSize = textSize or 16
	value.TextXAlignment = alignment or Enum.TextXAlignment.Left
	value.TextYAlignment = Enum.TextYAlignment.Center
	value.TextWrapped = true
	value.BorderSizePixel = 0
	value.Parent = parent
	return value
end

local tabBar = Instance.new("Frame")
tabBar.Name = "TabBar"
tabBar.Size = UDim2.new(1, 0, 0, 42)
tabBar.BackgroundColor3 = Theme.Colors.PanelDeep
tabBar.BorderSizePixel = 0
tabBar.Parent = body
corner(tabBar, 8)
stroke(tabBar, Theme.Colors.Stroke, 1)

local tabLayout = Instance.new("UIListLayout")
tabLayout.FillDirection = Enum.FillDirection.Horizontal
tabLayout.SortOrder = Enum.SortOrder.LayoutOrder
tabLayout.Padding = UDim.new(0, 4)
tabLayout.Parent = tabBar

local tabPadding = Instance.new("UIPadding")
tabPadding.PaddingTop = UDim.new(0, 4)
tabPadding.PaddingBottom = UDim.new(0, 4)
tabPadding.PaddingLeft = UDim.new(0, 4)
tabPadding.PaddingRight = UDim.new(0, 4)
tabPadding.Parent = tabBar

local function makeTab(name, order)
	local button = Instance.new("TextButton")
	button.Name = name .. "Tab"
	button.LayoutOrder = order
	button.Size = UDim2.new(0.5, -2, 1, 0)
	button.BackgroundColor3 = Theme.Colors.PanelSurface2
	button.BorderSizePixel = 0
	button.Text = name
	button.TextColor3 = Theme.Colors.TextSoft
	button.Font = Theme.Fonts.Button
	button.TextSize = 15
	button.AutoButtonColor = false
	button.Parent = tabBar
	corner(button, 6)
	return button
end

local overviewTab = makeTab("Overview", 1)
local titlesTab = makeTab("Titles", 2)

local content = Instance.new("Frame")
content.Name = "Content"
content.Position = UDim2.new(0, 0, 0, 50)
content.Size = UDim2.new(1, 0, 1, -50)
content.BackgroundTransparency = 1
content.ClipsDescendants = true
content.Parent = body

local activeTab = "Overview"
local currentStatus
local requestSerial = 0
local avatarImage = ""
local feedbackText = ""
local testViewportOverride
local renderCurrent

local function clearContent()
	for _, child in ipairs(content:GetChildren()) do child:Destroy() end
end

local function viewportSize()
	if testViewportOverride then return testViewportOverride end
	local viewport = gui.AbsoluteSize
	if viewport.X <= 1 or viewport.Y <= 1 then
		viewport = Workspace.CurrentCamera and Workspace.CurrentCamera.ViewportSize or Vector2.new(1280, 720)
	end
	return viewport
end

local function isCompact()
	local viewport = viewportSize()
	return viewport.X < Theme.Sizes.MobileBreakpoint or viewport.Y < 500
end

local function updateTabs()
	for name, button in pairs({ Overview = overviewTab, Titles = titlesTab }) do
		local active = name == activeTab
		button.BackgroundColor3 = active and Theme.Accents.PlayerStatus or Theme.Colors.PanelSurface2
		button.TextColor3 = active and Theme.Colors.Text or Theme.Colors.TextSoft
	end
end

local function showMessage(message, canRetry)
	clearContent()
	local messageLabel = label(
		content,
		canRetry and "ErrorLabel" or "LoadingLabel",
		message,
		UDim2.new(1, -40, 0, 70),
		UDim2.new(0, 20, 0.5, -50),
		Theme.Fonts.BodyBold,
		18,
		canRetry and Theme.Colors.Warning or Theme.Colors.TextSoft,
		Enum.TextXAlignment.Center
	)
	messageLabel.TextYAlignment = Enum.TextYAlignment.Center
	if canRetry then
		local retry = UI.createPrimaryButton(content, "Retry", nil, {
			name = "RetryButton",
			size = UDim2.fromOffset(150, 44),
			color = Theme.Accents.PlayerStatus,
		})
		retry.AnchorPoint = Vector2.new(0.5, 0)
		retry.Position = UDim2.new(0.5, 0, 0.5, 24)
		retry.Activated:Connect(function()
			requestSerial += 1
			local serial = requestSerial
			showMessage("Loading profile...", false)
			task.spawn(function()
				local ok, response = pcall(function() return getStatus:InvokeServer() end)
				if serial ~= requestSerial or not gui.Enabled then return end
				if ok and type(response) == "table" and response.ok and type(response.data) == "table" then
					currentStatus = response.data
					feedbackText = ""
					renderCurrent()
				else
					showMessage((ok and response and response.error) or "Player status is temporarily unavailable.", true)
				end
			end)
		end)
	end
end

local function makeSurface(parent, name)
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.BackgroundColor3 = Theme.Colors.PanelSurface
	frame.BorderSizePixel = 0
	frame.Parent = parent
	corner(frame, 8)
	stroke(frame, Theme.Colors.Stroke, 1)
	return frame
end

local function renderOverview()
	clearContent()
	local status = currentStatus
	if not status then showMessage("Loading profile...", false); return end
	local compact = isCompact()

	local identity = makeSurface(content, "Identity")
	identity.Size = UDim2.new(0.31, -6, 1, 0)

	local details = Instance.new("Frame")
	details.Name = "Progression"
	details.Position = UDim2.new(0.31, 8, 0, 0)
	details.Size = UDim2.new(0.69, -8, 1, 0)
	details.BackgroundTransparency = 1
	details.Parent = content

	local avatarSize = compact and 68 or 104
	local avatar = Instance.new("ImageLabel")
	avatar.Name = "Avatar"
	avatar.AnchorPoint = Vector2.new(0.5, 0)
	avatar.Position = UDim2.new(0.5, 0, 0, compact and 8 or 14)
	avatar.Size = UDim2.fromOffset(avatarSize, avatarSize)
	avatar.BackgroundColor3 = Theme.Colors.PanelDeep
	avatar.BorderSizePixel = 0
	avatar.Image = avatarImage
	avatar.ScaleType = Enum.ScaleType.Crop
	avatar.Parent = identity
	corner(avatar, UDim.new(1, 0))
	stroke(avatar, Theme.Accents.PlayerStatus, 2)

	local textTop = (compact and 82 or 126)
	local displayName = label(identity, "DisplayName", player.DisplayName,
		UDim2.new(1, -16, 0, compact and 22 or 28), UDim2.new(0, 8, 0, textTop),
		Theme.Fonts.Title, compact and 18 or 22, Theme.Colors.Text, Enum.TextXAlignment.Center)
	displayName.TextTruncate = Enum.TextTruncate.AtEnd
	displayName.TextWrapped = false

	local username = label(identity, "Username", "@" .. player.Name,
		UDim2.new(1, -16, 0, 18), UDim2.new(0, 8, 0, textTop + (compact and 22 or 30)),
		Theme.Fonts.Body, compact and 12 or 14, Theme.Colors.TextMuted, Enum.TextXAlignment.Center)
	username.TextTruncate = Enum.TextTruncate.AtEnd
	username.TextWrapped = false

	local equipped = TitleConfig.get(status.titles and status.titles.equippedId) or TitleConfig.get(TitleConfig.DEFAULT_ID)
	label(identity, "EquippedTitle", equipped.displayName,
		UDim2.new(1, -16, 0, 24), UDim2.new(0, 8, 0, textTop + (compact and 42 or 54)),
		Theme.Fonts.BodyBold, compact and 13 or 15, Theme.Colors.Warning, Enum.TextXAlignment.Center)

	local archetype = status.archetype or "UNALIGNED"
	local archetypeColor = Theme.Colors[archetype] or Theme.Colors.NEUTRAL
	local archetypeLabel = label(identity, "Archetype", archetype,
		UDim2.new(1, -20, 0, 22), UDim2.new(0, 10, 1, -30),
		Theme.Fonts.Button, compact and 12 or 13, archetypeColor, Enum.TextXAlignment.Center)
	archetypeLabel.TextWrapped = false

	local levelSurface = makeSurface(details, "LevelProgress")
	levelSurface.Size = UDim2.new(1, 0, compact and 0.48 or 0.42, -4)

	local level = status.level or {}
	label(levelSurface, "LevelHeading", level.maxed and "MAX LEVEL" or ("LEVEL " .. tostring(level.current or 1)),
		UDim2.new(0.52, -12, 0, compact and 30 or 38), UDim2.new(0, 14, 0, compact and 5 or 10),
		Theme.Fonts.Title, compact and 20 or 26, Theme.Colors.Text, Enum.TextXAlignment.Left)

	local expText = level.maxed and "Progress complete"
		or string.format("%s / %s EXP", tostring(level.expInto or 0), tostring(level.expNeeded or 0))
	label(levelSurface, "ExpText", expText,
		UDim2.new(0.48, -14, 0, compact and 26 or 34), UDim2.new(0.52, 0, 0, compact and 7 or 12),
		Theme.Fonts.BodyBold, compact and 12 or 14, Theme.Colors.TextSoft, Enum.TextXAlignment.Right)

	local fraction = 1
	if not level.maxed and (level.expNeeded or 0) > 0 then
		fraction = math.clamp((level.expInto or 0) / level.expNeeded, 0, 1)
	end
	local progress = UI.createProgressBar(levelSurface, {
		name = "ExpProgress",
		size = UDim2.new(1, -28, 0, compact and 14 or 18),
		initial = fraction,
		fillColor = Theme.Accents.PlayerStatus,
	})
	progress.Position = UDim2.new(0, 14, 1, compact and -24 or -32)

	local stats = makeSurface(details, "Stats")
	stats.Position = UDim2.new(0, 0, compact and 0.48 or 0.42, 5)
	stats.Size = UDim2.new(1, 0, compact and 0.52 or 0.58, -5)

	local pvp = status.pvp or {}
	local games = (pvp.wins or 0) + (pvp.losses or 0)
	local winRate = games > 0 and string.format("%.1f%%", (pvp.wins or 0) * 100 / games) or "—"
	local collection = status.collection or {}
	local trainers = status.trainers or {}

	local metrics = {
		{ "PVP RECORD", string.format("%dW / %dL", pvp.wins or 0, pvp.losses or 0), "Win rate " .. winRate },
		{ "COLLECTION", string.format("%d / %d", collection.uniqueOwned or 0, collection.totalCollectible or 0), "Unique cards" },
		{ "TRAINERS", string.format("%d / %d", trainers.cleared or 0, trainers.total or 3), "First clears" },
	}
	for index, metric in ipairs(metrics) do
		local metricFrame = Instance.new("Frame")
		metricFrame.Name = metric[1]:gsub(" ", "")
		metricFrame.Position = UDim2.new((index - 1) / 3, index == 1 and 0 or 4, 0, 0)
		metricFrame.Size = UDim2.new(1 / 3, index == 1 and -4 or -8, 1, 0)
		metricFrame.BackgroundTransparency = 1
		metricFrame.Parent = stats
		if index > 1 then
			local divider = Instance.new("Frame")
			divider.Name = "Divider"
			divider.Position = UDim2.new(0, -4, 0.18, 0)
			divider.Size = UDim2.new(0, 1, 0.64, 0)
			divider.BackgroundColor3 = Theme.Colors.Stroke
			divider.BorderSizePixel = 0
			divider.Parent = metricFrame
		end
		label(metricFrame, "Caption", metric[1], UDim2.new(1, -8, 0, 22), UDim2.new(0, 4, 0, compact and 5 or 12),
			Theme.Fonts.BodyBold, compact and 10 or 12, Theme.Colors.TextMuted, Enum.TextXAlignment.Center)
		label(metricFrame, "Value", metric[2], UDim2.new(1, -8, 0, compact and 30 or 38), UDim2.new(0, 4, 0.5, compact and -14 or -18),
			Theme.Fonts.Title, compact and 17 or 22, Theme.Colors.Text, Enum.TextXAlignment.Center)
		label(metricFrame, "Detail", metric[3], UDim2.new(1, -8, 0, 20), UDim2.new(0, 4, 1, compact and -25 or -30),
			Theme.Fonts.Body, compact and 10 or 12, Theme.Colors.TextSoft, Enum.TextXAlignment.Center)
	end
end

local function renderTitles()
	clearContent()
	local status = currentStatus
	if not status then showMessage("Loading profile...", false); return end
	local compact = isCompact()

	local feedbackHeight = feedbackText ~= "" and 28 or 0
	if feedbackHeight > 0 then
		label(content, "Feedback", feedbackText, UDim2.new(1, 0, 0, feedbackHeight), UDim2.fromOffset(0, 0),
			Theme.Fonts.BodyBold, 13, Theme.Colors.Warning, Enum.TextXAlignment.Center)
	end

	local list = Instance.new("ScrollingFrame")
	list.Name = "TitleList"
	list.Position = UDim2.new(0, 0, 0, feedbackHeight)
	list.Size = UDim2.new(1, 0, 1, -feedbackHeight)
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 6
	list.ScrollBarImageColor3 = Theme.Accents.PlayerStatus
	list.CanvasSize = UDim2.fromOffset(0, 0)
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.ScrollingDirection = Enum.ScrollingDirection.Y
	list.Parent = content

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list

	local padding = Instance.new("UIPadding")
	padding.PaddingRight = UDim.new(0, 8)
	padding.PaddingBottom = UDim.new(0, 4)
	padding.Parent = list

	for _, item in ipairs(status.titles.items or {}) do
		local row = makeSurface(list, item.id)
		row.LayoutOrder = item.order or 0
		row.Size = UDim2.new(1, -8, 0, compact and 68 or 78)
		row.BackgroundColor3 = item.unlocked and Theme.Colors.PanelSurface or Theme.Colors.PanelDeep
		row.BackgroundTransparency = item.unlocked and 0 or 0.18

		local rightWidth = compact and 92 or 116
		local nameLabel = label(row, "TitleName", item.displayName,
			UDim2.new(1, -(rightWidth + 28), 0, 28), UDim2.fromOffset(14, compact and 5 or 8),
			Theme.Fonts.BodyBold, compact and 15 or 17,
			item.unlocked and Theme.Colors.Text or Theme.Colors.TextMuted, Enum.TextXAlignment.Left)
		nameLabel.TextWrapped = false
		nameLabel.TextTruncate = Enum.TextTruncate.AtEnd

		local detailText = item.unlocked and item.description or item.unlockText
		local detail = label(row, "Detail", detailText,
			UDim2.new(1, -(rightWidth + 28), 0, compact and 28 or 32), UDim2.fromOffset(14, compact and 32 or 38),
			Theme.Fonts.Body, compact and 11 or 13,
			item.unlocked and Theme.Colors.TextSoft or Theme.Colors.TextMuted, Enum.TextXAlignment.Left)
		detail.TextYAlignment = Enum.TextYAlignment.Top

		if item.equipped then
			label(row, "Equipped", "✓ Equipped", UDim2.fromOffset(rightWidth, 34),
				UDim2.new(1, -(rightWidth + 12), 0.5, -17), Theme.Fonts.BodyBold, compact and 12 or 14,
				Theme.Colors.Success, Enum.TextXAlignment.Center)
		elseif not item.unlocked then
			label(row, "Locked", "Locked", UDim2.fromOffset(rightWidth, 34),
				UDim2.new(1, -(rightWidth + 12), 0.5, -17), Theme.Fonts.BodyBold, compact and 12 or 14,
				Theme.Colors.TextMuted, Enum.TextXAlignment.Center)
		else
			local equip = UI.createPrimaryButton(row, "Equip", nil, {
				name = "EquipButton",
				size = UDim2.fromOffset(rightWidth, compact and 36 or 40),
				color = Theme.Accents.PlayerStatus,
				textSize = compact and 12 or 14,
				radius = 7,
			})
			equip.AnchorPoint = Vector2.new(0, 0.5)
			equip.Position = UDim2.new(1, -(rightWidth + 12), 0.5, 0)
			equip.Activated:Connect(function()
				equip.Active = false
				equip.AutoButtonColor = false
				equip.Text = "Equipping..."
				task.spawn(function()
					local ok, response = pcall(function() return equipTitle:InvokeServer(item.id) end)
					if not gui.Enabled then return end
					if ok and type(response) == "table" and response.ok and type(response.data) == "table" then
						currentStatus = response.data
						feedbackText = ""
					else
						feedbackText = (ok and response and response.error) or "Could not equip that title."
					end
					renderTitles()
				end)
			end)
		end
	end
end

renderCurrent = function()
	updateTabs()
	if activeTab == "Titles" then renderTitles() else renderOverview() end
end

overviewTab.Activated:Connect(function()
	activeTab = "Overview"
	renderCurrent()
end)
titlesTab.Activated:Connect(function()
	activeTab = "Titles"
	renderCurrent()
end)

local function fetchStatus()
	requestSerial += 1
	local serial = requestSerial
	showMessage("Loading profile...", false)
	task.spawn(function()
		local ok, response = pcall(function() return getStatus:InvokeServer() end)
		if serial ~= requestSerial or not gui.Enabled then return end
		if ok and type(response) == "table" and response.ok and type(response.data) == "table" then
			currentStatus = response.data
			feedbackText = ""
			renderCurrent()
		else
			showMessage((ok and response and response.error) or "Player status is temporarily unavailable.", true)
		end
	end)
end

local function updateDialogSize()
	local viewport = viewportSize()
	if viewport.X < Theme.Sizes.MobileBreakpoint or viewport.Y < 500 then
		if testViewportOverride then
			dialog.Size = UDim2.fromOffset(math.floor(viewport.X * 0.90), math.floor(viewport.Y * 0.86))
		else
			dialog.Size = UDim2.fromScale(0.90, 0.86)
		end
	else
		dialog.Size = UDim2.fromOffset(
			math.clamp(math.floor(viewport.X * 0.66), 720, 980),
			math.clamp(math.floor(viewport.Y * 0.72), 440, 620)
		)
	end
	if gui.Enabled and currentStatus then renderCurrent() end
end

local viewportConnection
local function bindCamera(camera)
	if viewportConnection then viewportConnection:Disconnect() end
	if camera then
		viewportConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateDialogSize)
	end
	updateDialogSize()
end
bindCamera(Workspace.CurrentCamera)
gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateDialogSize)
Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
	bindCamera(Workspace.CurrentCamera)
end)

local function close()
	requestSerial += 1
	gui.Enabled = false
	feedbackText = ""
	PanelCoordinator.release("Profile")
end
PanelCoordinator.register("Profile", { close = close })

local function open()
	if not PanelCoordinator.claim("Profile") then return end
	activeTab = "Overview"
	updateTabs()
	gui.Enabled = true
	fetchStatus()
end

profileButton.Activated:Connect(function()
	if gui.Enabled then close() else open() end
end)
closeButton.Activated:Connect(close)
scrim.Activated:Connect(close)
fullscreenBackdrop.Activated:Connect(close)

for _, remoteName in ipairs({ "BattleLoading", "BattleSeated", "UpdateBattleState" }) do
	remotes:WaitForChild(remoteName).OnClientEvent:Connect(close)
end

local refreshQueued = false
local function refreshIfOpen()
	if not gui.Enabled or refreshQueued then return end
	refreshQueued = true
	task.delay(0.15, function()
		refreshQueued = false
		if gui.Enabled then fetchStatus() end
	end)
end
remotes:WaitForChild("LevelUp").OnClientEvent:Connect(refreshIfOpen)
remotes:WaitForChild("QuestStateChanged").OnClientEvent:Connect(refreshIfOpen)

-- Studio-only hook keeps live UI verification deterministic when simulated mouse
-- clicks are unavailable through the Studio bridge. It is absent in published play.
if RunService:IsStudio() then
	local testHook = Instance.new("BindableFunction")
	testHook.Name = "PlayerStatusUITest"
	testHook.OnInvoke = function(action, value)
		if action == "open" then open()
		elseif action == "close" then close()
		elseif action == "overview" then activeTab = "Overview"; renderCurrent()
		elseif action == "titles" then activeTab = "Titles"; renderCurrent()
		elseif action == "refresh" then fetchStatus()
		elseif action == "viewport" then
			testViewportOverride = typeof(value) == "Vector2" and value or nil
			updateDialogSize()
		end
		return true
	end
	testHook.Parent = gui
end

task.spawn(function()
	local ok, image = pcall(function()
		return Players:GetUserThumbnailAsync(
			player.UserId,
			Enum.ThumbnailType.HeadShot,
			Enum.ThumbnailSize.Size420x420
		)
	end)
	if ok and type(image) == "string" then
		avatarImage = image
		headerIcon.Image = image
		if gui.Enabled and currentStatus then renderCurrent() end
	end
end)

gui.Enabled = false
updateTabs()
print("[PlayerStatusUIController] loaded")
