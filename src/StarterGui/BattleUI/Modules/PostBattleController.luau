-- PostBattleController: battle result modal and animated EXP progress fill.
local TweenService = game:GetService("TweenService")

local PostBattleController = {}
PostBattleController.__index = PostBattleController

local function rewardTextFrom(data)
	local rewards = data and data.rewards
	local parts = {}
	if rewards then
		if rewards.message then parts[#parts + 1] = rewards.message end
		if (rewards.cardFragments or 0) > 0 then
			local amount = rewards.cardFragments
			parts[#parts + 1] = "+" .. amount .. " Card Fragment" .. (amount == 1 and "" or "s")
		end
		if rewards.firstClear then parts[#parts + 1] = "First Clear Bonus!" end
		if (rewards.exp or 0) > 0 then parts[#parts + 1] = "+" .. rewards.exp .. " EXP" end
	end
	local text = (#parts > 0) and table.concat(parts, "\n") or "No reward this time."
	if data and data.isTutorialComplete then text = "Tutorial Complete!\n" .. text end
	return text
end

function PostBattleController.new(player, gui, postFrame)
	local self = setmetatable({}, PostBattleController)
	self.player = player
	self.gui = gui
	self.post = postFrame

	local UI = require(player.PlayerGui:WaitForChild("SharedUI"):WaitForChild("UIComponents"))
	local Theme = UI.Theme
	self.scrim = gui:WaitForChild("PostBattleScrim")
	self.titleBar = postFrame:WaitForChild("TitleBar")
	local title = self.titleBar:WaitForChild("Title")
	self.closeButton = self.titleBar:WaitForChild("CloseButton")
	local body = postFrame:WaitForChild("Body")
	self.resultLabel = body:WaitForChild("ResultLabel")
	self.rewardLabel = body:WaitForChild("RewardLabel")
	self.levelLabel = body:WaitForChild("LevelLabel")
	self.expFill = body:WaitForChild("ExpBarTrack"):WaitForChild("Fill")
	self.continueButton = body:WaitForChild("ContinueBtn")
	self.successColor = Theme.Colors.Success
	self.dangerColor = Theme.Colors.Danger
	self.expTween = nil
	self.baseDisplayOrder = gui.DisplayOrder
	self.modalDisplayOrder = 50

	UI.styleScrim(self.scrim)
	self.scrim.Modal = true
	self.scrim.InputSink = Enum.InputSink.All
	self.scrim.Visible = false
	UI.applyModalShell(postFrame, self.titleBar, title, self.closeButton, nil, Theme.Colors.Success)
	title.Text = "Battle Result"
	self.expFill.Size = UDim2.new(0, 0, 1, 0)
	return self
end

function PostBattleController:hide()
	if self.expTween then self.expTween:Cancel(); self.expTween = nil end
	self.post.Visible = false
	self.scrim.Visible = false
	self.gui.DisplayOrder = self.baseDisplayOrder
end

function PostBattleController:showResult(data)
	local won = data and data.winner == "player"
	self.resultLabel.Text = won and "YOU WON!" or "YOU LOST."
	self.resultLabel.TextColor3 = won and Color3.fromRGB(255, 215, 60) or Color3.fromRGB(220, 90, 90)
	self.titleBar.BackgroundColor3 = won and self.successColor or self.dangerColor
	self.rewardLabel.Text = rewardTextFrom(data or {})

	if self.expTween then self.expTween:Cancel(); self.expTween = nil end
	local exp = data and data.exp
	local fraction = 0
	if exp then
		self.levelLabel.Text = "Level " .. tostring(exp.level or 1)
		local needed = exp.needed or 0
		fraction = needed > 0 and math.clamp((exp.into or 0) / needed, 0, 1) or 0
	else
		self.levelLabel.Text = "Level --"
	end
	self.expFill.Size = UDim2.new(0, 0, 1, 0)
	self.gui.DisplayOrder = self.modalDisplayOrder
	self.post.Visible = true
	self.scrim.Visible = true
	task.delay(0.18, function()
		if not self.post.Visible then return end
		self.expTween = TweenService:Create(
			self.expFill,
			TweenInfo.new(1.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Size = UDim2.new(fraction, 0, 1, 0) }
		)
		self.expTween:Play()
	end)
end

function PostBattleController:connectDismiss(callback)
	self.continueButton.Activated:Connect(callback)
	self.closeButton.Activated:Connect(callback)
end

return PostBattleController
