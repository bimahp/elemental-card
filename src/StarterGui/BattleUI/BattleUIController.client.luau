local Players      = game:GetService("Players")
local RS           = game:GetService("ReplicatedStorage")
local RunService   = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInput    = game:GetService("UserInputService")
local player     = Players.LocalPlayer
local Remotes    = RS:WaitForChild("Remotes")
local CardData   = require(RS:WaitForChild("Modules"):WaitForChild("CardData"))
local AssetIds   = require(RS:WaitForChild("Modules"):WaitForChild("AssetIds"))
local CardTraits = require(RS:WaitForChild("Modules"):WaitForChild("CardTraits"))
-- Crystal Core removed (Phase 3): replaced by the two-slot Charge system.

local gui   = player.PlayerGui:WaitForChild("BattleUI")
local main  = gui:WaitForChild("Main")
local bc    = main:WaitForChild("BoardContainer")
local mobileRoot   -- built by buildMobileLayout(); nil until then

local function getRow(n) return bc:FindFirstChild(n,true) end
local function getInner(n) local r=getRow(n); return r and r:FindFirstChild("Inner") end

local function showWarningToast(msg)
	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.new(0, 320, 0, 38)
	lbl.AnchorPoint = Vector2.new(0.5, 1)
	lbl.Position = UDim2.new(0.5, 0, 0.62, 0)
	lbl.BackgroundColor3 = Color3.fromRGB(30, 12, 12)
	lbl.BackgroundTransparency = 0.15
	lbl.BorderSizePixel = 0
	lbl.Font = Enum.Font.GothamBold
	lbl.TextSize = 15
	lbl.TextColor3 = Color3.fromRGB(255, 110, 80)
	lbl.Text = msg
	lbl.TextXAlignment = Enum.TextXAlignment.Center
	lbl.ZIndex = 120
	-- Parent to the always-on-top targeting overlay (ZIndex 60, sibling of the
	-- mobile root) so the toast shows on mobile too, not just behind mobileRoot.
	lbl.Parent = main.Parent:FindFirstChild("TargetingOverlay") or main
	local corner = Instance.new("UICorner", lbl); corner.CornerRadius = UDim.new(0, 8)
	local stroke = Instance.new("UIStroke", lbl)
	stroke.Color = Color3.fromRGB(180, 50, 30); stroke.Thickness = 1.5
	TweenService:Create(lbl, TweenInfo.new(0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = UDim2.new(0.5, 0, 0.58, 0),
	}):Play()
	task.delay(1.6, function()
		TweenService:Create(lbl, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			BackgroundTransparency = 1, TextTransparency = 1,
		}):Play()
		task.delay(0.45, function() lbl:Destroy() end)
	end)
end

-- Rows
local eHI = getInner("EnemyHandRow")
do
	local eHIList = eHI:FindFirstChildOfClass("UIListLayout")
	if eHIList then eHIList:Destroy() end
end
local eBI = getInner("EnemyBenchRow")   -- repurposed: all 3 enemy board slots (v0.3 board)
local pBI = getInner("PlayerBenchRow")  -- repurposed: all 3 player board slots (v0.3 board)
local hs  = (getRow("PlayerHandRow") or error("no PlayerHandRow")):FindFirstChild("HandScroll")
local deckPanel = main:WaitForChild("DeckPanel")
local abF = main:WaitForChild("ActionButtons")
local etBtn     = abF:WaitForChild("EndTurnBtn")
local forfBtn   = abF:WaitForChild("ForfeitBtn")
local post      = gui:WaitForChild("PostBattle")

-- Post-battle Result panel is handled by a small module so the main
-- BattleUIController chunk does not creep past Luau's local-register ceiling.
local Post = require(script.Parent.Modules.PostBattleController).new(player, gui, post)

local turnTimerLbl = Instance.new("TextLabel", abF)
turnTimerLbl.Name = "TurnTimerLabel"
turnTimerLbl.Size = UDim2.new(1, 0, 0, 26)
turnTimerLbl.Position = UDim2.new(0, 0, 0, 18)
turnTimerLbl.BackgroundColor3 = Color3.fromRGB(24, 24, 36)
turnTimerLbl.BackgroundTransparency = 0.08
turnTimerLbl.BorderSizePixel = 0
turnTimerLbl.Font = Enum.Font.GothamBold
turnTimerLbl.TextSize = 13
turnTimerLbl.TextColor3 = Color3.fromRGB(210, 220, 235)
turnTimerLbl.Text = "--:--"
turnTimerLbl.ZIndex = 20
Instance.new("UICorner", turnTimerLbl).CornerRadius = UDim.new(0, 6)

-- Card sizes & shared visuals
local CardVisuals = require(script.Parent.Modules.CardVisuals)
local TargetingSystem = require(script.Parent.Modules.TargetingSystem)
local UXMode = require(script.Parent.Modules.UXMode)
local CardPreviewController = require(script.Parent.Modules.CardPreviewController)
local GraveLogPanel     = require(script.Parent.Modules.GraveLogPanel)
local BattleDirector    = require(script.Parent.Modules.BattleDirector)
local EffectVisuals     = require(script.Parent.Modules.EffectVisuals)

local render     -- forward declaration; assigned below (must precede UXMode.Changed closure)
local lastState  -- set at top of render(); lets UXMode.Changed re-render after layout switch
print("[UXMode] initial mode:", UXMode.Current)
UXMode.Changed:Connect(function(newMode)
	main.Visible = (newMode == "Desktop")
	if mobileRoot then mobileRoot.Visible = (newMode == "Mobile") end
	if newMode ~= "Mobile" and collapseMobileHand then collapseMobileHand() end
	if newMode == "Desktop" then GraveLogPanel.detachFromMobile() end
	if lastState then render(lastState) end
end)

local vp = workspace.CurrentCamera.ViewportSize
local sm = vp.X < 800
local cardSz = CardVisuals.Sizes[sm]
local BW, BH = cardSz.BW, cardSz.BH
local HW, HH = cardSz.HW, cardSz.HH
local DW, DH = cardSz.DW, cardSz.DH

CardPreviewController.init({ main = main, CardVisuals = CardVisuals, HW = HW, HH = HH })

-- v0.4: 3-slot board, 3 battle types (MIGHTY/SWIFT/VITAL -- Armor/Combo/Siphon)
local BOARD_SIZE = 3

local TC_type = CardVisuals.TC_type
local ICON_ATK, ICON_HP, ICON_ENERGY = CardVisuals.ICON_ATK, CardVisuals.ICON_HP, CardVisuals.ICON_ENERGY
local STAT_WHITE, STAT_BUFF, STAT_DEBUFF = CardVisuals.STAT_WHITE, CardVisuals.STAT_BUFF, CardVisuals.STAT_DEBUFF

-- Helpers
local hidden={}
-- Guards against startCam() being called more than once per battle entry
-- (OfferMulligan calls it early to seat the camera before mulligan appears,
-- then the first post-mulligan render() calls it again via isFirstBattleRender)
-- without an intervening stopCam(). Without this flag, the second hideChar()
-- call re-snapshots the ALREADY-hidden (transparency=1) parts as if they were
-- the original values, so showChar() at battle end "restores" the character
-- to permanently invisible instead of visible.
local function hideChar()
	if #hidden > 0 then return end
	local char=player.Character; if not char then return end
	for _,p in ipairs(char:GetDescendants()) do
		if p:IsA("BasePart") then
			local arm=p.Name=="Right Arm" or p.Name=="Left Arm" or p.Name=="RightHand"
				or p.Name=="LeftHand" or p.Name=="RightLowerArm" or p.Name=="LeftLowerArm"
				or p.Name=="RightUpperArm" or p.Name=="LeftUpperArm"
			if not arm then table.insert(hidden,{p=p,v=p.LocalTransparencyModifier}); p.LocalTransparencyModifier=1 end
		end
	end
end
local function showChar()
	if #hidden == 0 then return end
	for _,e in ipairs(hidden) do if e.p and e.p.Parent then e.p.LocalTransparencyModifier=e.v end end; hidden={}
end

local camConn
local function currentOpponentSeatPosition()
	local char=player.Character
	local hum=char and char:FindFirstChildOfClass("Humanoid")
	local seat=hum and hum.SeatPart
	local chair=seat and seat.Parent
	local station=chair and chair.Parent
	if not seat or not chair or not station then return nil end
	local opponentName=chair.Name=="Chair 1" and "Chair 2" or chair.Name=="Chair 2" and "Chair 1" or nil
	local opponentChair=opponentName and station:FindFirstChild(opponentName)
	local opponentSeat=opponentChair and opponentChair:FindFirstChild("Seat")
	return opponentSeat and opponentSeat.Position or nil
end
local function startCam()
	if camConn then camConn:Disconnect(); camConn=nil end
	workspace.CurrentCamera.CameraType=Enum.CameraType.Scriptable
	local opponentSeatPosition=currentOpponentSeatPosition()
	hideChar()
	camConn=RunService.RenderStepped:Connect(function()
		local c=player.Character; if not c then return end
		local h=c:FindFirstChild("Head"); if not h then return end
		local lookPosition=opponentSeatPosition or currentOpponentSeatPosition() or h.Position+h.CFrame.LookVector*4
		workspace.CurrentCamera.CFrame=CFrame.lookAt(h.Position+Vector3.new(0,0.3,0),Vector3.new(lookPosition.X,h.Position.Y+0.3,lookPosition.Z))
	end)
end
local function stopCam()
	if camConn then camConn:Disconnect(); camConn=nil end
	workspace.CurrentCamera.CameraType=Enum.CameraType.Custom; showChar()
end

local rnd = CardVisuals.rnd
local pill = CardVisuals.pill
local function clearIn(p)
	for _,c in ipairs(p:GetChildren()) do
		if not c:IsA("UIListLayout") and not c:IsA("UIPadding") then c:Destroy() end
	end
end

-- Unified card frame -- now provided by Modules.CardVisuals
local buildCardFrame = CardVisuals.buildCardFrame
local updateCardFrame = CardVisuals.updateCardFrame
local stopSickLoop = CardVisuals.stopSickLoop
local startSickLoop = CardVisuals.startSickLoop

-- ── Board slot builder ────────────────────────────────────────────────────────

local function mkSlot(par,w,h)
	-- Wrap the card visual in a fixed-size cell so death/impact animations
	-- that tween this slot's UIScale toward 0 don't shrink the cell that
	-- `par`'s UIListLayout measures -- otherwise the other slots reflow and
	-- the dying slot visually "collapses" out of the row.
	local cell = Instance.new("Frame")
	cell.Size = UDim2.new(0,w,0,h)
	cell.BackgroundTransparency = 1
	cell.BorderSizePixel = 0
	cell.Parent = par

	local f = buildCardFrame(w, h, "compact")
	f.Size = UDim2.new(1,0,1,0)
	f.Parent = cell
	Instance.new("UIScale", f)
	local empty=Instance.new("TextLabel"); empty.Name="EmptyLabel"; empty.Parent=f
	empty.Size=UDim2.new(1,0,1,0); empty.BackgroundTransparency=1
	empty.Text="Empty"; empty.TextColor3=Color3.fromRGB(110,110,130)
	empty.Font=Enum.Font.Gotham; empty.TextScaled=true; empty.ZIndex=8
	return f
end

