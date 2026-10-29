-- ── CardVisuals ───────────────────────────────────────────────────────────────
-- Shared card-rendering primitives: the unified card frame (buildCardFrame /
-- updateCardFrame, v0.6 artwork-forward layout), the card-back visual (mkBack),
-- archetype/stat color & icon constants, and the per-mode card size table.
-- Extracted from BattleUIController (Phase 0) with zero behavior change.

local TweenService = game:GetService("TweenService")
local AssetIds = require(game:GetService("ReplicatedStorage"):WaitForChild("Modules"):WaitForChild("AssetIds"))

local CardVisuals = {}

-- ── Card sizes (Desktop / Mobile, keyed by `sm` = isSmallScreen) ──────────────
CardVisuals.Sizes = {
	[true]  = {BW=80, BH=108, HW=112, HH=152, DW=70, DH=95},
	[false] = {BW=96, BH=130, HW=132, HH=178, DW=86, DH=116},
}

local ChargeConfig = require(game:GetService("ReplicatedStorage"):WaitForChild("Modules"):WaitForChild("ChargeConfig"))
local TC_type = ChargeConfig.Colors
CardVisuals.TC_type = TC_type

local function typeGradient(c)
	return c:Lerp(Color3.new(1,1,1), 0.15), c:Lerp(Color3.new(0,0,0), 0.15)
end

local ARCHETYPE_BG           = AssetIds.ArchetypeBG
local CARD_ART               = AssetIds.CardArt
local SPELL_ART_PLACEHOLDER  = AssetIds.SpellArtPlaceholder
local ICON_ATK               = AssetIds.Icons.ATK
local ICON_HP                = AssetIds.Icons.HP
local ICON_ENERGY            = AssetIds.Icons.ENERGY
local CHARGE_EMBLEMS         = AssetIds.ChargeEmblems
local STAT_WHITE             = Color3.fromRGB(255, 255, 255)
local STAT_BUFF              = Color3.fromRGB(110, 235, 120)
local STAT_DEBUFF            = Color3.fromRGB(255, 95, 95)
CardVisuals.ICON_ATK, CardVisuals.ICON_HP, CardVisuals.ICON_ENERGY = ICON_ATK, ICON_HP, ICON_ENERGY
CardVisuals.STAT_WHITE, CardVisuals.STAT_BUFF, CardVisuals.STAT_DEBUFF = STAT_WHITE, STAT_BUFF, STAT_DEBUFF

local function rnd(f,r) Instance.new("UICorner",f).CornerRadius=UDim.new(0,r or 8) end
local function pill(f) Instance.new("UICorner",f).CornerRadius=UDim.new(1,0) end
CardVisuals.rnd, CardVisuals.pill = rnd, pill

