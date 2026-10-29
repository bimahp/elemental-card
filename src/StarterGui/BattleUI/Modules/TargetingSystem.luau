-- ── TargetingSystem ─────────────────────────────────────────────────────
-- Drag-to-target arrow rendering, drop/attack zone computation, highlight
-- management, and the press-drag-release lifecycle for both hand-card plays
-- and board-attack declarations. Extracted from BattleUIController (Phase 0)
-- with zero behavior change.

local RunService = game:GetService("RunService")
local UserInput  = game:GetService("UserInputService")
local BattleDirector = require(script.Parent.BattleDirector)

local TargetingSystem = {}

-- ── Drag-to-Target Arrow (prototype, Hearthstone-style rework) ─────────────
-- Holding (mouse-down/touch) on a hand card and dragging draws an arrow from
-- the card toward the cursor: a stretchable shaft, a circular tip, and a
-- two-piece chevron head, all plain Frames (no image assets).
local ARROW_COLOR = Color3.fromRGB(255, 221, 90)
local ARROW_THICK = 8
local ARROW_HEAD_LEN = 26
local ARROW_TIP_SIZE = 24
local DRAG_THRESHOLD = 12 -- px of pointer movement before the arrow appears

-- Set by init(); shared context for all functions below.
local ctx = nil

local arrowShaft, arrowHead1, arrowHead2, arrowTip
local dragHintBanner
local pBoardZone, eBoardZone, pSideZone, eSideZone

local dragFrame = nil
local dragRenderConn = nil
local dragInfo = nil -- {kind="card", cardId=, card=, frame=, zones=, moved=} for hand-card
                     -- drags, or {kind="attack", attackerSlot=, frame=, zones=, moved=}
                     -- for board-attack drags

local function makeArrowBar()
	local f = Instance.new("Frame")
	f.AnchorPoint = Vector2.new(0, 0.5)
	f.Size = UDim2.new(0, 0, 0, ARROW_THICK)
	f.BackgroundColor3 = ARROW_COLOR
	f.BorderSizePixel = 0
	f.ZIndex = 110
	f.Visible = false
	ctx.CardVisuals.rnd(f, ARROW_THICK/2)
	f.Parent = ctx.overlay
	return f
end

local function hideArrow()
	arrowShaft.Visible = false
	arrowHead1.Visible = false
	arrowHead2.Visible = false
	arrowTip.Visible = false
end

-- Mouse position in the same coordinate space as GuiObject.AbsolutePosition
-- (verified empirically: Mouse.X/Y matches AbsolutePosition exactly here,
-- while GetMouseLocation() is offset by GuiInset regardless of IgnoreGuiInset).
-- Latest pointer position (AbsolutePosition space). On touch -- including the
-- Studio emulator, where MouseEnabled can still be true and drags arrive as
-- MouseMovement -- GetMouse() does NOT follow the finger, so we track input
-- positions ourselves and prefer them whenever the device is touch-capable.
local lastPointer = nil
local function pointerPos()
	if UserInput.TouchEnabled and lastPointer then return lastPointer end
	local mouse = ctx.player:GetMouse()
	return Vector2.new(mouse.X, mouse.Y)
end

-- GuiObject.Rotation spins a frame around the center of its UNROTATED
-- bounding box, not around its AnchorPoint -- so a bar anchored at one end
-- drifts away from that anchor as it rotates (drift grows with bar length).
-- Center every rotated piece on its own midpoint/anchor instead and let the
-- rotation happen in place.
local function updateArrow(originAbs, mouseAbs)
	local mainAbs = ctx.main.AbsolutePosition
	local delta = mouseAbs - originAbs
	if delta.Magnitude < DRAG_THRESHOLD then hideArrow(); return end
	local angle = math.deg(math.atan2(delta.Y, delta.X))
	local originRel = originAbs - mainAbs
	local mouseRel = mouseAbs - mainAbs
	local midRel = (originRel + mouseRel) / 2

	arrowShaft.Position = UDim2.new(0, midRel.X, 0, midRel.Y)
	arrowShaft.Rotation = angle
	arrowShaft.Size = UDim2.new(0, delta.Magnitude, 0, ARROW_THICK)
	arrowShaft.Visible = true

	arrowTip.Position = UDim2.new(0, mouseRel.X, 0, mouseRel.Y)
	arrowTip.Visible = true

	local function setHead(head, ang)
		local rad = math.rad(ang)
		local off = Vector2.new(math.cos(rad), math.sin(rad)) * (ARROW_HEAD_LEN / 2)
		head.Position = UDim2.new(0, mouseRel.X - off.X, 0, mouseRel.Y - off.Y)
		head.Rotation = ang
		head.Visible = true
	end
	setHead(arrowHead1, angle - 25)
	setHead(arrowHead2, angle + 25)