-- ── Hero cell builder (4th board-row cell) ────────────────────────────────────
-- A 4th visual cell appended to each board row, showing a hero portrait with
-- HP (bottom-left) and Armor (bottom-right, hidden when 0) badges. Built on the
-- same fixed-size-cell + UIScale pattern as mkSlot so impactPunch/popDamage/
-- playCardLunge work on it unchanged when the hero is a combat target.
local function mkHeroSlot(par,w,h)
	local cell = Instance.new("Frame")
	cell.Size = UDim2.new(0,w,0,h)
	cell.BackgroundTransparency = 1
	cell.BorderSizePixel = 0
	cell.Parent = par

	local f = Instance.new("Frame")
	f.Name = "HeroCard"
	f.Size = UDim2.new(1,0,1,0)
	f.BackgroundColor3 = Color3.fromRGB(40,40,56)
	f.BackgroundTransparency = 0.2
	f.BorderSizePixel = 0
	f.ClipsDescendants = true
	f.Active = true
	rnd(f, math.floor(w*0.08))
	f.Parent = cell
	Instance.new("UIScale", f)
	local stk=Instance.new("UIStroke",f); stk.Color=Color3.fromRGB(55,55,75); stk.Thickness=1

	-- Circular avatar portrait, sized to the cell width -- reads as a hero
	-- badge rather than another card (board cards are tall rounded rects).
	local portrait = Instance.new("ImageLabel", f)
	portrait.Name = "Portrait"
	portrait.AnchorPoint = Vector2.new(0.5,0)
	portrait.Position = UDim2.new(0.5,0,0.06,0)
	portrait.Size = UDim2.new(0,math.floor(w*0.86),0,math.floor(w*0.86))
	portrait.BackgroundColor3 = Color3.fromRGB(60,60,82)
	portrait.BorderSizePixel = 0
	portrait.ScaleType = Enum.ScaleType.Crop
	portrait.Image = ""
	portrait.ZIndex = 1
	pill(portrait)
	local portraitStroke=Instance.new("UIStroke",portrait); portraitStroke.Color=Color3.fromRGB(80,150,220); portraitStroke.Thickness=3

	local hpB = Instance.new("Frame", f)
	hpB.Name = "HPBadge"
	hpB.AnchorPoint = Vector2.new(0,1)
	hpB.Position = UDim2.new(0.05,0,0.97,0)
	hpB.Size = UDim2.new(0.42,0,0.14,0)
	hpB.BackgroundColor3 = Color3.fromRGB(235,235,240)
	hpB.BorderSizePixel = 0
	hpB.ZIndex = 4
	pill(hpB)
	local hpStroke=Instance.new("UIStroke",hpB); hpStroke.Color=Color3.fromRGB(120,120,130); hpStroke.Thickness=1
	local hpIcon=Instance.new("ImageLabel",hpB)
	hpIcon.Name="Icon"; hpIcon.Size=UDim2.new(0.8,0,0.8,0); hpIcon.SizeConstraint=Enum.SizeConstraint.RelativeYY
	hpIcon.Position=UDim2.new(0.05,0,0.1,0); hpIcon.BackgroundTransparency=1; hpIcon.Image=ICON_HP
	local hpLbl=Instance.new("TextLabel",hpB)
	hpLbl.Name="Value"; hpLbl.Size=UDim2.new(0.62,0,1,0); hpLbl.Position=UDim2.new(0.38,0,0,0)
	hpLbl.BackgroundTransparency=1; hpLbl.Font=Enum.Font.GothamBold; hpLbl.TextScaled=true
	hpLbl.TextColor3=Color3.fromRGB(40,40,50); hpLbl.Text=""

	local armorB = Instance.new("Frame", f)
	armorB.Name = "ArmorBadge"
	armorB.AnchorPoint = Vector2.new(1,1)
	armorB.Position = UDim2.new(0.95,0,0.97,0)
	armorB.Size = UDim2.new(0.42,0,0.14,0)
	armorB.BackgroundColor3 = Color3.fromRGB(190,200,215)
	armorB.BorderSizePixel = 0
	armorB.ZIndex = 4
	armorB.Visible = false
	pill(armorB)
	local armorStroke=Instance.new("UIStroke",armorB); armorStroke.Color=Color3.fromRGB(230,235,245); armorStroke.Thickness=1
	local armorLbl=Instance.new("TextLabel",armorB)
	armorLbl.Name="Value"; armorLbl.Size=UDim2.new(1,0,1,0)
	armorLbl.BackgroundTransparency=1; armorLbl.Font=Enum.Font.GothamBold; armorLbl.TextScaled=true
	armorLbl.TextColor3=Color3.fromRGB(40,40,55); armorLbl.Text=""

	-- Two-slot hero Charge container (right edge). Always exactly two sockets,
	-- sized on a par with the board ATK/HP stat emblems so they read at a glance.
	-- Occupied sockets show their Battle Type emblem + amount; the current slot
	-- carries a bright glow. Overlaps the portrait's right edge instead of
	-- widening the board row.
	local chargeWrap = Instance.new("Frame", f)
	chargeWrap.Name = "ChargeSlots"
	chargeWrap.AnchorPoint = Vector2.new(1, 0.5)
	chargeWrap.Position = UDim2.new(0.985, 0, 0.46, 0)
	chargeWrap.Size = UDim2.new(0.30, 0, 0.80, 0)
	chargeWrap.BackgroundTransparency = 1
	chargeWrap.BorderSizePixel = 0
	chargeWrap.ZIndex = 6
	for i = 1, 2 do
		local sock = Instance.new("Frame", chargeWrap)
		sock.Name = "Socket"..i
		-- Square sockets via RelativeXX (Y scale relative to width); socket 1 pinned
		-- to the top of the wrap, socket 2 to the bottom (proven stat-emblem trick).
		sock.AnchorPoint = Vector2.new(0.5, (i == 1) and 0 or 1)
		sock.Position = UDim2.new(0.5, 0, (i == 1) and 0 or 1, 0)
		sock.Size = UDim2.new(1, 0, 1, 0)
		sock.SizeConstraint = Enum.SizeConstraint.RelativeXX
		sock.BackgroundColor3 = Color3.fromRGB(20, 20, 28)
		sock.BackgroundTransparency = 0.2
		sock.BorderSizePixel = 0
		sock.ZIndex = 6
		pill(sock)
		Instance.new("UIScale", sock)
		local sRim = Instance.new("UIStroke", sock)
		sRim.Name = "Rim"; sRim.Color = Color3.fromRGB(80,80,100); sRim.Thickness = 2
		local emblem = Instance.new("ImageLabel", sock)
		emblem.Name = "Emblem"
		emblem.AnchorPoint = Vector2.new(0.5, 0.5)
		emblem.Position = UDim2.new(0.5, 0, 0.5, 0)
		emblem.Size = UDim2.new(1.08, 0, 1.08, 0)
		emblem.BackgroundTransparency = 1
		emblem.ScaleType = Enum.ScaleType.Fit
		emblem.Image = ""
		emblem.Visible = false
		emblem.ZIndex = 6
		local amt = Instance.new("TextLabel", sock)
		amt.Name = "Amount"
		amt.AnchorPoint = Vector2.new(0.5, 0.5)
		amt.Position = UDim2.new(0.5, 0, 0.54, 0)
		amt.Size = UDim2.new(0.64, 0, 0.64, 0)
		amt.BackgroundTransparency = 1
		amt.Font = Enum.Font.FredokaOne
		amt.TextScaled = true
		amt.TextColor3 = Color3.fromRGB(255, 255, 255)
		amt.TextStrokeColor3 = Color3.fromRGB(0, 0, 0); amt.TextStrokeTransparency = 0
		amt.Text = ""
		amt.Visible = false
		amt.ZIndex = 8
	end

	return f
end

-- Paint a hero's two Charge sockets from side state (chargeSlots + currentChargeSlot).
-- Empty sockets stay visible (dark); occupied sockets take the Battle Type color
-- and show the amount; the current slot carries a persistent bright outline.
-- Charge socket change feedback: a quick scale pop on gain/replace, a dim shrink
-- on spend. Cosmetic only -- paintChargeSlots already set the socket to its
-- authoritative final state, so a skipped or late pop never affects rules.
local function popChargeSocket(heroFrame, ev)
	local wrap = heroFrame and heroFrame:FindFirstChild("ChargeSlots")
	local sock = wrap and ev.changedSlot and wrap:FindFirstChild("Socket"..ev.changedSlot)
	local us = sock and sock:FindFirstChildOfClass("UIScale")
	if not us then return end
	local reason = ev.reason
	if reason == "destroy_slot" then
		-- Slot destroyed: slam to zero then snap back (slot is now empty).
		us.Scale = 1
		TweenService:Create(us, TweenInfo.new(0.10, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {Scale = 0}):Play()
		task.delay(0.12, function() if us and us.Parent then us.Scale = 1 end end)
		return
	elseif reason == "drain" then
		-- Partial drain: sharper shrink than a spend, then recover.
		us.Scale = 1
		TweenService:Create(us, TweenInfo.new(0.10, Enum.EasingStyle.Quad), {Scale = 0.65}):Play()
		task.delay(0.10, function()
			if us and us.Parent then
				TweenService:Create(us, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Scale = 1}):Play()
			end
		end)
	elseif reason == "board_end_turn" then
		-- Ambient board generation: gentle pulse, less dramatic than an explicit gain.
		us.Scale = 1
		TweenService:Create(us, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Scale = 1.15}):Play()
		task.delay(0.18, function()
			if us and us.Parent then
				TweenService:Create(us, TweenInfo.new(0.16, Enum.EasingStyle.Quad), {Scale = 1}):Play()
			end
		end)
	elseif reason == "spend" then
		us.Scale = 1
		TweenService:Create(us, TweenInfo.new(0.14, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Scale = 0.78}):Play()
		task.delay(0.14, function()
			if us and us.Parent then
				TweenService:Create(us, TweenInfo.new(0.18, Enum.EasingStyle.Quad), {Scale = 1}):Play()
			end
		end)
	else
		-- effect_gain or any other gain: big pop.
		us.Scale = 1
		TweenService:Create(us, TweenInfo.new(0.14, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Scale = 1.3}):Play()
		task.delay(0.14, function()
			if us and us.Parent then
				TweenService:Create(us, TweenInfo.new(0.18, Enum.EasingStyle.Quad), {Scale = 1}):Play()
			end
		end)
	end
end

local CHARGE_CURRENT_COLOR = Color3.fromRGB(255, 236, 120)
local CHARGE_RIM_COLOR = Color3.fromRGB(80, 80, 100)
local CHARGE_EMBLEMS = AssetIds.ChargeEmblems
local function paintChargeSlots(heroFrame, sideState)
	local wrap = heroFrame and heroFrame:FindFirstChild("ChargeSlots")
	if not wrap or not sideState then return end
	local slots = sideState.chargeSlots or {}
	local current = sideState.currentChargeSlot
	for i = 1, 2 do
		local sock = wrap:FindFirstChild("Socket"..i)
		if sock then
			local data = slots[i]
			local occupied = data ~= nil and data.battleType ~= nil and (data.amount or 0) > 0
			local rim = sock:FindFirstChild("Rim")
			local emblem = sock:FindFirstChild("Emblem")
			local amt = sock:FindFirstChild("Amount")
			if occupied then
				local col = TC_type[data.battleType] or TC_type.NEUTRAL
				sock.BackgroundColor3 = col:Lerp(Color3.fromRGB(0,0,0), 0.45)
				sock.BackgroundTransparency = 0
				if emblem then
					emblem.Image = CHARGE_EMBLEMS[data.battleType] or ""
					emblem.Visible = emblem.Image ~= ""
				end
				if amt then amt.Text = tostring(data.amount); amt.Visible = true end
				if rim then
					if i == current then rim.Color = CHARGE_CURRENT_COLOR; rim.Thickness = 3
					else rim.Color = col; rim.Thickness = 2 end
				end
			else
				sock.BackgroundColor3 = Color3.fromRGB(20, 20, 28)
				sock.BackgroundTransparency = 0.5
				if emblem then emblem.Visible = false end
				if amt then amt.Text = ""; amt.Visible = false end
				if rim then rim.Color = CHARGE_RIM_COLOR; rim.Thickness = 1.5 end
			end
		end
	end
end

local function fillSlot(f, m, isPlayer)
	if not m then
		f.EmptyLabel.Visible = true
		stopSickLoop(f)
		updateCardFrame(f, {battleType="NEUTRAL", name="", dim=0.85})
		local s=f:FindFirstChildOfClass("UIStroke"); if s then s.Color=Color3.fromRGB(55,55,75); s.Thickness=1 end
		local sc=f:FindFirstChildOfClass("UIScale"); if sc then sc.Scale=1 end
		return
	end
	f.EmptyLabel.Visible = false

	local stealthed=false
	local taunted=false
	local hasCharge=false
	for _,k in ipairs(m.keywords or {}) do
		if k=="stealth" or k=="stealth_until_attack" then stealthed=true end
		if k=="taunt" then taunted=true end
		if k=="charge" then hasCharge=true end
	end
	local atk=(m.atk or 0)+(m.tempAtk or 0)
	local exhausted = m.attackedThisTurn or m.summonedThisTurn

	local base = CardData.Cards[m.cardId]
	local atkColor = STAT_WHITE
	if base then
		if atk > (base.atk or 0) then atkColor = STAT_BUFF
		elseif atk < (base.atk or 0) then atkColor = STAT_DEBUFF
		end
	end
	local hpColor = STAT_WHITE
	if m.hp < m.maxHp then
		hpColor = STAT_DEBUFF
	elseif base and m.maxHp > (base.hp or m.maxHp) then
		hpColor = STAT_BUFF
	end

	updateCardFrame(f, {
		cardId = m.cardId,
		battleType = m.battleType,
		race = m.race,
		name = m.name,
		atk = atk,
		hp = m.hp,
		atkColor = atkColor,
		hpColor = hpColor,
		dim = exhausted and 0.4 or 0,
		status = {
			taunt = taunted,
			stealth = stealthed,
			sick = m.summonedThisTurn and not hasCharge,
			shatterDisabled = m.shatterDisabled == true,
		},
	})

	local s=f:FindFirstChildOfClass("UIStroke")
	if s then
		s.Color = TC_type[m.battleType] or TC_type.NEUTRAL
		s.Thickness = 2
	end
end

-- ── Build slots ───────────────────────────────────────────────────────────────

local eBS,pBS={},{}
local eHero,pHero -- Hero cells: 4th cell per board row (mkHeroSlot), set in buildSlots()
local mEBI,mPBI -- mobile board inner containers; set in buildMobileBoardRows()
local meBS,mpBS={},{} -- mobile slot frames (parallel to eBS/pBS)
local meHero,mpHero -- mobile hero slot frames
local mEnemyHandRow -- mobile enemy hand row frame; set in buildMobileLayout()
local mhCards = {}          -- mobile player hand card frames
local handExpanded = false  -- true while mobile hand is in expanded state
local expandInputObject = nil  -- InputObject that triggered last expand; blocks its re-fire
local isDraggingMobileCard = false  -- true while mobileDragCard is active; suppresses re-expand
local collapseGuard = false -- blocks mHandRow from re-expanding the same frame scrim collapses
local mHandRow              -- PlayerHandRow frame; set in buildMobileLayout()
local mHandScrim            -- scrim covering board rows while hand is expanded
local mGraveBadge           -- count badge on mobile grave button; set in buildMobileLayout()
local mHUD         -- mobile HUD frame; set in buildMobileLayout()
local mEndTurnBtn  -- mobile end turn button
local mForfBtn     -- mobile forfeit button
local mEnergyLbl   -- energy value TextLabel in mobile HUD
local mDeckCount   -- deck count TextLabel in mobile HUD
local mTimerLbl    -- turn timer TextLabel in mobile HUD
local layoutMobileHand      -- fwd-declared; defined after handCompressionFactor
local expandMobileHand      -- fwd-declared; defined after handCompressionFactor
local collapseMobileHand    -- fwd-declared; defined after handCompressionFactor
local prevHandIds={}     -- snapshot of state.player.hand from the previous render,
                          -- used by the Draw/Play animations (IDEA_CARD_BATTLE.md)
local lastPlayedCardId, lastPlayedSlot -- set when PlayCard fires, read by the Play
                                        -- animation to find the destination slot
local applyHandHoverLeave -- fwd-declared; defined near the hand-hover helpers below
local setHandHoverDisabled -- fwd-declared; defined near the hand-hover helpers below
local hoveredIdx=nil    -- currently-hovered hand card index (nil if none); see
                        -- resolveHandHover below
local insideHand={}     -- idx -> true while the mouse is within that card's
                        -- overlay bounds; see resolveHandHover below
local handHoverDisabled=false -- true while a card/attack drag is in progress;
                               -- see resolveHandHover below
local boardPreviewLocked=false -- true while a drag/attack is in progress; suppresses board-card preview
local makeBoardPreviewOpts     -- fwd-declared; assigned below (needs CardData/CardVisuals)
local myTurn=false; local cur=nil
local battleEnded=false

-- ── Board-card preview (hover on desktop / tap-hold on mobile) ─────────────
-- Shows the enlarged card to the LEFT of the slot after a delay; on mobile a
-- drag past threshold instead begins an attack (friendly slots only). Always
-- suppressed while a card/attack drag is in progress (boardPreviewLocked).
local BOARD_PREVIEW_DELAY = 0.5
local BOARD_DRAG_THRESHOLD = 12
local function setBoardPreviewDisabled(disabled)
	boardPreviewLocked = disabled
	if disabled then CardPreviewController.hide() end