local function wrapAbility(text, maxChars)
	local out = {}
	for para in (tostring(text) .. "\n"):gmatch("(.-)\n") do
		local line, len = "", 0
		for word in para:gmatch("%S+") do
			local vis = #(word:gsub("</?b>", ""))
			if len > 0 and len + 1 + vis > maxChars then
				out[#out+1] = line; line, len = word, vis
			elseif len > 0 then
				line = line .. " " .. word; len = len + 1 + vis
			else
				line, len = word, vis
			end
		end
		out[#out+1] = line
	end
	return table.concat(out, "\n")
end

-- ── Unified card frame (v0.6 — artwork-forward) ──────────────────────────────
local SHIELD_ICON = utf8.char(0x1F6E1)
local STEALTH_ICON = utf8.char(0x2601)
local BASE_ABILITY_TEXT_SIZE = 10
CardVisuals.BASE_ABILITY_TEXT_SIZE = BASE_ABILITY_TEXT_SIZE

local function buildCardFrame(w, h, mode)
	local f = Instance.new("Frame")
	f.Name = "CardFrame"
	f.Size = UDim2.new(0, w, 0, h)
	f.BackgroundTransparency = 1
	f.BorderSizePixel = 0
	f.ClipsDescendants = false
	f:SetAttribute("CardMode", mode)

	local artPct = 0.62
	local cardScale = w / 132

	local body = Instance.new("Frame", f)
	body.Name = "Body"
	body.Size = UDim2.new(1, 0, 1, 0)
	body.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
	body.BorderSizePixel = 0
	body.ClipsDescendants = true
	rnd(body, math.floor(w * 0.04))

	local bg = Instance.new("ImageLabel", body)
	bg.Name = "Background"
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundTransparency = 1
	bg.ScaleType = Enum.ScaleType.Crop
	bg.ZIndex = 1
	bg.Image = ARCHETYPE_BG.NEUTRAL
	rnd(bg, math.floor(w * 0.04))

	if mode ~= "compact" then
		local circle = Instance.new("Frame", body)
		circle.Name = "CircleArt"
		circle.AnchorPoint = Vector2.new(0.5, 0)
		circle.Position = UDim2.new(0.5, 0, 0.04, 0)
		circle.Size = UDim2.new(0.84, 0, 0.84, 0)
		circle.SizeConstraint = Enum.SizeConstraint.RelativeXX
		circle.BackgroundTransparency = 1
		circle.BorderSizePixel = 0
		circle.ClipsDescendants = true
		circle.ZIndex = 1
		circle.Visible = false
		Instance.new("UICorner", circle).CornerRadius = UDim.new(0.5, 0)
		local cArt = Instance.new("ImageLabel", circle)
		cArt.Name = "Art"
		cArt.Size = UDim2.fromScale(1, 1)
		cArt.BackgroundTransparency = 1
		cArt.ScaleType = Enum.ScaleType.Crop
		cArt.ZIndex = 1
		Instance.new("UICorner", cArt).CornerRadius = UDim.new(0.5, 0)
		local cRing = Instance.new("UIStroke", circle)
		cRing.Name = "Ring"
		cRing.Thickness = 4
		cRing.Color = Color3.fromRGB(65, 65, 90)
	end

	local taunt = Instance.new("TextLabel", body)
	taunt.Name = "TauntOverlay"
	taunt.AnchorPoint = Vector2.new(0.5, 0.5)
	taunt.Position = UDim2.new(0.5, 0, artPct/2, 0)
	taunt.Size = UDim2.new(0.4, 0, 0.4, 0)
	taunt.SizeConstraint = Enum.SizeConstraint.RelativeXX
	taunt.BackgroundTransparency = 1
	taunt.Font = Enum.Font.GothamBold
	taunt.TextScaled = true
	taunt.Text = SHIELD_ICON
	taunt.TextColor3 = Color3.fromRGB(255, 255, 255)
	taunt.TextTransparency = 0.45
	taunt.ZIndex = 2
	taunt.Visible = false

	local stealth = Instance.new("TextLabel", body)
	stealth.Name = "StealthOverlay"
	stealth.AnchorPoint = Vector2.new(0.5, 0.5)
	stealth.Position = UDim2.new(0.5, 0, artPct/2, 0)
	stealth.Size = UDim2.new(0.52, 0, 0.52, 0)
	stealth.SizeConstraint = Enum.SizeConstraint.RelativeXX
	stealth.BackgroundTransparency = 1
	stealth.Font = Enum.Font.GothamBold
	stealth.TextScaled = true
	stealth.Text = STEALTH_ICON
	stealth.TextColor3 = Color3.fromRGB(210, 235, 255)
	stealth.TextStrokeColor3 = Color3.fromRGB(25, 40, 65)
	stealth.TextStrokeTransparency = 0.15
	stealth.TextTransparency = 0.18
	stealth.ZIndex = 3
	stealth.Visible = false

	local shatterDisabled = Instance.new("TextLabel", body)
	shatterDisabled.Name = "ShatterDisabledBadge"
	shatterDisabled.AnchorPoint = Vector2.new(1, 0)
	shatterDisabled.Position = UDim2.new(0.96, 0, 0.08, 0)
	shatterDisabled.Size = UDim2.new(0.2, 0, 0.14, 0)
	shatterDisabled.SizeConstraint = Enum.SizeConstraint.RelativeXX
	shatterDisabled.BackgroundColor3 = Color3.fromRGB(185, 40, 48)
	shatterDisabled.BackgroundTransparency = 0.05
	shatterDisabled.BorderSizePixel = 0
	shatterDisabled.Font = Enum.Font.FredokaOne
	shatterDisabled.TextScaled = true
	shatterDisabled.Text = "X"
	shatterDisabled.TextColor3 = Color3.fromRGB(255, 255, 255)
	shatterDisabled.TextStrokeColor3 = Color3.fromRGB(40, 0, 0)
	shatterDisabled.TextStrokeTransparency = 0
	shatterDisabled.ZIndex = 7
	shatterDisabled.Visible = false
	rnd(shatterDisabled, 5)

	if mode ~= "compact" then
		local desc = Instance.new("Frame", body)
		desc.Name = "DescPanel"
		desc.Position = UDim2.new(0.04, 0, artPct, 0)
		desc.Size = UDim2.new(0.92, 0, 0.34, 0)
		desc.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		desc.BackgroundTransparency = 0.2
		desc.BorderSizePixel = 0
		desc.ZIndex = 2
		rnd(desc, math.max(1, math.floor(h * 0.34 * 0.06)))
		local descGrad = Instance.new("UIGradient", desc)
		descGrad.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(232, 232, 236))
		descGrad.Rotation = 90
		local descStroke = Instance.new("UIStroke", desc)
		descStroke.Name = "DescStroke"
		descStroke.Color = Color3.fromRGB(20, 20, 20)
		descStroke.Thickness = 2
		descStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border

		local abilText = Instance.new("TextLabel", desc)
		abilText.Name = "AbilityText"
		abilText.Size = UDim2.new(1, -6*cardScale, 1, -6*cardScale)
		abilText.Position = UDim2.new(0, 3*cardScale, 0, 3*cardScale)
		abilText.BackgroundTransparency = 1
		abilText.Font = Enum.Font.Gotham
		abilText.TextWrapped = true
		abilText.RichText = true
		abilText.TextSize = BASE_ABILITY_TEXT_SIZE * cardScale
		abilText.TextColor3 = Color3.fromRGB(50, 50, 60)
		abilText.TextXAlignment = Enum.TextXAlignment.Center
		abilText.TextYAlignment = Enum.TextYAlignment.Top
		abilText.Text = ""
		abilText.ZIndex = 3
	end

	local fStroke = Instance.new("UIStroke", f)
	fStroke.Thickness = 4
	fStroke.Color = Color3.fromRGB(65, 65, 90)
	fStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	rnd(f, math.floor(w * 0.04))

	if mode ~= "compact" then
		local nameH = 0.08
		local nameGap = 0.015
		local nameCenterY = artPct - nameGap - nameH/2

		local nameShadow = Instance.new("TextLabel")
		nameShadow.Name = "NameBarShadow"
		nameShadow.AnchorPoint = Vector2.new(0.5, 0.5)
		nameShadow.Position = UDim2.new(0.51, 0, nameCenterY + 0.01, 0)
		nameShadow.Size = UDim2.new(0.80, 0, nameH, 0)
		nameShadow.BackgroundTransparency = 1
		nameShadow.Font = Enum.Font.FredokaOne
		nameShadow.TextScaled = true
		nameShadow.TextColor3 = Color3.new(0, 0, 0)
		nameShadow.TextTransparency = 0.5
		nameShadow.Text = ""
		nameShadow.ZIndex = 3
		nameShadow.Parent = f

		local nameBar = Instance.new("TextLabel")
		nameBar.Name = "NameBar"
		nameBar.AnchorPoint = Vector2.new(0.5, 0.5)
		nameBar.Position = UDim2.new(0.5, 0, nameCenterY, 0)
		nameBar.Size = UDim2.new(0.80, 0, nameH, 0)
		nameBar.BackgroundTransparency = 1
		nameBar.Font = Enum.Font.FredokaOne
		nameBar.TextScaled = true
		nameBar.TextColor3 = Color3.new(1, 1, 1)
		nameBar.Text = ""
		nameBar.ZIndex = 4
		nameBar.Parent = f
		local nbStroke = Instance.new("UIStroke", nameBar)
		nbStroke.Color = Color3.fromRGB(20, 30, 70)
		nbStroke.Thickness = 1.25
	end

	if mode ~= "compact" then
		local typeBadge = Instance.new("Frame", f)
		typeBadge.Name = "TypeBadge"
		typeBadge.AnchorPoint = Vector2.new(0.5, 0.5)
		typeBadge.Position = UDim2.new(0.5, 0, 0.985, 0)
		typeBadge.Size = UDim2.new(0.34, 0, 0.075, 0)
		typeBadge.BackgroundTransparency = 1
		typeBadge.ZIndex = 5
		local typeFill = Instance.new("Frame", typeBadge)
		typeFill.Name = "Fill"
		typeFill.Size = UDim2.new(1, 0, 1, 0)
		typeFill.BorderSizePixel = 0
		typeFill.ZIndex = 5
		rnd(typeFill, 5)
		Instance.new("UIGradient", typeFill).Rotation = 90
		local typeStroke = Instance.new("UIStroke", typeFill)
		typeStroke.Name = "TypeStroke"
		typeStroke.Thickness = 1
		typeStroke.Color = Color3.new(1, 1, 1)
		local typeLbl = Instance.new("TextLabel", typeBadge)
		typeLbl.Name = "Label"
		typeLbl.Size = UDim2.new(1, 0, 1, 0)
		typeLbl.BackgroundTransparency = 1
		typeLbl.ZIndex = 6
		typeLbl.Font = Enum.Font.FredokaOne
		typeLbl.TextScaled = true
		typeLbl.TextColor3 = STAT_WHITE
		typeLbl.Text = ""
		local typePad = Instance.new("UIPadding", typeLbl)
		typePad.PaddingLeft = UDim.new(0, 4)
		typePad.PaddingRight = UDim.new(0, 4)
	end

	-- Stat cluster: Energy / Attack / Health stacked along the upper-right edge.
	local EMBLEM_X, ENERGY_SIZE, STAT_SIZE
	if mode == "compact" then
		EMBLEM_X    = 0.03
		ENERGY_SIZE = 0.2
		STAT_SIZE   = 0.2
	else
		EMBLEM_X    = -0.05
		ENERGY_SIZE = 0.15
		STAT_SIZE   = 0.15
	end
	local STACK_TOP   = 0.03
	local EMBLEM_GAP  = 0.03
	local aspect  = h / w
	local energyH = ENERGY_SIZE / aspect
	local statH   = STAT_SIZE / aspect

	local energyY, atkY, hpY
	if mode == "compact" then
		energyY = STACK_TOP
		atkY = STACK_TOP
		hpY = atkY + statH + EMBLEM_GAP
	else
		energyY = STACK_TOP
		atkY = STACK_TOP + energyH + EMBLEM_GAP
		hpY = atkY + statH + EMBLEM_GAP
	end

	-- Store layout constants for runtime badge repositioning
	f:SetAttribute("EMBLEM_X",    EMBLEM_X)
	f:SetAttribute("ENERGY_SIZE", ENERGY_SIZE)
	f:SetAttribute("ENERGY_Y",    energyY)

	local cost = Instance.new("Frame", f)
	cost.Name = "CostBadge"
	cost.AnchorPoint = Vector2.new(0, 0)
	cost.Position = UDim2.new(EMBLEM_X, 0, energyY, 0)
	cost.Size = UDim2.new(ENERGY_SIZE, 0, ENERGY_SIZE, 0)
	cost.SizeConstraint = Enum.SizeConstraint.RelativeXX
	cost.BackgroundTransparency = 1
	cost.BorderSizePixel = 0
	cost.ZIndex = 5
	local costIcon = Instance.new("ImageLabel", cost)
	costIcon.Name = "Icon"
	costIcon.AnchorPoint = Vector2.new(0.5, 0.5)
	costIcon.Position = UDim2.new(0.5, 0, 0.6, 0)
	costIcon.Size = UDim2.new(1.56, 0, 1.56, 0)
	costIcon.SizeConstraint = Enum.SizeConstraint.RelativeXX
	costIcon.BackgroundTransparency = 1
	costIcon.ScaleType = Enum.ScaleType.Fit
	costIcon.ZIndex = 5
	costIcon.Image = ICON_ENERGY
	local costLbl = Instance.new("TextLabel", cost)
	costLbl.Name = "Value"
	costLbl.AnchorPoint = Vector2.new(0.5, 0.5)
	costLbl.Position = UDim2.new(0.44, 0, 0.5, 0)
	costLbl.Size = UDim2.new(1.89, 0, 1.116, 0)
	costLbl.SizeConstraint = Enum.SizeConstraint.RelativeXX
	costLbl.BackgroundTransparency = 1
	costLbl.Font = Enum.Font.FredokaOne
	costLbl.TextScaled = true
	costLbl.TextColor3 = Color3.fromRGB(255, 224, 70)
	costLbl.TextStrokeColor3 = Color3.fromRGB(20, 20, 30)
	costLbl.TextStrokeTransparency = 0
	costLbl.Text = ""
	costLbl.ZIndex = 6

	-- ChargeCostBadge: sits right of CostBadge (hybrid) or at same pos (pure-charge).
	-- Repositioned at runtime in updateCardFrame based on cost model.
	local chargeCostBadge = Instance.new("Frame", f)
	chargeCostBadge.Name = "ChargeCostBadge"
	chargeCostBadge.AnchorPoint = Vector2.new(0, 0)
	chargeCostBadge.Position = UDim2.new(EMBLEM_X + ENERGY_SIZE + 0.01, 0, energyY, 0)
	chargeCostBadge.Size = UDim2.new(ENERGY_SIZE, 0, ENERGY_SIZE, 0)
	chargeCostBadge.SizeConstraint = Enum.SizeConstraint.RelativeXX
	chargeCostBadge.BackgroundTransparency = 1
	chargeCostBadge.BorderSizePixel = 0
	chargeCostBadge.ZIndex = 5
	chargeCostBadge.Visible = false
	local chargeIcon = Instance.new("ImageLabel", chargeCostBadge)
	chargeIcon.Name = "Icon"
	chargeIcon.AnchorPoint = Vector2.new(0.5, 0.5)
	chargeIcon.Position = UDim2.new(0.5, 0, 0.6, 0)
	chargeIcon.Size = UDim2.new(1.56, 0, 1.56, 0)
	chargeIcon.SizeConstraint = Enum.SizeConstraint.RelativeXX
	chargeIcon.BackgroundTransparency = 1
	chargeIcon.ScaleType = Enum.ScaleType.Fit
	chargeIcon.ZIndex = 5
	chargeIcon.Image = ""
	local chargeLbl = Instance.new("TextLabel", chargeCostBadge)
	chargeLbl.Name = "Value"
	chargeLbl.AnchorPoint = Vector2.new(0.5, 0.5)
	chargeLbl.Position = UDim2.new(0.44, 0, 0.5, 0)
	chargeLbl.Size = UDim2.new(1.89, 0, 1.116, 0)
	chargeLbl.SizeConstraint = Enum.SizeConstraint.RelativeXX
	chargeLbl.BackgroundTransparency = 1
	chargeLbl.Font = Enum.Font.FredokaOne
	chargeLbl.TextScaled = true
	chargeLbl.TextColor3 = Color3.fromRGB(255, 224, 70)
	chargeLbl.TextStrokeColor3 = Color3.fromRGB(20, 20, 30)
	chargeLbl.TextStrokeTransparency = 0
	chargeLbl.Text = ""
	chargeLbl.ZIndex = 6

	local atkEmblem = Instance.new("Frame", f)
	atkEmblem.Name = "AttackEmblem"
	atkEmblem.AnchorPoint = Vector2.new(0, 0)
	atkEmblem.Position = UDim2.new(EMBLEM_X, 0, atkY, 0)
	atkEmblem.Size = UDim2.new(STAT_SIZE, 0, STAT_SIZE, 0)
	atkEmblem.SizeConstraint = Enum.SizeConstraint.RelativeXX
	atkEmblem.BackgroundTransparency = 1
	atkEmblem.BorderSizePixel = 0
	atkEmblem.ZIndex = 5
	local atkIcon = Instance.new("ImageLabel", atkEmblem)
	atkIcon.Name = "Icon"
	atkIcon.AnchorPoint = Vector2.new(0.5, 0.5)
	atkIcon.Position = UDim2.new(0.5, 0, 0.6, 0)
	atkIcon.Size = UDim2.new(1.56, 0, 1.56, 0)
	atkIcon.SizeConstraint = Enum.SizeConstraint.RelativeXX
	atkIcon.BackgroundTransparency = 1
	atkIcon.ScaleType = Enum.ScaleType.Fit
	atkIcon.ZIndex = 5
	atkIcon.Image = ICON_ATK
	local atkLbl = Instance.new("TextLabel", atkEmblem)
	atkLbl.Name = "Value"
	atkLbl.AnchorPoint = Vector2.new(0.5, 0.5)
	atkLbl.Position = UDim2.new(0.44, 0, 0.5, 0)
	atkLbl.Size = UDim2.new(1.89, 0, 1.116, 0)
	atkLbl.SizeConstraint = Enum.SizeConstraint.RelativeXX
	atkLbl.BackgroundTransparency = 1
	atkLbl.Font = Enum.Font.FredokaOne
	atkLbl.TextScaled = true
	atkLbl.TextColor3 = Color3.fromRGB(255, 255, 255)
	atkLbl.TextStrokeColor3 = Color3.fromRGB(20, 20, 30)
	atkLbl.TextStrokeTransparency = 0
	atkLbl.Text = ""
	atkLbl.ZIndex = 6

	local hpEmblem = Instance.new("Frame", f)
	hpEmblem.Name = "HealthEmblem"
	hpEmblem.AnchorPoint = Vector2.new(0, 0)
	hpEmblem.Position = UDim2.new(EMBLEM_X, 0, hpY, 0)
	hpEmblem.Size = UDim2.new(STAT_SIZE, 0, STAT_SIZE, 0)
	hpEmblem.SizeConstraint = Enum.SizeConstraint.RelativeXX
	hpEmblem.BackgroundTransparency = 1
	hpEmblem.BorderSizePixel = 0
	hpEmblem.ZIndex = 5
	local hpIcon = Instance.new("ImageLabel", hpEmblem)
	hpIcon.Name = "Icon"
	hpIcon.AnchorPoint = Vector2.new(0.5, 0.5)
	hpIcon.Position = UDim2.new(0.5, 0, 0.6, 0)
	hpIcon.Size = UDim2.new(1.56, 0, 1.56, 0)
	hpIcon.SizeConstraint = Enum.SizeConstraint.RelativeXX
	hpIcon.BackgroundTransparency = 1
	hpIcon.ScaleType = Enum.ScaleType.Fit
	hpIcon.ZIndex = 5
	hpIcon.Image = ICON_HP
	local hpLbl = Instance.new("TextLabel", hpEmblem)
	hpLbl.Name = "Value"
	hpLbl.AnchorPoint = Vector2.new(0.5, 0.5)
	hpLbl.Position = UDim2.new(0.44, 0, 0.5, 0)
	hpLbl.Size = UDim2.new(1.89, 0, 1.116, 0)
	hpLbl.SizeConstraint = Enum.SizeConstraint.RelativeXX
	hpLbl.BackgroundTransparency = 1
	hpLbl.Font = Enum.Font.FredokaOne
	hpLbl.TextScaled = true
	hpLbl.TextColor3 = Color3.fromRGB(255, 255, 255)
	hpLbl.TextStrokeColor3 = Color3.fromRGB(20, 20, 30)
	hpLbl.TextStrokeTransparency = 0
	hpLbl.Text = ""
	hpLbl.ZIndex = 6

	return f
end
CardVisuals.buildCardFrame = buildCardFrame

local function stopSickLoop(f)
	f:SetAttribute("SickRunning", false)
	local holder = f:FindFirstChild("ZzzHolder")
	if holder then holder:Destroy() end
end
CardVisuals.stopSickLoop = stopSickLoop

local function startSickLoop(f)
	if f:GetAttribute("SickRunning") then return end
	f:SetAttribute("SickRunning", true)
	local holder = Instance.new("Frame")
	holder.Name = "ZzzHolder"
	holder.Size = UDim2.new(1, 0, 1, 0)
	holder.BackgroundTransparency = 1
	holder.ZIndex = 6
	holder.Parent = f
	task.spawn(function()
		while f:GetAttribute("SickRunning") and f.Parent do
			local z = Instance.new("TextLabel")
			z.Name = "Z"
			z.Text = "Z"
			z.Font = Enum.Font.GothamBold
			z.BackgroundTransparency = 1
			z.TextColor3 = Color3.fromRGB(255, 255, 255)
			z.TextScaled = true
			z.SizeConstraint = Enum.SizeConstraint.RelativeXX
			z.Size = UDim2.new(0.18, 0, 0.18, 0)
			z.AnchorPoint = Vector2.new(0.5, 0.5)
			z.Position = UDim2.new(0.85, 0, 0.05, 0)
			z.ZIndex = 6
			z.Parent = holder
			local tw = TweenService:Create(z, TweenInfo.new(0.9, Enum.EasingStyle.Linear), {
				Position = UDim2.new(0.85, 0, -0.25, 0),
				TextTransparency = 1,
			})
			tw:Play()
			task.delay(0.9, function() z:Destroy() end)
			task.wait(0.45)
		end
	end)
end
CardVisuals.startSickLoop = startSickLoop

-- opts keys:
--   battleType, cardType, cardId, cost, chargeCost, corrupted,
--   name, race, atk, hp, abilityName, abilityText, dim, status,
--   costColor, chargeCostColor, atkColor, hpColor
local function updateCardFrame(f, opts)
	local mode = f:GetAttribute("CardMode")
	local bt = opts.battleType or "NEUTRAL"
	local body = f.Body
	local artImage = CARD_ART[opts.cardId] or ARCHETYPE_BG[bt] or ARCHETYPE_BG.NEUTRAL
	local circle = (mode ~= "compact") and body:FindFirstChild("CircleArt")
	if circle and opts.cardType == "spell" then
		circle.Visible = true
		circle.Art.Image = CARD_ART[opts.cardId] or SPELL_ART_PLACEHOLDER
		circle.Ring.Color = TC_type[bt] or TC_type.NEUTRAL
		body.Background.Image = ARCHETYPE_BG[bt] or ARCHETYPE_BG.NEUTRAL
	else
		if circle then circle.Visible = false end
		body.Background.Image = artImage
	end

	if mode ~= "compact" then
		local mainColor = TC_type[bt] or TC_type.NEUTRAL
		local typeBadge = f.TypeBadge
		local fill = typeBadge.Fill
		fill.UIGradient.Color = ColorSequence.new(typeGradient(mainColor))
		typeBadge.Label.Text = (opts.cardType == "spell") and "SPELL" or (opts.race or bt)
		local descStroke = body.DescPanel:FindFirstChild("DescStroke")
		if descStroke then descStroke.Color = mainColor end
		local typeStroke = fill:FindFirstChild("TypeStroke")
		if typeStroke then typeStroke.Color = mainColor:Lerp(Color3.new(0,0,0), 0.4) end

		local abilLabel = opts.abilityName or ""
		local abilBody = opts.abilityText or ""
		local abilDisplay
		if abilLabel ~= "" and abilBody ~= "" then
			abilDisplay = "<b>"..abilLabel..":</b>\n"..abilBody
		elseif abilLabel ~= "" then
			abilDisplay = "<b>"..abilLabel.."</b>"
		else
			abilDisplay = abilBody
		end
		body.DescPanel.AbilityText.Text = wrapAbility(abilDisplay, 20)

		-- CORRUPTED: prepend skull symbol to the card name (same font/color/size)
		local displayName = opts.name or ""
		if opts.corrupted then displayName = "\xE2\x98\xA0 " .. displayName end
		f.NameBar.Text = displayName
		f.NameBarShadow.Text = displayName
	end

	-- Cost badges: CostBadge (Energy) and ChargeCostBadge (Charge emblem)
	local cc = opts.chargeCost
	local isPureCharge = cc ~= nil and (opts.cost == nil or opts.cost == 0)

	-- Energy (CostBadge): hidden for pure-charge cards
	f.CostBadge.Visible = opts.cost ~= nil and not isPureCharge
	if opts.cost ~= nil and not isPureCharge then
		f.CostBadge.Value.Text = tostring(opts.cost)
		f.CostBadge.Value.TextColor3 = opts.costColor or Color3.fromRGB(255, 224, 70)
	end

	-- Charge (ChargeCostBadge): shown for hybrid and pure-charge
	local chargeBadge = f:FindFirstChild("ChargeCostBadge")
	if chargeBadge then
		if cc then
			chargeBadge.Visible = true
			chargeBadge.Icon.Image = (CHARGE_EMBLEMS and CHARGE_EMBLEMS[cc.battleType]) or ""
			chargeBadge.Value.Text = tostring(cc.amount)
			chargeBadge.Value.TextColor3 = opts.chargeCostColor or Color3.fromRGB(255, 224, 70)
			-- Reposition: pure-charge uses energy slot; hybrid sits to the right
			local emX  = f:GetAttribute("EMBLEM_X")    or -0.05
			local emSz = f:GetAttribute("ENERGY_SIZE")  or 0.15
			local emY  = f:GetAttribute("ENERGY_Y")     or 0.03
			if isPureCharge then
				chargeBadge.Position = UDim2.new(emX, 0, emY, 0)
			else
				chargeBadge.Position = UDim2.new(emX + emSz + 0.01, 0, emY, 0)
			end
		else
			chargeBadge.Visible = false
		end
	end

	f.AttackEmblem.Visible = opts.atk ~= nil
	if opts.atk ~= nil then
		f.AttackEmblem.Value.Text = tostring(opts.atk)
		f.AttackEmblem.Value.TextColor3 = opts.atkColor or STAT_WHITE
	end

	f.HealthEmblem.Visible = opts.hp ~= nil
	if opts.hp ~= nil then
		f.HealthEmblem.Value.Text = tostring(opts.hp)
		f.HealthEmblem.Value.TextColor3 = opts.hpColor or STAT_WHITE
	end

	body.Background.ImageTransparency = opts.dim or 0
	if circle and circle.Visible then circle.Art.ImageTransparency = opts.dim or 0 end

	local status = opts.status or {}
	body.TauntOverlay.Visible = status.taunt == true
	body.StealthOverlay.Visible = status.stealth == true
	body.ShatterDisabledBadge.Visible = status.shatterDisabled == true

	if status.sick then startSickLoop(f) else stopSickLoop(f) end
end
CardVisuals.updateCardFrame = updateCardFrame

-- ── Enemy hand backs / deck pile (card back visual) ──────────────────────────
local function mkBack(w,h)
	w=w or 132; h=h or 178
	local f=Instance.new("Frame"); f.Size=UDim2.new(0,w,0,h)
	f.BackgroundColor3=Color3.fromRGB(92,62,38); f.BorderSizePixel=0; rnd(f,math.floor(w*0.08))
	local stk=Instance.new("UIStroke",f); stk.Color=Color3.fromRGB(58,38,22); stk.Thickness=1.5
	local texture=Instance.new("ImageLabel",f)
	texture.Name="Texture"
	texture.Size=UDim2.fromScale(1,1)
	texture.BackgroundTransparency=1
	texture.ScaleType=Enum.ScaleType.Crop
	texture.Image=AssetIds.CardBackTexture
	rnd(texture,math.floor(w*0.08))
	local inner=Instance.new("Frame",f)
	inner.Size=UDim2.new(0.84,0,0.84,0); inner.Position=UDim2.new(0.08,0,0.08,0)
	inner.BackgroundTransparency=1; inner.BorderSizePixel=0; rnd(inner,math.floor(w*0.06))
	local innerStk=Instance.new("UIStroke",inner)
	innerStk.Color=Color3.new(0,0,0); innerStk.Thickness=2.5; innerStk.Transparency=0

	local gloss=Instance.new("Frame",f)
	gloss.Name="Gloss"
	gloss.Size=UDim2.fromScale(1,1)
	gloss.BackgroundColor3=Color3.new(1,1,1)
	gloss.BorderSizePixel=0
	rnd(gloss,math.floor(w*0.08))
	local glossGrad=Instance.new("UIGradient",gloss)
	glossGrad.Rotation=115
	glossGrad.Transparency=NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.32, 1),
		NumberSequenceKeypoint.new(0.5, 0.7),
		NumberSequenceKeypoint.new(0.68, 1),
		NumberSequenceKeypoint.new(1, 1),
	})
	return f
end
CardVisuals.mkBack = mkBack

return CardVisuals
