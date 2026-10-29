-- ── LoadingScreen ────────────────────────────────────────────────────────────────────────
-- Runs in ReplicatedFirst, before the rest of the game replicates. Shows a
-- branded loading screen and preloads gameplay art with retry so it is present
-- on the FIRST join (no rejoin needed).
--
-- Chicken-and-egg note: the functional layer of this screen uses ZERO remote
-- assets — a solid BackgroundColor3 fill, default-font text, and Frame-based
-- progress bar all render instantly. The decorative background IMAGE is layered
-- on top at full transparency and faded in only if/when it loads; if it never
-- loads the player simply keeps the solid color. So the screen can never be
-- blank/broken even though its background is itself an asset.
-- ──────────────────────────────────────────────────────────────────────────────────
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

ReplicatedFirst:RemoveDefaultLoadingScreen()

local BG_TIMEOUT     = 4    -- max seconds to wait on the decorative background image
local FADE_OUT       = 0.5
local BG_COLOR       = Color3.fromRGB(14, 16, 26)
local ACCENT         = Color3.fromRGB(120, 170, 255)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- ── Build the screen (no remote assets) ────────────────────────────────
local gui = Instance.new("ScreenGui")
gui.Name = "LoadingScreen"
gui.IgnoreGuiInset = true
gui.DisplayOrder = 1000
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

local root = Instance.new("Frame")
root.Name = "Root"
root.Size = UDim2.fromScale(1, 1)
root.BackgroundColor3 = BG_COLOR  -- instant solid fallback
root.BorderSizePixel = 0
root.ZIndex = 1
root.Parent = gui

-- Decorative background image, hidden until proven loaded
local bgImage = Instance.new("ImageLabel")
bgImage.Name = "Background"
bgImage.Size = UDim2.fromScale(1, 1)
bgImage.BackgroundTransparency = 1
bgImage.ImageTransparency = 1
bgImage.ScaleType = Enum.ScaleType.Crop
bgImage.ZIndex = 2
bgImage.Parent = root

-- Dim scrim so text stays legible over any background
local scrim = Instance.new("Frame")
scrim.Size = UDim2.fromScale(1, 1)
scrim.BackgroundColor3 = Color3.new(0, 0, 0)
scrim.BackgroundTransparency = 0.45
scrim.BorderSizePixel = 0
scrim.ZIndex = 3
scrim.Parent = root

local title = Instance.new("TextLabel")
title.Name = "Title"
title.AnchorPoint = Vector2.new(0.5, 0.5)
title.Position = UDim2.fromScale(0.5, 0.4)
title.Size = UDim2.fromScale(0.8, 0.12)
title.BackgroundTransparency = 1
title.Font = Enum.Font.GothamBold
title.Text = "Crystal Element"
title.TextScaled = true
title.TextColor3 = Color3.new(1, 1, 1)
title.ZIndex = 4
title.Parent = root

local status = Instance.new("TextLabel")
status.Name = "Status"
status.AnchorPoint = Vector2.new(0.5, 0.5)
status.Position = UDim2.fromScale(0.5, 0.62)
status.Size = UDim2.fromScale(0.6, 0.04)
status.BackgroundTransparency = 1
status.Font = Enum.Font.Gotham
status.Text = "Loading assets…"
status.TextScaled = true
status.TextColor3 = Color3.fromRGB(200, 205, 220)
status.ZIndex = 4
status.Parent = root

-- Progress bar (Frames only)
local barTrack = Instance.new("Frame")
barTrack.Name = "BarTrack"
barTrack.AnchorPoint = Vector2.new(0.5, 0.5)
barTrack.Position = UDim2.fromScale(0.5, 0.68)
barTrack.Size = UDim2.fromScale(0.5, 0.02)
barTrack.BackgroundColor3 = Color3.fromRGB(40, 44, 60)
barTrack.BorderSizePixel = 0
barTrack.ZIndex = 4
barTrack.Parent = root
Instance.new("UICorner", barTrack).CornerRadius = UDim.new(1, 0)