end
local function attachBoardPreview(s, getMon, attackable, slotIdx)
	-- Desktop: hover the slot for BOARD_PREVIEW_DELAY -> preview to its left.
	local hoverTarget = s:FindFirstChildWhichIsA("TextButton") or s
	local hoverTimer
	hoverTarget.MouseEnter:Connect(function()
		if UXMode.Current ~= "Desktop" then return end
		if boardPreviewLocked then return end
		if hoverTimer then task.cancel(hoverTimer) end
		hoverTimer = task.delay(BOARD_PREVIEW_DELAY, function()
			hoverTimer = nil
			if boardPreviewLocked then return end
			local m = getMon(); if not m then return end
			local opts = makeBoardPreviewOpts(m)
			if opts then CardPreviewController.show(s, opts, "left") end
		end)
	end)
	hoverTarget.MouseLeave:Connect(function()
		if hoverTimer then task.cancel(hoverTimer); hoverTimer = nil end
		CardPreviewController.hide()
	end)
	-- Mobile (incl. Studio emulator): tap-hold for BOARD_PREVIEW_DELAY -> preview;
	-- drag past threshold on a friendly attacker -> attack drag (mutually
	-- exclusive). Movement/end come from UserInputService (Touch + MouseMovement)
	-- because the emulator delivers drags as MouseMovement and the per-InputObject
	-- .Changed misses them (same approach as the mobile hand drag).
	s.InputBegan:Connect(function(inp)
		if UXMode.Current ~= "Mobile" then return end
		local t0 = inp.UserInputType
		if t0 ~= Enum.UserInputType.Touch and t0 ~= Enum.UserInputType.MouseButton1 then return end
		if boardPreviewLocked or not getMon() then return end
		local startPos = Vector2.new(inp.Position.X, inp.Position.Y)
		local previewShown, started, done = false, false, false
		local moveConn, endConn
		local function cleanup()
			if done then return end
			done = true
			if moveConn then moveConn:Disconnect() end
			if endConn then endConn:Disconnect() end
		end
		local timer = task.delay(BOARD_PREVIEW_DELAY, function()
			if done or boardPreviewLocked or started then return end
			local m = getMon(); if not m then return end
			local opts = makeBoardPreviewOpts(m)
			if opts then CardPreviewController.show(s, opts, "left"); previewShown = true end
		end)
		moveConn = UserInput.InputChanged:Connect(function(uinp)
			local t = uinp.UserInputType
			if t ~= Enum.UserInputType.Touch and t ~= Enum.UserInputType.MouseMovement then return end
			if previewShown or started then return end
			local p = Vector2.new(uinp.Position.X, uinp.Position.Y)
			if (p - startPos).Magnitude > BOARD_DRAG_THRESHOLD then
				if timer then task.cancel(timer); timer = nil end
				if attackable and myTurn then
					local m = getMon()
					local atk = m and ((m.atk or 0) + (m.tempAtk or 0)) or 0
					if m and not m.attackedThisTurn and not m.summonedThisTurn and atk > 0 then
						started = true
						TargetingSystem.beginAttackDrag(s, slotIdx)
					else
						print("[ATTACK] move on slot "..tostring(slotIdx).." but cannot attack (mon="..tostring(m ~= nil)..", atk="..atk..", myTurn="..tostring(myTurn)..")")
					end
				end
				cleanup()
			end
		end)
		endConn = UserInput.InputEnded:Connect(function(uinp)
			local t = uinp.UserInputType
			if t ~= Enum.UserInputType.Touch and t ~= Enum.UserInputType.MouseButton1 then return end
			if timer then task.cancel(timer); timer = nil end
			if previewShown then CardPreviewController.hide() end
			cleanup()
		end)
	end)
end

local function buildSlots()
	clearIn(eBI); clearIn(pBI)
	eBS={}; pBS={}
	for i=1,BOARD_SIZE do
		local cap=i
		eBS[i]=mkSlot(eBI,BW,BH)
		attachBoardPreview(eBS[i], function() return cur and cur.npc.board[cap] end, false, cap)
	end
	-- Friendly slots: press-and-drag a monster that can still attack toward an
	-- enemy slot or the enemy hero to declare that attack (beginAttackDrag).
	for i=1,BOARD_SIZE do
		local f=mkSlot(pBI,BW,BH); pBS[i]=f
		local btn=Instance.new("TextButton",f)
		btn.Size=UDim2.new(1,0,1,0); btn.BackgroundTransparency=1
		btn.Text=""; btn.ZIndex=6
		local cap=i
		btn.InputBegan:Connect(function(input)
			if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then
				if not myTurn then return end
				local mon = cur and cur.player.board[cap]
				if not mon then return end
				local atk=(mon.atk or 0)+(mon.tempAtk or 0)
				if mon.attackedThisTurn or mon.summonedThisTurn or atk <= 0 then return end
				TargetingSystem.beginAttackDrag(f, cap)
			end
		end)
		attachBoardPreview(f, function() return cur and cur.player.board[cap] end, true, cap)
	end
	eHero = mkHeroSlot(eBI, BW, BH)
	pHero = mkHeroSlot(pBI, BW, BH)
end
buildSlots()

-- ── Mobile layout builders ────────────────────────────────────────────────────
local mkBack     -- forward declaration; defined after TargetingSystem.init()
local function computeMobileCardSize(rowH)
	local bh = rowH - 20
	local bw = math.floor(bh * (BW / BH))
	return bw, bh
end

local function clearMobileHand()
	for _, cf in ipairs(mhCards) do cf:Destroy() end
	mhCards = {}
end

local function layoutMobileEnemyHand(n)
	if not mEnemyHandRow then return end
	clearIn(mEnemyHandRow)
	if n == 0 then return end
	local cards = {}
	for _ = 1, n do
		local cf = mkBack(); cf.Parent = mEnemyHandRow; table.insert(cards, cf)
	end
	local rowW = mEnemyHandRow.AbsoluteSize.X
	local spacing = math.min(HW * 0.3, (rowW - HW) / math.max(n - 1, 1))
	local totalW = spacing * (n - 1) + HW
	local angleStep = n > 1 and 12 / (n - 1) or 0
	for i, cf in ipairs(cards) do
		local centerOff = i - (n + 1) / 2
		cf.Size = UDim2.new(0, HW, 0, HH)
		cf.AnchorPoint = Vector2.new(0.5, 1)
		cf.Position = UDim2.new(0, (rowW - totalW) / 2 + (i - 1) * spacing + HW / 2, 0, 46) -- peek; matches COLLAPSED_VISIBLE for symmetric hand/board gaps
		cf.Rotation = -centerOff * angleStep -- mirror the player hand's fan (was same-handed)
	end
end

makeBoardPreviewOpts = function(mon)
	if not mon then return nil end
	local card = CardData.Cards[mon.cardId]
	if not card then return nil end
	local abilName, abilText = CardData.getAbilityDisplay(mon.cardId)
	return {
		cardId     = mon.cardId,
		battleType = mon.battleType or card.battleType,
		cardType   = card.cardType,
		race       = mon.race or card.race,
		cost       = card.cost,
		chargeCost = card.chargeCost,
		corrupted  = CardTraits.has(card, "corrupted"),
		name       = mon.name or card.name,
		atk        = mon.atk,
		hp         = mon.hp,
		abilityName = abilName,
		abilityText = abilText,
		status = {
			shatterDisabled = mon.shatterDisabled == true,
		},
	}
end

local function buildMobileBoardRows()
	local vp = workspace.CurrentCamera.ViewportSize
	local vpX, vpY = vp.X, vp.Y
	local boardRowH = math.floor(vpY * 0.30) -- matches EnemyBoardRow/PlayerBoardRow rowPct
	local mBW, mBH = computeMobileCardSize(boardRowH)

	-- Sizing degradation: fit 4 cells in viewport width.
	local GAP, MARGIN = 4, 16
	if mBW * 4 + GAP * 3 > vpX - MARGIN then GAP = 1 end
	if mBW * 4 + GAP * 3 > vpX - MARGIN then
		mBW = math.max(math.floor((vpX - MARGIN - GAP * 3) / 4), math.floor(BW * 0.6))
		mBH = math.floor(mBW * BH / BW)
	end
	local innerW = mBW * 4 + GAP * 3

	local function makeBoardInner(parent)
		local bi = Instance.new("Frame", parent)
		bi.Size = UDim2.new(0, innerW, 0, mBH)
		bi.AnchorPoint = Vector2.new(0.5, 0.5)
		bi.Position = UDim2.new(0.5, 0, 0.5, 0)
		bi.BackgroundTransparency = 1
		bi.BorderSizePixel = 0
		local ull = Instance.new("UIListLayout", bi)
		ull.FillDirection = Enum.FillDirection.Horizontal
		ull.SortOrder = Enum.SortOrder.LayoutOrder
		ull.Padding = UDim.new(0, GAP)
		return bi
	end

	mEBI = makeBoardInner(mobileRoot:FindFirstChild("EnemyBoardRow"))
	mPBI = makeBoardInner(mobileRoot:FindFirstChild("PlayerBoardRow"))

	meBS = {}; mpBS = {}

	-- Enemy slots: tap-hold -> preview (read-only)
	for i = 1, BOARD_SIZE do
		local s = mkSlot(mEBI, mBW, mBH); meBS[i] = s
		local cap = i
		attachBoardPreview(s, function() return cur and cur.npc.board[cap] end, false, cap)
	end

	meHero = mkHeroSlot(mEBI, mBW, mBH)

	-- Player slots: tap-hold -> preview; drag -> attack
	for i = 1, BOARD_SIZE do
		local s = mkSlot(mPBI, mBW, mBH); mpBS[i] = s
		local cap = i
		attachBoardPreview(s, function() return cur and cur.player.board[cap] end, true, cap)
	end

	mpHero = mkHeroSlot(mPBI, mBW, mBH)
end

local function buildMobileLayout()
	mobileRoot = Instance.new("Frame")
	mobileRoot.Name = "MobileRoot"
	mobileRoot.Size = UDim2.new(1, 0, 1, 0)
	mobileRoot.BackgroundTransparency = 1
	mobileRoot.BorderSizePixel = 0
	mobileRoot.Visible = false
	mobileRoot.Parent = gui

	local rowPct   = {0.20, 0.30, 0.30, 0.20}
	local rowNames = {"EnemyHandRow", "EnemyBoardRow", "PlayerBoardRow", "PlayerHandRow"}
	local yOff = 0
	for i, pct in ipairs(rowPct) do
		local row = Instance.new("Frame", mobileRoot)
		row.Name = rowNames[i]
		row.Size = UDim2.new(1, 0, pct, 0)
		row.Position = UDim2.new(0, 0, yOff, 0)
		row.BackgroundTransparency = 1
		row.BorderSizePixel = 0
		yOff = yOff + pct
	end

	mEnemyHandRow = mobileRoot:FindFirstChild("EnemyHandRow")
	mHandRow = mobileRoot:FindFirstChild("PlayerHandRow")
	mHandRow.ZIndex = 20

	mHandScrim = Instance.new("Frame", mobileRoot)
	mHandScrim.Name = "HandScrim"
	mHandScrim.Size = UDim2.new(1, 0, 1, 0)
	mHandScrim.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	mHandScrim.BackgroundTransparency = 0.5
	mHandScrim.BorderSizePixel = 0
	mHandScrim.ZIndex = 15
	mHandScrim.Active = true
	mHandScrim.Visible = false
	mHandScrim.InputBegan:Connect(function(inp)
		local t = inp.UserInputType
		if t ~= Enum.UserInputType.Touch and t ~= Enum.UserInputType.MouseButton1 then return end
		if not handExpanded then return end
		if inp.Position.Y >= mHandRow.AbsolutePosition.Y then return end
		CardPreviewController.hide()
		collapseGuard = true
		collapseMobileHand()
		task.defer(function() collapseGuard = false end)
	end)

	buildMobileBoardRows()

	task.spawn(function()
		local ok, content = pcall(Players.GetUserThumbnailAsync, Players, player.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size100x100)
		if ok and content then mpHero.Portrait.Image = content end
	end)

	-- Grave button (bottom-left) with discard count badge
	local graveBtn = Instance.new("TextButton", mobileRoot)
	graveBtn.Name = "GraveBtn"
	graveBtn.Size = UDim2.new(0,44,0,44)
	graveBtn.AnchorPoint = Vector2.new(0,1)
	graveBtn.Position = UDim2.new(0,8, 1,-8)
	graveBtn.BackgroundColor3 = Color3.fromRGB(30,30,44)
	graveBtn.Text = "\xf0\x9f\xaa\xa6"
	graveBtn.TextSize = 22
	graveBtn.ZIndex = 10
	graveBtn.BorderSizePixel = 0
	Instance.new("UICorner", graveBtn).CornerRadius = UDim.new(0, 8)

	mGraveBadge = Instance.new("TextLabel", graveBtn)
	mGraveBadge.Name = "GraveCount"
	mGraveBadge.Size = UDim2.new(0,18,0,18)
	mGraveBadge.AnchorPoint = Vector2.new(1,0)
	mGraveBadge.Position = UDim2.new(1,2, 0,-2)
	mGraveBadge.BackgroundColor3 = Color3.fromRGB(180,50,50)
	mGraveBadge.Text = "0"
	mGraveBadge.TextSize = 9
	mGraveBadge.Font = Enum.Font.GothamBold
	mGraveBadge.TextColor3 = Color3.fromRGB(255,255,255)
	mGraveBadge.BorderSizePixel = 0
	Instance.new("UICorner", mGraveBadge).CornerRadius = UDim.new(1, 0)

	graveBtn.InputBegan:Connect(function(inp)
		local t = inp.UserInputType
		if t == Enum.UserInputType.Touch or t == Enum.UserInputType.MouseButton1 then
			GraveLogPanel.showOverlay(mobileRoot)
		end
	end)

	-- Mobile HUD (top-right): Energy | Deck | End Turn | Forfeit
	mHUD = Instance.new("Frame", mobileRoot)
	mHUD.Name = "MobileHUD"
	mHUD.AnchorPoint = Vector2.new(1, 1)
	mHUD.Position = UDim2.new(1, -8, 1, -8)
	mHUD.Size = UDim2.new(0, 86, 0, 174)
	mHUD.BackgroundTransparency = 1
	mHUD.BorderSizePixel = 0
	mHUD.ZIndex = 10
	local hudList = Instance.new("UIListLayout", mHUD)
	hudList.FillDirection = Enum.FillDirection.Vertical
	hudList.SortOrder = Enum.SortOrder.LayoutOrder
	hudList.Padding = UDim.new(0, 6)
	hudList.HorizontalAlignment = Enum.HorizontalAlignment.Right
	local mEnBadge = Instance.new("Frame", mHUD)
	mEnBadge.Name = "EnergyBadge"
	mEnBadge.Size = UDim2.new(0, 48, 0, 48)
	mEnBadge.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
	mEnBadge.BorderSizePixel = 0
	mEnBadge.LayoutOrder = 1
	Instance.new("UICorner", mEnBadge).CornerRadius = UDim.new(0, 8)
	mEnergyLbl = Instance.new("TextLabel", mEnBadge)
	mEnergyLbl.Name = "Value"
	mEnergyLbl.Size = UDim2.new(1, 0, 1, 0)
	mEnergyLbl.BackgroundTransparency = 1
	mEnergyLbl.TextColor3 = Color3.fromRGB(255, 215, 60)
	mEnergyLbl.Font = Enum.Font.GothamBold
	mEnergyLbl.TextSize = 14
	mEnergyLbl.Text = "0/0"
	mDeckCount = Instance.new("TextLabel", mHUD)
	mDeckCount.Name = "DeckCount"
	mDeckCount.Size = UDim2.new(0, 48, 0, 20)
	mDeckCount.BackgroundColor3 = Color3.fromRGB(30, 30, 44)
	mDeckCount.TextColor3 = Color3.fromRGB(200, 200, 220)
	mDeckCount.Font = Enum.Font.Gotham
	mDeckCount.TextSize = 11
	mDeckCount.Text = "Deck: 0"
	mDeckCount.BorderSizePixel = 0
	mDeckCount.LayoutOrder = 2
	Instance.new("UICorner", mDeckCount).CornerRadius = UDim.new(0, 4)
	mTimerLbl = Instance.new("TextLabel", mHUD)
	mTimerLbl.Name = "TurnTimerLabel"
	mTimerLbl.Size = UDim2.new(0, 72, 0, 22)
	mTimerLbl.BackgroundColor3 = Color3.fromRGB(24, 24, 36)
	mTimerLbl.TextColor3 = Color3.fromRGB(210, 220, 235)
	mTimerLbl.Font = Enum.Font.GothamBold
	mTimerLbl.TextSize = 11
	mTimerLbl.Text = "--:--"
	mTimerLbl.BorderSizePixel = 0
	mTimerLbl.LayoutOrder = 3
	Instance.new("UICorner", mTimerLbl).CornerRadius = UDim.new(0, 5)
	mEndTurnBtn = Instance.new("TextButton", mHUD)
	mEndTurnBtn.Name = "EndTurnBtn"
	mEndTurnBtn.Size = UDim2.new(0, 80, 0, 40)
	mEndTurnBtn.BackgroundColor3 = Color3.fromRGB(14, 36, 14)
	mEndTurnBtn.TextColor3 = Color3.fromRGB(180, 220, 180)
	mEndTurnBtn.Font = Enum.Font.GothamBold
	mEndTurnBtn.TextSize = 12
	mEndTurnBtn.Text = "End Turn"
	mEndTurnBtn.BorderSizePixel = 0
	mEndTurnBtn.LayoutOrder = 4
	Instance.new("UICorner", mEndTurnBtn).CornerRadius = UDim.new(0, 6)
	mEndTurnBtn.Activated:Connect(function()
		if myTurn and not BattleDirector.isLocked() then
			TargetingSystem.cancelIfDragging()
			Remotes.EndTurn:FireServer()
			if collapseMobileHand then collapseMobileHand() end
		end
	end)
	mForfBtn = Instance.new("TextButton", mHUD)
	mForfBtn.Name = "ForfeitBtn"
	mForfBtn.Size = UDim2.new(0, 60, 0, 24)
	mForfBtn.BackgroundColor3 = Color3.fromRGB(44, 20, 20)
	mForfBtn.TextColor3 = Color3.fromRGB(200, 150, 150)
	mForfBtn.Font = Enum.Font.Gotham
	mForfBtn.TextSize = 11
	mForfBtn.Text = "Forfeit"
	mForfBtn.BorderSizePixel = 0
	mForfBtn.LayoutOrder = 5
	Instance.new("UICorner", mForfBtn).CornerRadius = UDim.new(0, 6)
	mForfBtn.Activated:Connect(function() Remotes.Forfeit:FireServer() end)
	main.Visible       = (UXMode.Current == "Desktop")
	mobileRoot.Visible = (UXMode.Current == "Mobile")
