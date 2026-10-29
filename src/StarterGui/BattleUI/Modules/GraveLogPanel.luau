local GraveLogPanel = {}

local panel, bigCard, historyScroll
local cardVis, cardData, DW, DH

local function isCorrupted(card)
	for _, e in ipairs((card and card.effects) or {}) do
		if e.action == "corrupted" then return true end
	end
	return false
end

function GraveLogPanel.init(ctx)
	cardVis  = ctx.CardVisuals
	cardData = ctx.CardData
	DW, DH   = ctx.DW, ctx.DH
	local main = ctx.main
	local buildCardFrame = cardVis.buildCardFrame
	local rnd = cardVis.rnd

	-- Panel fills the top of the right column above EnergyBadge.
	panel = Instance.new("Frame")
	panel.Name = "GraveLogPanel"
	panel.AnchorPoint = Vector2.new(0, 1)
	panel.Position = UDim2.new(0,8, 1,-8)
	panel.Size = UDim2.new(0,DW+14, 0,280)
	panel.BackgroundColor3 = Color3.fromRGB(30,30,44)
	panel.BackgroundTransparency = 0.15
	panel.BorderSizePixel = 0
	rnd(panel, 6)
	local stk = Instance.new("UIStroke", panel)
	stk.Color = Color3.fromRGB(55,55,75); stk.Thickness = 1
	panel.Parent = main

	local hdr = Instance.new("TextLabel", panel)
	hdr.Size = UDim2.new(1,-8, 0,14)
	hdr.Position = UDim2.new(0,4, 0,4)
	hdr.BackgroundTransparency = 1
	hdr.Font = Enum.Font.GothamBold; hdr.TextSize = 9
	hdr.TextColor3 = Color3.fromRGB(160,160,180)
	hdr.TextXAlignment = Enum.TextXAlignment.Left
	hdr.Text = "DISCARD HISTORY"

	bigCard = buildCardFrame(DW, DH, "full")
	bigCard.Position = UDim2.new(0,7, 0,22)
	bigCard.Parent = panel
	cardVis.updateCardFrame(bigCard, {battleType="NEUTRAL", name="Empty", dim=0.85})
	bigCard.AttackEmblem.Visible = false
	bigCard.HealthEmblem.Visible = false
	bigCard.CostBadge.Visible = false

	historyScroll = Instance.new("ScrollingFrame", panel)
	historyScroll.Position = UDim2.new(0,4, 0, 22+DH+8)
	historyScroll.Size = UDim2.new(1,-8, 1, -(22+DH+8+4))
	historyScroll.BackgroundTransparency = 1
	historyScroll.BorderSizePixel = 0
	historyScroll.ScrollBarThickness = 3
	historyScroll.CanvasSize = UDim2.new(0,0,0,0)
	historyScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	local ull = Instance.new("UIListLayout", historyScroll)
	ull.FillDirection = Enum.FillDirection.Vertical
	ull.SortOrder = Enum.SortOrder.LayoutOrder
	ull.Padding = UDim.new(0,2)
end

