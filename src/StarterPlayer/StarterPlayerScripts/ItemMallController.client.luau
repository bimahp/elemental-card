-- ItemMallController: policy-gated Developer Product shop with page-stack navigation.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local gui = playerGui:WaitForChild("ItemMallUI")
local hud = playerGui:WaitForChild("Hud")
local mallButton = hud:WaitForChild("TopRightAnchor"):WaitForChild("ItemMallButton")
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local policyRemote = remotes:WaitForChild("GetMonetizationPolicy")
local QuestStateChanged = remotes:WaitForChild("QuestStateChanged")
local ShopConfig = require(ReplicatedStorage.Modules.ShopConfig)
local AssetIds = require(ReplicatedStorage.Modules.AssetIds)
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
UI.applyModalShell(dialog, titleBar, title, closeButton, backButton, Theme.Accents.Mall)
local homeIcon = UI.createHeaderIcon(titleBar, AssetIds.ItemMallIcon)
body.Position = UDim2.new(0, 18, 0, 76)
body.Size = UDim2.new(1, -36, 1, -104)
body.BackgroundTransparency = 1

local currentShards = 0
local allowed = false
local pageStack = {}
local pages = {}
local pageToken = 0

local function clearBody()
	pageToken += 1
	for _, child in ipairs(body:GetChildren()) do child:Destroy() end
end

local function button(parent, text, size, opts)
	opts = opts or {}
	opts.size = size or opts.size or UDim2.fromOffset(220, 48)
	return UI.createPrimaryButton(parent, text, opts.icon, opts)
end

local function setTitle(value)
	title.Text = value
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

function pages.Home()
	setTitle("Item Mall")
	local root = Instance.new("Frame", body)
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundTransparency = 1
	local balance = Instance.new("TextLabel", root)
	balance.Name = "Balance"
	balance.Size = UDim2.new(1, 0, 0, 42)
	balance.BackgroundTransparency = 1
	balance.Text = "Balance: " .. currentShards .. " Crystal Shards"
	balance.TextColor3 = Theme.Colors.TextSoft
	balance.Font = Theme.Fonts.BodyBold
	balance.TextSize = 17
	local category = button(root, "Crystal Shards", UDim2.fromOffset(340, 78), { color = Theme.Colors.Shard, icon = AssetIds.Icons.CRYSTAL_SHARD, font = Theme.Fonts.Title, textSize = 24 })
	category.AnchorPoint = Vector2.new(0.5, 0.5)
	category.Position = UDim2.fromScale(0.5, 0.5)
	category.Activated:Connect(function() show("Bundles") end)
end