end

-- Player Hero portrait: real avatar headshot (NPC keeps the placeholder color
-- set in mkHeroSlot).
task.spawn(function()
	local ok, content = pcall(Players.GetUserThumbnailAsync, Players, player.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size100x100)
	if ok and content then
		pHero.Portrait.Image = content
	end
end)

-- Enemy Hero cell: highlighted red as a face-attack target while dragging an
-- attacker (see applyDragHighlights/computeAttackZones).
local eHeroStroke = eHero:FindFirstChildOfClass("UIStroke")
eHeroStroke.Name = "TargetStroke"

-- Player Hero cell: drop target for untargeted action cards while dragging
-- (mirrors eHeroStroke above).
local pHeroStroke = pHero:FindFirstChildOfClass("UIStroke")
pHeroStroke.Name = "DropTargetStroke"

-- Always-visible overlay for the targeting arrow + hint, so they render in both
-- Desktop and Mobile layouts (main is hidden in Mobile mode, which would hide a
-- main-parented arrow).
local targetOverlay = Instance.new("Frame")
targetOverlay.Name = "TargetingOverlay"
targetOverlay.Size = UDim2.fromScale(1, 1)
targetOverlay.BackgroundTransparency = 1
targetOverlay.BorderSizePixel = 0
targetOverlay.ZIndex = 60
targetOverlay.Active = false
targetOverlay.Parent = main.Parent

local tsCtx = {
	main = main,
	overlay = targetOverlay,
	player = player,
	Remotes = Remotes,
	CardData = CardData,
	CardVisuals = CardVisuals,
	BOARD_SIZE = BOARD_SIZE,
	pBS = pBS,
	eBS = eBS,
	pHero = pHero,
	eHero = eHero,
	pHeroStroke = pHeroStroke,
	eHeroStroke = eHeroStroke,
	eBI = eBI,
	getState = function() return cur end,
	onPlayCard = function(cardId, slotIdx) lastPlayedCardId, lastPlayedSlot = cardId, slotIdx end,
	onDragStateChanged = function(active)
		if not active then
			-- Clear stale entries; MouseEnter will re-fire naturally on next mouse move.
			-- (hCards/HAND_OV are declared after this closure and can't be upvalues.)
			table.clear(insideHand)
		end
		setHandHoverDisabled(active)
		setBoardPreviewDisabled(active)
	end,
}
TargetingSystem.init(tsCtx)

-- Crystal Core active power removed (Phase 3): hero preview/drag input deleted.

-- ── Enemy hand backs ──────────────────────────────────────────────────────────
mkBack = function(w, h)
	return CardVisuals.mkBack(w or HW, h or HH)
end

-- ── Deck / Graveyard card stacks (IDEA_CARD_BATTLE.md: card-shaped, Deck face-down,
-- Grave face-up showing the most recently discarded card) ──────────────────────

local function setupStackPanel(panel)
	panel.Size = UDim2.new(0, DW+14, 0, DH+24)
	for _,c in ipairs(panel:GetChildren()) do
		if c:IsA("ImageLabel") or (c:IsA("TextLabel") and c.Name~="Count") then c:Destroy() end
	end
	local count = panel:FindFirstChild("Count")
	if not count then count=Instance.new("TextLabel"); count.Name="Count" end
	count.Size=UDim2.new(1,0,0,16)
	count.Position=UDim2.new(0,0,1,-16)
	count.BackgroundTransparency=1
	count.Font=Enum.Font.GothamBold
	count.TextScaled=true
	count.TextColor3=Color3.fromRGB(255,255,255)
	count.ZIndex=10
	local cOutline=count:FindFirstChildOfClass("UIStroke") or Instance.new("UIStroke",count)
	cOutline.Color=Color3.new(0,0,0); cOutline.Thickness=1.25
	count.Parent=panel
	return count
end

deckPanel.AnchorPoint = Vector2.new(1,1)
deckPanel.Position = UDim2.new(1,-8,1,-8-86-8)
setupStackPanel(deckPanel)

-- Player energy badge: single right column, above DeckPanel.
local pEnergyBadge = Instance.new("Frame")
pEnergyBadge.Name = "EnergyBadge"
pEnergyBadge.AnchorPoint = Vector2.new(1,1)
pEnergyBadge.Position = UDim2.new(1,-8,1,-8-86-8-(DH+24)-8)
pEnergyBadge.Size = UDim2.new(0,DW+14,0,86)
pEnergyBadge.BackgroundTransparency = 1
pEnergyBadge.BorderSizePixel = 0
pEnergyBadge.Parent = main
local pEnergyIcon=Instance.new("ImageLabel",pEnergyBadge)
pEnergyIcon.Name="Icon"; pEnergyIcon.AnchorPoint=Vector2.new(0.5,0.5)
pEnergyIcon.Position=UDim2.new(0.5,0,0.5,0); pEnergyIcon.Size=UDim2.new(1.15,0,1.15,0)
pEnergyIcon.SizeConstraint=Enum.SizeConstraint.RelativeYY
pEnergyIcon.BackgroundTransparency=1; pEnergyIcon.Image=ICON_ENERGY
local pEnergyLbl=Instance.new("TextLabel",pEnergyBadge)
pEnergyLbl.Name="Value"; pEnergyLbl.AnchorPoint=Vector2.new(0.5,0.5)
pEnergyLbl.Position=UDim2.new(0.5,0,0.5,0); pEnergyLbl.Size=UDim2.new(1.15,0,1.15,0)
pEnergyLbl.SizeConstraint=Enum.SizeConstraint.RelativeYY
pEnergyLbl.BackgroundTransparency=1; pEnergyLbl.Font=Enum.Font.FredokaOne; pEnergyLbl.TextScaled=false; pEnergyLbl.TextSize=32
pEnergyLbl.TextColor3=Color3.fromRGB(255,224,70)
pEnergyLbl.TextStrokeColor3=Color3.fromRGB(20,20,30); pEnergyLbl.TextStrokeTransparency=0
pEnergyLbl.Text=""

-- End Turn / Forfeit buttons: bottom of the right column.
abF.AnchorPoint = Vector2.new(1,1)
abF.Position = UDim2.new(1,-8,1,-8)
abF.Size = UDim2.new(0,DW+14,0,86)
etBtn.Position = UDim2.new(0,0,0,0)
etBtn.Size = UDim2.new(1,0,0,48)
forfBtn.Position = UDim2.new(0,0,0,54)
forfBtn.Size = UDim2.new(1,0,0,32)

local deckCard = mkBack(DW,DH)
deckCard.Position = UDim2.new(0,7,0,4)
deckCard.Parent = deckPanel

GraveLogPanel.init({main=main, CardVisuals=CardVisuals, CardData=CardData, DW=DW, DH=DH})
buildMobileLayout()

-- Point the TargetingSystem at the active layout's on-screen board frames.
local function applyTargetingMode()
	if UXMode.Current == "Mobile" then
		tsCtx.pBS, tsCtx.eBS = mpBS, meBS
		tsCtx.pHero, tsCtx.eHero = mpHero, meHero
		tsCtx.pHeroStroke = mpHero and mpHero:FindFirstChildOfClass("UIStroke")
		tsCtx.eHeroStroke = meHero and meHero:FindFirstChildOfClass("UIStroke")
		tsCtx.eBI = mEBI
	else
		tsCtx.pBS, tsCtx.eBS = pBS, eBS
		tsCtx.pHero, tsCtx.eHero = pHero, eHero
		tsCtx.pHeroStroke = pHeroStroke
		tsCtx.eHeroStroke = eHeroStroke
		tsCtx.eBI = eBI
	end
end
applyTargetingMode()
UXMode.Changed:Connect(applyTargetingMode)

-- ── Hand card builder ─────────────────────────────────────────────────────────
-- v0.4 schema: just two cardTypes ("monster"/"action"), every card carries a
-- single flat `cost` plus exactly one `battleType`, and there is no per-card
-- skill layer any more -- stats (Attack/Health, for monsters) plus a single
-- Effect (rendered via CardData.getAbilityDisplay) are the whole card.
local function clientEffectiveCost(costMods, cardId, baseCost)
	local cost = baseCost
	for _, mod in ipairs(costMods or {}) do
		if mod.ids and mod.ids[cardId] then
			if mod.kind == "set" then cost = mod.value
			elseif mod.kind == "reduce" then cost = cost - (mod.value or 0) end
		end
	end
	return math.max(0, cost)
end
local function clientEffectiveChargeCost(chargeCostMods, cardId, rawCc)
	if not rawCc then return nil end
	local bonus = 0
	for _, mod in ipairs(chargeCostMods or {}) do
		if mod.cardId == cardId then bonus += (mod.value or 0) end
	end
	if bonus == 0 then return rawCc end
	return { battleType = rawCc.battleType, amount = rawCc.amount + bonus }
end
local function buildCard(cardId, effCost, effChargeCost)
	local card=CardData.Cards[cardId]; if not card then return nil end
	local f = buildCardFrame(HW, HH, "full")
	Instance.new("UIScale", f)
	local stk=f:FindFirstChildOfClass("UIStroke")
	if stk then
		stk.Thickness=4
		stk.Color = TC_type[card.battleType] or TC_type.NEUTRAL
	end

	local abilName, abilText = CardData.getAbilityDisplay(cardId)
	local displayCost = effCost ~= nil and effCost or card.cost
	local costColor
	if effCost ~= nil and effCost < card.cost then costColor = STAT_BUFF
	elseif effCost ~= nil and effCost > card.cost then costColor = STAT_DEBUFF end
	local displayChargeCost = effChargeCost ~= nil and effChargeCost or card.chargeCost
	local chargeCostColor
	if effChargeCost and card.chargeCost and effChargeCost.amount > card.chargeCost.amount then
		chargeCostColor = STAT_DEBUFF
	end
	local opts = {
		cardId = cardId,
		battleType = card.battleType,
		cardType = card.cardType,
		race = card.race,
		cost = displayCost,
		costColor = costColor,
		chargeCost = displayChargeCost,
		chargeCostColor = chargeCostColor,
		corrupted = CardTraits.has(card, "corrupted"),
		name = card.name,
		atk = (card.cardType=="creature") and card.atk or nil,
		hp = (card.cardType=="creature") and card.hp or nil,
		abilityName = abilName,
		abilityText = abilText,
	}
	updateCardFrame(f, opts)

	return f, opts
end


-- ── Render ────────────────────────────────────────────────────────────────────
local battleOn=false; local hCards={}

-- Hand fan layout (arc-positioned cards, per IDEA_CARD_BATTLE.md). Small
-- hands sit nearly straight; larger hands fan out more. Each card pivots
-- from its bottom-center so rotation reads as a hand held in an arc.
local HAND_BASE={}
local HAND_OV={}   -- cf -> overlay TextButton (fixed-size hover hitbox)
local HAND_OPTS={} -- cf -> updateCardFrame opts (used to build the hover preview)
local function clearHand() for _,c in ipairs(hCards) do c:Destroy() end; hCards={}; table.clear(HAND_OV); table.clear(HAND_OPTS) end

-- Hides/restores a hand card's own visuals while leaving its overlay hitbox
-- (ov) visible and interactive, so ov's MouseEnter/MouseLeave keep firing
-- and never re-trigger from ov's own size/position changing (it never
-- changes -- ov stays at the card's normal layout size/position at all times).
local function setCardHidden(cf, ov, hidden)
	for _,child in ipairs(cf:GetChildren()) do
		if child==ov then continue end
		if child:IsA("GuiObject") then
			if hidden then
				child:SetAttribute("_wasVisible", child.Visible)
				child.Visible = false
			else
				local was = child:GetAttribute("_wasVisible")
				child.Visible = (was == nil) and true or was
			end
		elseif child:IsA("UIStroke") then
			child.Enabled = not hidden
		end
	end
end

-- render() rebuilds every hand card frame from scratch on each push, which
-- would otherwise silently drop an in-progress hover (the new frame starts
-- unhovered and the cursor never "enters" it again since it was already
-- sitting there). render() re-applies hoveredIdx after layoutHand() so the
-- hover survives the rebuild.

-- Roblox fires MouseEnter/MouseLeave for each overlay purely by bounding-box
-- containment, ignoring ZIndex -- in the overlap region between two fanned
-- cards, BOTH overlays report "inside" regardless of which is drawn on top.
-- insideHand tracks that raw containment per card index; resolveHandHover
-- picks the actual hover target from it (the rightmost/topmost card among
-- those currently "inside", matching the fan's visual stacking order) and
-- applies the hide/preview swap when that target changes.
local function resolveHandHover()
	local target=nil
	if not handHoverDisabled then
		for idx in pairs(insideHand) do
			if not target or idx>target then target=idx end
		end
	end
	if target==hoveredIdx then return end

	if hoveredIdx then
		local cf=hCards[hoveredIdx]; local ov=cf and HAND_OV[cf]
		if cf and ov then setCardHidden(cf, ov, false) end
	end

	if target then
		local cf=hCards[target]; local ov,opts=HAND_OV[cf],HAND_OPTS[cf]
		if cf and ov and opts then
			setCardHidden(cf, ov, true)
			CardPreviewController.show(ov, opts)
		end
	else
		CardPreviewController.hide()
	end
	hoveredIdx=target
end

local function applyHandHoverEnter(idx)
	insideHand[idx]=true
	resolveHandHover()
end
applyHandHoverLeave = function(idx)
	insideHand[idx]=nil
	resolveHandHover()
end
setHandHoverDisabled = function(disabled)
	handHoverDisabled = disabled
	resolveHandHover()
end

-- Fan tuning shared by layoutHand/layoutEnemyHand: hands at or below
-- FAN_THRESHOLD lay out as a flat row (rot=0, no arc). Above that, fan
-- strength ramps in gradually over FAN_RAMP additional cards (so a hand
-- just past the threshold is barely skewed, not an abrupt jump to full
-- rotation) until it reaches the full per-card angle (FAN_ANGLE_STEP),
-- which is then held constant so the curve looks the same across hand
-- sizes, capped at MAX_FAN_ANGLE total span for big hands.
local FAN_THRESHOLD=3
local FAN_RAMP=3
local FAN_ANGLE_STEP=4
local MAX_FAN_ANGLE=28

-- Hand margins: gap between the fanned hand's outer edge (bottom for player,
-- top for enemy) and its row container's matching edge. Positive = inset
-- (gap preserved), negative = the hand overflows past that edge, sitting
-- closer to the screen edge.
local PLAYER_HAND_BOTTOM_MARGIN=-60
local ENEMY_HAND_TOP_MARGIN=-120

-- Per-side cap on card spacing, as a fraction of card width (HW). Lower =
-- cards sit closer together / overlap more when the row has room.
local PLAYER_SPACING_FACTOR=0.8
local ENEMY_SPACING_FACTOR=0.5

-- Hand compression: extra multiplier on the spacing cap so larger hands
-- overlap more instead of just hitting the row-width clamp. 1-3 cards: none.
-- 4: slight. 5: moderate. 6+: increasing, floored so cards never fully overlap.
local function handCompressionFactor(n)
	if n<=3 then return 1
	elseif n==4 then return 0.92
	elseif n==5 then return 0.84
	else return math.max(0.55, 0.84-0.06*(n-5))
	end
end

-- Arc height scales with actual card spacing (relative to ARC_REFERENCE_FACTOR,
-- the spacing factor BASE_ARC_HEIGHT was tuned at) so tighter fans get a
-- proportionally smaller vertical rise -- keeping the curve smooth instead of
-- jagged when cards sit closer together.
local BASE_ARC_HEIGHT=52
local ARC_REFERENCE_FACTOR=0.9

-- ── Mobile hand layout ────────────────────────────────────────────────────────
local COLLAPSED_VISIBLE = 46  -- px of each card's top visible when collapsed (matches enemy hand peek for symmetric gaps)

layoutMobileHand = function(expanded, rowH)
	local n = #mhCards
	if n == 0 or not mHandRow then return end
	local rowW = mHandRow.AbsoluteSize.X
	if expanded then
		local spacing = math.min(HW * PLAYER_SPACING_FACTOR * handCompressionFactor(n), (rowW - HW) / math.max(n - 1, 1))
		local totalW = spacing * (n - 1) + HW
		local angleStep = n > 1 and 8 / (n - 1) or 0
		for i, cf in ipairs(mhCards) do
			local centerOff = i - (n + 1) / 2
			cf.AnchorPoint = Vector2.new(0.5, 0)
			cf.Size = UDim2.new(0, HW, 0, HH)
			cf.Rotation = centerOff * angleStep
			cf.ZIndex = 25 + i
			cf.Active = true
			local xPos = (rowW - totalW) / 2 + (i - 1) * spacing + HW / 2
			cf.Position = UDim2.new(0, xPos, 0, 4)
		end
	else
		local targetH = rowH or math.floor(mHandRow.AbsoluteSize.Y)
		local spacing = math.min(HW * 0.35, (rowW - HW) / math.max(n - 1, 1))
		local totalW = spacing * (n - 1) + HW
		local yPos = targetH - COLLAPSED_VISIBLE
		local angleStep = n > 1 and 16 / (n - 1) or 0
		for i, cf in ipairs(mhCards) do
			local centerOff = i - (n + 1) / 2
			cf.AnchorPoint = Vector2.new(0.5, 0)
			cf.Size = UDim2.new(0, HW, 0, HH)
			cf.Rotation = centerOff * angleStep
			cf.ZIndex = 25 + i
			cf.Active = false
			local xPos = (rowW - totalW) / 2 + (i - 1) * spacing + HW / 2
			cf.Position = UDim2.new(0, xPos, 0, yPos)
		end
	end
end

expandMobileHand = function()
	if handExpanded or not mHandRow then return end
	handExpanded = true
	if mHandScrim then mHandScrim.Visible = true end
	if mHandRow then mHandRow.Active = true end
	local expSize = (HH + 8) / gui.AbsoluteSize.Y
	local expPos  = 1 - expSize
	TweenService:Create(mHandRow, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = UDim2.new(1, 0, expSize, 0),
		Position = UDim2.new(0, 0, expPos, 0),
	}):Play()
	task.delay(0.18, function() layoutMobileHand(true) end)
