-- Headless checks for MovementLock's reason rules (PLAN_UI_FOUNDATIONS step 6).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MovementLock = require(ReplicatedStorage.Modules.MovementLock)

local Spec = {}

function Spec.run()
	local realApply = MovementLock._apply
	local calls = {}
	MovementLock._apply = function(locked)
		table.insert(calls, locked)
	end
	MovementLock._reset()

	MovementLock.hold("Dialogue")
	assert(#calls == 1 and calls[1] == true, "the first reason locks")
	MovementLock.hold("Battle")
	MovementLock.hold("Battle")
	assert(#calls == 1, "more reasons, or the same one twice, do not lock again")
	assert(MovementLock.isHeld("Battle") and MovementLock.isHeld(), "isHeld reports reasons")

	MovementLock.release("Dialogue")
	assert(#calls == 1 and MovementLock.isHeld(), "releasing one of two reasons keeps the lock")
	MovementLock.release("NotHeld")
	assert(#calls == 1, "releasing a reason that is not held does nothing")
	MovementLock.release("Battle")
	assert(#calls == 2 and calls[2] == false and not MovementLock.isHeld(), "releasing the last reason unlocks")

	MovementLock.hold("PackReveal")
	MovementLock.release("PackReveal")
	assert(#calls == 4 and calls[3] == true and calls[4] == false, "a later hold locks and unlocks again")
	assert(not pcall(MovementLock.hold, ""), "a blank reason errors")
	assert(#MovementLock.debugInfo().held == 0, "nothing is left held")

	MovementLock._reset()
	MovementLock._apply = realApply
	return "MovementLockSpec: all checks passed"
end

return Spec