function pages.Bundles()
	setTitle("Crystal Shards")
	local token = pageToken
	local balance = Instance.new("TextLabel", body)
	balance.Name = "Balance"
	balance.Size = UDim2.new(1, 0, 0, 38)
	balance.BackgroundTransparency = 1
	balance.Text = "Balance: " .. currentShards .. " Crystal Shards"
	balance.TextColor3 = Theme.Colors.TextSoft
	balance.Font = Theme.Fonts.BodyBold
	balance.TextSize = 16

	local grid = Instance.new("ScrollingFrame", body)
	grid.Position = UDim2.fromOffset(0, 42)
	grid.Size = UDim2.new(1, 0, 1, -42)
	grid.BackgroundTransparency = 1
	grid.BorderSizePixel = 0
	grid.ScrollBarThickness = 7
	grid.AutomaticCanvasSize = Enum.AutomaticSize.Y
	grid.CanvasSize = UDim2.new()
	local layout = Instance.new("UIGridLayout", grid)
	layout.CellSize = UDim2.new(0.48, -6, 0, 148)
	layout.CellPadding = UDim2.fromOffset(12, 12)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder

	for index, bundle in ipairs(ShopConfig.Bundles) do
		local card = UI.createSectionSurface(grid, "BundleCard", { padding = false, color = Theme.Colors.PanelSurface })
		card.LayoutOrder = index

		local icon = Instance.new("ImageLabel", card)
		icon.BackgroundTransparency = 1
		icon.Position = UDim2.fromOffset(14, 18)
		icon.Size = UDim2.fromOffset(64, 64)
		icon.Image = AssetIds.Icons.CRYSTAL_SHARD
		icon.ScaleType = Enum.ScaleType.Fit

		local amount = Instance.new("TextLabel", card)
		amount.BackgroundTransparency = 1
		amount.Position = UDim2.fromOffset(90, 14)
		amount.Size = UDim2.new(1, -104, 0, 32)
		amount.TextXAlignment = Enum.TextXAlignment.Left
		amount.Text = tostring(bundle.shards) .. " Shards"
		amount.TextColor3 = Theme.Colors.Text
		amount.Font = Theme.Fonts.Title
		amount.TextSize = 22
		amount.TextStrokeTransparency = 0.55

		local buy = button(card, bundle.productId > 0 and "Loading price..." or "Coming soon", UDim2.new(1, -104, 0, 44), { color = Theme.Colors.Disabled, disabled = true })
		buy.Position = UDim2.new(0, 90, 0, 60)
		local enabled = false
		buy.Active = false
		buy.AutoButtonColor = false
		buy.BackgroundColor3 = Theme.Colors.Disabled
		buy.Activated:Connect(function()
			if enabled and allowed and bundle.productId > 0 then
				MarketplaceService:PromptProductPurchase(player, bundle.productId)
			end
		end)

		if bundle.productId > 0 then
			task.spawn(function()
				local ok, info = pcall(function()
					return MarketplaceService:GetProductInfoAsync(bundle.productId, Enum.InfoType.Product)
				end)
				if token ~= pageToken or not card.Parent then return end
				if ok and type(info) == "table" and type(info.PriceInRobux) == "number" then
					buy.Text = tostring(info.PriceInRobux) .. " Robux"
					buy.Active = true
					buy.AutoButtonColor = true
					buy.BackgroundColor3 = Theme.Colors.Success
					local grad = buy:FindFirstChild("ButtonGradient")
					if grad then grad:Destroy() end
					local newGrad = Instance.new("UIGradient", buy)
					newGrad.Name = "ButtonGradient"
					newGrad.Color = ColorSequence.new({ColorSequenceKeypoint.new(0, Theme.Colors.Success:Lerp(Color3.new(1,1,1), 0.12)), ColorSequenceKeypoint.new(1, Theme.Colors.Success:Lerp(Color3.new(0,0,0), 0.16))})
					newGrad.Rotation = 90
					enabled = true
				else
					buy.Text = "Unavailable"
				end
			end)
		end
	end
end

-- StarterGui keeps the button visible for editor-first layout authoring.
-- Runtime policy is authoritative, so hide it until the server confirms access.
mallButton.Visible = false
mallButton.Activated:Connect(function()
	if not allowed or gui.Enabled then return end
	gui.Enabled = true
	pageStack = {}
	show("Home")
end)
backButton.Activated:Connect(goBack)
closeButton.Activated:Connect(close)
scrim.Activated:Connect(close)
fullscreenBackdrop.Activated:Connect(close)

QuestStateChanged.OnClientEvent:Connect(function(snapshot)
	if type(snapshot) == "table" and type(snapshot.crystalShards) == "number" then
		currentShards = snapshot.crystalShards
		local balance = body:FindFirstChild("Balance")
		if balance then balance.Text = "Balance: " .. currentShards .. " Crystal Shards" end
	end
end)

for _, remoteName in ipairs({"BattleLoading", "BattleSeated", "UpdateBattleState"}) do
	remotes:WaitForChild(remoteName).OnClientEvent:Connect(close)
end

task.spawn(function()
	for _ = 1, 5 do
		local ok, result = pcall(function() return policyRemote:InvokeServer() end)
		if ok and type(result) == "table" and result.ok then
			allowed = result.itemMallAllowed == true
			mallButton.Visible = allowed
			return
		end
		task.wait(1)
	end
	allowed = false
	mallButton.Visible = false
end)
