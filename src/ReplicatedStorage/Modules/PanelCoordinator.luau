-- PanelCoordinator: one world panel open at a time; Escape or gamepad B goes back
-- (UI §10.1, ARCHITECTURE §12.3). Client only.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local PanelCoordinator = {}

type Handlers = { close: () -> boolean?, back: (() -> ())? }

local panels: { [string]: Handlers } = {}
local current: string? = nil
local started = false

local BACK_KEYS = {
	[Enum.KeyCode.Escape] = true,
	[Enum.KeyCode.ButtonB] = true,
}
-- Battle states close every panel (UI §4.1).
local BATTLE_REMOTES = { "BattleLoading", "BattleSeated", "UpdateBattleState" }

-- Input and battle hooks start with the first panel in a running game, so specs
-- can use the module in Edit mode without them.
local function start()
	if started or not RunService:IsRunning() then
		return
	end
	started = true
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if not gameProcessed and BACK_KEYS[input.KeyCode] then
			PanelCoordinator.back()
		end
	end)
	task.spawn(function()
		local remotes = ReplicatedStorage:WaitForChild("Remotes")
		for _, name in ipairs(BATTLE_REMOTES) do
			remotes:WaitForChild(name).OnClientEvent:Connect(PanelCoordinator.closeAll)
		end
	end)
end

-- close may return false to refuse (for example during a purchase).
-- back defaults to close; a panel with pages passes its own.
function PanelCoordinator.register(id: string, handlers: Handlers)
	assert(type(handlers.close) == "function", "PanelCoordinator: " .. id .. " needs a close function")
	panels[id] = handlers
	start()
end

-- Makes id the open panel, closing whichever other one is open. Returns false when
-- the open panel refuses to close; the caller then does not open.
function PanelCoordinator.claim(id: string): boolean
	assert(panels[id], "PanelCoordinator: " .. id .. " is not registered")
	if current and current ~= id then
		local other = current
		if panels[other].close() == false then
			return false
		end
		if current == other then
			current = nil
		end
	end
	current = id
	return true
end

-- Called by a panel when it closes; ignored unless that panel holds the claim.
function PanelCoordinator.release(id: string)
	if current == id then
		current = nil
	end
end

-- Escape or B: the open panel goes back a page, or closes from its root page.
function PanelCoordinator.back(): boolean
	if not current then
		return false
	end
	local handlers = panels[current]
	if handlers.back then
		handlers.back()
	else
		handlers.close()
	end
	return true
end

function PanelCoordinator.closeAll()
	if current then
		panels[current].close()
		current = nil
	end
end

function PanelCoordinator.current(): string?
	return current
end

function PanelCoordinator.debugInfo()
	local registered = {}
	for id in pairs(panels) do
		table.insert(registered, id)
	end
	table.sort(registered)
	return { current = current, registered = registered, started = started }
end

-- Specs only: forget every panel.
function PanelCoordinator._reset()
	panels = {}
	current = nil
end

return PanelCoordinator
