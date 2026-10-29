-- PhaseRegistry: presentation-phase handler registry, keyed by phase.type.
-- Mirrors the server's Effects/Actions registry (Ops.recordAnim events on the
-- server drive phase descriptors here on the client) -- one handler per
-- phase type, no mega-switch in BattleUIController.render().
--
-- Handler contract: function(phase, done) -- phase is the descriptor passed
-- to BattleDirector.enqueue/enqueueMany; call done() when the phase's
-- animation/UI is finished. BattleDirector force-completes the phase after
-- phase.maxDuration (or its own default) if done() is never called.
--
-- Filled in phase-by-phase per PLAN_CARD_BATTLE_REVAMP.md:
--   Phase 4 adds draw / play / attack (ported from BattleUIController's former
--   inline tweens)
--   Phase 5 adds turn_banner
--   Phase 6 adds effect (sub-dispatch on the event's action verb -> visual archetype)
--   Phase 8 adds mulligan
local TweenService = game:GetService("TweenService")
local AssetIds = require(game:GetService("ReplicatedStorage"):WaitForChild("Modules"):WaitForChild("AssetIds"))

local PhaseRegistry = {}

local function isCancelled(phase)
	return phase and phase.cancelled
end

local function safeDelay(phase, seconds, fn)
	task.delay(seconds, function()
		if isCancelled(phase) then return end
		fn()
	end)
end

local function playTween(phase, instance, info, props)
	local tw = TweenService:Create(instance, info, props)
	if phase and phase.trackTween then phase.trackTween(tw) end
	tw:Play()
	return tw
end

-- ── shared combat-feedback helpers (Phase 4: ported from BattleUIController) ──

-- Floating "-N" that rises and fades over the target.
local function popDamage(targetFrame, amount)
	local lbl=Instance.new("TextLabel")
	lbl.Size=UDim2.new(0,50,0,26)
	lbl.AnchorPoint=Vector2.new(0.5,0.5)
	lbl.Position=UDim2.new(0.5,0,0.5,0)
	lbl.BackgroundTransparency=1
	lbl.Font=Enum.Font.GothamBold
	lbl.TextScaled=true
	lbl.TextColor3=Color3.fromRGB(255,80,80)
	lbl.Text="-"..tostring(amount)
	lbl.ZIndex=50
	lbl.Parent=targetFrame
	local stroke=Instance.new("UIStroke",lbl); stroke.Color=Color3.new(0,0,0); stroke.Thickness=1.5
	local tw=TweenService:Create(lbl, TweenInfo.new(0.5,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),
		{Position=UDim2.new(0.5,0,0.5,-34), TextTransparency=1})
	tw:Play()
	tw.Completed:Connect(function() lbl:Destroy() end)
end

-- "Taunted!!" callout shown on the taunt minion before a redirected attack lands.
local function popTaunted(targetFrame)
	local lbl=Instance.new("TextLabel")
	lbl.Size=UDim2.new(1,10,0,28)
	lbl.AnchorPoint=Vector2.new(0.5,1)
	lbl.Position=UDim2.new(0.5,0,0,0)
	lbl.BackgroundTransparency=1
	lbl.Font=Enum.Font.GothamBlack
	lbl.TextScaled=true
	lbl.TextColor3=Color3.fromRGB(255,210,40)
	lbl.Text="TAUNTED!!"
	lbl.ZIndex=50
	lbl.Parent=targetFrame
	local stroke=Instance.new("UIStroke",lbl); stroke.Color=Color3.new(0,0,0); stroke.Thickness=2
	local scale=Instance.new("UIScale",lbl); scale.Scale=0.4
	TweenService:Create(scale, TweenInfo.new(0.18,Enum.EasingStyle.Back,Enum.EasingDirection.Out), {Scale=1}):Play()
	task.delay(0.55, function()
		local tw=TweenService:Create(lbl, TweenInfo.new(0.2,Enum.EasingStyle.Quad,Enum.EasingDirection.In), {TextTransparency=1})
		TweenService:Create(stroke, TweenInfo.new(0.2,Enum.EasingStyle.Quad,Enum.EasingDirection.In), {Transparency=1}):Play()
		tw:Play()
		tw.Completed:Connect(function() lbl:Destroy() end)
	end)
end

-- Impact: brief shake + scale punch (1.00 -> 1.05 -> 1.00 over 0.08s).
local function impactPunch(frame)
	local scale=frame:FindFirstChildOfClass("UIScale") or Instance.new("UIScale",frame)
	TweenService:Create(scale, TweenInfo.new(0.04,Enum.EasingStyle.Quad,Enum.EasingDirection.Out), {Scale=1.05}):Play()
	task.delay(0.04, function()
		TweenService:Create(scale, TweenInfo.new(0.04,Enum.EasingStyle.Quad,Enum.EasingDirection.In), {Scale=1}):Play()
	end)
	local origPos=frame.Position
	task.spawn(function()
		for _,dx in ipairs({4,-4,2,-2,0}) do
			frame.Position=UDim2.new(origPos.X.Scale,origPos.X.Offset+dx,origPos.Y.Scale,origPos.Y.Offset)
			task.wait(0.016)
		end
		frame.Position=origPos
	end)
end

-- ── attack (Card Lunge, per IDEA_CARD_BATTLE.md) ─────────────────────────────
-- phase = { attackerFrame, targetFrame, dmg, isDying, isFace, attackerDying,
--           onImpact, onAttackerDone, tauntRedirect }
-- Timings: creature-vs-creature 0.45s (0.05/0.15/0.10/0.15), face attack 0.37s
-- (0.05/0.12/0.08/0.12). `done` fires once the whole sequence -- including the
-- return tween -- has finished, regardless of which branch (dying or not) ran.
PhaseRegistry.attack = function(phase, done)
	local attackerFrame, targetFrame = phase.attackerFrame, phase.targetFrame
	local windup, lunge, impact, ret
	if phase.isFace then windup,lunge,impact,ret=0.05,0.12,0.08,0.12
	else windup,lunge,impact,ret=0.05,0.15,0.10,0.15 end

	if phase.tauntRedirect then popTaunted(targetFrame) end

	local aPos=attackerFrame.AbsolutePosition + attackerFrame.AbsoluteSize/2
	local tPos=targetFrame.AbsolutePosition + targetFrame.AbsoluteSize/2
	local delta=tPos-aPos
	local pct=0.25+math.random()*0.10
	local travel=delta*pct
	local origPos=attackerFrame.Position

	task.delay(windup, function()
		TweenService:Create(attackerFrame, TweenInfo.new(lunge,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),
			{Position=UDim2.new(origPos.X.Scale,origPos.X.Offset+travel.X,origPos.Y.Scale,origPos.Y.Offset+travel.Y)}):Play()
	end)
	local tScaleTween, aScaleTween
	task.delay(windup+lunge, function()
		impactPunch(targetFrame)
		popDamage(targetFrame, phase.dmg)
		if phase.onImpact then phase.onImpact() end
		if phase.isDying then
			local tScale=targetFrame:FindFirstChildOfClass("UIScale") or Instance.new("UIScale",targetFrame)
			tScaleTween = TweenService:Create(tScale, TweenInfo.new(ret,Enum.EasingStyle.Quad,Enum.EasingDirection.In), {Scale=0})
			tScaleTween:Play()
			task.delay(ret, function()
				if tScaleTween then tScaleTween:Cancel() end
				tScale.Scale=1
			end)
		end
		if phase.attackerDying then
			local aScale=attackerFrame:FindFirstChildOfClass("UIScale") or Instance.new("UIScale",attackerFrame)
			aScaleTween = TweenService:Create(aScale, TweenInfo.new(impact+ret,Enum.EasingStyle.Quad,Enum.EasingDirection.In), {Scale=0})
			aScaleTween:Play()
		end
	end)
	task.delay(windup+lunge+impact, function()
		TweenService:Create(attackerFrame, TweenInfo.new(ret,Enum.EasingStyle.Quad,Enum.EasingDirection.In), {Position=origPos}):Play()
		if phase.attackerDying then
			task.delay(ret, function()
				attackerFrame.Position=origPos
				if aScaleTween then aScaleTween:Cancel() end
				local aScale=attackerFrame:FindFirstChildOfClass("UIScale")
				if aScale then aScale.Scale=1 end
				if phase.onAttackerDone then phase.onAttackerDone() end
			end)
		end
	end)
	task.delay(windup+lunge+impact+ret, done)
end

-- ── play (Hand -> Board/Graveyard, per IDEA_CARD_BATTLE.md) ──────────────────
-- phase = { frame, mainFrame, destFrame, onLand }
PhaseRegistry.play = function(phase, done)
	local frame = phase.frame
	local main = phase.mainFrame
	local destFrame = phase.destFrame
	local startAbs, startSize = frame.AbsolutePosition, frame.AbsoluteSize
	local fScale=frame:FindFirstChildOfClass("UIScale")
	if fScale then fScale.Scale=1 end
	frame.Parent=main
	frame.AnchorPoint=Vector2.new(0,0)
	frame.Position=UDim2.new(0, startAbs.X-main.AbsolutePosition.X, 0, startAbs.Y-main.AbsolutePosition.Y)
	frame.Size=UDim2.new(0, startSize.X, 0, startSize.Y)
	frame.ZIndex=103

	local destAbs, destSize = destFrame.AbsolutePosition, destFrame.AbsoluteSize
	local PLAY_TIME=0.35
	TweenService:Create(frame, TweenInfo.new(PLAY_TIME,Enum.EasingStyle.Quad,Enum.EasingDirection.Out), {
		Position=UDim2.new(0, destAbs.X-main.AbsolutePosition.X + (destSize.X-startSize.X)/2,
		                    0, destAbs.Y-main.AbsolutePosition.Y + (destSize.Y-startSize.Y)/2),
		Size=UDim2.new(0, destSize.X, 0, destSize.Y),
		Rotation=0,
	}):Play()
	task.delay(PLAY_TIME, function()
		if phase.onLand then phase.onLand() end
		frame:Destroy()
		done()
	end)
end

-- ── draw (Deck -> Hand, per IDEA_CARD_BATTLE.md) ─────────────────────────────
-- phase = { cards = { {frame, fromPos, toPos, toRot, stagger}, ... }, glowStroke? }
PhaseRegistry.draw = function(phase, done)
	local DRAW_TIME = 0.3
	local maxDelay = 0
	for _, c in ipairs(phase.cards) do
		local scale = c.frame:FindFirstChildOfClass("UIScale")
		c.frame.Visible = false
		c.frame.Position = c.fromPos
		c.frame.Rotation = 0
		if scale then scale.Scale = 0.3 end
		safeDelay(phase, c.stagger, function()
			c.frame.Visible = true
			playTween(phase, c.frame, TweenInfo.new(DRAW_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Position=c.toPos, Rotation=c.toRot})
			if scale then playTween(phase, scale, TweenInfo.new(DRAW_TIME, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Scale=1}) end
		end)
		maxDelay = math.max(maxDelay, c.stagger + DRAW_TIME)
	end
	if phase.glowStroke then
		local stroke = phase.glowStroke
		local origColor, origThick = stroke.Color, stroke.Thickness
		stroke.Color = Color3.fromRGB(255,255,255)
		stroke.Thickness = origThick + 2
		playTween(phase, stroke, TweenInfo.new(DRAW_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Color=origColor, Thickness=origThick})
	end
	safeDelay(phase, maxDelay, done)
end

-- ── turn_banner (YOUR TURN / ENEMY TURN) ─────────────────────────────
-- phase = { label, text, color }. `label` is a persistent TextLabel owned by
-- BattleUIController (created once, reused every turn) so this handler stays
-- a pure tween executor with no knowledge of the surrounding GUI hierarchy,
-- matching the draw/play/attack handlers above.
PhaseRegistry.turn_banner = function(phase, done)
	local label = phase.label
	local scale = label:FindFirstChildOfClass("UIScale")
	local stroke = label:FindFirstChildOfClass("UIStroke")
	label.Text = phase.text
	label.BackgroundColor3 = phase.color or Color3.fromRGB(15, 15, 25)
	label.Visible = true
	label.BackgroundTransparency = 1
	label.TextTransparency = 1
	label.TextStrokeTransparency = 1
	if stroke then stroke.Transparency = 1 end
	if scale then scale.Scale = 0.7 end

	local IN_TIME, HOLD_TIME, OUT_TIME = 0.15, 0.6, 0.15
	TweenService:Create(label, TweenInfo.new(IN_TIME, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		BackgroundTransparency = 0.15, TextTransparency = 0, TextStrokeTransparency = 0,
	}):Play()
	if stroke then TweenService:Create(stroke, TweenInfo.new(IN_TIME), {Transparency = 0.3}):Play() end
	if scale then TweenService:Create(scale, TweenInfo.new(IN_TIME, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Scale = 1}):Play() end

	task.delay(IN_TIME + HOLD_TIME, function()
		TweenService:Create(label, TweenInfo.new(OUT_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			BackgroundTransparency = 1, TextTransparency = 1, TextStrokeTransparency = 1,
		}):Play()
		if stroke then TweenService:Create(stroke, TweenInfo.new(OUT_TIME), {Transparency = 1}):Play() end
		task.delay(OUT_TIME, function()
			label.Visible = false
			done()
		end)
	end)
end

-- ── cast_reveal (card zooms center-screen before its effect plays) ─────────
-- phase = { frame, mainFrame }. Restores the frame to its exact starting
-- anchor/position/parent before calling done(), so a later `play` phase
-- reusing the same frame reference picks it up from a clean hand-position
-- state (PLAN_CARD_BATTLE_REVAMP.md Phase 6).
PhaseRegistry.cast_reveal = function(phase, done)
	local frame = phase.frame
	local main = phase.mainFrame
	local startParent = frame.Parent
	local startAnchor = frame.AnchorPoint
	local startPos = frame.Position
	local startRot = frame.Rotation
	local startSizeUDim = frame.Size
	local startZIndex = frame.ZIndex
	local startAbs, startSize = frame.AbsolutePosition, frame.AbsoluteSize
	local startCenterX = startAbs.X - main.AbsolutePosition.X + startSize.X/2
	local startCenterY = startAbs.Y - main.AbsolutePosition.Y + startSize.Y/2

	frame.Parent = main
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.new(0, startCenterX, 0, startCenterY)
	frame.Size = UDim2.new(0, startSize.X, 0, startSize.Y)
	frame.ZIndex = 105

	local function restore()
		if not frame then return end
		frame.AnchorPoint = startAnchor
		frame.Position = startPos
		frame.Rotation = startRot
		frame.Size = startSizeUDim
		frame.ZIndex = startZIndex
		frame.Parent = startParent
	end

	local REVEAL_TIME, HOLD_TIME = 0.18, 0.25
	local zoomSize = UDim2.new(0, startSize.X * 1.8, 0, startSize.Y * 1.8)
	local centerPos = UDim2.new(0, main.AbsoluteSize.X * 0.5, 0, main.AbsoluteSize.Y * 0.42)

	playTween(phase, frame, TweenInfo.new(REVEAL_TIME, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Position = centerPos, Size = zoomSize, Rotation = 0,
	})

	safeDelay(phase, REVEAL_TIME + HOLD_TIME, function()
		playTween(phase, frame, TweenInfo.new(REVEAL_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Position = UDim2.new(0, startCenterX, 0, startCenterY),
			Size = UDim2.new(0, startSize.X, 0, startSize.Y),
		})
		safeDelay(phase, REVEAL_TIME, function()
			restore()
			done()
		end)
	end)

	if phase.trackConnection then
		phase.trackConnection({ Disconnect = restore })
	end
end

-- ── effect (sub-dispatch on visual archetype) ────────────────────────
-- phase = { archetype, fromFrame, toFrame, amount, mainFrame, color }
-- Only "projectile" is a real handler this pass; any other archetype
-- (reserved for the future VFX-library follow-up) completes instantly rather
-- than hanging the Director queue.
PhaseRegistry.effect = function(phase, done)
	if phase.archetype ~= "projectile" then done(); return end
	local main = phase.mainFrame
	local fromFrame, toFrame = phase.fromFrame, phase.toFrame
	local fromPos = fromFrame.AbsolutePosition + fromFrame.AbsoluteSize/2
	local toPos = toFrame.AbsolutePosition + toFrame.AbsoluteSize/2

	local bolt = Instance.new("ImageLabel")
	bolt.Name = "ProjectileBolt"
	bolt.Size = UDim2.new(0, 30, 0, 30)
	bolt.AnchorPoint = Vector2.new(0.5, 0.5)
	bolt.BackgroundTransparency = 1
	bolt.ScaleType = Enum.ScaleType.Fit
	bolt.Image = AssetIds.Icons.ENERGY
	bolt.ImageColor3 = phase.color or Color3.fromRGB(255, 224, 70)
	bolt.ZIndex = 106
	bolt.Position = UDim2.new(0, fromPos.X - main.AbsolutePosition.X, 0, fromPos.Y - main.AbsolutePosition.Y)
	bolt.Parent = main
	local boltGlow = Instance.new("UIStroke", bolt)
	boltGlow.Color = Color3.new(1,1,1)
	boltGlow.Thickness = 2
	boltGlow.Transparency = 0.4

	local TRAVEL_TIME = 0.22
	TweenService:Create(bolt, TweenInfo.new(TRAVEL_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		Position = UDim2.new(0, toPos.X - main.AbsolutePosition.X, 0, toPos.Y - main.AbsolutePosition.Y),
	}):Play()
	task.delay(TRAVEL_TIME, function()
		bolt:Destroy()
		impactPunch(toFrame)
		if phase.amount and phase.amount > 0 then popDamage(toFrame, phase.amount) end
		done()
	end)
end

return PhaseRegistry