end

collapseMobileHand = function()
	if not handExpanded or not mHandRow then return end
	handExpanded = false
	if mHandScrim then mHandScrim.Visible = false end
	if mHandRow then mHandRow.Active = false end
	local colSize = 0.20
	local colPos  = 1 - colSize
	layoutMobileHand(false, math.floor(colSize * gui.AbsoluteSize.Y))
	TweenService:Create(mHandRow, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = UDim2.new(1, 0, colSize, 0),
		Position = UDim2.new(0, 0, colPos, 0),
	}):Play()
end

local function layoutHand()
	local n=#hCards; if n==0 then return end
	local rowW=hs.AbsoluteSize.X
	local rowH=hs.AbsoluteSize.Y
	local spacing=math.min(HW*PLAYER_SPACING_FACTOR*handCompressionFactor(n), (rowW-HW)/math.max(n-1,1))
	local totalW=spacing*(n-1)+HW
	local maxOffset=(n-1)/2
	local ARC_HEIGHT=BASE_ARC_HEIGHT*(spacing/(HW*ARC_REFERENCE_FACTOR))
	local fanAmt=math.min(math.max(n-FAN_THRESHOLD,0)/FAN_RAMP, 1)
	local angleStep=(n>1) and math.min(fanAmt*FAN_ANGLE_STEP, MAX_FAN_ANGLE/(n-1)) or 0

	for i,cf in ipairs(hCards) do
		local centerOffset=i-(n+1)/2
		local rot=centerOffset*angleStep
		local x=(rowW-totalW)/2+(i-1)*spacing+HW/2
		local norm=(maxOffset>0) and (centerOffset/maxOffset) or 0
		local y=rowH-PLAYER_HAND_BOTTOM_MARGIN+ARC_HEIGHT*fanAmt*norm*norm
		cf.AnchorPoint=Vector2.new(0.5,1)
		cf.Rotation=rot
		cf.ZIndex=i
		cf.Position=UDim2.new(0,x,0,y)
		HAND_BASE[cf]={x=x, y=y, zindex=i, rot=rot}
	end
end