function GraveLogPanel.update(discardHistory)
	if not panel then return end
	local TC_type = cardVis.TC_type

	local latest = discardHistory and discardHistory[1]
	if latest then
		local card = cardData.Cards[latest.cardId]
		if card then
			local abilName, abilText = cardData.getAbilityDisplay(latest.cardId)
			cardVis.updateCardFrame(bigCard, {
				cardId = latest.cardId,
				battleType = card.battleType, cardType = card.cardType, race = card.race,
				cost = card.cost, name = card.name,
				chargeCost = card.chargeCost,
				corrupted = isCorrupted(card),
				atk  = (card.cardType=="creature") and card.atk or nil,
				hp   = (card.cardType=="creature") and card.hp or nil,
				abilityName = abilName, abilityText = abilText,
			})
			bigCard.AttackEmblem.Visible = (card.cardType == "creature")
			bigCard.HealthEmblem.Visible = (card.cardType == "creature")
			end
	else
		cardVis.updateCardFrame(bigCard, {battleType="NEUTRAL", name="Empty", dim=0.85})
		bigCard.AttackEmblem.Visible = false
		bigCard.HealthEmblem.Visible = false
		bigCard.CostBadge.Visible = false
	end

	for _,c in ipairs(historyScroll:GetChildren()) do
		if not c:IsA("UIListLayout") then c:Destroy() end
	end
	for i=2, math.min(#(discardHistory or {}), 10) do
		local entry = discardHistory[i]
		local card = cardData.Cards[entry.cardId]
		local name = card and card.name or entry.cardId
		local bt   = card and card.battleType or "NEUTRAL"

		local row = Instance.new("Frame", historyScroll)
		row.Size = UDim2.new(1,0,0,22)
		row.BackgroundTransparency = 1; row.BorderSizePixel = 0; row.LayoutOrder = i

		local sw = Instance.new("Frame", row)
		sw.Size = UDim2.new(0,8,0,8); sw.Position = UDim2.new(0,2, 0.5,-4)
		sw.BackgroundColor3 = TC_type[bt] or TC_type.NEUTRAL
		sw.BorderSizePixel = 0; cardVis.rnd(sw, 2)

		local nameL = Instance.new("TextLabel", row)
		nameL.Size = UDim2.new(1,-36, 1,0); nameL.Position = UDim2.new(0,14, 0,0)
		nameL.BackgroundTransparency = 1; nameL.Font = Enum.Font.Gotham; nameL.TextSize = 9
		nameL.TextColor3 = Color3.fromRGB(200,200,215)
		nameL.TextXAlignment = Enum.TextXAlignment.Left
		nameL.TextTruncate = Enum.TextTruncate.AtEnd
		nameL.Text = name

		local whoL = Instance.new("TextLabel", row)
		whoL.Size = UDim2.new(0,28, 1,0); whoL.Position = UDim2.new(1,-30, 0,0)
		whoL.BackgroundTransparency = 1; whoL.Font = Enum.Font.GothamBold; whoL.TextSize = 8
		whoL.TextColor3 = (entry.who=="player") and Color3.fromRGB(100,200,100) or Color3.fromRGB(200,100,100)
		whoL.TextXAlignment = Enum.TextXAlignment.Right
		whoL.Text = (entry.who=="player") and "You" or "Foe"
	end
end

function GraveLogPanel.getFrame()
	return panel
end

local overlayFrame, overlayScrim
local origParent, origPos, origSize, origAnchor

function GraveLogPanel.showOverlay(mobileRoot)
	if not overlayFrame then
		origParent = panel.Parent
		origPos    = panel.Position
		origSize   = panel.Size
		origAnchor = panel.AnchorPoint

		overlayScrim = Instance.new("TextButton", mobileRoot)
		overlayScrim.Name = "GraveScrim"
		overlayScrim.Size = UDim2.new(1,0,1,0)
		overlayScrim.BackgroundColor3 = Color3.fromRGB(0,0,0)
		overlayScrim.BackgroundTransparency = 0.4
		overlayScrim.BorderSizePixel = 0
		overlayScrim.ZIndex = 19
		overlayScrim.Text = ""
		overlayScrim.InputBegan:Connect(function(inp)
			if inp.UserInputType == Enum.UserInputType.Touch then
				GraveLogPanel.hideOverlay()
			end
		end)

		overlayFrame = Instance.new("Frame", mobileRoot)
		overlayFrame.Name = "GraveOverlay"
		overlayFrame.Size = UDim2.new(0.85,0, 0.72,0)
		overlayFrame.AnchorPoint = Vector2.new(0.5, 0.5)
		overlayFrame.Position = UDim2.new(0.5,0, 0.46,0)
		overlayFrame.BackgroundTransparency = 1
		overlayFrame.BorderSizePixel = 0
		overlayFrame.ZIndex = 20

		panel.Parent    = overlayFrame
		panel.AnchorPoint = Vector2.new(0, 0)
		panel.Position  = UDim2.new(0,0, 0,0)
		panel.Size      = UDim2.new(1,0, 1,0)
	end
	overlayFrame.Visible = true
	overlayScrim.Visible = true
end

function GraveLogPanel.hideOverlay()
	if overlayFrame then overlayFrame.Visible = false end
	if overlayScrim then overlayScrim.Visible = false end
end

function GraveLogPanel.detachFromMobile()
	if not origParent then return end
	-- Restore panel before destroying overlayFrame or it gets destroyed with it
	panel.Parent    = origParent
	panel.AnchorPoint = origAnchor
	panel.Position  = origPos
	panel.Size      = origSize
	if overlayFrame then overlayFrame:Destroy(); overlayFrame = nil end
	if overlayScrim then overlayScrim:Destroy(); overlayScrim = nil end
	origParent = nil
end

return GraveLogPanel
