-- Card Library Controller: My Cards + deck builder (Core-free, Charge-aware).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local gui = script.Parent
local pg = gui.Parent
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local modules = pg:WaitForChild("BattleUI"):WaitForChild("Modules")
local CardVisuals = require(modules:WaitForChild("CardVisuals"))
local CardData = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("CardData"))
local ChargeConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("ChargeConfig"))
local CardTraits  = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("CardTraits"))
local AssetIds = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("AssetIds"))
local UI = require(pg:WaitForChild("SharedUI"):WaitForChild("UIComponents"))
local PanelCoordinator = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("PanelCoordinator"))
local Theme = UI.Theme
local VendorConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("VendorConfig"))

local getInv = remotes:WaitForChild("GetInventory")
local rf = {
	GetDecks = remotes:WaitForChild("GetDecks"),
	CreateDeck = remotes:WaitForChild("CreateDeck"),
	SaveDeckCards = remotes:WaitForChild("SaveDeckCards"),
	RenameDeck = remotes:WaitForChild("RenameDeck"),
	DeleteDeck = remotes:WaitForChild("DeleteDeck"),
	SetActiveDeck = remotes:WaitForChild("SetActiveDeck"),
	DestroyCards = remotes:WaitForChild("DestroyCards"),
}

local dialog = gui:WaitForChild("Dialog")
local scrim = gui:WaitForChild("Scrim")
local titleBar = dialog:WaitForChild("TitleBar")
local title = titleBar:WaitForChild("Title")
local closeBtn = titleBar:WaitForChild("CloseButton")
local body = dialog:WaitForChild("Body")

local backBtn = titleBar:FindFirstChild("BackButton") or Instance.new("TextButton")
backBtn.Name = "BackButton"
backBtn.AnchorPoint = Vector2.new(0, 0.5)
backBtn.Position = UDim2.new(0, 0, 0.5, 0)
backBtn.Size = UDim2.fromOffset(76, 30)
backBtn.BackgroundColor3 = Color3.fromRGB(24, 30, 46)
backBtn.TextColor3 = Color3.fromRGB(235, 240, 255)
backBtn.Font = Enum.Font.GothamBold
backBtn.TextSize = 14
backBtn.Text = "< Back"
backBtn.Visible = false
backBtn.Parent = titleBar
if not backBtn:FindFirstChildOfClass("UICorner") then Instance.new("UICorner", backBtn).CornerRadius = UDim.new(0, 6) end

local errorLabel = dialog:FindFirstChild("StatusLabel") or Instance.new("TextLabel")
errorLabel.Name = "StatusLabel"
errorLabel.AnchorPoint = Vector2.new(0.5, 1)
errorLabel.Position = UDim2.new(0.5, 0, 1, -8)
errorLabel.Size = UDim2.new(0.9, 0, 0, 24)
errorLabel.BackgroundTransparency = 1
errorLabel.Font = Enum.Font.GothamBold
errorLabel.TextSize = 13
errorLabel.TextColor3 = Color3.fromRGB(255, 180, 120)
errorLabel.Text = ""
errorLabel.ZIndex = 20
errorLabel.Parent = dialog
UI.styleScrim(scrim)
local fullscreenBackdrop = UI.bindFullscreenBackdrop(gui, scrim)
UI.applyModalShell(dialog, titleBar, title, closeBtn, backBtn, Theme.Accents.Inventory)
local homeIcon = UI.createHeaderIcon(titleBar, AssetIds.InventoryIcon)
body.Position = UDim2.new(0, 18, 0, 76)
body.Size = UDim2.new(1, -36, 1, -112)
body.BackgroundTransparency = 1

local pageStack = {}
local rawCollection = {}
local deckPayload = { decks = {}, activeDeckId = nil, maxDecks = 12 }
local currentDeck
local previewCard
local recycleQueue = {}

local CELL_W, CELL_H = 112, 152
local function clearBody()
	for _, child in ipairs(body:GetChildren()) do child:Destroy() end
	if previewCard then previewCard:Destroy(); previewCard = nil end
	errorLabel.Text = ""
end
local function setTitle(text)
	title.Text = text
	backBtn.Visible = #pageStack > 1
	homeIcon.Visible = not backBtn.Visible
end
local function call(remote, ...)
	local ok, result = pcall(function(...) return remote:InvokeServer(...) end, ...)
	if not ok then return false, tostring(result) end
	if type(result) == "table" and result.ok ~= nil then
		return result.ok, result.ok and result.data or result.error
	end
	return true, result
