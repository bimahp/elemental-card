-- MatchmakingController: HUD icon + panel for cross-server matchmaking
-- (PLAN_MATCHMAKING Phase 5). Mirrors ItemMallController's shell/page pattern
-- verbatim (small enough to duplicate rather than extract a premature shared
-- module, matching how ItemMallController itself didn't share this pattern).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local gui = playerGui:WaitForChild("MatchmakingUI")
local hud = playerGui:WaitForChild("Hud")
local matchButton = hud:WaitForChild("TopRightAnchor"):WaitForChild("MatchmakingButton")
local floatingLabel = matchButton:WaitForChild("FloatingLabel")
local remotes = ReplicatedStorage:WaitForChild("Remotes")

local UI = require(playerGui:WaitForChild("SharedUI"):WaitForChild("UIComponents"))
local Theme = UI.Theme
local AssetIds = require(ReplicatedStorage.Modules.AssetIds)
local PanelCoordinator = require(ReplicatedStorage.Modules.PanelCoordinator)

local dialog = gui:WaitForChild("Dialog")
local scrim = gui:WaitForChild("Scrim")
local titleBar = dialog:WaitForChild("TitleBar")
local title = titleBar:WaitForChild("Title")
local closeButton = titleBar:WaitForChild("CloseButton")
local body = dialog:WaitForChild("Body")

UI.styleScrim(scrim)
local fullscreenBackdrop = UI.bindFullscreenBackdrop(gui, scrim)
UI.applyModalShell(dialog, titleBar, title, closeButton, nil, Theme.Accents.Matchmaking)
UI.createHeaderIcon(titleBar, AssetIds.Icons.MATCHMAKING)
title.Text = "Matchmaking"
-- applyModalShell only gives the title a wide (76px) left margin when a
-- backButton is passed -- otherwise it assumes no header icon and uses 24px,
-- which the icon (spanning out to ~63px) then overlaps. This panel has no
-- back navigation, so fix the margin directly instead of wiring an unused
-- fake backButton just to trigger the wider-margin branch.
title.Position = UDim2.new(0, 76, 0.5, 0)
title.Size = UDim2.new(1, -142, 1, 0)

-- applyModalShell/createModalShell are the only two things that ever
-- position+size Body -- this controller uses applyModalShell (no page-stack
-- needed), so Body's layout is this controller's own responsibility, exactly
-- like ItemMallController explicitly sets these same three lines. Omitting
-- them left Body at its default zero Size, which collapsed every
-- scale-relative position inside it (including the primary button) to the
-- Dialog's origin instead of the panel's content area.
body.Position = UDim2.new(0, 18, 0, 76)
body.Size = UDim2.new(1, -36, 1, -104)
body.BackgroundTransparency = 1

-- ── Elapsed-timer (client display only; server is the sole authority on state) ──
-- Adapted from MulliganController's existing countdown pattern -- same
-- RunService.Heartbeat + os.clock() mechanism, counting UP from a start
-- clock instead of down from a deadline. No auto-stop condition: this only
-- stops on a server-confirmed "cancelled"/"matched" update or the shared
-- battle-remote close wiring below.
local timerConn
local startClock

local function fmtElapsed(seconds)
	seconds = math.max(0, math.floor(seconds or 0))
	local m = math.floor(seconds / 60)
	local s = seconds % 60
	return string.format("%d:%02d", m, s)
end

local function stopTimer()
	if timerConn then timerConn:Disconnect(); timerConn = nil end
end

local function startTimer()
	stopTimer()
	startClock = os.clock()
	floatingLabel.Text = fmtElapsed(0)
	timerConn = RunService.Heartbeat:Connect(function()
		floatingLabel.Text = fmtElapsed(os.clock() - startClock)
	end)
end

local function resetIcon()
	stopTimer()
	floatingLabel.Text = "Matchmaking"
end

-- ── Panel content (single page -- no page-stack needed for this feature's v1 scope) ──
local queued = false

local function clearBody()
	for _, child in ipairs(body:GetChildren()) do child:Destroy() end
end

local function renderPanel()
	clearBody()

	local levelVal = player:FindFirstChild("Level")
	local levelLabel = Instance.new("TextLabel")
	levelLabel.Name = "LevelLabel"
	levelLabel.Size = UDim2.new(1, 0, 0, 42)
	levelLabel.BackgroundTransparency = 1
	levelLabel.Text = "Level " .. tostring(levelVal and levelVal.Value or 1)
	levelLabel.TextColor3 = Theme.Colors.TextSoft
	levelLabel.Font = Theme.Fonts.BodyBold
	levelLabel.TextSize = 20
	levelLabel.TextXAlignment = Enum.TextXAlignment.Left
	levelLabel.Parent = body

	if queued then
		local elapsedLabel = Instance.new("TextLabel")
		elapsedLabel.Name = "ElapsedLabel"
		elapsedLabel.Size = UDim2.new(1, 0, 0, 30)
		elapsedLabel.Position = UDim2.new(0, 0, 0, 44)
		elapsedLabel.BackgroundTransparency = 1
		elapsedLabel.Text = "Searching for an opponent..."
		elapsedLabel.TextColor3 = Theme.Colors.TextMuted
		elapsedLabel.Font = Theme.Fonts.Body
		elapsedLabel.TextSize = 15
		elapsedLabel.TextXAlignment = Enum.TextXAlignment.Left
		elapsedLabel.Parent = body
	end

	local primaryButton = UI.createPrimaryButton(body,
		queued and "Cancel Matchmaking" or "Find Opponent",
		nil,
		{ size = UDim2.fromOffset(260, 52), color = queued and Theme.Colors.Danger or Theme.Colors.Success }
	)
	primaryButton.AnchorPoint = Vector2.new(0.5, 0.5)
	primaryButton.Position = UDim2.fromScale(0.5, 0.62)

	primaryButton.Activated:Connect(function()
		if queued then
			remotes.CancelMatchmaking:FireServer()
		else
			remotes.JoinMatchmaking:FireServer()
		end
	end)
end

local function open()
	if not PanelCoordinator.claim("Matchmaking") then return end
	gui.Enabled = true
	renderPanel()
end

local function close()
	gui.Enabled = false
	clearBody()
	PanelCoordinator.release("Matchmaking")
end
PanelCoordinator.register("Matchmaking", { close = close })

-- Clicking the icon opens the panel whether idle ("Find Opponent") or already
-- queued (ticking -- reopens showing the live timer + "Cancel Matchmaking"),
-- per the confirmed cancel flow.
matchButton.Activated:Connect(function()
	if gui.Enabled then close() else open() end
end)
closeButton.Activated:Connect(close)
scrim.Activated:Connect(close)
fullscreenBackdrop.Activated:Connect(close)

-- Server-confirmed state transitions -- displayed state is never purely
-- optimistic (same defensive posture as BattleLoading/BattleSeated/
-- UpdateBattleState gating elsewhere in this project).
remotes.MatchmakingUpdate.OnClientEvent:Connect(function(status)
	if status == "queued" then
		queued = true
		startTimer()
		close()
	elseif status == "cancelled" then
		queued = false
		resetIcon()
		close()
	elseif status == "matched" then
		queued = false
		resetIcon()
		close()
	end
end)

for _, remoteName in ipairs({ "BattleLoading", "BattleSeated", "UpdateBattleState" }) do
	remotes:WaitForChild(remoteName).OnClientEvent:Connect(function()
		close()
		if queued then
			queued = false
			resetIcon()
		end
	end)
end

print("[MatchmakingController] loaded")
