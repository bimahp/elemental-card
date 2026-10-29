-- VendingMachineController: leveled pack browser, live odds, purchase, and reveal lifecycle.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local OpenCardPack = remotes:WaitForChild("OpenCardPack")
local GetPackOdds = remotes:WaitForChild("GetPackOdds")
local GetQuestSnapshot = remotes:WaitForChild("GetQuestSnapshot")
local QuestStateChanged = remotes:WaitForChild("QuestStateChanged")

local Config = require(ReplicatedStorage.Modules.GachaConfig)
local AssetIds = require(ReplicatedStorage.Modules.AssetIds)
local CardData = require(ReplicatedStorage.Modules.CardData)
local CardTraits = require(ReplicatedStorage.Modules.CardTraits)
local ChargeConfig = require(ReplicatedStorage.Modules.ChargeConfig)
local PanelCoordinator = require(ReplicatedStorage.Modules.PanelCoordinator)
local battleModules = playerGui:WaitForChild("BattleUI"):WaitForChild("Modules")
local CardVisuals = require(battleModules:WaitForChild("CardVisuals"))
local CardPreviewController = require(battleModules:WaitForChild("CardPreviewController"))
local UXMode = require(battleModules:WaitForChild("UXMode"))
local PackRevealController = require(script.Parent:WaitForChild("PackRevealController"))
local UI = require(playerGui:WaitForChild("SharedUI"):WaitForChild("UIComponents"))
local Theme = UI.Theme

local gui = playerGui:WaitForChild("VendingMachineUI")
local packUI = playerGui:WaitForChild("PackOpenUI")
local revealController = PackRevealController.new(packUI)
local dialog = gui:WaitForChild("Dialog")
local scrim = gui:WaitForChild("Scrim")
local titleBar = dialog:WaitForChild("TitleBar")
local title = titleBar:WaitForChild("Title")
local closeButton = titleBar:WaitForChild("CloseButton")
local body = dialog:WaitForChild("Body")
local previewSize = CardVisuals.Sizes[UXMode.Current == "Mobile"]
local oddsPreview = CardPreviewController.new({
	host = gui,
	CardVisuals = CardVisuals,
	HW = previewSize.HW,
	HH = previewSize.HH,
	layerName = "VendingPreviewLayer",
	zIndex = 80,
})
UXMode.Changed:Connect(function(modeName)
	local sizes = CardVisuals.Sizes[modeName == "Mobile"]
	oddsPreview:setCardSize(sizes.HW, sizes.HH)
end)

local backButton = titleBar:FindFirstChild("BackButton") or Instance.new("TextButton")
backButton.Name = "BackButton"
backButton.AnchorPoint = Vector2.new(0, 0.5)
backButton.Position = UDim2.new(0, 0, 0.5, 0)
backButton.Size = UDim2.fromOffset(76, 30)
backButton.BackgroundColor3 = Color3.fromRGB(24, 30, 46)
backButton.TextColor3 = Color3.fromRGB(235, 240, 255)
backButton.Font = Enum.Font.GothamBold
backButton.TextSize = 14
backButton.Text = "< Back"
backButton.Visible = false
backButton.Parent = titleBar
if not backButton:FindFirstChildOfClass("UICorner") then
	Instance.new("UICorner", backButton).CornerRadius = UDim.new(0, 6)
end

local statusLabel = dialog:FindFirstChild("StatusLabel") or Instance.new("TextLabel")
statusLabel.Name = "StatusLabel"
statusLabel.AnchorPoint = Vector2.new(0.5, 1)
statusLabel.Position = UDim2.new(0.5, 0, 1, -8)
statusLabel.Size = UDim2.new(0.9, 0, 0, 24)
statusLabel.BackgroundTransparency = 1
statusLabel.Font = Enum.Font.GothamBold
statusLabel.TextSize = 13
statusLabel.TextColor3 = Color3.fromRGB(255, 180, 120)
statusLabel.Text = ""
statusLabel.ZIndex = 20
statusLabel.Parent = dialog
UI.styleScrim(scrim)
local fullscreenBackdrop = UI.bindFullscreenBackdrop(gui, scrim)
UI.applyModalShell(dialog, titleBar, title, closeButton, backButton, Theme.Accents.Vending)
local homeIcon = UI.createHeaderIcon(titleBar, AssetIds.VendingIcon)
body.Position = UDim2.new(0, 18, 0, 76)
body.Size = UDim2.new(1, -36, 1, -104)
body.BackgroundTransparency = 1