-- Enemy hand fan (mirrors layoutHand above): cards anchor from their
-- top-center and use the inverse (1-norm*norm) arc, so the curve mirrors
-- the player's hand -- center cards dip down toward the board while wing
-- cards ride up near the top screen edge. eHI's UIListLayout is disabled
-- above so these absolute positions take effect.
local function layoutEnemyHand(cards)
	local n=#cards; if n==0 then return end
	local rowW=eHI.AbsoluteSize.X
	local spacing=math.min(HW*ENEMY_SPACING_FACTOR*handCompressionFactor(n), (rowW-HW)/math.max(n-1,1))
	local totalW=spacing*(n-1)+HW
	local maxOffset=(n-1)/2
	local ARC_HEIGHT=BASE_ARC_HEIGHT*(spacing/(HW*ARC_REFERENCE_FACTOR))
	local fanAmt=math.min(math.max(n-FAN_THRESHOLD,0)/FAN_RAMP, 1)
	local angleStep=(n>1) and math.min(fanAmt*FAN_ANGLE_STEP, MAX_FAN_ANGLE/(n-1)) or 0
	local maxAngle=angleStep*math.max(n-1,0)
	-- eHI can sit above the visible viewport (GUI inset quirks push BoardContainer
	-- up at the top edge). Push the whole row down so the topmost card edge never
	-- renders off-screen. Also add a margin for the wing cards' rotation, since
	-- rotating around the top-center anchor swings their top corner above y=0
	-- and sliced it flat against the screen edge.
	local rotMargin=(HW/2)*math.sin(math.rad(maxAngle/2))
	local topClip=math.max(0, -eHI.AbsolutePosition.Y)+rotMargin+ENEMY_HAND_TOP_MARGIN

	for i,cf in ipairs(cards) do
		local centerOffset=i-(n+1)/2
		-- Mirroring the Y-arc (1-norm^2 vs the player's norm^2) also reverses
		-- rotational handedness, so the wing cards' tips overlap their neighbors
		-- instead of splaying apart -- flip the rotation sign to match.
		local rot=-centerOffset*angleStep
		local x=(rowW-totalW)/2+(i-1)*spacing+HW/2
		local norm=(maxOffset>0) and (centerOffset/maxOffset) or 0
		local y=ARC_HEIGHT*fanAmt*(1-norm*norm)+topClip
		cf.AnchorPoint=Vector2.new(0.5,0)
		cf.Rotation=rot
		cf.ZIndex=i
		cf.Position=UDim2.new(0,x,0,y)
	end
end

-- ── Combat animations (Card Lunge) ────────────────────────────────────────────
-- Draw/Play/Attack tweens now live in Modules.PhaseRegistry, driven by
-- state.animEvents (PLAN_CARD_BATTLE_REVAMP.md Phase 4) instead of the former
-- before/after board-snapshot diff heuristic, which could only ever recover
-- one attacker + one damaged target per broadcast and couldn't distinguish a
-- damage event from a heal/buff. See translateEventsToPhases() in render().

-- Resolves the currently-active board/hero frame set (desktop vs mobile),
-- mirroring TargetingSystem.applyTargetingMode's switch, so animated phases
-- always target the frames actually on screen instead of hardcoded desktop ones.
local function activeFrames()
	if UXMode.Current == "Mobile" then
		return { pBS = mpBS, eBS = meBS, pHero = mpHero, eHero = meHero }
	else
		return { pBS = pBS, eBS = eBS, pHero = pHero, eHero = eHero }
	end
end

-- Turn-start banner ("YOUR TURN"/"ENEMY TURN"), PLAN_CARD_BATTLE_REVAMP.md
-- Phase 5 -- created once and reused every turn; render() only sets its text/
-- color and hands it to PhaseRegistry.turn_banner via the Director.
local turnBannerGui = Instance.new("ScreenGui")
turnBannerGui.Name = "TurnBannerOverlay"
turnBannerGui.ResetOnSpawn = false
turnBannerGui.IgnoreGuiInset = true
turnBannerGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
turnBannerGui.DisplayOrder = 50
turnBannerGui.Parent = player.PlayerGui

local turnBannerLabel = Instance.new("TextLabel")
turnBannerLabel.Name = "TurnBannerLabel"
turnBannerLabel.AnchorPoint = Vector2.new(0.5, 0.5)
turnBannerLabel.Position = UDim2.new(0.5, 0, 0.3, 0)
turnBannerLabel.Size = UDim2.new(0, 360, 0, 64)
turnBannerLabel.BackgroundColor3 = Color3.fromRGB(15, 15, 25)
turnBannerLabel.BackgroundTransparency = 1
turnBannerLabel.BorderSizePixel = 0
turnBannerLabel.Font = Enum.Font.FredokaOne
turnBannerLabel.TextSize = 36
turnBannerLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
turnBannerLabel.TextTransparency = 1
turnBannerLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
turnBannerLabel.TextStrokeTransparency = 1
turnBannerLabel.Text = ""
turnBannerLabel.Visible = false
turnBannerLabel.ZIndex = 1
turnBannerLabel.Parent = turnBannerGui
local turnBannerCorner = Instance.new("UICorner", turnBannerLabel)
turnBannerCorner.CornerRadius = UDim.new(0, 14)
local turnBannerStroke = Instance.new("UIStroke", turnBannerLabel)
turnBannerStroke.Color = Color3.fromRGB(55, 55, 75)
turnBannerStroke.Thickness = 2
turnBannerStroke.Transparency = 1
local turnBannerScale = Instance.new("UIScale", turnBannerLabel)
turnBannerScale.Scale = 0.7

local timerState
local timerConn
local function fmtTimer(seconds)
	seconds = math.max(0, math.ceil(seconds or 0))
	return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end
local function paintTimerLabel(lbl, text, warning, urgent)
	if not lbl then return end
	lbl.Text = text
	lbl.TextColor3 = urgent and Color3.fromRGB(255, 110, 80)
		or warning and Color3.fromRGB(255, 205, 80)
		or Color3.fromRGB(210, 220, 235)
	lbl.BackgroundColor3 = warning and Color3.fromRGB(52, 34, 22) or Color3.fromRGB(24, 24, 36)
end
local function refreshTurnTimer()
	if not timerState then
		paintTimerLabel(turnTimerLbl, "--:--", false, false)
		paintTimerLabel(mTimerLbl, "--:--", false, false)
		return
	end
	local remaining = timerState.endsAtClient - os.clock()
	local warning = remaining <= 10
	local urgent = remaining <= 5
	local prefix = myTurn and "Your" or "Enemy"
	local text = prefix .. " " .. fmtTimer(remaining)
	paintTimerLabel(turnTimerLbl, text, warning, urgent)
	paintTimerLabel(mTimerLbl, text, warning, urgent)
end
local function clearTurnTimer()
	timerState = nil
	if timerConn then timerConn:Disconnect(); timerConn = nil end
	refreshTurnTimer()
end
local function syncTurnTimer(state)
	if state.turnEndsAt and state.serverNow then
		if timerState and timerState.turnEndsAt == state.turnEndsAt then
			refreshTurnTimer()
			return
		end
		local remaining = math.max(0, state.turnEndsAt - state.serverNow)
		timerState = {
			turnEndsAt = state.turnEndsAt,
			endsAtClient = os.clock() + remaining,
			duration = state.turnDuration or remaining,
		}
		if not timerConn then
			timerConn = RunService.RenderStepped:Connect(refreshTurnTimer)
		end
	else
		clearTurnTimer()
	end
	refreshTurnTimer()
end

local function syncActionButtons(isPlayerTurn)
	etBtn.BackgroundColor3 = isPlayerTurn and Color3.fromRGB(18,70,18) or Color3.fromRGB(14,36,14)
	etBtn.Active = isPlayerTurn
	if mEndTurnBtn then
		mEndTurnBtn.BackgroundColor3 = isPlayerTurn and Color3.fromRGB(18,70,18) or Color3.fromRGB(14,36,14)
		mEndTurnBtn.Active = isPlayerTurn
	end
end

render = function(state)
	if battleEnded then return end
	lastState = state
	-- Captured before `cur` is reassigned below: last render's player board,
	-- used by the Play animation to find a monster's newly-summoned slot.
	local oldPlayerBoard = cur and cur.player.board
	cur=state; myTurn=(state.currentTurn=="player")
	syncTurnTimer(state)
	local isFirstBattleRender = not battleOn and not battleEnded
	if isFirstBattleRender then battleOn=true; startCam() end
	local frames = activeFrames()

	-- Animation phases are queued in server event-log order near the end of
	-- render(), after frames have been rebuilt. Do not enqueue turn_start here:
	-- an NPC turn arrives as one batched broadcast, so an early banner would jump
	-- ahead of unresolved NPC casts/attacks from the same ordered animEvents list.

	-- Detect a combat event from this broadcast's ordered event log (replaces
	-- the old before/after snapshot diff -- PLAN_CARD_BATTLE_REVAMP.md Phase 4).
	-- One DeclareAttack produces exactly one `attack` envelope followed by the
	-- defender's damage[+death] and, if the defender didn't die to a Quickstrike
	-- kill, the attacker's retaliation damage[+death] -- matching BattleLogic.
	-- attack's fixed resolution order. Driven directly by the presence of the
	-- event itself, so (unlike the old diff) it can't misfire on a non-attack
	-- broadcast that happens to kill multiple monsters (AOE + deathrattles).
	local combatEvent = nil
	local combatEvents = {}
	local combatByEvent = {}
	do
		local events = state.animEvents or {}
		for idx, ev in ipairs(events) do
			if ev.action == "attack" then
				local dmg, dying, attackerDying = 0, false, false
				local j = idx + 1
				while j <= #events do
					local e2 = events[j]
					if e2.action == "damage" and e2.target and e2.target.side == ev.target.side and e2.target.slot == ev.target.slot then
						dmg = e2.amount
						local nxt = events[j+1]
						if nxt and nxt.action == "death" and nxt.target
							and nxt.target.side == ev.target.side and nxt.target.slot == ev.target.slot then
							dying = true
						end
					elseif e2.action == "damage" and e2.target and e2.target.side == ev.who and e2.target.slot == ev.attackerSlot then
						local nxt = events[j+1]
						if nxt and nxt.action == "death" and nxt.target
							and nxt.target.side == ev.who and nxt.target.slot == ev.attackerSlot then
							attackerDying = true
						end
						break
					elseif e2.action == "attack" or e2.action == "cast" or e2.action == "turn_start" then
						break
					end
					j += 1
				end
				local ce = {
					attackerSide = ev.who, attackerSlot = ev.attackerSlot, attackerDying = attackerDying,
					target = (ev.target.slot == 0)
						and { kind = "hero", dmg = dmg }
						or  { kind = "board", slot = ev.target.slot, dmg = dmg, dying = dying },
				}
				table.insert(combatEvents, ce)
				combatByEvent[ev] = ce
				if not combatEvent then combatEvent = ce end
			end
		end
	end

	local attackerFrame, targetFrame, deferredUpdate, dyingAttackerFrame, deferredAttackerUpdate
	if combatEvent then
		local atkBoard = (combatEvent.attackerSide=="player") and frames.pBS or frames.eBS
		local atkIsPlayer = (combatEvent.attackerSide=="player")
		local atkSlot = combatEvent.attackerSlot
		attackerFrame = atkBoard[atkSlot]
		if combatEvent.attackerDying then
			dyingAttackerFrame = attackerFrame
			-- Read `cur` (the latest known state) at fire time rather than
			-- capturing this render's data -- otherwise a slow animation from
			-- an older combat event can fire after a newer card has already
			-- been placed in this slot and stomp it back to "Empty".
			deferredAttackerUpdate = function()
				local liveBoard = atkIsPlayer and cur.player.board or cur.npc.board
				fillSlot(attackerFrame, liveBoard[atkSlot], atkIsPlayer)
			end
		end
		local tgt = combatEvent.target
		if tgt.kind=="board" then
			local tgtBoard = (combatEvent.attackerSide=="player") and frames.eBS or frames.pBS
			local tgtIsPlayer = (combatEvent.attackerSide=="npc")
			local tgtSlot = tgt.slot
			targetFrame = tgtBoard[tgtSlot]
			deferredUpdate = function()
				local liveBoard = tgtIsPlayer and cur.player.board or cur.npc.board
				fillSlot(targetFrame, liveBoard[tgtSlot], tgtIsPlayer)
			end
		else
			targetFrame = (combatEvent.attackerSide=="player") and frames.eHero or frames.pHero
		end
	end

	-- Hero panels -- hero HP/Armor live on the Hero cell (desktop + mobile
	-- together, since both show identical data); player Energy on the status
	-- bar. If this side's hero is the active combat target, the update is
	-- deferred to impact and reads `cur` at fire time for staleness safety.
	local function updateNpcHero()
		local s = cur.npc
		eHero.HPBadge.Value.Text=s.heroHp.."/"..(s.maxHeroHp or 30)
		local npcArmorN=s.armor or 0
		eHero.ArmorBadge.Visible = true
		eHero.ArmorBadge.Value.Text="\xf0\x9f\x9b\xa1"..npcArmorN
		paintChargeSlots(eHero, s)
		if meHero then
			meHero.HPBadge.Value.Text=s.heroHp.."/"..(s.maxHeroHp or 30)
			meHero.ArmorBadge.Visible = true
			meHero.ArmorBadge.Value.Text="\xf0\x9f\x9b\xa1"..npcArmorN
			paintChargeSlots(meHero, s)
		end
	end
	local function updatePlayerHero()
		local s = cur.player
		pEnergyBadge.Value.Text=(s.energy or 0).."/"..(s.energyCap or 0)
		if mEnergyLbl then mEnergyLbl.Text=(s.energy or 0).."/"..(s.energyCap or 0) end
		pHero.HPBadge.Value.Text=s.heroHp.."/"..(s.maxHeroHp or 30)
		local plrArmorN=s.armor or 0
		pHero.ArmorBadge.Visible = true
		pHero.ArmorBadge.Value.Text="\xf0\x9f\x9b\xa1"..plrArmorN
		paintChargeSlots(pHero, s)
		if mpHero then
			mpHero.HPBadge.Value.Text=s.heroHp.."/"..(s.maxHeroHp or 30)
			mpHero.ArmorBadge.Visible = true
			mpHero.ArmorBadge.Value.Text="\xf0\x9f\x9b\xa1"..plrArmorN
			paintChargeSlots(mpHero, s)
		end
	end
	if targetFrame==frames.eHero then deferredUpdate=updateNpcHero else updateNpcHero() end
	if targetFrame==frames.pHero then deferredUpdate=updatePlayerHero else updatePlayerHero() end

	-- Charge change feedback (cosmetic; authoritative slot state already painted).
	for _, ev in ipairs(state.chargeEvents or {}) do
		if ev.side == "player" then
			popChargeSocket(pHero, ev); popChargeSocket(mpHero, ev)
		elseif ev.side == "npc" then
			popChargeSocket(eHero, ev); popChargeSocket(meHero, ev)
		end
	end

	deckPanel.Count.Text=tostring(state.player.deckCount or 0)
	if mDeckCount then mDeckCount.Text="Deck: "..tostring(state.player.deckCount or 0) end

	-- Play animation setup (IDEA_CARD_BATTLE.md Play: Hand -> Board/Graveyard):
	-- driven by this broadcast's `cast` event (mine) instead of a multiset diff
	-- against the previous hand -- the server already told us exactly which
	-- card was played (PLAN_CARD_BATTLE_REVAMP.md Phase 4). Still runs before
	-- clearHand() below so the old frame survives; any duplicate-id copy is
	-- representationally identical, so the first match is always correct.
	local playAnim, castEv = nil, nil
	for _, ev in ipairs(state.animEvents or {}) do
		if ev.action == "cast" and ev.who == "player" then
			castEv = ev
			for i, id in ipairs(prevHandIds) do
				if id == ev.cardId and hCards[i] then
					playAnim = { frame = hCards[i], cardId = id }
					table.remove(hCards, i)
					break
				end
			end
			break
		end
	end

	local function frameForAnimTarget(target)
		if not target then return nil end
		if target.slot == 0 then
			return (target.side == "npc") and frames.eHero or frames.pHero
		end
		local board = (target.side == "npc") and frames.eBS or frames.pBS
		return board and board[target.slot]
	end

	local function enqueueCastVfx(ev, revealFrame)
		local castCard = CardData.Cards[ev.cardId]
		local castEntry = nil
		for _, e in ipairs((castCard and castCard.effects) or {}) do
			if e.trigger == "cast" then castEntry = e; break end
		end
		local archetype = castEntry and EffectVisuals.resolveVisualArchetype(castEntry, castCard)
		if revealFrame then
			BattleDirector.enqueue({ type = "cast_reveal", frame = revealFrame, mainFrame = main })
		end
		if archetype == "projectile" and ev.target then
			local amount = 0
			for idx, logged in ipairs(state.animEvents or {}) do
				if logged == ev then
					for j = idx + 1, #(state.animEvents or {}) do
						local e2 = state.animEvents[j]
						if e2.action == "damage" and e2.target and e2.target.side == ev.target.side and e2.target.slot == ev.target.slot then
							amount = e2.amount; break
						elseif e2.action == "cast" or e2.action == "attack" or e2.action == "turn_start" then
							break
						end
					end
					break
				end
			end
			local toFrame = frameForAnimTarget(ev.target)
			local fromFrame = (ev.who == "player") and frames.pHero or frames.eHero
			if toFrame and fromFrame then
				BattleDirector.enqueue({
					type = "effect", archetype = "projectile", fromFrame = fromFrame, toFrame = toFrame,
					amount = amount, mainFrame = main,
					color = CardVisuals.TC_type[(castCard and castCard.battleType) or "NEUTRAL"] or CardVisuals.TC_type.NEUTRAL,
				})
			end
		end
	end

	-- Destination of the Play animation: a newly-summoned board slot
	-- (monster), the equipped slot (equip action), or the Grave (other
	-- instant actions/discards). Its visual update is deferred to when the
	-- flying clone lands, below.
	local playDestFrame, playDestSlot, playDestIsGrave = nil, nil, false
	if playAnim then
		local card=CardData.Cards[playAnim.cardId]
		if card and card.cardType=="creature" then
			for i=1,BOARD_SIZE do
				if oldPlayerBoard and not oldPlayerBoard[i] and state.player.board[i] then playDestSlot=i; break end
			end
			if playDestSlot then playDestFrame=frames.pBS[playDestSlot] end
		else
			local isEquip = card and card.cardType=="action" and card.effect and card.effect.type=="buff_friendly_minion"
			if isEquip and lastPlayedSlot then playDestSlot=lastPlayedSlot; playDestFrame=frames.pBS[lastPlayedSlot] end
		end
		if not playDestFrame then playDestIsGrave=true end
	end
	if not playDestIsGrave then
		GraveLogPanel.update(state.discardHistory or {})
		if mGraveBadge then mGraveBadge.Text = tostring(#(state.discardHistory or {})) end
	end

	-- Enemy hand backs (fanned, mirrors the player hand below)
	clearIn(eHI)
	local eCards={}
	for _=1,state.npc.handCount do
		local cf=mkBack(); cf.Parent=eHI; table.insert(eCards,cf)
	end
	layoutEnemyHand(eCards)
	if mobileRoot and mobileRoot.Visible then layoutMobileEnemyHand(state.npc.handCount) end

	-- Boards (3 slots) -- the combat target slot (if any) is updated at
	-- impact time by the Card Lunge animation instead of immediately, and a
	-- Play destination slot (if any) is updated when its flying clone lands.
	for i=1,BOARD_SIZE do if eBS[i]~=targetFrame and eBS[i]~=dyingAttackerFrame then fillSlot(eBS[i],state.npc.board[i],false) end end
	for i=1,BOARD_SIZE do if pBS[i]~=targetFrame and pBS[i]~=dyingAttackerFrame and pBS[i]~=playDestFrame then fillSlot(pBS[i],state.player.board[i],true) end end
	if mobileRoot and mobileRoot.Visible then
		for i=1,BOARD_SIZE do if meBS[i]~=targetFrame and meBS[i]~=dyingAttackerFrame then fillSlot(meBS[i], state.npc.board[i], false) end end
		for i=1,BOARD_SIZE do if mpBS[i]~=targetFrame and mpBS[i]~=dyingAttackerFrame and mpBS[i]~=playDestFrame then fillSlot(mpBS[i], state.player.board[i], true) end end
	end

	-- Hand
	clearHand()
	for _,cid in ipairs(state.player.hand) do
		local baseCard = CardData.Cards[cid]
		local eff = baseCard and clientEffectiveCost(state.player.costMods, cid, baseCard.cost)
		local effCc = baseCard and clientEffectiveChargeCost(state.player.chargeCostMods, cid, baseCard.chargeCost)
		local cf,opts=buildCard(cid, eff, effCc); if not cf then continue end
		cf.Parent=hs; table.insert(hCards,cf)
		local captured=cid
		local idx=#hCards
		local ov=Instance.new("TextButton",cf)
		ov.Size=UDim2.new(1,0,1,0); ov.BackgroundTransparency=1; ov.Text=""; ov.ZIndex=6
		HAND_OV[cf]=ov
		HAND_OPTS[cf]=opts

		-- Hover (desktop): hide the card's own visuals and show an enlarged
		-- preview above it via CardPreviewController. ov stays the fixed-size
		-- hitbox throughout, so its MouseEnter/MouseLeave never re-fire from
		-- its own size change.
		ov.MouseEnter:Connect(function() applyHandHoverEnter(idx) end)
		ov.MouseLeave:Connect(function() applyHandHoverLeave(idx) end)

		-- Drag-to-target: press-and-drag a hand card toward a glowing valid
		-- target and release to play it there; releasing elsewhere cancels.
		ov.InputBegan:Connect(function(input)
			if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then
				if myTurn then TargetingSystem.beginDrag(cf, captured, function() applyHandHoverLeave(idx) end) end
			end
		end)
	end
	layoutHand()
	if hoveredIdx and hCards[hoveredIdx] then
		-- Force resolveHandHover to re-apply against the new frame: hoveredIdx
		-- already equals the target, which would otherwise look like "no
		-- change" and skip hiding/preview-ing the freshly rebuilt card.
		local idx=hoveredIdx
		hoveredIdx=nil
		insideHand={[idx]=true}
		resolveHandHover()
	else
		hoveredIdx=nil
		insideHand={}
	end

	-- Mobile hand
	if mobileRoot and mobileRoot.Visible then
		clearMobileHand()

		local function mobileDragCard(cf, cardId, startPos)
			local cur = lastState
			if not cur or cur.currentTurn ~= "player" then return end
			local card = CardData.Cards[cardId]
			if not card then return end
			isDraggingMobileCard = true
			setBoardPreviewDisabled(true)
			-- Mobile drop zones mirror Modules.TargetingSystem.computeDropZones:
			-- playTarget drives explicit single targets and broader board/side zone drops.
			local zones = {}
			local function mobileStealthed(m)
				if not m then return false end
				for _, k in ipairs(m.keywords or {}) do
					if k == "stealth" or k == "stealth_until_attack" then return true end
				end
				return false
			end
			local pt = CardData.playTarget(card)
			if pt == "empty_slot" then
				for i = 1, BOARD_SIZE do
					if mpBS and mpBS[i] and not cur.player.board[i] then
						table.insert(zones, {kind="slot", idx=i, frame=mpBS[i]})
					end
				end
			elseif pt == "friendly_creature" then
				for i = 1, BOARD_SIZE do
					if mpBS and mpBS[i] and cur.player.board[i] then
						table.insert(zones, {kind="friendly", idx=i, frame=mpBS[i]})
					end
				end
			elseif pt == "friendly_character" then
				for i = 1, BOARD_SIZE do
					if mpBS and mpBS[i] and cur.player.board[i] then
						table.insert(zones, {kind="friendly", idx=i, frame=mpBS[i]})
					end
				end
				if mpHero then table.insert(zones, {kind="hero", idx=0, frame=mpHero}) end
			elseif pt == "enemy_creature" then
				for i = 1, BOARD_SIZE do
					local em = cur.npc.board[i]
					if meBS and meBS[i] and em and not mobileStealthed(em) then
						table.insert(zones, {kind="enemyCreature", idx=i, frame=meBS[i]})
					end
				end
			elseif pt == "enemy_character" then
				for i = 1, BOARD_SIZE do
					local em = cur.npc.board[i]
					if meBS and meBS[i] and em and not mobileStealthed(em) then
						table.insert(zones, {kind="enemyCreature", idx=i, frame=meBS[i]})
					end
				end
				if meHero then table.insert(zones, {kind="enemyHero", idx=0, frame=meHero}) end
			elseif pt == "any_creature" then
				for i = 1, BOARD_SIZE do
					if mpBS and mpBS[i] and cur.player.board[i] then
						table.insert(zones, {kind="friendly", idx=i, frame=mpBS[i]})
					end
				end
				for i = 1, BOARD_SIZE do
					local em = cur.npc.board[i]
					if meBS and meBS[i] and em and not mobileStealthed(em) then
						table.insert(zones, {kind="enemyCreature", idx=i, frame=meBS[i]})
					end
				end
			elseif pt == "own_hero" then
				if mpHero then table.insert(zones, {kind="hero", idx=0, frame=mpHero}) end
			elseif pt == "enemy_hero" then
				if meHero then table.insert(zones, {kind="enemyHero", idx=0, frame=meHero}) end
			elseif pt == "own_board" then
				for i = 1, BOARD_SIZE do if mpBS and mpBS[i] then table.insert(zones, {kind="zoneDrop", zone="own_board", frame=mpBS[i]}) end end
			elseif pt == "enemy_board" then
				for i = 1, BOARD_SIZE do if meBS and meBS[i] then table.insert(zones, {kind="zoneDrop", zone="enemy_board", frame=meBS[i]}) end end
			elseif pt == "battle_board" then
				for i = 1, BOARD_SIZE do if mpBS and mpBS[i] then table.insert(zones, {kind="zoneDrop", zone="battle_board", frame=mpBS[i]}) end end
				for i = 1, BOARD_SIZE do if meBS and meBS[i] then table.insert(zones, {kind="zoneDrop", zone="battle_board", frame=meBS[i]}) end end
			elseif pt == "own_side" then
				for i = 1, BOARD_SIZE do if mpBS and mpBS[i] then table.insert(zones, {kind="zoneDrop", zone="own_side", frame=mpBS[i]}) end end
				if mpHero then table.insert(zones, {kind="zoneDrop", zone="own_side", frame=mpHero}) end
			elseif pt == "enemy_side" then
				for i = 1, BOARD_SIZE do if meBS and meBS[i] then table.insert(zones, {kind="zoneDrop", zone="enemy_side", frame=meBS[i]}) end end
				if meHero then table.insert(zones, {kind="zoneDrop", zone="enemy_side", frame=meHero}) end
			end
			for _, z in ipairs(zones) do
				local s = z.frame and z.frame:FindFirstChildOfClass("UIStroke")
				if s then s.Color = Color3.fromRGB(80,230,110); s.Thickness = 3 end
			end
			local origParent = cf.Parent
			local origZIndex = cf.ZIndex
			cf.ZIndex = 100
			cf.AnchorPoint = Vector2.new(0.5, 0.5)
			cf.Parent = mobileRoot
			collapseMobileHand()
			-- layoutMobileHand(false) inside collapseMobileHand overwrites ZIndex/AnchorPoint/Position on cf
			-- because cf is still in mhCards. Restore drag-specific values immediately.
			cf.ZIndex = 100
			cf.AnchorPoint = Vector2.new(0.5, 0.5)
			if startPos then
				local rp = mobileRoot.AbsolutePosition
				cf.Position = UDim2.new(0, startPos.X - rp.X, 0, startPos.Y - rp.Y)
			end
			local UIS = game:GetService("UserInputService")
			local trackConn, releaseConn
			trackConn = UIS.InputChanged:Connect(function(uinp)
				local t = uinp.UserInputType
				if t ~= Enum.UserInputType.Touch and t ~= Enum.UserInputType.MouseMovement then return end
				if not cf.Parent then trackConn:Disconnect(); return end
				local rp = mobileRoot.AbsolutePosition
				cf.Position = UDim2.new(0, uinp.Position.X - rp.X, 0, uinp.Position.Y - rp.Y)
			end)
			releaseConn = UIS.InputEnded:Connect(function(uinp)
				local t = uinp.UserInputType
				if t ~= Enum.UserInputType.Touch and t ~= Enum.UserInputType.MouseButton1 then return end
				trackConn:Disconnect(); releaseConn:Disconnect()
				for _, z in ipairs(zones) do
					local s = z.frame and z.frame:FindFirstChildOfClass("UIStroke")
					if s then s.Color = Color3.fromRGB(55,55,75); s.Thickness = 1 end
				end
				local touchPos = Vector2.new(uinp.Position.X, uinp.Position.Y)
				local cardPlayed = false
				for _, z in ipairs(zones) do
					local f = z.frame
					if f and f.Parent then
						local ap, as = f.AbsolutePosition, f.AbsoluteSize
						if touchPos.X >= ap.X and touchPos.X <= ap.X + as.X and
						   touchPos.Y >= ap.Y and touchPos.Y <= ap.Y + as.Y then
							local opts
							if z.kind == "slot" then opts = {slot=z.idx}
							elseif z.kind == "friendly" then opts = {target={side="player", slot=z.idx}}
							elseif z.kind == "enemyCreature" then opts = {target={side="npc", slot=z.idx}}
							elseif z.kind == "enemyHero" then opts = {target={side="npc", slot=0}}
							elseif z.kind == "zoneDrop" then opts = {zone=z.zone}
							else opts = {} end
							Remotes.PlayCard:FireServer(cardId, opts)
							cardPlayed = true
							break
						end
					end
				end
				if not cardPlayed and cf and cf.Parent then
					cf.Parent = origParent
					cf.ZIndex = origZIndex
				end
				if cardPlayed and cf then cf.Visible = false end
				isDraggingMobileCard = false
				setBoardPreviewDisabled(false)
				layoutMobileHand(handExpanded)
			end)
		end

		for _, cid in ipairs(state.player.hand) do
			local baseCard = CardData.Cards[cid]
			local eff = baseCard and clientEffectiveCost(state.player.costMods, cid, baseCard.cost)
			local effCc = baseCard and clientEffectiveChargeCost(state.player.chargeCostMods, cid, baseCard.chargeCost)
			local cf, opts = buildCard(cid, eff, effCc); if not cf then continue end
			cf.Parent = mHandRow
			table.insert(mhCards, cf)
			local captured = cid
			local capturedOpts = opts
			local dragStartPos
			local isDragging = false
			cf.InputBegan:Connect(function(inp)
				local t = inp.UserInputType
				if t ~= Enum.UserInputType.Touch and t ~= Enum.UserInputType.MouseButton1 then return end
				if isDraggingMobileCard then return end
				if not handExpanded then expandInputObject = inp; expandMobileHand(); return end
				if inp == expandInputObject then return end
				dragStartPos = inp.Position
				isDragging = false
				CardPreviewController.show(cf, capturedOpts)
			end)
			cf.InputChanged:Connect(function(inp)
				if not dragStartPos or isDragging then return end
				local t = inp.UserInputType
				if t ~= Enum.UserInputType.Touch and t ~= Enum.UserInputType.MouseMovement then return end
				local dx = inp.Position.X - dragStartPos.X
				local dy = inp.Position.Y - dragStartPos.Y
				if dx*dx + dy*dy > 625 then
					isDragging = true
					dragStartPos = nil
					CardPreviewController.hide()
					mobileDragCard(cf, captured, inp.Position)
				end
			end)
			cf.InputEnded:Connect(function(inp)
				local t = inp.UserInputType
				if t ~= Enum.UserInputType.Touch and t ~= Enum.UserInputType.MouseButton1 then return end
				dragStartPos = nil
				isDragging = false
				CardPreviewController.hide()
			end)
		end
		layoutMobileHand(handExpanded)
		if handExpanded and #mhCards == 0 then collapseMobileHand() end
	end

	-- Draw animation (IDEA_CARD_BATTLE.md Draw: Deck -> Hand). Counts
	-- draw_card events (mine) in this broadcast instead of diffing prevHandIds
	-- against the new hand -- drawn cards are always appended to the end of
	-- hand server-side, so the last N hand/hCards entries (N = draw_card event
	-- count) are exactly the new draws (PLAN_CARD_BATTLE_REVAMP.md Phase 4).
	local drawPhase = nil
	do
		local drawCount = 0
		for _, ev in ipairs(state.animEvents or {}) do
			if ev.action == "draw_card" and ev.who == "player" then drawCount += 1 end
		end
		if isFirstBattleRender and #(prevHandIds or {}) == 0 and #(state.player.hand or {}) > 0 then
			drawCount = #(state.player.hand or {})
		end
		if drawCount > 0 then
			local deckRelX = deckPanel.AbsolutePosition.X + deckPanel.AbsoluteSize.X/2 - hs.AbsolutePosition.X
			local deckRelY = deckPanel.AbsolutePosition.Y + deckPanel.AbsoluteSize.Y/2 - hs.AbsolutePosition.Y
			local fromPos = UDim2.new(0, deckRelX, 0, deckRelY)
			local cardsPhase, stagger = {}, 0
			local n = #hCards
			for i = math.max(1, n - drawCount + 1), n do
				local cf = hCards[i]
				local base = cf and HAND_BASE[cf]
				if base then
					cf.Visible = false
					table.insert(cardsPhase, { frame = cf, fromPos = fromPos, toPos = UDim2.new(0, base.x, 0, base.y), toRot = base.rot, stagger = stagger })
					stagger += 0.06
				end
			end
			if #cardsPhase > 0 then
				drawPhase = {
					type = "draw", cards = cardsPhase, glowStroke = deckPanel:FindFirstChildOfClass("UIStroke"),
					onCancel = function()
						for _, c in ipairs(cardsPhase) do if c.frame then c.frame.Visible = true end end
					end,
				}
			end
		end
	end

	-- Play animation (IDEA_CARD_BATTLE.md Play: Hand -> Board/Graveyard). The
	-- frame captured before clearHand() (in the setup step above) travels from
	-- its old hand position to the newly-summoned board slot (monster), the
	-- equipped slot (equip action), or the graveyard (other instant
	-- actions/discards). onLand reveals the destination's real visual
	-- (fillSlot/grave card, deferred above) once the flying clone lands, then
	-- discards the clone -- `cur` is read at fire time, same staleness-safety
	-- pattern as the combat lunge's deferred updates.
	local playPhase = nil
	if playAnim then
		local destFrame = playDestFrame or GraveLogPanel.getFrame()
		playPhase = {
			type = "play", frame = playAnim.frame, mainFrame = main, destFrame = destFrame,
			onLand = function()
				if playDestFrame and playDestSlot then
					fillSlot(playDestFrame, cur.player.board[playDestSlot], true)
				elseif playDestIsGrave then
					GraveLogPanel.update(cur.discardHistory or {})
					if mGraveBadge then mGraveBadge.Text = tostring(#(cur.discardHistory or {})) end
				end
			end,
		}
	end
	lastPlayedCardId, lastPlayedSlot = nil, nil


	-- Button states
	syncActionButtons(myTurn)

	local function enqueueAttackPhase(ce, isFirstCombat)
		if not ce then return end
		local atkBoard = (ce.attackerSide=="player") and frames.pBS or frames.eBS
		local atkFrame = atkBoard and atkBoard[ce.attackerSlot]
		local tgt = ce.target
		local tgtFrame
		if tgt.kind == "board" then
			local tgtBoard = (ce.attackerSide=="player") and frames.eBS or frames.pBS
			tgtFrame = tgtBoard and tgtBoard[tgt.slot]
		else
			tgtFrame = (ce.attackerSide=="player") and frames.eHero or frames.pHero
		end
		if atkFrame and tgtFrame then
			BattleDirector.enqueue({
				type = "attack", attackerFrame = atkFrame, targetFrame = tgtFrame, dmg = tgt.dmg,
				isDying = (tgt.kind=="board" and tgt.dying) or false, isFace = (tgt.kind=="hero"),
				onImpact = isFirstCombat and deferredUpdate or nil,
				attackerDying = ce.attackerDying,
				onAttackerDone = isFirstCombat and deferredAttackerUpdate or nil,
				tauntRedirect = isFirstCombat and state.tauntRedirect or nil,
			})
		end
	end

	local drawQueued = false
	local playQueued = false
	for _, ev in ipairs(state.animEvents or {}) do
		if ev.action == "turn_start" then
			BattleDirector.enqueue({
				type = "turn_banner", label = turnBannerLabel,
				text = (ev.who == "player") and "YOUR TURN" or "ENEMY TURN",
				color = (ev.who == "player") and Color3.fromRGB(20, 60, 30) or Color3.fromRGB(60, 20, 20),
			})
		elseif ev.action == "draw_card" and ev.who == "player" and drawPhase and not drawQueued then
			BattleDirector.enqueue(drawPhase)
			drawQueued = true
		elseif ev.action == "cast" then
			local isLocalCast = (ev == castEv and playAnim ~= nil)
			enqueueCastVfx(ev, isLocalCast and playAnim.frame or nil)
			if isLocalCast and playPhase then
				BattleDirector.enqueue(playPhase)
				playQueued = true
			end
		elseif ev.action == "attack" then
			enqueueAttackPhase(combatByEvent[ev], combatByEvent[ev] == combatEvent)
		end
	end
	if drawPhase and not drawQueued then BattleDirector.enqueue(drawPhase) end
	if playPhase and not playQueued then BattleDirector.enqueue(playPhase) end

	prevHandIds={}
	for i,id in ipairs(state.player.hand) do prevHandIds[i]=id end

	if state.warnings then
		for i, msg in ipairs(state.warnings) do
			task.delay((i - 1) * 0.25, function() showWarningToast(msg) end)
		end
	end

end

-- ── Remote listeners ──────────────────────────────────────────────────────────
-- Movement lock: hold the shared MovementLock for the duration of a battle. It
-- disables the ControlModule (hiding the mobile thumbstick and jump button) and
-- blocks jump, which would otherwise eject the player from the duel seat.
local MovementLock = require(RS:WaitForChild("Modules"):WaitForChild("MovementLock"))
local function setBattleControlsLocked(locked)
	if locked then MovementLock.hold("Battle") else MovementLock.release("Battle") end
end

local tablePromptsSuppressed = false
local function setTablePromptsSuppressed(suppressed)
	tablePromptsSuppressed = suppressed
	-- Client-only switch: hides every world prompt while seated or in battle without
	-- overriding the server-owned TablePrompt.Enabled (TableManager.refreshPrompt).
	game:GetService("ProximityPromptService").Enabled = not suppressed
end

local loadingOverlay = Instance.new("ScreenGui")
loadingOverlay.Name = "BattleLoadingOverlay"
loadingOverlay.ResetOnSpawn = false
loadingOverlay.IgnoreGuiInset = true
loadingOverlay.Enabled = false
loadingOverlay.DisplayOrder = 1000
loadingOverlay.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
loadingOverlay.Parent = player.PlayerGui

local loadingScrim = Instance.new("Frame", loadingOverlay)
loadingScrim.Size = UDim2.fromScale(1, 1)
loadingScrim.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
loadingScrim.BackgroundTransparency = 0.2
loadingScrim.BorderSizePixel = 0
loadingScrim.ZIndex = 200

local loadingLabel = Instance.new("TextLabel", loadingScrim)
loadingLabel.AnchorPoint = Vector2.new(0.5, 0.5)
loadingLabel.Position = UDim2.fromScale(0.5, 0.5)
loadingLabel.Size = UDim2.new(0, 320, 0, 54)
loadingLabel.BackgroundTransparency = 1
loadingLabel.Font = Enum.Font.GothamBold
loadingLabel.TextSize = 18
loadingLabel.TextColor3 = Color3.fromRGB(235, 235, 245)
loadingLabel.Text = "Finding Table..."
loadingLabel.ZIndex = 201

local loadingToken = 0
local loadingStartedAt = 0
local function hideBattleLoading()
	loadingToken += 1
	loadingOverlay.Enabled = false
end
local function showBattleLoading()
	battleEnded=false
	lastState=nil
	loadingToken += 1
	local token = loadingToken
	loadingStartedAt = os.clock()
	loadingOverlay.Enabled = true
	setBattleControlsLocked(true)
	setTablePromptsSuppressed(true)
	task.delay(8, function()
		if token == loadingToken and loadingOverlay.Enabled then
			hideBattleLoading()
			setBattleControlsLocked(false)
			setTablePromptsSuppressed(false)
		end
	end)
end

local function setBattleSurfaceBlocked(blocked)
	if blocked then
		TargetingSystem.cancelIfDragging()
		BattleDirector.skip()
		myTurn=false
		cur=nil
		setHandHoverDisabled(true)
		setBoardPreviewDisabled(true)
		table.clear(insideHand)
		CardPreviewController.hide()
	else
		table.clear(insideHand)
		setHandHoverDisabled(false)
		setBoardPreviewDisabled(false)
	end
end

-- The mulligan window (PLAN_CARD_BATTLE_REVAMP.md Phase 7) deliberately never
-- fires UpdateBattleState, so entering the battle presentation has to happen on
-- OfferMulligan. Seating is already complete server-side by this point; start
-- the battle camera/locks first, then MulliganController shows the dialog after
-- a short settle delay so players see themselves seated/facing the opponent.
Remotes.OfferMulligan.OnClientEvent:Connect(function()
	setBattleSurfaceBlocked(false)
	battleEnded=false
	hideBattleLoading()
	setBattleControlsLocked(true)
	setTablePromptsSuppressed(true)
	startCam()
end)

Remotes.UpdateBattleState.OnClientEvent:Connect(function(state)
	setBattleSurfaceBlocked(false)
	battleEnded=false
	hideBattleLoading()
	gui.Enabled=true; Post:hide(); setBattleControlsLocked(true); setTablePromptsSuppressed(true); render(state)
end)

Remotes.BattleOver.OnClientEvent:Connect(function(data)
	battleEnded=true
	setBattleSurfaceBlocked(true)
	lastState=nil
	hideBattleLoading()
	clearTurnTimer()
	Post:showResult(data)
end)

-- ── Button actions ────────────────────────────────────────────────────────────
etBtn.Activated:Connect(function()
	if myTurn and not BattleDirector.isLocked() then
		TargetingSystem.cancelIfDragging()
		Remotes.EndTurn:FireServer()
	end
end)
forfBtn.Activated:Connect(function() Remotes.Forfeit:FireServer() end)

local function dismissPostBattle()
	Post:hide(); gui.Enabled=false; battleOn=false; battleEnded=true; myTurn=false; cur=nil; lastState=nil
	clearHand(); setBattleSurfaceBlocked(false); stopCam(); hideBattleLoading(); clearTurnTimer(); setTablePromptsSuppressed(false)
	local c=player.Character; if not c then return end
	local h=c:FindFirstChildOfClass("Humanoid"); if not h then return end
	h.Sit=false
	setBattleControlsLocked(false)
end
Post:connectDismiss(dismissPostBattle)

player.CharacterAdded:Connect(function()
	battleOn=false; battleEnded=true; cur=nil; lastState=nil; setBattleSurfaceBlocked(false); stopCam(); hideBattleLoading(); clearTurnTimer(); setTablePromptsSuppressed(false); setBattleControlsLocked(false)
end)

Remotes.BattleLoading.OnClientEvent:Connect(function()
	setBattleSurfaceBlocked(false)
	battleEnded=false
	lastState=nil
	showBattleLoading()
end)

-- ── Pre-battle seated overlay (PVP: shown between Sit and battle start) ──────
-- BattleSeated fires when server seats this player at a table but no battle
-- has started yet (PVP: waiting for the opponent + ReadyUp handshake).
-- PvE skips this state entirely (battle auto-starts immediately).
-- ── Free-roam notifications (server -> client toast) ──────────────────────
-- Lives in its own ScreenGui (not inside BattleUI, which is disabled in free
-- roam) so messages like "all tables busy" show even when no battle is running.
local notifyOverlay = Instance.new("ScreenGui")
notifyOverlay.Name = "NotifyOverlay"
notifyOverlay.ResetOnSpawn = false
notifyOverlay.IgnoreGuiInset = true
notifyOverlay.DisplayOrder = 1500
notifyOverlay.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
notifyOverlay.Parent = player.PlayerGui

local function showNotify(msg)
	local lbl = Instance.new("TextLabel")
	lbl.AnchorPoint = Vector2.new(0.5, 0)
	lbl.Position = UDim2.new(0.5, 0, 0.12, 0)
	lbl.Size = UDim2.new(0, 400, 0, 46)
	lbl.BackgroundColor3 = Color3.fromRGB(28, 16, 16)
	lbl.BackgroundTransparency = 0.1
	lbl.BorderSizePixel = 0
	lbl.Font = Enum.Font.GothamBold
	lbl.TextSize = 15
	lbl.TextColor3 = Color3.fromRGB(255, 140, 110)
	lbl.Text = tostring(msg)
	lbl.TextWrapped = true
	lbl.ZIndex = 10
	lbl.Parent = notifyOverlay
	Instance.new("UICorner", lbl).CornerRadius = UDim.new(0, 8)
	local stroke = Instance.new("UIStroke", lbl)
	stroke.Color = Color3.fromRGB(180, 60, 40); stroke.Thickness = 1.5
	TweenService:Create(lbl, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = UDim2.new(0.5, 0, 0.1, 0),
	}):Play()
	task.delay(2.6, function()
		TweenService:Create(lbl, TweenInfo.new(0.4), { BackgroundTransparency = 1, TextTransparency = 1 }):Play()
		task.wait(0.45); lbl:Destroy()
	end)
end

do
	local notifyRemote = Remotes:FindFirstChild("Notify") or Remotes:WaitForChild("Notify", 10)
	if notifyRemote then notifyRemote.OnClientEvent:Connect(showNotify) end
end

local SeatedOverlay = require(script.Parent.Modules.SeatedOverlayController).new({
	player = player,
	Remotes = Remotes,
	RunService = RunService,
	hideBattleLoading = hideBattleLoading,
	setBattleControlsLocked = setBattleControlsLocked,
	setTablePromptsSuppressed = setTablePromptsSuppressed,
	onSeated = function()
		battleEnded = false
		lastState = nil
	end,
	onBattleStarted = function()
		battleEnded = false
	end,
})

-- PLAN_MATCHMAKING Phase 4c: fires when the server resumes an already-active
-- battle for a reconnecting player. A fresh client session has no
-- BattleSeated/OfferMulligan history to build on, so this bypasses that
-- entire sequence -- primes the camera/lock state OfferMulligan normally
-- sets up first, then renders directly from a full state snapshot, mirroring
-- UpdateBattleState's own entry sequence.
Remotes.BattleReconnected.OnClientEvent:Connect(function(state)
	setBattleSurfaceBlocked(false)
	battleEnded = false
	lastState = nil
	hideBattleLoading()
	SeatedOverlay:hide()
	Post:hide()
	setBattleControlsLocked(true)
	setTablePromptsSuppressed(true)
	startCam()
	gui.Enabled = true
	render(state)
end)

-- QUEST_REPAIR_V31