end

local ZONE_DROP_TARGETS = {own_board=true,enemy_board=true,battle_board=true,own_side=true,enemy_side=true}

local function isStealthed(m)
	if not m then return false end
	for _, k in ipairs(m.keywords or {}) do
		if k == "stealth" or k == "stealth_until_attack" then return true end
	end
	return false
end

local ZONE_PAD = 20

-- Positions zf as a padded bounding box covering all memberFrames.
local function positionZoneFrame(zf, memberFrames)
	local ovAbs = ctx.overlay.AbsolutePosition
	local minX, minY = math.huge, math.huge
	local maxX, maxY = -math.huge, -math.huge
	for _, f in ipairs(memberFrames) do
		local ap, as = f.AbsolutePosition, f.AbsoluteSize
		if ap.X         < minX then minX = ap.X         end
		if ap.Y         < minY then minY = ap.Y         end
		if ap.X + as.X > maxX then maxX = ap.X + as.X end
		if ap.Y + as.Y > maxY then maxY = ap.Y + as.Y end
	end
	zf.Position = UDim2.fromOffset(minX - ovAbs.X - ZONE_PAD, minY - ovAbs.Y - ZONE_PAD)
	zf.Size     = UDim2.fromOffset((maxX - minX) + ZONE_PAD*2, (maxY - minY) + ZONE_PAD*2)
end

-- Drop-target zones for the dragged card, computed once at drag-start.
local function computeDropZones(card)
	local zones = {}
	local cur = ctx.getState()
	if not cur then return zones end
	local BOARD_SIZE, pBS, eBS, pHero, eHero = ctx.BOARD_SIZE, ctx.pBS, ctx.eBS, ctx.pHero, ctx.eHero
	local pt = ctx.CardData.playTarget(card)

	if pt == "empty_slot" then
		for i=1,BOARD_SIZE do
			if not cur.player.board[i] then table.insert(zones, {kind="slot", idx=i, frame=pBS[i]}) end
		end
	elseif pt == "friendly_creature" then
		for i=1,BOARD_SIZE do
			if cur.player.board[i] then table.insert(zones, {kind="friendly", idx=i, frame=pBS[i]}) end
		end
	elseif pt == "friendly_character" then
		for i=1,BOARD_SIZE do
			if cur.player.board[i] then table.insert(zones, {kind="friendly", idx=i, frame=pBS[i]}) end
		end
		table.insert(zones, {kind="hero", frame=pHero})
	elseif pt == "enemy_creature" then
		for i=1,BOARD_SIZE do
			local em = cur.npc.board[i]
			if em and not isStealthed(em) then table.insert(zones, {kind="enemyCreature", idx=i, frame=eBS[i]}) end
		end
	elseif pt == "enemy_character" then
		for i=1,BOARD_SIZE do
			local em = cur.npc.board[i]
			if em and not isStealthed(em) then table.insert(zones, {kind="enemyCreature", idx=i, frame=eBS[i]}) end
		end
		table.insert(zones, {kind="enemyHero", idx=0, frame=eHero})
	elseif pt == "any_creature" then
		for i=1,BOARD_SIZE do
			if cur.player.board[i] then table.insert(zones, {kind="friendly", idx=i, frame=pBS[i]}) end
		end
		for i=1,BOARD_SIZE do
			local em = cur.npc.board[i]
			if em and not isStealthed(em) then table.insert(zones, {kind="enemyCreature", idx=i, frame=eBS[i]}) end
		end
	elseif pt == "own_hero" then
		table.insert(zones, {kind="hero", frame=pHero})
	elseif pt == "enemy_hero" then
		table.insert(zones, {kind="enemyHero", idx=0, frame=eHero})
	elseif pt == "own_board" then
		positionZoneFrame(pBoardZone, {pBS[1],pBS[2],pBS[3]})
		table.insert(zones, {kind="zoneDrop", zone="own_board", frame=pBoardZone})
	elseif pt == "enemy_board" then
		positionZoneFrame(eBoardZone, {eBS[1],eBS[2],eBS[3]})
		table.insert(zones, {kind="zoneDrop", zone="enemy_board", frame=eBoardZone})
	elseif pt == "battle_board" then
		positionZoneFrame(pBoardZone, {pBS[1],pBS[2],pBS[3]})
		positionZoneFrame(eBoardZone, {eBS[1],eBS[2],eBS[3]})
		table.insert(zones, {kind="zoneDrop", zone="battle_board", frame=pBoardZone})
		table.insert(zones, {kind="zoneDrop", zone="battle_board", frame=eBoardZone})
	elseif pt == "own_side" then
		positionZoneFrame(pSideZone, {pBS[1],pBS[2],pBS[3],pHero})
		table.insert(zones, {kind="zoneDrop", zone="own_side", frame=pSideZone})
	elseif pt == "enemy_side" then
		positionZoneFrame(eSideZone, {eBS[1],eBS[2],eBS[3],eHero})
		table.insert(zones, {kind="zoneDrop", zone="enemy_side", frame=eSideZone})
	end
	return zones
