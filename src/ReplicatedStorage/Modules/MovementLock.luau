-- MovementLock: the only client code that stops the player (ARCHITECTURE §12.3).
-- Callers hold and release a named reason ("Dialogue", "Battle", "PackReveal"); while
-- any reason is held, the controls are off, movement keys are sunk and jumping is off.
-- No caller saves or restores WalkSpeed or JumpPower, so locks cannot undo each other.
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")

local MovementLock = {}

local SINK_ACTION = "MovementLock"
local MOVEMENT_ACTIONS = {
	Enum.PlayerActions.CharacterForward,
	Enum.PlayerActions.CharacterBackward,
	Enum.PlayerActions.CharacterLeft,
	Enum.PlayerActions.CharacterRight,
	Enum.PlayerActions.CharacterJump,
}

local reasons: { [string]: boolean } = {}
local applied = false
local controls = nil
local characterConnection: RBXScriptConnection? = nil

local function setJump(character: Model?, enabled: boolean)
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, enabled)
	end
end

-- The real effect; specs replace MovementLock._apply to record calls instead.
function MovementLock._apply(locked: boolean)
	local player = Players.LocalPlayer
	if not controls then
		local ok, playerModule = pcall(function()
			return require(player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule"))
		end)
		if ok and playerModule then
			controls = playerModule:GetControls()
		end
	end
	if not characterConnection then
		-- A respawn during a lock gets a locked humanoid too.
		characterConnection = player.CharacterAdded:Connect(function(character)
			if applied then
				character:WaitForChild("Humanoid", 5)
				setJump(character, not applied)
			end
		end)
	end
	if locked then
		if controls then
			controls:Disable()
		end
		ContextActionService:BindActionAtPriority(SINK_ACTION, function()
			return Enum.ContextActionResult.Sink
		end, false, Enum.ContextActionPriority.High.Value + 100, table.unpack(MOVEMENT_ACTIONS))
	else
		if controls then
			controls:Enable()
		end
		ContextActionService:UnbindAction(SINK_ACTION)
	end
	setJump(player.Character, not locked)
end

local function sync()
	local wanted = next(reasons) ~= nil
	if wanted ~= applied then
		applied = wanted
		MovementLock._apply(wanted)
	end
end

function MovementLock.hold(reason: string)
	assert(type(reason) == "string" and reason ~= "", "MovementLock: a reason is required")
	reasons[reason] = true
	sync()
end

function MovementLock.release(reason: string)
	reasons[reason] = nil
	sync()
end

-- With a reason: whether that reason is held. Without: whether anything is.
function MovementLock.isHeld(reason: string?): boolean
	if reason then
		return reasons[reason] == true
	end
	return next(reasons) ~= nil
end

function MovementLock.debugInfo()
	local held = {}
	for reason in pairs(reasons) do
		table.insert(held, reason)
	end
	table.sort(held)
	return { held = held, applied = applied }
end

-- Specs only: drop every reason without applying anything.
function MovementLock._reset()
	reasons = {}
	applied = false
end

return MovementLock
