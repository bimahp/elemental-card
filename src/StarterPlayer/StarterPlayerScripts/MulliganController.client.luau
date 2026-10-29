-- MulliganController: standalone pre-battle mulligan UI (PLAN_CARD_BATTLE_REVAMP.md
-- Phase 8). Driven directly by OfferMulligan/ConfirmMulligan, independent of
-- BattleDirector/PhaseRegistry -- the mulligan window deliberately never
-- fires UpdateBattleState (Phase 7), so there is no render() cycle to enqueue
-- a phase into. Same shape as DialogueController for onboarding: its own
-- self-contained flow.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local CardData = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("CardData"))

local playerGui = player:WaitForChild("PlayerGui")
local gui = playerGui:WaitForChild("MulliganUI")
local dialog = gui:WaitForChild("Dialog")
local cardRow = dialog:WaitForChild("CardRow")
local waitingLabel = dialog:WaitForChild("WaitingLabel")
local confirmBtn = dialog:WaitForChild("ConfirmBtn")
local timerLabel = dialog:WaitForChild("TimerLabel")
local subtitle = dialog:WaitForChild("Subtitle")

local battleUI = playerGui:WaitForChild("BattleUI")
local CardVisuals = require(battleUI.Modules.CardVisuals)

-- Display-only mirror of DuelSession.MULLIGAN_TIMEOUT_SECONDS -- the server
-- is the sole authority on the actual auto-keep timeout; this just paces the
-- visible countdown so it doesn't need to match to the millisecond.
local MULLIGAN_TIMEOUT_SECONDS = 30

local INSTRUCTIONS = "Tap Re-draw on one card to swap it, then tap Battle."

local tiles = {}  -- index -> { frame }
local hand = nil
local redrawnIndex = nil
local redrawing = false
local deadline = nil
local timerConn

local function fmtTimer(seconds)
	seconds = math.max(0, math.ceil(seconds or 0))
	return string.format("0:%02d", seconds)
end

local function clearTiles()
	for _, c in ipairs(cardRow:GetChildren()) do
		if not c:IsA("UIListLayout") then c:Destroy() end
	end
	tiles = {}
end

