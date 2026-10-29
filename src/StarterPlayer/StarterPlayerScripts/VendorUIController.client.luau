-- VendorUIController: Card Merchant NPC dialogue trigger + rotating stock Craft/Buy shop UI.
-- Dialogue trigger mirrors TrainerInteraction.lua; shop UI page-stack mirrors ItemMallController.lua.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ProximityPromptService = game:GetService("ProximityPromptService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local gui = playerGui:WaitForChild("VendorUI")
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local GetVendorStock = remotes:WaitForChild("GetVendorStock")
local CraftCard = remotes:WaitForChild("CraftCard")
local BuyCard = remotes:WaitForChild("BuyCard")

local DialogueController = require(script.Parent.DialogueController)
local CardData = require(ReplicatedStorage.Modules.CardData)
local AssetIds = require(ReplicatedStorage.Modules.AssetIds)
local modules = playerGui:WaitForChild("BattleUI"):WaitForChild("Modules")
local CardVisuals = require(modules:WaitForChild("CardVisuals"))
local UI = require(playerGui:WaitForChild("SharedUI"):WaitForChild("UIComponents"))
local Theme = UI.Theme

local dialog = gui:WaitForChild("Dialog")
local scrim = gui:WaitForChild("Scrim")
local titleBar = dialog:WaitForChild("TitleBar")
local title = titleBar:WaitForChild("Title")
local closeButton = titleBar:WaitForChild("CloseButton")
local body = dialog:WaitForChild("Body")

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
UI.styleScrim(scrim)
local fullscreenBackdrop = UI.bindFullscreenBackdrop(gui, scrim)
UI.applyModalShell(dialog, titleBar, title, closeButton, backButton, Theme.Accents.Vendor)
local homeIcon = UI.createHeaderIcon(titleBar, AssetIds.VendingIcon)
body.Position = UDim2.new(0, 18, 0, 76)
body.Size = UDim2.new(1, -36, 1, -104)
body.BackgroundTransparency = 1

local CELL_W, CELL_H = 112, 152
local pageStack = {}
local pages = {}
local currentStock = {} -- cardId -> stock entry (rarity/craftCost/buyCost/owned/maxed)
local nextRotationAt = 0

local function clearBody()
	for _, child in ipairs(body:GetChildren()) do child:Destroy() end
end

local function setTitle(text)
	title.Text = text
	backButton.Visible = #pageStack > 1
	homeIcon.Visible = not backButton.Visible
end

local function show(page, arg, push)
	if push ~= false then pageStack[#pageStack + 1] = { page = page, arg = arg } end
	clearBody()
	pages[page](arg)
end

local function close()
	gui.Enabled = false
	pageStack = {}
	clearBody()
end

local function goBack()
	if #pageStack <= 1 then close(); return end
	table.remove(pageStack)
	local previous = pageStack[#pageStack]
	show(previous.page, previous.arg, false)
end

local function makeCard(parent, cardId, w, h)
	local card = CardData.Cards[cardId]
	if not card then return nil end
	local abilName, abilText = CardData.getAbilityDisplay(cardId)
	local opts = {
		cardId = cardId, battleType = card.battleType, cardType = card.cardType, race = card.race,
		cost = card.cost, name = card.name, chargeCost = card.chargeCost,
		atk = card.cardType == "creature" and card.atk or nil,
		hp = card.cardType == "creature" and card.hp or nil,
		abilityName = abilName, abilityText = abilText,
	}
	local f = CardVisuals.buildCardFrame(w or CELL_W, h or CELL_H, "full")
	CardVisuals.updateCardFrame(f, opts)
	if f:FindFirstChild("AttackEmblem") then f.AttackEmblem.Visible = card.cardType == "creature" end
	if f:FindFirstChild("HealthEmblem") then f.HealthEmblem.Visible = card.cardType == "creature" end
	local stk = f:FindFirstChildOfClass("UIStroke")
	if stk then stk.Color = CardVisuals.TC_type[card.battleType] or CardVisuals.TC_type.NEUTRAL end
	f.Parent = parent
	return f
end

local function fetchStock()
	local ok, result = pcall(function() return GetVendorStock:InvokeServer() end)
	if not ok or type(result) ~= "table" or not result.ok then
		return false, (type(result) == "table" and result.error) or "Vendor unavailable"
	end
	currentStock = {}
	for _, entry in ipairs(result.stock or {}) do currentStock[entry.cardId] = entry end
	nextRotationAt = result.nextRotationAt or 0
	return true
end

local function rotationLabel()
	local remaining = math.max(0, nextRotationAt - os.time())
	local h = math.floor(remaining / 3600)
	local m = math.floor((remaining % 3600) / 60)
	return string.format("New stock in %dh %dm", h, m)
end

function pages.Stock()
	setTitle("Card Merchant")
	local root = Instance.new("Frame", body)
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundTransparency = 1

	local ok, err = fetchStock()
	if not ok then
		UI.createEmptyState(root, "card", err or "Vendor unavailable")
		return
	end

	local rotation = Instance.new("TextLabel", root)
	rotation.Name = "Rotation"
	rotation.Size = UDim2.new(1, 0, 0, 26)
	rotation.BackgroundTransparency = 1
	rotation.Text = rotationLabel()
	rotation.TextColor3 = Theme.Colors.TextMuted
	rotation.Font = Theme.Fonts.Body
	rotation.TextSize = 14

	local grid = Instance.new("ScrollingFrame", root)
	grid.Name = "Stock"
	grid.Position = UDim2.new(0, 0, 0, 32)
	grid.Size = UDim2.new(1, 0, 1, -32)
	grid.BackgroundColor3 = Theme.Colors.PanelSurface
	grid.BorderSizePixel = 0
	grid.ScrollBarThickness = 8
	grid.AutomaticCanvasSize = Enum.AutomaticSize.Y
	grid.CanvasSize = UDim2.new()
	Instance.new("UICorner", grid).CornerRadius = UDim.new(0, Theme.Sizes.SurfaceRadius)
	local gridStroke = Instance.new("UIStroke", grid)
	gridStroke.Color = Theme.Colors.Stroke
	gridStroke.Thickness = Theme.Sizes.StrokeThin
	local gl = Instance.new("UIGridLayout", grid)
	gl.CellSize = UDim2.fromOffset(CELL_W, CELL_H)
	gl.CellPadding = UDim2.fromOffset(10, 10)
	gl.SortOrder = Enum.SortOrder.LayoutOrder
	local gp = Instance.new("UIPadding", grid)
	gp.PaddingTop = UDim.new(0, 10); gp.PaddingLeft = UDim.new(0, 10)
	gp.PaddingRight = UDim.new(0, 10); gp.PaddingBottom = UDim.new(0, 10)

	local order = {}
	for cardId in pairs(currentStock) do order[#order + 1] = cardId end
	table.sort(order)
	for i, cardId in ipairs(order) do
		local entry = currentStock[cardId]
		local cell = Instance.new("TextButton", grid)
		cell.LayoutOrder = i
		cell.BackgroundTransparency = 1
		cell.Text = ""
		cell.AutoButtonColor = false
		makeCard(cell, cardId, CELL_W, CELL_H)
		if entry.maxed then
			local lab = Instance.new("TextLabel", cell)
			lab.AnchorPoint = Vector2.new(1, 1)
			lab.Position = UDim2.new(1, -4, 1, -4)
			lab.Size = UDim2.fromOffset(60, 22)
			lab.BackgroundColor3 = Theme.Colors.PanelDeep
			lab.BackgroundTransparency = 0.08
			lab.TextColor3 = Theme.Colors.TextMuted
			lab.Font = Theme.Fonts.BodyBold
			lab.TextSize = 12
			lab.Text = "Owned Max"
			Instance.new("UICorner", lab).CornerRadius = UDim.new(0, 7)
		end
		cell.Activated:Connect(function() show("Detail", cardId) end)
	end
end

function pages.Detail(cardId)
	local card = CardData.Cards[cardId]
	local entry = currentStock[cardId]
	setTitle(card and card.name or "Card")
	if not card or not entry then
		UI.createEmptyState(body, "card", "This card is no longer in stock.")
		return
	end

	local root = Instance.new("Frame", body)
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundTransparency = 1

	local preview = UI.createSectionSurface(root, "Preview", { padding = false })
	preview.Position = UDim2.new(0, 0, 0, 0)
	preview.Size = UDim2.new(0.4, -8, 1, 0)
	local previewCard = makeCard(preview, cardId, 170, 230)
	if previewCard then
		previewCard.AnchorPoint = Vector2.new(0.5, 0.5)
		previewCard.Position = UDim2.fromScale(0.5, 0.5)
	end

	local info = Instance.new("Frame", root)
	info.Position = UDim2.new(0.4, 8, 0, 0)
	info.Size = UDim2.new(0.6, -8, 1, 0)
	info.BackgroundTransparency = 1
	local list = Instance.new("UIListLayout", info)
	list.Padding = UDim.new(0, 10)
	list.SortOrder = Enum.SortOrder.LayoutOrder

	local rarity = Instance.new("TextLabel", info)
	rarity.Size = UDim2.new(1, 0, 0, 24)
	rarity.BackgroundTransparency = 1
	rarity.Text = "Rarity: " .. (card.rarity or "?"):gsub("^%l", string.upper)
	rarity.TextColor3 = Theme.Colors.TextSoft
	rarity.Font = Theme.Fonts.BodyBold
	rarity.TextSize = 15
	rarity.TextXAlignment = Enum.TextXAlignment.Left

	local status = Instance.new("TextLabel", info)
	status.Name = "Status"
	status.Size = UDim2.new(1, 0, 0, 40)
	status.BackgroundTransparency = 1
	status.Text = entry.maxed and "You already own the maximum useful copies (2)." or ""
	status.TextColor3 = Theme.Colors.Warning
	status.Font = Theme.Fonts.Body
	status.TextSize = 14
	status.TextWrapped = true
	status.TextXAlignment = Enum.TextXAlignment.Left

	local craftBtn = UI.createPrimaryButton(info, "Craft (" .. entry.craftCost .. " Fragments)",
		AssetIds.Icons.CARD_FRAGMENT, { size = UDim2.new(1, 0, 0, 56), color = Theme.Colors.Fragment, disabled = entry.maxed })
	local buyBtn = UI.createPrimaryButton(info, "Buy (" .. entry.buyCost .. " Shards)",
		AssetIds.Icons.CRYSTAL_SHARD, { size = UDim2.new(1, 0, 0, 56), color = Theme.Colors.Shard, disabled = entry.maxed })

	local function attempt(remote, label)
		if entry.maxed then return end
		status.TextColor3 = Theme.Colors.TextMuted
		status.Text = label .. "..."
		local ok, result = pcall(function() return remote:InvokeServer(cardId) end)
		if not ok or type(result) ~= "table" then
			status.TextColor3 = Theme.Colors.Danger
			status.Text = "Vendor unavailable, try again."
			return
		end
		if not result.ok then
			status.TextColor3 = Theme.Colors.Danger
			status.Text = result.error or "Purchase failed."
			return
		end
		status.TextColor3 = Theme.Colors.Success
		status.Text = label .. " successful!"
		task.delay(0.6, function()
			if pageStack[#pageStack] and pageStack[#pageStack].page == "Detail" and pageStack[#pageStack].arg == cardId then
				-- Re-fetch from the server, not a re-render from the stale currentStock cache --
				-- the owned/maxed state just changed and the cache still reflects the pre-purchase count.
				fetchStock()
				show("Detail", cardId, false)
			end
		end)
	end
	craftBtn.Activated:Connect(function() attempt(CraftCard, "Craft") end)
	buyBtn.Activated:Connect(function() attempt(BuyCard, "Buy") end)
end

backButton.Activated:Connect(goBack)
closeButton.Activated:Connect(close)
scrim.Activated:Connect(close)
fullscreenBackdrop.Activated:Connect(close)

for _, remoteName in ipairs({"BattleLoading", "BattleSeated", "UpdateBattleState"}) do
	remotes:WaitForChild(remoteName).OnClientEvent:Connect(close)
end

-- Dialogue trigger: talk to the Card Merchant NPC to open the shop.
local vendorModel = workspace:WaitForChild("Card Merchant", 30)
local SHOP_DIALOGUE = {
	Segments = {"Welcome, traveler. I deal in exact cards -- no gambling required.",
		"Craft with Fragments if you can wait, or Buy with Shards for speed. Your call."},
	Options = {
		{ Label = "Show me your wares.", Action = "SHOP" },
		{ Label = "Not right now.", Action = "CLOSE" },
	},
}

local function openShop()
	gui.Enabled = true
	pageStack = {}
	show("Stock")
end

ProximityPromptService.PromptTriggered:Connect(function(prompt, triggeringPlayer)
	if triggeringPlayer and triggeringPlayer ~= player then return end
	if DialogueController.IsOpen then return end
	if not vendorModel or not prompt:IsDescendantOf(vendorModel) then return end
	DialogueController:Open(vendorModel, SHOP_DIALOGUE, function(action)
		if action == "SHOP" then openShop() end
	end)
end)

print("[VendorUIController] Card Merchant dialogue + shop UI wired")
