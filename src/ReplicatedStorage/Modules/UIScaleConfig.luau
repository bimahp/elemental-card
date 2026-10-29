-- UIScaleConfig: starting values for UI scaling and the battle layout switch (UI §10.2).
return {
	-- Every layer is authored on the touch reference; desktop gets the larger pointer canvas.
	TOUCH_REFERENCE = Vector2.new(1280, 720),
	POINTER_REFERENCE = Vector2.new(1777, 1000),
	MIN_SCALE = 0.55, -- keeps an 80 px tap target at 44 pt on the smallest phone
	MAX_SCALE = 1.5,
	-- The battle uses its mobile grid below this viewport width, or on touch (UI §5.3).
	MOBILE_WIDTH = 800,
}
