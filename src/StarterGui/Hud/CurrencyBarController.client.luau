-- CurrencyBarController: authoritative Crystal Shards and Card Fragments HUD readout.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local bar = script.Parent:WaitForChild("CurrencyBar")
local shardsText = bar:WaitForChild("ShardsBadge"):WaitForChild("Count")
local fragmentsText = bar:WaitForChild("FragmentsBadge"):WaitForChild("Count")
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local GetQuestSnapshot = remotes:WaitForChild("GetQuestSnapshot")
local QuestStateChanged = remotes:WaitForChild("QuestStateChanged")
local UI = require(player:WaitForChild("PlayerGui"):WaitForChild("SharedUI"):WaitForChild("UIComponents"))
local Theme = UI.Theme

local function formatCount(value)
	value = math.max(0, math.floor(tonumber(value) or 0))
	if value >= 1000000 then
		return string.format("%.1fM", value / 1000000):gsub("%.0M$", "M")
	end
	if value >= 1000 then
		return string.format("%.1fK", value / 1000):gsub("%.0K$", "K")
	end
	return tostring(value)
end

local function styleBadge(badge, accent)
	badge.BackgroundColor3 = Theme.Colors.PanelDeep
	badge.BorderSizePixel = 0
	local corner = badge:FindFirstChildOfClass("UICorner") or Instance.new("UICorner", badge)
	corner.CornerRadius = UDim.new(0, 18)
	local stroke = badge:FindFirstChildOfClass("UIStroke") or Instance.new("UIStroke", badge)
	stroke.Color = accent
	stroke.Thickness = 2
	local count = badge:FindFirstChild("Count")
	if count then
		count.Font = Theme.Fonts.BodyBold
		count.TextColor3 = Theme.Colors.TextSoft
		count.TextSize = 14
		count.TextTruncate = Enum.TextTruncate.AtEnd
	end
end
styleBadge(bar:WaitForChild("ShardsBadge"), Theme.Colors.Shard)
styleBadge(bar:WaitForChild("FragmentsBadge"), Theme.Colors.Fragment)

local function apply(snapshot)
	if type(snapshot) ~= "table" then return end
	if type(snapshot.crystalShards) == "number" then
		shardsText.Text = formatCount(snapshot.crystalShards) .. " Shards"
	end
	if type(snapshot.cardFragments) == "number" then
		fragmentsText.Text = formatCount(snapshot.cardFragments) .. " Fragments"
	end
end

QuestStateChanged.OnClientEvent:Connect(apply)
task.spawn(function()
	for _ = 1, 5 do
		local ok, snapshot = pcall(function() return GetQuestSnapshot:InvokeServer() end)
		if ok and type(snapshot) == "table" then apply(snapshot); return end
		task.wait(1)
	end
end)