local barFill = Instance.new("Frame")
barFill.Name = "Fill"
barFill.Size = UDim2.fromScale(0, 1)
barFill.BackgroundColor3 = ACCENT
barFill.BorderSizePixel = 0
barFill.ZIndex = 5
barFill.Parent = barTrack
Instance.new("UICorner", barFill).CornerRadius = UDim.new(1, 0)

gui.Parent = playerGui

-- ── Modules ───────────────────────────────────────────────────
local modules = ReplicatedStorage:WaitForChild("Modules")
local AssetIds = require(modules:WaitForChild("AssetIds"))
local AssetPreloader = require(modules:WaitForChild("AssetPreloader"))

local function setProgress(frac)
	frac = math.clamp(frac, 0, 1)
	TweenService:Create(barFill, TweenInfo.new(0.2), { Size = UDim2.fromScale(frac, 1) }):Play()
end

-- ── Decorative background: preload then fade in, never block ───────────────
task.spawn(function()
	local got = false
	task.spawn(function()
		local summary = AssetPreloader.preload({ AssetIds.LoadingBackground }, {
			attempts = 2,
			assetTimeout = 4,
			concurrency = 1,
			parent = playerGui,
		})
		got = summary.ok
	end)
	local t0 = os.clock()
	while not got and os.clock() - t0 < BG_TIMEOUT do task.wait(0.1) end
	if got then
		bgImage.Image = AssetIds.LoadingBackground
		TweenService:Create(bgImage, TweenInfo.new(0.6), { ImageTransparency = 0 }):Play()
	end
end)

-- Do not preload Workspace/Lighting here. Roblox streams world assets as
-- needed, and a whole-world request competes with the small essential UI gate.

-- ── Essential shared assets: gated, with callback-verified retry ───────
local criticalDone = false
local criticalSummary
task.spawn(function()
	local ok, result = pcall(function()
		return AssetPreloader.preload(AssetIds.startupList(), {
			attempts = 2,
			assetTimeout = 6,
			concurrency = 4,
			parent = playerGui,
			onProgress = function(done, total)
				if total > 0 then
					status.Text = ("Loading essential assets… %d/%d"):format(done, total)
					setProgress(done / total)
				end
			end,
		})
	end)
	if ok then
		criticalSummary = result
	else
		criticalSummary = {
			ok = false,
			total = 0,
			loaded = 0,
			failed = {},
			error = tostring(result),
		}
	end
	criticalDone = true
end)

-- ── Gate: essential shared art must finish its bounded retry cycle ───────
while not game:IsLoaded() do
	task.wait(0.1)
end
while not criticalDone do
	task.wait(0.1)
end

if criticalSummary and criticalSummary.error then
	warn("[LoadingScreen] essential preload crashed: " .. criticalSummary.error)
elseif criticalSummary and #criticalSummary.failed > 0 then
	warn(("[LoadingScreen] %d essential asset(s) failed to preload after retries: %s")
		:format(#criticalSummary.failed, AssetPreloader.describeFailures(criticalSummary)))
elseif criticalSummary then
	print(("[LoadingScreen] preloaded %d/%d essential assets")
		:format(criticalSummary.loaded, criticalSummary.total))
else
	warn("[LoadingScreen] essential preload returned no summary")
end

setProgress(1)
status.Text = "Ready"

-- ── Fade out ────────────────────────────────────────────────
task.wait(0.15)
local ti = TweenInfo.new(FADE_OUT, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
TweenService:Create(root, ti, { BackgroundTransparency = 1 }):Play()
for _, d in ipairs(root:GetDescendants()) do
	if d:IsA("Frame") then
		TweenService:Create(d, ti, { BackgroundTransparency = 1 }):Play()
	elseif d:IsA("ImageLabel") then
		TweenService:Create(d, ti, { ImageTransparency = 1, BackgroundTransparency = 1 }):Play()
	elseif d:IsA("TextLabel") then
		TweenService:Create(d, ti, { TextTransparency = 1, BackgroundTransparency = 1 }):Play()
	end
end
task.wait(FADE_OUT)
gui:Destroy()