end

-- Stealth/exhaustion dimming for a monster, used both for board rendering and
-- for computing valid attack-drag targets (computeAttackZones below).
local function monsterBaseDim(m)
	if not m then return 0 end
	if m.attackedThisTurn or m.summonedThisTurn then return 0.4 end
	return 0
end
TargetingSystem.monsterBaseDim = monsterBaseDim

local function setSlotDim(f, m, extraDim)
	local dimAmt = math.max(monsterBaseDim(m), extraDim or 0)
	f.Body.Background.ImageTransparency = dimAmt
end

-- Valid attack-drag targets for a friendly attacker: enemy slots not blocked
-- by Stealth/Taunt, plus the enemy hero unless a Taunt minion is present.
-- Ports the Taunt/Stealth logic from the old refreshEnemyTargetHighlights.
local function computeAttackZones(attackerSlot)
	local zones = {}
	local cur = ctx.getState()
	if not cur or not cur.npc then return zones end
	local BOARD_SIZE, eBS, eHero = ctx.BOARD_SIZE, ctx.eBS, ctx.eHero
	local hasTaunt, taunts, stealths = false, {}, {}
	for i=1,BOARD_SIZE do
		local em = cur.npc.board[i]
		if em then
			stealths[i] = monsterBaseDim(em) >= 0.55
			taunts[i] = false
			for _,k in ipairs(em.keywords or {}) do if k=="taunt" then taunts[i]=true end end
			if taunts[i] and not stealths[i] then hasTaunt=true end
		end
	end
	for i=1,BOARD_SIZE do
		local em = cur.npc.board[i]
		if em and not stealths[i] and (not hasTaunt or taunts[i]) then
			table.insert(zones, {kind="enemySlot", idx=i, frame=eBS[i]})
		end
	end
	if not hasTaunt then
		table.insert(zones, {kind="enemyHero", frame=eHero})
	end
	return zones
end

