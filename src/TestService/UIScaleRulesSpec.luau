-- Headless checks for UIScaleRules (PLAN_UI_FOUNDATIONS step 4).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Rules = require(ReplicatedStorage.Modules.UIScaleRules)

local Spec = {}

local function near(a: number, b: number): boolean
	return math.abs(a - b) < 1e-3
end

function Spec.run()
	-- Scale: the phone floor, the 4:3 width term, desktop, the ceiling, and UI size on top.
	assert(near(Rules.scaleFor(640, 360, "touch"), 0.55), "a small phone sits at the 0.55 floor")
	assert(near(Rules.scaleFor(844, 390, "touch"), 0.55), "iPhone 12 sits at the floor")
	assert(near(Rules.scaleFor(932, 430, "touch"), 430 / 720), "iPhone Pro Max scales by height")
	assert(near(Rules.scaleFor(1024, 768, "touch"), 0.8), "a 4:3 tablet scales by width")
	assert(near(Rules.scaleFor(1280, 720, "pointer"), 0.72), "a 720p window uses the pointer canvas")
	assert(near(Rules.scaleFor(1920, 1080, "pointer"), 1.08), "1080p desktop")
	assert(near(Rules.scaleFor(3840, 2160, "pointer"), 1.5), "4K stops at the 1.5 ceiling")
	assert(near(Rules.scaleFor(1920, 1080, "pointer", 1.3), 1.08 * 1.3), "UI size multiplies after the clamp")
	assert(near(Rules.scaleFor(1920, 1080, "pointer", -2), 1.08), "a bad UI size counts as 1")

	-- Input kind.
	assert(Rules.inputKind(Enum.PreferredInput.Touch, true, false) == "touch", "PreferredInput Touch is touch")
	assert(Rules.inputKind(Enum.PreferredInput.KeyboardAndMouse, true, true) == "pointer", "keyboard and mouse is pointer")
	assert(Rules.inputKind(Enum.PreferredInput.Gamepad, false, false) == "pointer", "a gamepad is pointer")
	assert(Rules.inputKind(nil, true, false) == "touch", "fallback: touch without a mouse")
	assert(Rules.inputKind(nil, true, true) == "pointer", "fallback: a touch laptop with a mouse is pointer")

	-- Layout: the PC window from the research log (2171 wide) stays Desktop.
	assert(Rules.layoutMode(2171, "pointer") == "Desktop", "a wide pointer window is Desktop")
	assert(Rules.layoutMode(700, "pointer") == "Mobile", "a narrow window is Mobile")
	assert(Rules.layoutMode(1920, "touch") == "Mobile", "touch is Mobile at any width")
	return "UIScaleRulesSpec: all checks passed"
end

return Spec
