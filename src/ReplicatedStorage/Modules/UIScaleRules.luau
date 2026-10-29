-- UIScaleRules: pure rules for UI scale, input kind and battle layout (UI §10.2, §5.3).
local Config = require(script.Parent.UIScaleConfig)

local UIScaleRules = {}

-- "touch" or "pointer". PreferredInput decides; the Touch/Mouse flags are the fallback
-- when it is not available. A gamepad is treated as a pointer screen.
function UIScaleRules.inputKind(preferredInput: EnumItem?, touchEnabled: boolean, mouseEnabled: boolean): string
	if preferredInput ~= nil then
		return preferredInput == Enum.PreferredInput.Touch and "touch" or "pointer"
	end
	if touchEnabled and not mouseEnabled then
		return "touch"
	end
	return "pointer"
end

-- clamp(min(height / refHeight, width / refWidth), MIN, MAX) × uiSize.
function UIScaleRules.scaleFor(width: number, height: number, input: string, uiSize: number?): number
	local reference = input == "touch" and Config.TOUCH_REFERENCE or Config.POINTER_REFERENCE
	local fit = math.min(height / reference.Y, width / reference.X)
	local size = (type(uiSize) == "number" and uiSize > 0) and uiSize or 1
	return math.clamp(fit, Config.MIN_SCALE, Config.MAX_SCALE) * size
end

-- "Mobile" or "Desktop" for screens whose arrangement changes. Never the last input.
function UIScaleRules.layoutMode(width: number, input: string): string
	if input == "touch" or width < Config.MOBILE_WIDTH then
		return "Mobile"
	end
	return "Desktop"
end

return UIScaleRules