-- Highlight valid drop zones and dim everything else. Reads dragInfo
-- directly since it is only ever called while a drag is in progress.
-- Hand-card drags (dragInfo.kind=="card") get the green "valid drop target"
-- treatment (board slots / pHero / enemyArea); attack drags
-- (dragInfo.kind=="attack") get the red "valid attack target" treatment on
-- the enemy board / eHero instead.
local function applyDragHighlights()
	local TC_type = ctx.CardVisuals.TC_type
	local BOARD_SIZE, pBS, eBS, pHero, eHero = ctx.BOARD_SIZE, ctx.pBS, ctx.eBS, ctx.pHero, ctx.eHero
	local pHeroStroke, eHeroStroke = ctx.pHeroStroke, ctx.eHeroStroke
	local cur = ctx.getState()
	local zones = dragInfo.zones
	local zoneFrames = {}
	for _,z in ipairs(zones) do zoneFrames[z.frame]=true end

	if dragInfo.kind=="attack" then
		for i=1,BOARD_SIZE do
			local em = cur and cur.npc.board[i]
			local valid = zoneFrames[eBS[i]]
			local s = eBS[i] and eBS[i]:FindFirstChildOfClass("UIStroke")
			if s then
				if valid then
					s.Color = Color3.fromRGB(230,70,50)
					s.Thickness = 2.5
				else
					s.Color = (em and TC_type[em.battleType]) or Color3.fromRGB(55,55,75)
					s.Thickness = em and 2 or 1
				end
			end
			if eBS[i] then setSlotDim(eBS[i], em, (em and not valid) and 0.65 or 0) end
		end
		if zoneFrames[eHero] then
			eHeroStroke.Color = Color3.fromRGB(230,70,50)
			eHeroStroke.Thickness = 2.5
		end
		return
	end

	local card = dragInfo.card
	local pt = ctx.CardData.playTarget(card)

	if ZONE_DROP_TARGETS[pt] then
		for _,z in ipairs(zones) do z.frame.Visible = true end
		return
	end

	local touchesPlayerBoard = pt=="friendly_creature" or pt=="friendly_character" or pt=="any_creature" or pt=="empty_slot"
	local touchesEnemyBoard  = pt=="enemy_creature"   or pt=="enemy_character"   or pt=="any_creature"

	if touchesPlayerBoard then
		for i=1,BOARD_SIZE do
			local m = cur and cur.player.board[i]
			local valid = zoneFrames[pBS[i]]
			local s = pBS[i] and pBS[i]:FindFirstChildOfClass("UIStroke")
			if s then
				if valid then s.Color=Color3.fromRGB(80,230,110); s.Thickness=3
				else s.Color=(m and TC_type[m.battleType]) or Color3.fromRGB(55,55,75); s.Thickness=m and 2 or 1 end
			end
			if pBS[i] then setSlotDim(pBS[i], m, (not valid) and 0.65 or 0) end
		end
	end
	if touchesEnemyBoard then
		for i=1,BOARD_SIZE do
			local em = cur and cur.npc.board[i]
			local valid = zoneFrames[eBS[i]]
			local s = eBS[i] and eBS[i]:FindFirstChildOfClass("UIStroke")
			if s then
				if valid then s.Color=Color3.fromRGB(80,230,110); s.Thickness=3
				else s.Color=(em and TC_type[em.battleType]) or Color3.fromRGB(55,55,75); s.Thickness=em and 2 or 1 end
			end
			if eBS[i] then setSlotDim(eBS[i], em, (em and not valid) and 0.4 or 0) end
		end
	end
	if zoneFrames[pHero] then
		pHeroStroke.Color = Color3.fromRGB(80,230,110)
		pHeroStroke.Thickness = 3
	end
	if zoneFrames[eHero] then
		eHeroStroke.Color = Color3.fromRGB(80,230,110)
		eHeroStroke.Thickness = 3
	end
end

-- Restore default slot/hero strokes and dimming after a drag ends/cancels.
local function clearDragHighlights()
	local TC_type = ctx.CardVisuals.TC_type
	local BOARD_SIZE, pBS, eBS = ctx.BOARD_SIZE, ctx.pBS, ctx.eBS
	local pHeroStroke, eHeroStroke = ctx.pHeroStroke, ctx.eHeroStroke
	local cur = ctx.getState()
	for i=1,BOARD_SIZE do
		local m = cur and cur.player.board[i]
		local s = pBS[i] and pBS[i]:FindFirstChildOfClass("UIStroke")
		if s then
			s.Color = (m and TC_type[m.battleType]) or Color3.fromRGB(55,55,75)
			s.Thickness = m and 2 or 1
		end
		if pBS[i] then setSlotDim(pBS[i], m, 0) end

		local em = cur and cur.npc.board[i]
		local es = eBS[i] and eBS[i]:FindFirstChildOfClass("UIStroke")
		if es then
			es.Color = (em and TC_type[em.battleType]) or Color3.fromRGB(55,55,75)
			es.Thickness = em and 2 or 1
		end
		if eBS[i] then setSlotDim(eBS[i], em, 0) end
	end
	pHeroStroke.Color = Color3.fromRGB(55,55,75); pHeroStroke.Thickness = 1
	eHeroStroke.Color = Color3.fromRGB(55,55,75); eHeroStroke.Thickness = 1
	if pBoardZone then pBoardZone.Visible = false end
	if eBoardZone then eBoardZone.Visible = false end
	if pSideZone  then  pSideZone.Visible = false end
	if eSideZone  then  eSideZone.Visible = false end
	dragHintBanner.Visible = false