end
local function counts(list)
	local c = {}
	for _, id in ipairs(list or {}) do c[id] = (c[id] or 0) + 1 end
	return c
end
local function maxDeckCopiesForCard(card)
	if card and card.rarity == "legendary" then return 1 end
	return 2
end
local function recycleThreshold(card)
	return (card and VendorConfig.RECYCLE_DECK_CHECK_THRESHOLD_BY_RARITY[card.rarity]) or maxDeckCopiesForCard(card)
end
local function maxDeckUse(cardId)
	local maxUsed = 0
	for _, deck in ipairs(deckPayload.decks or {}) do
		local used = 0
		for _, id in ipairs(deck.cards or {}) do if id == cardId then used += 1 end end
		if used > maxUsed then maxUsed = used end
	end
	return maxUsed
end
local function cloneList(list)
	local out = {}
	for _, v in ipairs(list or {}) do out[#out+1] = v end
	return out
end
local function refreshData()
	rawCollection = getInv:InvokeServer() or {}
	local ok, data = call(rf.GetDecks)
	if ok and type(data) == "table" then deckPayload = data end
end
-- Distinct Charge-producing Battle Types in a card list (NEUTRAL never counts).
-- A hero holds at most 2 Charge Types, so >2 is a soft builder warning.
local function distinctChargeTypes(cards)
	local seen, n = {}, 0
	for _, id in ipairs(cards or {}) do
		local card = CardData.Cards[id]
		if card and ChargeConfig.isProducing(card.battleType) and not seen[card.battleType] then
			seen[card.battleType] = true; n += 1
		end
	end
	return n
end
-- Fires the ">2 Charge Types" toast once per crossing (not repeatedly while above 2).
local chargeWarnState = {}
-- Any owned, known card is legal in any deck now (no Core type restriction).
local function ownsAllowed(_, cardId)
	return CardData.Cards[cardId] ~= nil
end
local function cardOpts(cardId)
	local card = CardData.Cards[cardId]
	if not card then return nil end
	local abilName, abilText = CardData.getAbilityDisplay(cardId)
	return {
		cardId = cardId, battleType = card.battleType, cardType = card.cardType, race = card.race,
		cost = card.cost, name = card.name,
		chargeCost = card.chargeCost,
		corrupted = CardTraits.has(card, "corrupted"),
		atk = card.cardType == "creature" and card.atk or nil,
		hp = card.cardType == "creature" and card.hp or nil,
		abilityName = abilName, abilityText = abilText,
	}, card
end
local function makeCard(parent, cardId, w, h)
	local opts, card = cardOpts(cardId)
	if not opts then return nil end
	local f = CardVisuals.buildCardFrame(w or CELL_W, h or CELL_H, "full")
	CardVisuals.updateCardFrame(f, opts)
	if f:FindFirstChild("AttackEmblem") then f.AttackEmblem.Visible = card.cardType == "creature" end
	if f:FindFirstChild("HealthEmblem") then f.HealthEmblem.Visible = card.cardType == "creature" end
	local stk = f:FindFirstChildOfClass("UIStroke")
	if stk then stk.Color = CardVisuals.TC_type[card.battleType] or CardVisuals.TC_type.NEUTRAL end
	f.Parent = parent
	return f
end
local function button(parent, text, size, opts)
	opts = opts or {}
	opts.size = size or opts.size or UDim2.fromOffset(180, 44)
	return UI.createPrimaryButton(parent, text, opts.icon, opts)
end
local function showUsedOnDeckPopup()
	local existing = gui:FindFirstChild("UsedOnDeckPopup")
	if existing then existing:Destroy() end

	local overlay = Instance.new("Frame")
	overlay.Name = "UsedOnDeckPopup"
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	overlay.BackgroundTransparency = 0.35
	overlay.ZIndex = 100
	overlay.Active = true
	overlay.Parent = gui

	local panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(360, 180)
	panel.BackgroundColor3 = Theme.Colors.Panel
	panel.BorderSizePixel = 0
	panel.ZIndex = 101
	panel.Parent = overlay
	Instance.new("UICorner", panel).CornerRadius = UDim.new(0, Theme.Sizes.SurfaceRadius)
	local panelStroke = Instance.new("UIStroke", panel); panelStroke.Color = Theme.Colors.Outline; panelStroke.Thickness = 2

	local message = Instance.new("TextLabel")
	message.BackgroundTransparency = 1
	message.Position = UDim2.fromOffset(24, 24)
	message.Size = UDim2.new(1, -48, 0, 78)
	message.Font = Theme.Fonts.BodyBold
	message.TextSize = 18
	message.TextColor3 = Theme.Colors.Text
	message.TextWrapped = true
	message.Text = "Cant add card, used on deck"
	message.ZIndex = 102
	message.Parent = panel

	local confirm = button(panel, "Confirm", UDim2.new(1, -48, 0, 42), { color = Theme.Colors.Shard })
	confirm.Position = UDim2.new(0, 24, 1, -62)
	confirm.ZIndex = 102
	confirm.Activated:Connect(function()
		overlay:Destroy()
	end)
end

local function makeScroll(parent, name)
	local s = Instance.new("ScrollingFrame")
	s.Name = name
	s.Size = UDim2.fromScale(1, 1)
	s.BackgroundColor3 = Theme.Colors.PanelSurface
	s.BackgroundTransparency = 0
	s.BorderSizePixel = 0
	s.ScrollBarThickness = 8
	s.AutomaticCanvasSize = Enum.AutomaticSize.Y
	s.CanvasSize = UDim2.new()
	s.Parent = parent
	Instance.new("UICorner", s).CornerRadius = UDim.new(0, Theme.Sizes.SurfaceRadius)
	local stroke = Instance.new("UIStroke", s); stroke.Color = Theme.Colors.Stroke; stroke.Thickness = Theme.Sizes.StrokeThin
	local pad = Instance.new("UIPadding", s); pad.PaddingTop = UDim.new(0, 8); pad.PaddingBottom = UDim.new(0, 8); pad.PaddingLeft = UDim.new(0, 8); pad.PaddingRight = UDim.new(0, 8)
	local list = Instance.new("UIListLayout", s); list.Padding = UDim.new(0, 8); list.SortOrder = Enum.SortOrder.LayoutOrder
	return s
end

local pages = {}
local function show(page, arg, push)
	if push ~= false then table.insert(pageStack, { page = page, arg = arg }) end
	clearBody()
	pages[page](arg)
end
local close -- assigned below; Back from the root page closes the panel
local function goBack()
	if #pageStack <= 1 then close(); return end
	table.remove(pageStack)
	local top = pageStack[#pageStack]
	show(top.page, top.arg, false)
end

function pages.Home()
	setTitle("Card Library")
	local root = Instance.new("Frame", body)
	root.Size = UDim2.fromScale(1,1)
	root.BackgroundTransparency = 1
	local list = Instance.new("UIListLayout", root); list.HorizontalAlignment = Enum.HorizontalAlignment.Center; list.VerticalAlignment = Enum.VerticalAlignment.Center; list.Padding = UDim.new(0, 14)
	button(root, "My Cards", UDim2.fromOffset(300, 58), { color = Theme.Accents.Inventory, font = Theme.Fonts.Title, textSize = 21 }).Activated:Connect(function() show("MyCards") end)
	button(root, "Recycle", UDim2.fromOffset(300, 58), { color = Theme.Colors.Shard, font = Theme.Fonts.Title, textSize = 21, icon = AssetIds.Icons.CRYSTAL_SHARD }).Activated:Connect(function() recycleQueue = {}; refreshData(); show("Recycle") end)
	button(root, "Deck Builder", UDim2.fromOffset(300, 58), { color = Theme.Accents.Deck, font = Theme.Fonts.Title, textSize = 21 }).Activated:Connect(function() refreshData(); show("DeckList") end)
end
function pages.MyCards()
	setTitle("My Cards")
	local split = Instance.new("Frame", body); split.Size = UDim2.fromScale(1,1); split.BackgroundTransparency = 1
	local grid = Instance.new("ScrollingFrame", split)
	grid.Size = UDim2.new(0.62, -6, 1, 0); grid.BackgroundColor3 = Theme.Colors.PanelSurface; grid.BorderSizePixel = 0; grid.ScrollBarThickness = 8; grid.AutomaticCanvasSize = Enum.AutomaticSize.Y
	Instance.new("UICorner", grid).CornerRadius = UDim.new(0, Theme.Sizes.SurfaceRadius); local gridStroke = Instance.new("UIStroke", grid); gridStroke.Color = Theme.Colors.Stroke; gridStroke.Thickness = Theme.Sizes.StrokeThin
	local gl = Instance.new("UIGridLayout", grid); gl.CellSize = UDim2.fromOffset(CELL_W, CELL_H); gl.CellPadding = UDim2.fromOffset(10, 10); gl.SortOrder = Enum.SortOrder.LayoutOrder
	local gp = Instance.new("UIPadding", grid); gp.PaddingTop = UDim.new(0,10); gp.PaddingLeft = UDim.new(0,10); gp.PaddingRight = UDim.new(0,10); gp.PaddingBottom = UDim.new(0,10)
	local preview = UI.createSectionSurface(split, "Preview", { padding = false })
	preview.Position = UDim2.new(0.62, 6, 0, 0); preview.Size = UDim2.new(0.38, -6, 1, 0)
	local empty = UI.createEmptyState(preview, "card", "Tap a card to inspect")
	local owned = counts(rawCollection); local order = {}
	for _, id in ipairs(rawCollection) do if not owned[id.."_seen"] then owned[id.."_seen"] = true; order[#order+1]=id end end
	for i, id in ipairs(order) do
		local cell = Instance.new("TextButton", grid); cell.LayoutOrder = i; cell.BackgroundTransparency = 1; cell.Text = ""; cell.AutoButtonColor = false
		makeCard(cell, id, CELL_W, CELL_H)
		if (owned[id] or 0) > 1 then local lab = Instance.new("TextLabel", cell); lab.AnchorPoint=Vector2.new(1,1); lab.Position=UDim2.new(1,-4,1,-4); lab.Size=UDim2.fromOffset(38,22); lab.BackgroundColor3=Theme.Colors.PanelDeep; lab.BackgroundTransparency=0.08; lab.TextColor3=Theme.Colors.Text; lab.Font=Theme.Fonts.BodyBold; lab.TextSize=14; lab.Text="x"..owned[id]; Instance.new("UICorner", lab).CornerRadius=UDim.new(0,7); local ls=Instance.new("UIStroke", lab); ls.Color=Theme.Colors.Outline; ls.Thickness=1 end
		cell.Activated:Connect(function()
			empty.Visible = false
			if previewCard then previewCard:Destroy() end
			previewCard = makeCard(preview, id, 170, 230)
			if previewCard then previewCard.AnchorPoint=Vector2.new(0.5,0.5); previewCard.Position=UDim2.fromScale(0.52,0.5) end
		end)
	end
end

function pages.Recycle()
	setTitle("Recycle")
	local owned = counts(rawCollection)
	for cardId, amount in pairs(recycleQueue) do
		if (owned[cardId] or 0) <= 0 then recycleQueue[cardId] = nil
		elseif amount > owned[cardId] then recycleQueue[cardId] = owned[cardId] end
	end

	local split = Instance.new("Frame", body); split.Size = UDim2.fromScale(1,1); split.BackgroundTransparency = 1
	local grid = Instance.new("ScrollingFrame", split)
	grid.Size = UDim2.new(0.62, -6, 1, 0); grid.BackgroundColor3 = Theme.Colors.PanelSurface; grid.BorderSizePixel = 0; grid.ScrollBarThickness = 8; grid.AutomaticCanvasSize = Enum.AutomaticSize.Y
	Instance.new("UICorner", grid).CornerRadius = UDim.new(0, Theme.Sizes.SurfaceRadius); local gridStroke = Instance.new("UIStroke", grid); gridStroke.Color = Theme.Colors.Stroke; gridStroke.Thickness = Theme.Sizes.StrokeThin
	local gl = Instance.new("UIGridLayout", grid); gl.CellSize = UDim2.fromOffset(CELL_W, CELL_H); gl.CellPadding = UDim2.fromOffset(10, 10); gl.SortOrder = Enum.SortOrder.LayoutOrder
	local gp = Instance.new("UIPadding", grid); gp.PaddingTop = UDim.new(0,10); gp.PaddingLeft = UDim.new(0,10); gp.PaddingRight = UDim.new(0,10); gp.PaddingBottom = UDim.new(0,10)

	local right = UI.createSectionSurface(split, "To Recycle", { padding = false })
	right.Position = UDim2.new(0.62, 6, 0, 0); right.Size = UDim2.new(0.38, -6, 1, 0)
	local listFrame = Instance.new("Frame", right); listFrame.Position = UDim2.fromOffset(10, 10); listFrame.Size = UDim2.new(1, -20, 1, -126); listFrame.BackgroundTransparency = 1
	local list = makeScroll(listFrame, "RecycleList")

	local function queueTotal()
		local selected, shards = 0, 0
		for cardId, amount in pairs(recycleQueue) do
			local card = CardData.Cards[cardId]
			local value = card and VendorConfig.DESTROY_VALUE_BY_RARITY[card.rarity] or 0
			selected += amount
			shards += amount * value
		end
		return selected, shards
	end

	local function addOne(cardId)
		local card = CardData.Cards[cardId]
		local queued = recycleQueue[cardId] or 0
		if queued >= (owned[cardId] or 0) then
			errorLabel.TextColor3 = Theme.Colors.Danger
			errorLabel.Text = "No more copies to recycle"
			return
		end
		local remaining = (owned[cardId] or 0) - queued - 1
		if remaining < recycleThreshold(card) and remaining < maxDeckUse(cardId) then
			showUsedOnDeckPopup()
			return
		end
		recycleQueue[cardId] = queued + 1
		show("Recycle", nil, false)
	end

	local order = {}
	for _, id in ipairs(rawCollection) do if not owned[id.."_seen"] then owned[id.."_seen"] = true; order[#order+1]=id end end
	for i, id in ipairs(order) do
		local cell = Instance.new("TextButton", grid); cell.LayoutOrder = i; cell.BackgroundTransparency = 1; cell.Text = ""; cell.AutoButtonColor = false
		makeCard(cell, id, CELL_W, CELL_H)
		local queued = recycleQueue[id] or 0
		if (owned[id] or 0) > 1 or queued > 0 then
			local lab = Instance.new("TextLabel", cell); lab.AnchorPoint=Vector2.new(1,1); lab.Position=UDim2.new(1,-4,1,-4); lab.Size=UDim2.fromOffset(54,22); lab.BackgroundColor3=Theme.Colors.PanelDeep; lab.BackgroundTransparency=0.08; lab.TextColor3=queued > 0 and Theme.Colors.Shard or Theme.Colors.Text; lab.Font=Theme.Fonts.BodyBold; lab.TextSize=13; lab.Text="x"..(owned[id] or 0)..(queued > 0 and (" -"..queued) or ""); Instance.new("UICorner", lab).CornerRadius=UDim.new(0,7); local ls=Instance.new("UIStroke", lab); ls.Color=Theme.Colors.Outline; ls.Thickness=1
		end
		cell.Activated:Connect(function() addOne(id) end)
	end

	local queueOrder = {}
	for _, id in ipairs(order) do if (recycleQueue[id] or 0) > 0 then queueOrder[#queueOrder+1] = id end end
	if #queueOrder == 0 then UI.createEmptyState(list, "card", "Select cards to recycle") end
	for i, id in ipairs(queueOrder) do
		local card = CardData.Cards[id]
		local amount = recycleQueue[id] or 0
		local value = card and VendorConfig.DESTROY_VALUE_BY_RARITY[card.rarity] or 0
		local row = button(list, string.format("%s  x%d  +%d", card and card.name or id, amount, amount * value), UDim2.new(1,-8,0,34), { color = Theme.Colors.Shard })
		row.LayoutOrder = i; row.TextSize = 13
		row.Activated:Connect(function()
			if amount <= 1 then recycleQueue[id] = nil else recycleQueue[id] = amount - 1 end
			show("Recycle", nil, false)
		end)
	end

	local selected, shards = queueTotal()
	local summary = Instance.new("TextLabel", right); summary.Position = UDim2.new(0, 10, 1, -108); summary.Size = UDim2.new(1, -20, 0, 34); summary.BackgroundTransparency = 1; summary.TextColor3 = Theme.Colors.TextSoft; summary.Font = Theme.Fonts.BodyBold; summary.TextSize = 14; summary.TextWrapped = true; summary.Text = string.format("%d card%s selected  |  +%d Crystal Shards", selected, selected == 1 and "" or "s", shards)
	local recycleBtn = button(right, "Recycle Selected", UDim2.new(1, -20, 0, 36), { color = Theme.Colors.Shard, disabled = selected <= 0, icon = AssetIds.Icons.CRYSTAL_SHARD }); recycleBtn.Position = UDim2.new(0, 10, 1, -68)
	local clearBtn = button(right, "Clear", UDim2.new(1, -20, 0, 30), { color = Theme.Colors.Disabled, disabled = selected <= 0 }); clearBtn.Position = UDim2.new(0, 10, 1, -28)
	clearBtn.Activated:Connect(function() recycleQueue = {}; show("Recycle", nil, false) end)
	recycleBtn.Activated:Connect(function()
		if selected <= 0 then return end
		local requests = {}
		for cardId, amount in pairs(recycleQueue) do requests[#requests+1] = { cardId = cardId, count = amount } end
		local ok, result = call(rf.DestroyCards, requests)
		if ok then
			recycleQueue = {}
			refreshData()
			show("Recycle", nil, false)
			errorLabel.TextColor3 = Theme.Colors.Success
			errorLabel.Text = "+" .. tostring((type(result) == "table" and result.gained) or shards) .. " Crystal Shards"
		else
			if tostring(result) == "Cant add card, used on deck" then
				showUsedOnDeckPopup()
			else
				errorLabel.TextColor3 = Theme.Colors.Danger
				errorLabel.Text = tostring(result)
			end
		end
	end)
end
function pages.DeckList()
	setTitle("Deck Builder")
	refreshData()
	local root = Instance.new("Frame", body); root.Size = UDim2.fromScale(1,1); root.BackgroundTransparency = 1
	local top = Instance.new("Frame", root); top.Size = UDim2.new(1,0,0,48); top.BackgroundTransparency = 1
	button(top, "+ Create Deck", UDim2.fromOffset(170,40)).Position = UDim2.fromOffset(0,4)
	top:FindFirstChildOfClass("TextButton").Activated:Connect(function()
		local ok, deckOrErr = call(rf.CreateDeck, "New Deck")
		if ok then currentDeck = deckOrErr; show("DeckEditor", deckOrErr.id) else errorLabel.Text = tostring(deckOrErr) end
	end)
	local listFrame = Instance.new("Frame", root); listFrame.Position = UDim2.new(0,0,0,54); listFrame.Size = UDim2.new(1,0,1,-54); listFrame.BackgroundTransparency = 1
	local list = makeScroll(listFrame, "DeckList")
	for i, deck in ipairs(deckPayload.decks or {}) do
		local nTypes = distinctChargeTypes(deck.cards)
		local row = UI.createSectionSurface(list, "DeckRow", { padding = false, color = deck.isActive and Color3.fromRGB(25, 68, 45) or Theme.Colors.PanelSurface2 })
		row.Size = UDim2.new(1,-4,0,82); row.LayoutOrder = i
		local name = Instance.new("TextLabel", row); name.Position=UDim2.fromOffset(12,6); name.Size=UDim2.new(1,-300,0,26); name.BackgroundTransparency=1; name.TextXAlignment=Enum.TextXAlignment.Left; name.Font=Enum.Font.GothamBold; name.TextSize=18; name.TextColor3=Color3.new(1,1,1); name.Text=(deck.isActive and "ACTIVE - " or "")..deck.name
		local meta = Instance.new("TextLabel", row); meta.Position=UDim2.fromOffset(12,34); meta.Size=UDim2.new(1,-300,0,22); meta.BackgroundTransparency=1; meta.TextXAlignment=Enum.TextXAlignment.Left; meta.Font=Enum.Font.Gotham; meta.TextSize=14; meta.TextColor3=Color3.fromRGB(205,215,235); meta.Text=string.format("%d/30 cards | %s%s", deck.cardCount or #(deck.cards or {}), deck.valid and "Valid" or "Draft", nTypes > 2 and string.format("  |  %d Charge Types - Hero Slots: 2", nTypes) or "")
		local edit = button(row, "Edit", UDim2.fromOffset(78,34), { color = Theme.Accents.Inventory }); edit.Position = UDim2.new(1,-254,0,24); edit.Activated:Connect(function() currentDeck = deck; show("DeckEditor", deck.id) end)
		local set = button(row, "Set Active", UDim2.fromOffset(94,34), { color = Theme.Colors.Success, disabled = not deck.valid }); set.Position = UDim2.new(1,-170,0,24); set.Activated:Connect(function() local ok, err = call(rf.SetActiveDeck, deck.id); if not ok then errorLabel.Text = tostring(err) else show("DeckList", nil, false) end end)
		local del = button(row, "Delete", UDim2.fromOffset(70,34), { color = Theme.Colors.Danger }); del.Position = UDim2.new(1,-72,0,24); del.Activated:Connect(function() local ok, err = call(rf.DeleteDeck, deck.id); if not ok then errorLabel.Text=tostring(err) else show("DeckList", nil, false) end end)
	end
end

local function deckCount(deck)
	return counts(deck.cards or {})
end
function pages.DeckEditor(deckId)
	refreshData()
	local deck
	for _, d in ipairs(deckPayload.decks or {}) do if d.id == deckId then deck = d end end
	if not deck then show("DeckList", nil, false); return end
	currentDeck = deck
	local nTypes = distinctChargeTypes(deck.cards)
	setTitle(deck.name)
	local root = Instance.new("Frame", body); root.Size=UDim2.fromScale(1,1); root.BackgroundTransparency=1
	local header = Instance.new("Frame", root); header.Size=UDim2.new(1,0,0,48); header.BackgroundTransparency=1
	local nameBox = Instance.new("TextBox", header); nameBox.Size=UDim2.new(0.34,0,0,38); nameBox.Position=UDim2.fromOffset(0,4); nameBox.BackgroundColor3=Theme.Colors.PanelSurface; nameBox.TextColor3=Theme.Colors.Text; nameBox.Font=Theme.Fonts.BodyBold; nameBox.TextSize=16; nameBox.Text=deck.name; Instance.new("UICorner", nameBox).CornerRadius=UDim.new(0,8); local nameStroke=Instance.new("UIStroke", nameBox); nameStroke.Color=Theme.Colors.Stroke; nameStroke.Thickness=1
	nameBox.FocusLost:Connect(function() call(rf.RenameDeck, deck.id, nameBox.Text); show("DeckEditor", deck.id, false) end)
	-- Deck charge feedback: gen=produces +1 charge, spe=spends charge, PC=pure-charge cards
	local _fbGen,_fbSpe,_fbPC={},{},0
	for _,_id in ipairs(deck.cards or {}) do
		local _c=CardData.Cards[_id]; if _c then
			local _co=false; for _,_e in ipairs(_c.effects or {}) do if _e.action=="corrupted" then _co=true end end
			if ChargeConfig.isProducing(_c.battleType) and not _co then _fbGen[_c.battleType]=(_fbGen[_c.battleType] or 0)+1 end
			if _c.chargeCost then _fbSpe[_c.chargeCost.battleType]=(_fbSpe[_c.chargeCost.battleType] or 0)+1; if(_c.cost or 0)==0 then _fbPC+=1 end end
		end
	end
	local _fbP,_fbLine={},"" 
	for _,_bt in ipairs({"MIGHTY","SWIFT","VITAL"}) do
		local _g,_s=_fbGen[_bt] or 0,_fbSpe[_bt] or 0
		if _g>0 or _s>0 then _fbP[#_fbP+1]=_bt:sub(1,3)..":+".._g.."/-".._s end
	end
	if #_fbP>0 then _fbLine="\n"..table.concat(_fbP,"  ")..(_fbPC>0 and ("  PC:".._fbPC) or "") end
	local info = Instance.new("TextLabel", header); info.Position=UDim2.new(0.36,0,0,0); info.Size=UDim2.new(0.34,0,1,0); info.BackgroundTransparency=1; info.TextXAlignment=Enum.TextXAlignment.Left; info.Font=Enum.Font.Gotham; info.TextSize=13; info.TextWrapped=true
	info.Text = ((nTypes > 2) and string.format("%d Charge Types - Hero Slots: 2", nTypes) or string.format("%d Charge Type%%s in deck", nTypes, nTypes==1 and "" or "s")) .. _fbLine
	info.TextColor3 = (nTypes > 2) and Color3.fromRGB(255,170,90) or Color3.fromRGB(215,225,245)
	if nTypes > 2 then
		if not chargeWarnState[deck.id] then
			chargeWarnState[deck.id] = true
			errorLabel.Text = string.format("Heads up - %d Charge Types, but a hero has only 2 Charge Slots. Extra types still play; their Charge competes for the 2 slots.", nTypes)
		end
	else
		chargeWarnState[deck.id] = nil
	end
	local active = button(header, "Set Active", UDim2.fromOffset(104,36), { color = Theme.Colors.Success }); active.Position=UDim2.new(1,-218,0,4); active.Activated:Connect(function() local ok, err=call(rf.SetActiveDeck, deck.id); if ok then show("DeckEditor", deck.id, false) else errorLabel.Text=tostring(err) end end)
	local save = button(header, "Save", UDim2.fromOffset(86,36), { color = Theme.Accents.Inventory }); save.Position=UDim2.new(1,-102,0,4); save.Activated:Connect(function() local ok, err=call(rf.SaveDeckCards, deck.id, deck.cards or {}); if ok then show("DeckEditor", deck.id, false) else errorLabel.Text=tostring(err) end end)
	local columns = Instance.new("Frame", root); columns.Position=UDim2.new(0,0,0,54); columns.Size=UDim2.new(1,0,1,-54); columns.BackgroundTransparency=1
	local left = Instance.new("Frame", columns); left.Size=UDim2.new(0.42,-6,1,0); left.BackgroundTransparency=1
	local right = Instance.new("Frame", columns); right.Position=UDim2.new(0.42,6,0,0); right.Size=UDim2.new(0.58,-6,1,0); right.BackgroundTransparency=1
	local deckScroll = makeScroll(left, "DeckCards")
	local availScroll = Instance.new("ScrollingFrame", right); availScroll.Size=UDim2.fromScale(1,1); availScroll.BackgroundColor3=Theme.Colors.PanelSurface; availScroll.BorderSizePixel=0; availScroll.ScrollBarThickness=8; availScroll.AutomaticCanvasSize=Enum.AutomaticSize.Y; Instance.new("UICorner", availScroll).CornerRadius=UDim.new(0,Theme.Sizes.SurfaceRadius); local availStroke=Instance.new("UIStroke", availScroll); availStroke.Color=Theme.Colors.Stroke; availStroke.Thickness=Theme.Sizes.StrokeThin
	local ag = Instance.new("UIGridLayout", availScroll); ag.CellSize=UDim2.fromOffset(96,130); ag.CellPadding=UDim2.fromOffset(8,8); ag.SortOrder=Enum.SortOrder.LayoutOrder
	local ap = Instance.new("UIPadding", availScroll); ap.PaddingTop=UDim.new(0,8); ap.PaddingLeft=UDim.new(0,8); ap.PaddingRight=UDim.new(0,8); ap.PaddingBottom=UDim.new(0,8)
	local dcounts = deckCount(deck)
	local owned = counts(rawCollection)
	local unique = {}
	for _, id in ipairs(rawCollection) do if owned[id] and not owned[id.."_seen"] and ownsAllowed(deck,id) then owned[id.."_seen"] = true; unique[#unique+1]=id end end
	local status = Instance.new("TextLabel", deckScroll); status.Size=UDim2.new(1,-8,0,42); status.BackgroundTransparency=1; status.TextColor3=deck.valid and Color3.fromRGB(120,240,150) or Color3.fromRGB(255,190,110); status.Font=Enum.Font.GothamBold; status.TextSize=14; status.TextWrapped=true; status.Text=string.format("%d/30 cards - %s", #(deck.cards or {}), deck.valid and "Valid" or table.concat(deck.errors or {"Draft"}, "; "))
	for i, id in ipairs(deck.cards or {}) do
		local card = CardData.Cards[id]
		local row = button(deckScroll, (card and card.name or id) .. "  -", UDim2.new(1,-8,0,32)); row.LayoutOrder=i+1; row.TextSize=13; row.Activated:Connect(function()
			table.remove(deck.cards, i)
			local ok, err = call(rf.SaveDeckCards, deck.id, deck.cards)
			if ok then show("DeckEditor", deck.id, false) else errorLabel.Text=tostring(err) end
		end)
	end
	for i, id in ipairs(unique) do
		local cell = Instance.new("TextButton", availScroll); cell.LayoutOrder=i; cell.BackgroundTransparency=1; cell.Text=""; cell.AutoButtonColor=false
		makeCard(cell, id, 96, 130)
		local canAdd = #(deck.cards or {}) < 30 and (dcounts[id] or 0) < math.min(maxDeckCopiesForCard(card), owned[id] or 0)
		cell.BackgroundTransparency = canAdd and 1 or 0.45
		cell.Activated:Connect(function()
			if not canAdd then return end
			deck.cards = deck.cards or {}; table.insert(deck.cards, id)
			local ok, err = call(rf.SaveDeckCards, deck.id, deck.cards)
			if ok then show("DeckEditor", deck.id, false) else errorLabel.Text=tostring(err) end
		end)
	end
end

local isOpen = false
local function open()
	if isOpen or not PanelCoordinator.claim("CardLibrary") then return end
	isOpen = true
	gui.Enabled = true
	refreshData()
	pageStack = {}
	show("Home")
end
function close()
	isOpen = false
	local popup = gui:FindFirstChild("UsedOnDeckPopup")
	if popup then popup:Destroy() end
	gui.Enabled = false
	pageStack = {}
	clearBody()
	PanelCoordinator.release("CardLibrary")
end
PanelCoordinator.register("CardLibrary", { close = close, back = goBack })

backBtn.Activated:Connect(goBack)
scrim.Activated:Connect(close)
fullscreenBackdrop.Activated:Connect(close)
closeBtn.Activated:Connect(close)

local hud = pg:WaitForChild("Hud")
local invButton = hud:WaitForChild("TopRightAnchor"):WaitForChild("InventoryButton")
invButton.Activated:Connect(open)

remotes:WaitForChild("BattleLoading").OnClientEvent:Connect(close)
remotes:WaitForChild("BattleSeated").OnClientEvent:Connect(close)
remotes:WaitForChild("UpdateBattleState").OnClientEvent:Connect(close)