local machine = workspace:WaitForChild("Card Vending Machine")
local prompt = machine:WaitForChild("InteractionAnchor"):WaitForChild("ProximityPrompt")

local currentFragments = 0
local mode = "idle"
local pageStack = {}
local pages = {}
local pageToken = 0
local pageCleanup

local function clearBody()
	pageToken += 1
	if pageCleanup then pageCleanup(); pageCleanup = nil end
	oddsPreview:hide()
	for _, child in ipairs(body:GetChildren()) do child:Destroy() end
	statusLabel.Text = ""
end

local function updateVisibleBalance()
	local balance = body:FindFirstChild("Balance", true)
	if balance and balance:IsA("TextLabel") then
		balance.Text = string.format("Balance: %d Card Fragments", currentFragments)
	end
end

local function applyBalance(data)
	if type(data) ~= "table" then return end
	if type(data.cardFragments) == "number" then currentFragments = data.cardFragments end
	updateVisibleBalance()
end

local function setMode(nextMode)
	mode = nextMode
	if nextMode ~= "vending" then oddsPreview:hide() end
	gui.Enabled = nextMode == "vending" or nextMode == "purchasing"
	prompt.Enabled = nextMode == "idle"
	if nextMode == "idle" then PanelCoordinator.release("VendingMachine") end
	closeButton.Active = nextMode == "vending"
	closeButton.AutoButtonColor = nextMode == "vending"
	backButton.Active = nextMode == "vending"
	backButton.AutoButtonColor = nextMode == "vending"
end

local function setTitle(value)
	title.Text = value
	backButton.Visible = #pageStack > 1
	homeIcon.Visible = not backButton.Visible
end

local function button(parent, text, size, opts)
	opts = opts or {}
	opts.size = size or opts.size or UDim2.fromOffset(220, 48)
	return UI.createPrimaryButton(parent, text, opts.icon, opts)
end

local RARITY_COLORS = {
	common = Theme.Colors.NEUTRAL,
	rare = Theme.Colors.Shard,
	epic = Theme.Colors.Dust,
}

local function cardPreviewOpts(cardId)
	local card = CardData.Cards[cardId]
	if not card then return nil end
	local abilityName, abilityText = CardData.getAbilityDisplay(cardId)
	return {
		cardId = cardId,
		name = card.name,
		cardType = card.cardType,
		battleType = card.battleType,
		race = card.race,
		cost = card.cost,
		chargeCost = card.chargeCost,
		corrupted = CardTraits.has(card, "corrupted"),
		atk = card.cardType == "creature" and card.atk or nil,
		hp = card.cardType == "creature" and card.hp or nil,
		abilityName = abilityName,
		abilityText = abilityText,
	}
end

local function formatPercent(value)
	local formatted = string.format("%.4f", tonumber(value) or 0)
	formatted = formatted:gsub("0+$", ""):gsub("%.$", "")
	return formatted .. "%"
end