end

local function dragHintText()
	if dragInfo.kind=="attack" then
		return (#dragInfo.zones>0) and "Drop on an enemy to attack" or "No valid targets"
	end
	local card, zones = dragInfo.card, dragInfo.zones
	local pt = ctx.CardData.playTarget(card)
	if pt == "empty_slot" then return (#zones>0) and "Drop on an empty slot to summon" or "Board is full"
	elseif pt == "friendly_creature" then return (#zones>0) and "Drop on a friendly creature" or "No friendly creature"
	elseif pt == "friendly_character" then return (#zones>0) and "Drop on a friendly creature or your hero" or "No friendly target"
	elseif pt == "enemy_creature" then return (#zones>0) and "Drop on an enemy creature" or "No valid target"
	elseif pt == "enemy_character" then return (#zones>0) and "Drop on an enemy creature or hero" or "No valid target"
	elseif pt == "any_creature" then return (#zones>0) and "Drop on any creature" or "No creatures in play"
	elseif pt == "own_hero" then return "Drop on your hero to play"
	elseif pt == "enemy_hero" then return "Drop on the enemy hero to play"
	elseif pt == "own_board" then return "Drop on your board to play"
	elseif pt == "enemy_board" then return "Drop on the enemy board to play"
	elseif pt == "battle_board" then return "Drop anywhere on the board to play"
	elseif pt == "own_side" then return "Drop on your side to play"
	elseif pt == "enemy_side" then return "Drop on the enemy side to play"
	else return "Drop to play" end
end

-- Point-in-rect hit test for the dragged card's drop zones, using the same
-- coordinate space as pointerPos()/AbsolutePosition.
local function hitZone(zones, pos)
	for _,z in ipairs(zones) do
		local f = z.frame
		local p, sz = f.AbsolutePosition, f.AbsoluteSize
		if pos.X >= p.X and pos.X <= p.X+sz.X and pos.Y >= p.Y and pos.Y <= p.Y+sz.Y then
			return z
		end
	end
	return nil
end

local function endDrag()
	if dragRenderConn then dragRenderConn:Disconnect(); dragRenderConn=nil end
	dragFrame = nil
	hideArrow()
	if dragInfo and dragInfo.moved then
		local zone = hitZone(dragInfo.zones, pointerPos())
		if zone then
			if dragInfo.kind=="attack" then
				ctx.Remotes.DeclareAttack:FireServer(dragInfo.attackerSlot, zone.idx or 0)
			else
				local opts
				if zone.kind == "slot" then opts = {slot=zone.idx}
				elseif zone.kind == "friendly" then opts = {target={side="player", slot=zone.idx}}
				elseif zone.kind == "enemyCreature" then opts = {target={side="npc", slot=zone.idx}}
				elseif zone.kind == "enemyHero" then opts = {target={side="npc", slot=0}}
				elseif zone.kind == "zoneDrop" then opts = {zone=zone.zone}
				else opts = {} end
				if ctx.onPlayCard then ctx.onPlayCard(dragInfo.cardId, opts) end
				ctx.Remotes.PlayCard:FireServer(dragInfo.cardId, opts)
			end
		end
	end
	clearDragHighlights()
	dragInfo = nil
	if ctx.onDragStateChanged then ctx.onDragStateChanged(false) end
end

local function cancelDrag()
	if dragRenderConn then dragRenderConn:Disconnect(); dragRenderConn=nil end
	dragFrame = nil
	hideArrow()
	clearDragHighlights()
	dragInfo = nil
	if ctx.onDragStateChanged then ctx.onDragStateChanged(false) end
end

-- Collapse all 4 pieces onto the card's center, zero-length and hidden, so a
-- new drag never starts by flashing the previous drag's leftover shape/place
-- before the first RenderStepped catches up.
local function resetArrowTo(originAbs)
	local mainAbs = ctx.main.AbsolutePosition
	local originRel = originAbs - mainAbs
	local originPos = UDim2.new(0, originRel.X, 0, originRel.Y)
	arrowShaft.Position = originPos
	arrowShaft.Rotation = 0
	arrowShaft.Size = UDim2.new(0, 0, 0, ARROW_THICK)
	arrowTip.Position = originPos
	arrowHead1.Position = originPos
	arrowHead1.Rotation = 0
	arrowHead2.Position = originPos
	arrowHead2.Rotation = 0
end

-- Shared RenderStepped loop for both hand-card and attack drags: tracks the
-- arrow from `dragFrame`'s center to the cursor, revealing
-- highlights/hint once the cursor moves past DRAG_THRESHOLD.
local function startDragRenderLoop()
	-- Gate the arrow's first appearance (and highlight reveal) on actual
	-- cursor movement, not on the card-vs-cursor delta -- the hand card's own
	-- select/lift tween moves its center away from a still cursor, which
	-- would otherwise pop the arrow in on click before the player has
	-- dragged at all.
	local dragStartMouse = pointerPos()
	dragRenderConn = RunService.RenderStepped:Connect(function()
		if not dragFrame or not dragFrame.Parent then endDrag(); return end
		local originAbs = dragFrame.AbsolutePosition + dragFrame.AbsoluteSize/2
		local mouseAbs = pointerPos()
		if (mouseAbs - dragStartMouse).Magnitude < DRAG_THRESHOLD then
			resetArrowTo(originAbs)
			return
		end
		if dragInfo and not dragInfo.moved then
			dragInfo.moved = true
			applyDragHighlights()
			dragHintBanner.Text = dragHintText()
			dragHintBanner.Visible = true
		end
		updateArrow(originAbs, mouseAbs)
	end)
end

-- Begin a hand-card drag. `onBeforeDrag`, if provided, is called before the
-- drag starts (BattleUIController uses this to run applyHandHoverLeave on the
-- source card).
function TargetingSystem.beginDrag(cf, cardId, onBeforeDrag)
	if BattleDirector.isLocked() then return end
	local card = ctx.CardData.Cards[cardId]; if not card then return end
	if onBeforeDrag then onBeforeDrag() end
	if ctx.onDragStateChanged then ctx.onDragStateChanged(true) end
	dragFrame = cf
	if dragRenderConn then dragRenderConn:Disconnect() end
	resetArrowTo(cf.AbsolutePosition + cf.AbsoluteSize/2)
	dragInfo = {kind="card", cardId=cardId, card=card, frame=cf, zones=computeDropZones(card), moved=false}
	startDragRenderLoop()
end

function TargetingSystem.beginAttackDrag(f, slotIdx)
	if BattleDirector.isLocked() then return end
	if ctx.onDragStateChanged then ctx.onDragStateChanged(true) end
	dragFrame = f
	if dragRenderConn then dragRenderConn:Disconnect() end
	resetArrowTo(f.AbsolutePosition + f.AbsoluteSize/2)
	dragInfo = {kind="attack", attackerSlot=slotIdx, frame=f, zones=computeAttackZones(slotIdx), moved=false}
	print("[ATTACK] beginAttackDrag slot="..tostring(slotIdx).." zones="..#dragInfo.zones.." touchEnabled="..tostring(UserInput.TouchEnabled))
	startDragRenderLoop()
end

-- Cancels any in-progress drag; safe to call unconditionally.
function TargetingSystem.cancelIfDragging()
	if dragInfo then cancelDrag() end
end

-- ctx fields: main, player, Remotes, CardData, CardVisuals, BOARD_SIZE,
-- pBS, eBS, pHero, eHero, pHeroStroke, eHeroStroke, eBI,
-- getState() -> current battle state (or nil), onPlayCard(cardId, slotIdx)
function TargetingSystem.init(initCtx)
	ctx = initCtx

	-- Drag hint banner: shown once a drag exceeds DRAG_THRESHOLD, describing
	-- the dragged card's valid drop target(s) (IDEA_CARD_BATTLE.md Targeting State).
	dragHintBanner = Instance.new("TextLabel")
	dragHintBanner.Name = "DragHintBanner"
	dragHintBanner.Size = UDim2.new(0, 380, 0, 36)
	dragHintBanner.AnchorPoint = Vector2.new(0.5, 0)
	dragHintBanner.Position = UDim2.new(0.5, 0, 0, 8)
	dragHintBanner.BackgroundColor3 = Color3.fromRGB(20,20,30)
	dragHintBanner.BackgroundTransparency = 0.1
	dragHintBanner.BorderSizePixel = 0
	dragHintBanner.Font = Enum.Font.GothamBold
	dragHintBanner.TextScaled = true
	dragHintBanner.TextColor3 = Color3.fromRGB(255,255,255)
	dragHintBanner.Text = ""
	dragHintBanner.ZIndex = 50
	dragHintBanner.Visible = false
	dragHintBanner.Parent = ctx.overlay
	ctx.CardVisuals.rnd(dragHintBanner,8)

	local function mkZoneFrame()
		local f = Instance.new("Frame")
		f.BackgroundColor3 = Color3.fromRGB(80, 230, 110)
		f.BackgroundTransparency = 0.8
		f.BorderSizePixel = 0
		f.Visible = false
		f.ZIndex = 55
		f.Active = false
		Instance.new("UICorner", f).CornerRadius = UDim.new(0, 14)
		f.Parent = ctx.overlay
		return f
	end
	pBoardZone = mkZoneFrame()
	eBoardZone = mkZoneFrame()
	pSideZone  = mkZoneFrame()
	eSideZone  = mkZoneFrame()

	arrowShaft = makeArrowBar()
	arrowShaft.AnchorPoint = Vector2.new(0.5, 0.5)
	arrowHead1 = makeArrowBar()
	arrowHead2 = makeArrowBar()
	arrowHead1.Size = UDim2.new(0, ARROW_HEAD_LEN, 0, ARROW_THICK)
	arrowHead2.Size = UDim2.new(0, ARROW_HEAD_LEN, 0, ARROW_THICK)
	arrowHead1.AnchorPoint = Vector2.new(0.5, 0.5)
	arrowHead2.AnchorPoint = Vector2.new(0.5, 0.5)

	arrowTip = Instance.new("Frame")
	arrowTip.AnchorPoint = Vector2.new(0.5, 0.5)
	arrowTip.Size = UDim2.new(0, ARROW_TIP_SIZE, 0, ARROW_TIP_SIZE)
	arrowTip.BackgroundColor3 = ARROW_COLOR
	arrowTip.BorderSizePixel = 0
	arrowTip.ZIndex = 110
	arrowTip.Visible = false
	ctx.CardVisuals.pill(arrowTip)
	arrowTip.Parent = ctx.overlay

	-- Cancel an in-progress drag via Escape or right-click.
	UserInput.InputBegan:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.Escape or input.UserInputType == Enum.UserInputType.MouseButton2 then
			if dragInfo then
				cancelDrag()
			end
		end
	end)

	UserInput.InputEnded:Connect(function(input)
		if dragFrame and (input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch) then
			endDrag()
		end
	end)

	-- Track the active finger so pointerPos() can follow touch drags (the arrow
	-- render loop polls pointerPos() each frame).
	-- Track the pointer for pointerPos() so the arrow follows touch drags.
	local function trackPointer(input)
		local t = input.UserInputType
		if t == Enum.UserInputType.Touch or t == Enum.UserInputType.MouseMovement
			or t == Enum.UserInputType.MouseButton1 then
			lastPointer = Vector2.new(input.Position.X, input.Position.Y)
		end
	end
	UserInput.InputBegan:Connect(trackPointer)
	UserInput.InputChanged:Connect(trackPointer)
end

return TargetingSystem
