-- UIFeedbackController: shows every Notify from the server in the Kit toast (UI §10.4).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UIFeedback = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("UIFeedback"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

Remotes:WaitForChild("Notify").OnClientEvent:Connect(UIFeedback.show)