-- buildTile and pickRedraw reference each other (picking a card rebuilds
-- its tile; the tile's button calls back into pickRedraw), so both names
-- are forward-declared and assigned as plain function values below.
local buildTile
local pickRedraw

-- Redraw happens immediately and for real: this asks the server to swap
-- this exact hand slot right now and shows the actual new card the instant
-- it comes back, instead of just marking the old card and waiting for
-- Battle. At most one redraw per mulligan -- picking one removes every
-- Re-draw button (including the picked card's own) and can't be undone.
pickRedraw = function(idx)
	if redrawnIndex or redrawing then return end
	redrawing = true
	local ok, cardIdOrErr = Remotes.RedrawMulliganCard:InvokeServer(idx)
	redrawing = false
	if not ok then return end
	redrawnIndex = idx
	hand[idx] = cardIdOrErr
	local order = tiles[idx].frame.LayoutOrder
	tiles[idx].frame:Destroy()
	buildTile(idx, cardIdOrErr)
	tiles[idx].frame.LayoutOrder = order
	for _, t in pairs(tiles) do
		local btn = t.frame:FindFirstChild("RedrawBtn")
		if btn then btn:Destroy() end
	end
end

buildTile = function(idx, cardId)
	local card = CardData.Cards[cardId]
	local frame = CardVisuals.buildCardFrame(112, 152, "full")
	frame.LayoutOrder = idx
	local stk = frame:FindFirstChildOfClass("UIStroke")
	if stk and card then
		stk.Thickness = 4
		stk.Color = CardVisuals.TC_type[card.battleType] or CardVisuals.TC_type.NEUTRAL
	end
	if card then
		local abilName, abilText = CardData.getAbilityDisplay(cardId)
		CardVisuals.updateCardFrame(frame, {
			cardId = cardId, battleType = card.battleType, cardType = card.cardType, race = card.race,
			cost = card.cost, chargeCost = card.chargeCost, name = card.name,
			atk = (card.cardType == "creature") and card.atk or nil,
			hp = (card.cardType == "creature") and card.hp or nil,
			abilityName = abilName, abilityText = abilText,
		})
	end

	-- Parented directly to the card's own frame (not a separate row-level
	-- layout), so it moves together with the card and needs no coordination
	-- with the CardRow's UIListLayout.
	local redrawBtn = Instance.new("TextButton")
	redrawBtn.Name = "RedrawBtn"
	redrawBtn.AnchorPoint = Vector2.new(0.5, 0)
	redrawBtn.Position = UDim2.new(0.5, 0, 1, 6)
	redrawBtn.Size = UDim2.new(1, 0, 0, 28)
	redrawBtn.BackgroundColor3 = Color3.fromRGB(160, 30, 30)
	redrawBtn.BorderSizePixel = 0
	redrawBtn.Font = Enum.Font.FredokaOne
	redrawBtn.TextSize = 16
	redrawBtn.TextColor3 = Color3.new(1, 1, 1)
	redrawBtn.Text = "Re-draw"
	redrawBtn.ZIndex = 5
	Instance.new("UICorner", redrawBtn).CornerRadius = UDim.new(0, 6)
	redrawBtn.Parent = frame
	redrawBtn.Activated:Connect(function()
		pickRedraw(idx)
	end)

	frame.Parent = cardRow
	tiles[idx] = { frame = frame }
end

local function stopTimer()
	if timerConn then timerConn:Disconnect(); timerConn = nil end
end

local function startTimer()
	stopTimer()
	deadline = os.clock() + MULLIGAN_TIMEOUT_SECONDS
	timerLabel.Text = fmtTimer(MULLIGAN_TIMEOUT_SECONDS)
	timerConn = RunService.Heartbeat:Connect(function()
		local remaining = deadline - os.clock()
		timerLabel.Text = fmtTimer(remaining)
		if remaining <= 0 then stopTimer() end
	end)
end

local function showWaiting()
	cardRow.Visible = false
	waitingLabel.Visible = true
	confirmBtn.Visible = false
	subtitle.Text = "Waiting for your opponent..."
end

local function closeUI()
	stopTimer()
	gui.Enabled = false
	clearTiles()
	redrawnIndex = nil
	redrawing = false
	cardRow.Visible = true
	waitingLabel.Visible = false
	confirmBtn.Visible = true
	confirmBtn.Active = true
	subtitle.Text = INSTRUCTIONS
end

Remotes.OfferMulligan.OnClientEvent:Connect(function(dealtHand)
	hand = dealtHand
	redrawnIndex = nil
	redrawing = false
	clearTiles()
	gui.Enabled = false
	confirmBtn.Active = true
	confirmBtn.Visible = true
	cardRow.Visible = true
	waitingLabel.Visible = false
	subtitle.Text = INSTRUCTIONS
	for i, cardId in ipairs(hand) do
		buildTile(i, cardId)
	end
	-- Let BattleUIController enter battle camera/seat presentation first; without
	-- this, First Draw can appear over the free-roam camera before the seated view
	-- has a frame to settle.
	task.delay(0.45, function()
		if hand ~= dealtHand then return end
		gui.Enabled = true
		startTimer()
	end)
end)

confirmBtn.Activated:Connect(function()
	if not hand or not confirmBtn.Active then return end
	confirmBtn.Active = false
	Remotes.ConfirmMulligan:FireServer()
	showWaiting()
end)

-- The real battle's first UpdateBattleState is the signal that mulligan (for
-- both seats) is fully resolved -- close the mulligan UI and hand off to the
-- normal BattleUI.
Remotes.UpdateBattleState.OnClientEvent:Connect(function()
	if gui.Enabled then closeUI() end
end)

print("[MulliganController] loaded")
