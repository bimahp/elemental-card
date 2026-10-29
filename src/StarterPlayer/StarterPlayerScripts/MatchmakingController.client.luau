-- MatchmakingController: HUD icon + panel for cross-server matchmaking
-- (PLAN_MATCHMAKING Phase 5). The panel is authored in Panels.Root.Matchmaking by
-- matchmaking-ui-v1 (UI §10); this script only fills it, switches its state and wires it.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local hud = playerGui:WaitForChild("Hud")
local matchButton = hud:WaitForChild("TopRightAnchor"):WaitForChild("MatchmakingButton")
local floatingLabel = matchButton:WaitForChild("FloatingLabel")
local remotes = ReplicatedStorage:WaitForChild("Remotes")

local UIKit = require(ReplicatedStorage.Modules.UIKit)
local PanelCoordinator = require(ReplicatedStorage.Modules.PanelCoordinator)

local panel = playerGui:WaitForChild("Panels"):WaitForChild("Root"):WaitForChild("Matchmaking")
local closeButton = panel:WaitForChild("TitleBar"):WaitForChild("CloseButton")
local body = panel:WaitForChild("Body")
local levelLabel = body:WaitForChild("LevelLabel")
local statusLabel = body:WaitForChild("StatusLabel")
local findButton = body:WaitForChild("FindButton")
local cancelButton = body:WaitForChild("CancelButton")

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

-- ── Panel ──
local queued = false

local function render()
	local levelVal = player:FindFirstChild("Level")
	levelLabel.Text = "Level " .. tostring(levelVal and levelVal.Value or 1)
	statusLabel.Visible = queued
	findButton.Visible = not queued
	cancelButton.Visible = queued
end

local function open()
	if not PanelCoordinator.claim("Matchmaking") then return end
	render()
	panel.Visible = true
	UIKit.entrance(panel)
end

local function close()
	panel.Visible = false
	PanelCoordinator.release("Matchmaking")
end
PanelCoordinator.register("Matchmaking", { close = close, backdrop = true })

-- The press lock keeps a double tap from sending two requests (UI §10.3).
UIKit.bindPress(findButton, function() remotes.JoinMatchmaking:FireServer() end)
UIKit.bindPress(cancelButton, function() remotes.CancelMatchmaking:FireServer() end)
UIKit.bindPress(closeButton, close)

-- Clicking the icon opens the panel whether idle ("Find Opponent") or already
-- queued (ticking -- reopens showing the live timer + "Cancel Matchmaking"),
-- per the confirmed cancel flow.
matchButton.Activated:Connect(function()
	if panel.Visible then close() else open() end
end)

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