local function show(page, arg, push)
	if push ~= false then pageStack[#pageStack + 1] = { page = page, arg = arg } end
	clearBody()
	pages[page](arg)
end

local function close()
	if mode ~= "vending" then return end
	pageStack = {}
	clearBody()
	setMode("idle")
end

local function goBack()
	if mode ~= "vending" then return end
	if #pageStack <= 1 then close(); return end
	table.remove(pageStack)
	local previous = pageStack[#pageStack]
	show(previous.page, previous.arg, false)
end

local function refreshBalance()
	local ok, snapshot = pcall(function() return GetQuestSnapshot:InvokeServer() end)
	if ok and type(snapshot) == "table" then
		applyBalance(snapshot)
		return true
	end
	return false
end

local function purchase(openButton)
	if mode ~= "vending" or not openButton.Active then return end
	statusLabel.Text = ""
	setMode("purchasing")
	openButton.Text = "Opening..."
	openButton.Active = false
	openButton.AutoButtonColor = false

	local invoked, result = pcall(function() return OpenCardPack:InvokeServer() end)
	if not invoked or type(result) ~= "table" then
		statusLabel.Text = "Pack service temporarily unavailable"
		setMode("vending")
		openButton.Text = "Open (" .. Config.COST_CARD_FRAGMENTS .. " Fragments)"
		openButton.Active = true
		openButton.AutoButtonColor = true
		return
	end
	applyBalance(result)
	if not result.ok then
		statusLabel.Text = result.error or "Purchase failed"
		setMode("vending")
		openButton.Text = "Open (" .. Config.COST_CARD_FRAGMENTS .. " Fragments)"
		openButton.Active = true
		openButton.AutoButtonColor = true
		return
	end

	setMode("reveal")
	local opened, revealError = revealController:Open(result, function()
		pageStack = {}
		clearBody()
		setMode("idle")
	end)
	if not opened then
		statusLabel.Text = revealError or "The pack could not be displayed"
		setMode("vending")
		show("PackDetail", "standard", false)
	end
end

function pages.PackSelect()
	setTitle("Card Packs")
	local isMobile = UXMode.Current == "Mobile"
	local tileSize = isMobile and Vector2.new(160, 190) or Vector2.new(220, 270)
	local artSize = isMobile and Vector2.new(104, 140) or Vector2.new(148, 200)

	local scroll = Instance.new("ScrollingFrame", body)
	scroll.Name = "PackBrowser"
	scroll.Size = UDim2.fromScale(1, 1)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = isMobile and 6 or 8
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.new()
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.ClipsDescendants = true

	local padding = Instance.new("UIPadding", scroll)
	padding.PaddingTop = UDim.new(0, 8)
	padding.PaddingBottom = UDim.new(0, 12)
	padding.PaddingLeft = UDim.new(0, 8)
	padding.PaddingRight = UDim.new(0, 8)
	local sectionsLayout = Instance.new("UIListLayout", scroll)
	sectionsLayout.Padding = UDim.new(0, isMobile and 10 or 16)
	sectionsLayout.SortOrder = Enum.SortOrder.LayoutOrder

	local function addSection(sectionName, packs, order)
		local section = Instance.new("Frame", scroll)
		section.Name = sectionName:gsub("%s+", "") .. "Section"
		section.LayoutOrder = order
		section.Size = UDim2.new(1, -4, 0, 0)
		section.AutomaticSize = Enum.AutomaticSize.Y
		section.BackgroundTransparency = 1

		local sectionLayout = Instance.new("UIListLayout", section)
		sectionLayout.Padding = UDim.new(0, 8)
		sectionLayout.SortOrder = Enum.SortOrder.LayoutOrder

		local heading = Instance.new("TextLabel", section)
		heading.LayoutOrder = 1
		heading.Size = UDim2.new(1, 0, 0, isMobile and 28 or 36)
		heading.BackgroundTransparency = 1
		heading.Text = sectionName
		heading.TextXAlignment = Enum.TextXAlignment.Left
		heading.TextColor3 = Theme.Colors.Text
		heading.Font = Theme.Fonts.Title
		heading.TextSize = isMobile and 20 or 24
		heading.TextStrokeTransparency = 0.45
		heading.TextStrokeColor3 = Theme.Colors.Outline

		local grid = Instance.new("Frame", section)
		grid.Name = "PackGrid"
		grid.LayoutOrder = 2
		grid.Size = UDim2.new(1, 0, 0, 0)
		grid.AutomaticSize = Enum.AutomaticSize.Y
		grid.BackgroundTransparency = 1

		local gridLayout = Instance.new("UIGridLayout", grid)
		gridLayout.CellSize = UDim2.fromOffset(tileSize.X, tileSize.Y)
		gridLayout.CellPadding = UDim2.fromOffset(isMobile and 10 or 14, isMobile and 10 or 14)
		gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
		gridLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left

		for index, pack in ipairs(packs) do
			local tile = button(grid, "", UDim2.fromOffset(tileSize.X, tileSize.Y), {
				color = Theme.Colors.PanelSurface2,
				name = pack.id .. "Pack",
			})
			tile.LayoutOrder = index

			local art = Instance.new("ImageLabel", tile)
			art.Name = "PackArt"
			art.AnchorPoint = Vector2.new(0.5, 0)
			art.Position = UDim2.new(0.5, 0, 0, isMobile and 6 or 10)
			art.Size = UDim2.fromOffset(artSize.X, artSize.Y)
			art.BackgroundTransparency = 1
			art.Image = pack.image
			art.ScaleType = Enum.ScaleType.Fit

			local name = Instance.new("TextLabel", tile)
			name.Name = "PackName"
			name.AnchorPoint = Vector2.new(0.5, 1)
			name.Position = UDim2.new(0.5, 0, 1, -8)
			name.Size = UDim2.new(1, -14, 0, isMobile and 30 or 42)
			name.BackgroundTransparency = 1
			name.Text = pack.name
			name.TextColor3 = Theme.Colors.Text
			name.Font = Theme.Fonts.Title
			name.TextSize = isMobile and 17 or 21
			name.TextWrapped = true
			name.TextStrokeTransparency = 0.45
			name.TextStrokeColor3 = Theme.Colors.Outline
			tile.Activated:Connect(function() show("PackDetail", pack.id) end)
		end
	end

	addSection("Standard", {
		{ id = "standard", name = "Standard Pack", image = AssetIds.PackArt.standard },
	}, 1)
end

function pages.PackDetail(packId)
	setTitle("Standard Pack")
	local root = Instance.new("Frame", body)
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundTransparency = 1
	local art = Instance.new("ImageLabel", root)
	art.BackgroundTransparency = 1
	art.Position = UDim2.new(0.06, 0, 0.08, 0)
	art.Size = UDim2.new(0.4, 0, 0.68, 0)
	art.Image = AssetIds.PackArt[packId] or AssetIds.PackArt.standard
	art.ScaleType = Enum.ScaleType.Fit
	local info = UI.createSectionSurface(root, "PackInfo", { padding = 18, color = Theme.Colors.PanelSurface })
	info.Position = UDim2.new(0.52, 0, 0.09, 0)
	info.Size = UDim2.new(0.42, 0, 0.78, 0)
	local layout = Instance.new("UIListLayout", info)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, 14)
	local description = Instance.new("TextLabel", info)
	description.Size = UDim2.new(1, 0, 0, 70)
	description.BackgroundTransparency = 1
	description.Text = "5 cards from the complete Standard collection\n70% Common  |  25% Rare  |  5% Epic"
	description.TextWrapped = true
	description.TextColor3 = Theme.Colors.TextSoft
	description.Font = Theme.Fonts.Body
	description.TextSize = 16
	local balance = Instance.new("TextLabel", info)
	balance.Name = "Balance"
	balance.Size = UDim2.new(1, 0, 0, 30)
	balance.BackgroundTransparency = 1
	balance.TextColor3 = Theme.Colors.Text
	balance.Font = Theme.Fonts.BodyBold
	balance.TextSize = 15
	updateVisibleBalance()
	local details = button(info, "Pack Content Details", UDim2.new(1, 0, 0, 50), { color = Theme.Accents.Inventory })
	details.Activated:Connect(function() show("PackContents", packId) end)
	local open = button(info, "Open (" .. Config.COST_CARD_FRAGMENTS .. " Fragments)", UDim2.new(1, 0, 0, 56), { color = Theme.Colors.Success, icon = AssetIds.Icons.CARD_FRAGMENT })
	open.Activated:Connect(function() purchase(open) end)
	updateVisibleBalance()
end

function pages.PackContents(packId)
	setTitle("Standard Pack Contents")
	local token = pageToken
	local isMobile = UXMode.Current == "Mobile"
	local loading = Instance.new("TextLabel", body)
	loading.Size = UDim2.fromScale(1, 1)
	loading.BackgroundTransparency = 1
	loading.Text = "Loading your live odds..."
	loading.TextColor3 = Theme.Colors.TextSoft
	loading.Font = Theme.Fonts.BodyBold
	loading.TextSize = isMobile and 15 or 18

	task.spawn(function()
		local ok, result = pcall(function() return GetPackOdds:InvokeServer() end)
		if token ~= pageToken then return end
		if not ok or type(result) ~= "table" or not result.ok then
			loading.Text = type(result) == "table" and (result.error or "Odds unavailable") or "Odds unavailable"
			return
		end
		loading:Destroy()

		local split = Instance.new("Frame", body)
		split.Name = "OddsLayout"
		split.Size = UDim2.fromScale(1, 1)
		split.BackgroundTransparency = 1

		local list = Instance.new("ScrollingFrame", split)
		list.Name = "OddsList"
		list.Size = UDim2.new(0.68, -6, 1, 0)
		list.BackgroundColor3 = Theme.Colors.PanelSurface
		list.BorderSizePixel = 0
		list.ScrollBarThickness = isMobile and 6 or 8
		list.AutomaticCanvasSize = Enum.AutomaticSize.Y
		list.CanvasSize = UDim2.new()
		list.ScrollingDirection = Enum.ScrollingDirection.Y
		list.ClipsDescendants = true
		Instance.new("UICorner", list).CornerRadius = UDim.new(0, Theme.Sizes.SurfaceRadius)
		local listStroke = Instance.new("UIStroke", list)
		listStroke.Color = Theme.Colors.Stroke
		listStroke.Thickness = Theme.Sizes.StrokeThin
		local listPadding = Instance.new("UIPadding", list)
		listPadding.PaddingTop = UDim.new(0, 8)
		listPadding.PaddingBottom = UDim.new(0, 8)
		listPadding.PaddingLeft = UDim.new(0, 8)
		listPadding.PaddingRight = UDim.new(0, 8)
		local listLayout = Instance.new("UIListLayout", list)
		listLayout.Padding = UDim.new(0, isMobile and 6 or 8)
		listLayout.SortOrder = Enum.SortOrder.LayoutOrder

		local info = UI.createSectionSurface(split, "OddsInfo", {
			padding = false,
			color = Theme.Colors.PanelSurface,
		})
		info.Position = UDim2.new(0.68, 6, 0, 0)
		info.Size = UDim2.new(0.32, -6, 1, 0)
		info.ClipsDescendants = true

		local infoScroll = Instance.new("ScrollingFrame", info)
		infoScroll.Name = "InfoScroll"
		infoScroll.Size = UDim2.fromScale(1, 1)
		infoScroll.BackgroundTransparency = 1
		infoScroll.BorderSizePixel = 0
		infoScroll.CanvasSize = UDim2.new()
		infoScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
		infoScroll.ScrollingDirection = Enum.ScrollingDirection.Y
		infoScroll.ScrollBarThickness = isMobile and 5 or 6
		infoScroll.ScrollBarImageColor3 = Theme.Colors.TextMuted
		infoScroll.ScrollBarImageTransparency = 0.2
		infoScroll.VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar
		infoScroll.ElasticBehavior = Enum.ElasticBehavior.WhenScrollable
		infoScroll.ClipsDescendants = true

		local infoPadding = Instance.new("UIPadding", infoScroll)
		local infoPaddingSize = isMobile and 10 or 16
		infoPadding.PaddingTop = UDim.new(0, infoPaddingSize)
		infoPadding.PaddingBottom = UDim.new(0, infoPaddingSize)
		infoPadding.PaddingLeft = UDim.new(0, infoPaddingSize)
		infoPadding.PaddingRight = UDim.new(0, infoPaddingSize)

		local infoLayout = Instance.new("UIListLayout", infoScroll)
		infoLayout.Padding = UDim.new(0, isMobile and 5 or 10)
		infoLayout.SortOrder = Enum.SortOrder.LayoutOrder

		local function infoHeading(text, order)
			local label = Instance.new("TextLabel", infoScroll)
			label.LayoutOrder = order
			label.Size = UDim2.new(1, 0, 0, isMobile and 22 or 30)
			label.BackgroundTransparency = 1
			label.Text = text
			label.TextXAlignment = Enum.TextXAlignment.Left
			label.TextColor3 = Theme.Colors.Text
			label.Font = Theme.Fonts.Title
			label.TextSize = isMobile and 15 or 19
			label.TextStrokeTransparency = 0.55
			label.TextStrokeColor3 = Theme.Colors.Outline
			return label
		end
		local function infoBody(text, order)
			local label = Instance.new("TextLabel", infoScroll)
			label.LayoutOrder = order
			label.Size = UDim2.new(1, 0, 0, 0)
			label.AutomaticSize = Enum.AutomaticSize.Y
			label.BackgroundTransparency = 1
			label.Text = text
			label.TextWrapped = true
			label.TextXAlignment = Enum.TextXAlignment.Left
			label.TextYAlignment = Enum.TextYAlignment.Top
			label.TextColor3 = Theme.Colors.TextSoft
			label.Font = Theme.Fonts.Body
			label.TextSize = isMobile and 11 or 13
			return label
		end
		infoHeading("Duplicate Protection", 1)
		infoBody("Cards already owned twice are excluded while same-rarity alternatives remain. If every card in that rarity is capped, the full tier becomes available again and extra copies are added to your collection as duplicates.", 2)
		infoHeading("Displayed Odds", 3)
		infoBody("Odds are based on your current collection and apply to each card draw. Percentages are rounded, so displayed values may not total exactly 100%.", 4)

		local hoverTimers = {}
		local inputConnections = {}
		local activeHold

		local function cancelHoverTimers()
			for row, timer in pairs(hoverTimers) do
				task.cancel(timer)
				hoverTimers[row] = nil
			end
		end
		local function cancelHold()
			local hold = activeHold
			if hold and hold.timer then task.cancel(hold.timer) end
			if hold and hold.setHighlighted then hold.setHighlighted(false) end
			activeHold = nil
			oddsPreview:hide()
		end
		pageCleanup = function()
			cancelHoverTimers()
			cancelHold()
			for _, connection in ipairs(inputConnections) do connection:Disconnect() end
			inputConnections = {}
		end

		inputConnections[#inputConnections + 1] = UserInputService.InputChanged:Connect(function(input)
			if not activeHold then return end
			local relevant = input == activeHold.input
				or (activeHold.input.UserInputType == Enum.UserInputType.MouseButton1 and input.UserInputType == Enum.UserInputType.MouseMovement)
			if not relevant then return end
			local position = Vector2.new(input.Position.X, input.Position.Y)
			if (position - activeHold.startPosition).Magnitude > 12 then cancelHold() end
		end)
		inputConnections[#inputConnections + 1] = UserInputService.InputEnded:Connect(function(input)
			if not activeHold then return end
			if input == activeHold.input
				or (activeHold.input.UserInputType == Enum.UserInputType.MouseButton1 and input.UserInputType == Enum.UserInputType.MouseButton1) then
				cancelHold()
			end
		end)
		inputConnections[#inputConnections + 1] = list:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
			cancelHoverTimers()
			cancelHold()
		end)

		local rowHeight = isMobile and 58 or 66
		local iconSize = isMobile and 42 or 48
		local percentWidth = isMobile and 76 or 92
		local rarityOrder = { common = 1, rare = 2, epic = 3 }
		local sortedCards = table.clone(result.cards or {})
		table.sort(sortedCards, function(a, b)
			local aCard = CardData.Cards[a.cardId] or {}
			local bCard = CardData.Cards[b.cardId] or {}
			local aRarity = rarityOrder[a.rarity or aCard.rarity] or math.huge
			local bRarity = rarityOrder[b.rarity or bCard.rarity] or math.huge
			if aRarity ~= bRarity then return aRarity < bRarity end
			local aBattle = aCard.battleType or "NEUTRAL"
			local bBattle = bCard.battleType or "NEUTRAL"
			if aBattle ~= bBattle then return aBattle < bBattle end
			local aName = aCard.name or a.cardId or ""
			local bName = bCard.name or b.cardId or ""
			if aName ~= bName then return aName < bName end
			return (a.cardId or "") < (b.cardId or "")
		end)
		for index, entry in ipairs(sortedCards) do
			local card = CardData.Cards[entry.cardId]
			local opts = cardPreviewOpts(entry.cardId)
			if card and opts then
				local battleColor = ChargeConfig.color(card.battleType)
				local rarityColor = RARITY_COLORS[entry.rarity or card.rarity] or Theme.Colors.NEUTRAL
				local row = Instance.new("TextButton", list)
				row.Name = entry.cardId
				row.LayoutOrder = index
				row.Size = UDim2.new(1, -4, 0, rowHeight)
				row.BackgroundColor3 = Theme.Colors.PanelSurface2
				row.BorderSizePixel = 0
				row.Text = ""
				row.AutoButtonColor = false
				Instance.new("UICorner", row).CornerRadius = UDim.new(0, 9)
				local rowStroke = Instance.new("UIStroke", row)
				rowStroke.Color = battleColor
				rowStroke.Thickness = 3
				local restingColor = Theme.Colors.PanelSurface2
				local highlightedColor = restingColor:Lerp(battleColor, 0.22)
				local function setHighlighted(isHighlighted)
					row.BackgroundColor3 = isHighlighted and highlightedColor or restingColor
					rowStroke.Thickness = isHighlighted and 4 or 3
				end

				local emblem = Instance.new("ImageLabel", row)
				emblem.Name = "BattleTypeIcon"
				emblem.AnchorPoint = Vector2.new(0, 0.5)
				emblem.Position = UDim2.new(0, 7, 0.5, 0)
				emblem.Size = UDim2.fromOffset(iconSize, iconSize)
				emblem.BackgroundTransparency = 1
				emblem.Image = AssetIds.ChargeEmblems[card.battleType] or AssetIds.Icons.ENERGY
				emblem.ScaleType = Enum.ScaleType.Fit
				emblem.ZIndex = row.ZIndex + 1

				local race = Instance.new("TextLabel", row)
				race.AnchorPoint = Vector2.new(0.5, 0.5)
				race.Position = UDim2.new(0, 7 + iconSize / 2, 0.5, 0)
				race.Size = UDim2.fromOffset(iconSize + 12, iconSize)
				race.BackgroundTransparency = 1
				race.Text = string.upper(card.race or "SPELL")
				race.TextColor3 = Theme.Colors.Text
				race.Font = Theme.Fonts.Title
				race.TextSize = isMobile and 10 or 11
				race.TextYAlignment = Enum.TextYAlignment.Center
				race.TextStrokeColor3 = Theme.Colors.Outline
				race.TextStrokeTransparency = 0.15
				race.ZIndex = emblem.ZIndex + 1

				local percent = Instance.new("TextLabel", row)
				percent.Name = "Percent"
				percent.AnchorPoint = Vector2.new(1, 0.5)
				percent.Position = UDim2.new(1, -7, 0.5, 0)
				percent.Size = UDim2.fromOffset(percentWidth, isMobile and 36 or 40)
				percent.BackgroundColor3 = Theme.Colors.PanelDeep
				percent.BackgroundTransparency = 0.04
				percent.BorderSizePixel = 0
				percent.Text = formatPercent(entry.percent)
				percent.TextColor3 = Theme.Colors.Text
				percent.Font = Theme.Fonts.Title
				percent.TextSize = isMobile and 14 or 16
				Instance.new("UICorner", percent).CornerRadius = UDim.new(0, 8)

				local cardName = Instance.new("TextLabel", row)
				cardName.Name = "CardName"
				cardName.Position = UDim2.new(0, iconSize + 26, 0, 0)
				cardName.Size = UDim2.new(1, -(iconSize + percentWidth + 42), 1, 0)
				cardName.BackgroundTransparency = 1
				cardName.Text = card.name
				cardName.TextXAlignment = Enum.TextXAlignment.Left
				cardName.TextColor3 = Theme.Colors.Text
				cardName.Font = Theme.Fonts.Title
				cardName.TextSize = isMobile and 15 or 18
				cardName.TextTruncate = Enum.TextTruncate.AtEnd
				local nameStroke = Instance.new("UIStroke", cardName)
				nameStroke.Color = rarityColor
				nameStroke.Thickness = 3
				nameStroke.Transparency = 0
				nameStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
				nameStroke.LineJoinMode = Enum.LineJoinMode.Round

				row.MouseEnter:Connect(function()
					if UXMode.Current ~= "Desktop" then return end
					setHighlighted(true)
					if hoverTimers[row] then task.cancel(hoverTimers[row]) end
					hoverTimers[row] = task.delay(0.5, function()
						hoverTimers[row] = nil
						if token == pageToken and row.Parent then oddsPreview:show(row, opts, "right") end
					end)
				end)
				row.MouseLeave:Connect(function()
					if hoverTimers[row] then task.cancel(hoverTimers[row]); hoverTimers[row] = nil end
					setHighlighted(false)
					oddsPreview:hide()
				end)
				row.InputBegan:Connect(function(input)
					if UXMode.Current ~= "Mobile" then return end
					if input.UserInputType ~= Enum.UserInputType.Touch and input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
					cancelHold()
					setHighlighted(true)
					activeHold = {
						input = input,
						startPosition = Vector2.new(input.Position.X, input.Position.Y),
						setHighlighted = setHighlighted,
					}
					local hold = activeHold
					hold.timer = task.delay(0.5, function()
						hold.timer = nil
						if activeHold == hold and token == pageToken and row.Parent then oddsPreview:show(row, opts, "right") end
					end)
				end)
			end
		end
	end)
end

QuestStateChanged.OnClientEvent:Connect(applyBalance)
-- A purchase or reveal in progress refuses to close, so no other panel opens over it.
PanelCoordinator.register("VendingMachine", {
	close = function()
		if mode == "purchasing" or mode == "reveal" then return false end
		close()
	end,
	back = goBack,
})

prompt.Triggered:Connect(function()
	if mode ~= "idle" or not PanelCoordinator.claim("VendingMachine") then return end
	setMode("vending")
	pageStack = {}
	show("PackSelect")
	task.spawn(function()
		if not refreshBalance() and mode == "vending" then
			statusLabel.Text = "Your profile is still loading. Please try again."
		end
	end)
end)
backButton.Activated:Connect(goBack)
closeButton.Activated:Connect(close)
scrim.Activated:Connect(close)
fullscreenBackdrop.Activated:Connect(close)

for _, remoteName in ipairs({"BattleLoading", "BattleSeated", "UpdateBattleState"}) do
	remotes:WaitForChild(remoteName).OnClientEvent:Connect(function()
		if mode == "vending" then close() end
	end)
end

setMode("idle")
print("[VendingMachineController] leveled Standard Pack browser and live odds loaded")
