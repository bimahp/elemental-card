-- UIFeedback: every server reason as one sentence and one icon, shown in the Kit
-- toast (UI §10.4, ARCHITECTURE §12.3). The server sends { code, values } through
-- Notify; plain text still shows as it is while older senders are converted.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local AssetIds = require(ReplicatedStorage.Modules.AssetIds)

local UIFeedback = {}

local SHOW_SECONDS = 2.6
local FADE_SECONDS = 0.4

-- text is a string or a function of the values; icon names an AssetIds.Icons key.
-- tone "refusal" draws a red rim; "info" the normal stroke.
UIFeedback.MESSAGES = {
	MatchmakingCooldown = {
		text = function(values)
			local total = math.max(0, math.floor(tonumber(values.seconds) or 0))
			return string.format("Matchmaking cooldown: %dm %ds left (too many early forfeits today).",
				total // 60, total % 60)
		end,
		icon = "MATCHMAKING",
		tone = "refusal",
	},
	TablesBusy = {
		text = "All tables are busy right now. Please wait for one to free up.",
		icon = "MATCHMAKING",
		tone = "refusal",
	},
	SeatFailed = {
		text = "Could not seat you at the table. Please try again.",
		icon = "MATCHMAKING",
		tone = "refusal",
	},
}

local FALLBACK = "Something went wrong. Please try again."

-- Pure: turns a Notify payload into { text, image, tone }. Never errors.
function UIFeedback.resolve(payload: any)
	if type(payload) == "string" then
		return { text = payload, image = "", tone = "info" }
	end
	if type(payload) ~= "table" then
		return { text = tostring(payload), image = "", tone = "info" }
	end
	local entry = UIFeedback.MESSAGES[payload.code]
	if not entry then
		return { text = FALLBACK, image = "", tone = "refusal" }
	end
	local values = type(payload.values) == "table" and payload.values or {}
	local text = entry.text
	if type(text) == "function" then
		local ok, result = pcall(text, values)
		text = ok and result or FALLBACK
	end
	return { text = text, image = AssetIds.Icons[entry.icon] or "", tone = entry.tone or "info" }
end

-- Shows one toast in Popups, replacing the one on screen.
function UIFeedback.show(payload: any)
	local UIKit = require(ReplicatedStorage.Modules.UIKit)
	local resolved = UIFeedback.resolve(payload)
	local popups = Players.LocalPlayer:WaitForChild("PlayerGui"):WaitForChild("Popups")
	local root = popups:WaitForChild("Root")

	local old = root:FindFirstChild("Toast")
	if old then
		old:Destroy()
	end
	local toast = UIKit.clone("Toast") :: Frame
	local label = toast:FindFirstChild("Label") :: TextLabel
	local icon = toast:FindFirstChild("Icon") :: ImageLabel
	local stroke = toast:FindFirstChildOfClass("UIStroke")
	label.Text = resolved.text
	icon.Image = resolved.image
	if resolved.image == "" then
		-- A missing icon shows a tinted square, never an empty hole (UI §10.3).
		icon.BackgroundTransparency = 0
		icon.BackgroundColor3 = UIKit.token(resolved.tone == "refusal" and "Danger" or "Stroke")
	end
	if stroke and resolved.tone == "refusal" then
		stroke.Color = UIKit.token("Danger")
	end
	toast.Parent = root

	task.delay(SHOW_SECONDS, function()
		if not toast.Parent then
			return
		end
		local info = TweenInfo.new(FADE_SECONDS)
		TweenService:Create(toast, info, { BackgroundTransparency = 1 }):Play()
		TweenService:Create(label, info, { TextTransparency = 1 }):Play()
		TweenService:Create(icon, info, { ImageTransparency = 1, BackgroundTransparency = 1 }):Play()
		if stroke then
			TweenService:Create(stroke, info, { Transparency = 1 }):Play()
		end
		task.wait(FADE_SECONDS)
		toast:Destroy()
	end)
	return toast
end

return UIFeedback
