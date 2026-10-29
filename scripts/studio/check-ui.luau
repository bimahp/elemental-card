-- check-ui.luau: touch-target and phone-frame checks for UI roots. Edit mode only.
--
-- Clones each root's children into a temporary ScreenGui sized like each device,
-- applies that device's safe insets and, for an AutoScale layer, its UIScale, then
-- reads the computed layout. Nothing in the roots is changed; the temporary gui
-- is destroyed even when a check fails.
--
--   local ARGS = {
--     roots = { "StarterGui.MatchmakingUI" },
--     show = { "StarterGui.MatchmakingUI.Dialog" },  -- force these visible in the clone
--     checks = { "touch", "frames" },                -- default: both
--     devices = { "iPhone 12/13" },                  -- default: all
--   }
local ARGS = ARGS or {}

-- Landscape sizes in points. Safe insets and the Roblox top bar height are
-- approximate; confirm on a real device before relying on a few pixels.
local DEVICES = {
	{ name = "Small phone", w = 640, h = 360, input = "touch", side = 0, bottom = 0 },
	{ name = "iPhone SE", w = 667, h = 375, input = "touch", side = 0, bottom = 0 },
	{ name = "iPhone 12/13", w = 844, h = 390, input = "touch", side = 47, bottom = 21 },
	{ name = "iPhone Pro Max", w = 932, h = 430, input = "touch", side = 59, bottom = 21 },
	{ name = "Android mid", w = 800, h = 360, input = "touch", side = 0, bottom = 0 },
	{ name = "Tablet", w = 1024, h = 768, input = "touch", side = 0, bottom = 20 },
	{ name = "Desktop 720p", w = 1280, h = 720, input = "pointer", side = 0, bottom = 0 },
	{ name = "Desktop 1080p", w = 1920, h = 1080, input = "pointer", side = 0, bottom = 0 },
}
local TOPBAR = 58
local MIN_TOUCH = 44 -- points; 80 px at the 1280 x 720 reference (UI §10.2)
local MAX_LINES = 40

local StarterGui = game:GetService("StarterGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local function resolve(path: string): Instance
	local current: Instance = game
	for segment in string.gmatch(path, "[^.]+") do
		local nextInst: Instance?
		if current == game then
			local ok, service = pcall(function()
				return game:GetService(segment)
			end)
			nextInst = ok and service or nil
		end
		nextInst = nextInst or current:FindFirstChild(segment)
		if not nextInst then
			error("not found: " .. path .. " (at " .. segment .. ")")
		end
		current = nextInst
	end
	return current
end

-- Uses the real rules once UIScaleRules exists (plan step 4); same formula until then.
local function scaleFor(shortSide: number, input: string): number
	local modules = ReplicatedStorage:FindFirstChild("Modules")
	local rules = modules and modules:FindFirstChild("UIScaleRules")
	if rules then
		return (require(rules) :: any).scaleFor(shortSide, input, 1)
	end
	local ref = input == "touch" and 720 or 1000
	return math.clamp(shortSide / ref, 0.55, 1.5)
end

local function insetRect(gui: ScreenGui, d)
	if gui.ScreenInsets == Enum.ScreenInsets.None then
		return 0, 0, d.w, d.h
	elseif gui.ScreenInsets == Enum.ScreenInsets.DeviceSafeInsets then
		return d.side, 0, d.w - 2 * d.side, d.h - d.bottom
	end
	return d.side, TOPBAR, d.w - 2 * d.side, d.h - TOPBAR - d.bottom
end

local function wanted(list, value)
	if not list then
		return true
	end
	for _, v in ipairs(list) do
		if v == value then
			return true
		end
	end
	return false
end

--------------------------------------------------------------------------------

local findings = {} -- key -> { text, devices = {} }
local order = {}

-- detail is part of the key only for overlaps, where it names the other element;
-- other kinds keep the first device's numbers.
local function note(rootName: string, kind: string, path: string, detail: string, device: string)
	local key = rootName .. "|" .. kind .. "|" .. path .. (kind == "overlap" and ("|" .. detail) or "")
	local f = findings[key]
	if not f then
		f = { root = rootName, kind = kind, path = path, detail = detail, devices = {} }
		findings[key] = f
		table.insert(order, key)
	end
	if f.devices[#f.devices] ~= device then
		table.insert(f.devices, device)
	end
end

local function hasText(inst: Instance)
	return (inst:IsA("TextLabel") or inst:IsA("TextButton") or inst:IsA("TextBox")) and (inst :: any).Text ~= ""
end

-- What an element draws: its text where the text sits, otherwise its whole rect.
-- Returns nil for an element that draws nothing (a transparent hit area).
local function inkRect(inst: GuiObject)
	local pos, size = inst.AbsolutePosition, inst.AbsoluteSize
	if hasText(inst) then
		local t = inst :: any
		local left, top, w, h = pos.X, pos.Y, size.X, size.Y
		local pad = inst:FindFirstChildOfClass("UIPadding")
		if pad then
			local l = pad.PaddingLeft.Scale * size.X + pad.PaddingLeft.Offset
			local r = pad.PaddingRight.Scale * size.X + pad.PaddingRight.Offset
			local tp = pad.PaddingTop.Scale * size.Y + pad.PaddingTop.Offset
			local b = pad.PaddingBottom.Scale * size.Y + pad.PaddingBottom.Offset
			left, top, w, h = left + l, top + tp, w - l - r, h - tp - b
		end
		local tb = t.TextBounds
		local x = left
		if t.TextXAlignment == Enum.TextXAlignment.Center then
			x = left + (w - tb.X) / 2
		elseif t.TextXAlignment == Enum.TextXAlignment.Right then
			x = left + w - tb.X
		end
		local y = top
		if t.TextYAlignment == Enum.TextYAlignment.Center then
			y = top + (h - tb.Y) / 2
		elseif t.TextYAlignment == Enum.TextYAlignment.Bottom then
			y = top + h - tb.Y
		end
		return { x, y, tb.X, tb.Y }, true
	end
	local image = (inst:IsA("ImageLabel") or inst:IsA("ImageButton")) and (inst :: any).Image ~= ""
	if inst.BackgroundTransparency >= 1 and not image then
		return nil, false
	end
	return { pos.X, pos.Y, size.X, size.Y }, false
end

local function contains(a, b)
	return a[1] <= b[1] + 1 and a[2] <= b[2] + 1 and a[1] + a[3] >= b[1] + b[3] - 1 and a[2] + a[4] >= b[2] + b[4] - 1
end

local function relPath(inst: Instance, layer: Instance, rootName: string)
	local parts = {}
	local cur = inst
	while cur and cur ~= layer do
		table.insert(parts, 1, cur.Name)
		cur = cur.Parent
	end
	return rootName .. "." .. table.concat(parts, ".")
end

local function outside(pos: Vector2, size: Vector2, lx, ly, lw, lh)
	return pos.X < lx - 1 or pos.Y < ly - 1 or pos.X + size.X > lx + lw + 1 or pos.Y + size.Y > ly + lh + 1
end

local function checkLayer(root: ScreenGui, layer: Frame, device, checks, lx, ly, lw, lh)
	local leaves = {}

	local function visit(inst: Instance, inScroll: boolean, rotated: boolean)
		if inst:IsA("GuiObject") then
			if not inst.Visible then
				return
			end
			rotated = rotated or inst.Rotation ~= 0
			local pos, size = inst.AbsolutePosition, inst.AbsoluteSize
			local path = relPath(inst, layer, root.Name)

			if wanted(checks, "frames") and not inScroll and not rotated and size.X > 0 and size.Y > 0
				and not inst:GetAttribute("CheckOffscreenOK") and outside(pos, size, lx, ly, lw, lh) then
				note(root.Name, "offscreen", path, string.format("%dx%d at %d,%d", size.X, size.Y, pos.X - lx, pos.Y - ly), device.name)
				return -- its children would only repeat the finding
			end

			if wanted(checks, "touch") and device.input == "touch" and inst:IsA("GuiButton") and inst.Interactable
				and math.min(size.X, size.Y) < MIN_TOUCH then
				note(root.Name, "touch", path, string.format("%dx%d", size.X, size.Y), device.name)
			end

			if wanted(checks, "frames") and (inst:IsA("TextLabel") or inst:IsA("TextButton") or inst:IsA("TextBox")) then
				local text = inst :: any
				if text.Text ~= "" and not text.TextScaled and not text.TextFits then
					note(root.Name, "text", path, string.format("%q in %dx%d", text.Text:sub(1, 40), size.X, size.Y), device.name)
				end
			end

			local isLeaf = inst:IsA("GuiButton") or inst:IsA("TextBox")
				or (inst:IsA("TextLabel") and (inst :: TextLabel).Text ~= "")
			if isLeaf and not inScroll and not rotated and not inst:GetAttribute("CheckOverlapOK") then
				table.insert(leaves, inst)
			end
			inScroll = inScroll or inst:IsA("ScrollingFrame")
		end
		for _, child in ipairs(inst:GetChildren()) do
			visit(child, inScroll, rotated)
		end
	end

	for _, child in ipairs(layer:GetChildren()) do
		visit(child, false, false)
	end

	-- Overlap: two drawn things cross. A textless element that fully contains the
	-- other is a background (a scrim, a bar, a card) and is not reported.
	if wanted(checks, "frames") then
		local inks = {}
		for _, leaf in ipairs(leaves) do
			local rect, isText = inkRect(leaf)
			if rect and rect[3] > 0 and rect[4] > 0 then
				table.insert(inks, { inst = leaf, rect = rect, text = isText })
			end
		end
		for i = 1, math.min(#inks, 400) do
			local a = inks[i]
			for j = i + 1, math.min(#inks, 400) do
				local b = inks[j]
				if not a.inst:IsAncestorOf(b.inst) and not b.inst:IsAncestorOf(a.inst) then
					local ra, rb = a.rect, b.rect
					local w = math.min(ra[1] + ra[3], rb[1] + rb[3]) - math.max(ra[1], rb[1])
					local h = math.min(ra[2] + ra[4], rb[2] + rb[4]) - math.max(ra[2], rb[2])
					local background = (not a.text and contains(ra, rb)) or (not b.text and contains(rb, ra))
					if w > 2 and h > 2 and not background then
						note(root.Name, "overlap", relPath(a.inst, layer, root.Name), "with " .. relPath(b.inst, layer, root.Name), device.name)
					end
				end
			end
		end
	end
end

local function runDevice(device, roots, checks, show)
	local gui = Instance.new("ScreenGui")
	gui.Name = "_UICheck"
	gui.ScreenInsets = Enum.ScreenInsets.None
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = 10000
	local frame = Instance.new("Frame")
	frame.Name = "Device"
	frame.Size = UDim2.fromOffset(device.w, device.h)
	frame.BackgroundTransparency = 1
	frame.Parent = gui

	local layers = {}
	for _, root in ipairs(roots) do
		local lx, ly, lw, lh = insetRect(root, device)
		local layer = Instance.new("Frame")
		layer.Name = "Layer_" .. root.Name
		layer.Position = UDim2.fromOffset(lx, ly)
		layer.Size = UDim2.fromOffset(lw, lh)
		layer.BackgroundTransparency = 1
		layer.Parent = frame
		for _, child in ipairs(root:GetChildren()) do
			if child.Archivable and not child:IsA("LuaSourceContainer") then
				local copy = child:Clone()
				for _, d in ipairs(copy:GetDescendants()) do
					if d:IsA("LuaSourceContainer") then
						d:Destroy()
					end
				end
				copy.Parent = layer
			end
		end
		local scaled = root:FindFirstChild("Root")
		local uiScale = scaled and scaled:FindFirstChildOfClass("UIScale")
		local layerRoot = layer:FindFirstChild("Root")
		if root:GetAttribute("AutoScale") and uiScale and layerRoot then
			local scale = scaleFor(math.min(device.w, device.h), device.input)
			layerRoot.Size = UDim2.fromScale(1 / scale, 1 / scale);
			(layerRoot:FindFirstChildOfClass("UIScale") :: UIScale).Scale = scale
		end
		for _, path in ipairs(show) do
			local prefix = root:GetFullName() .. "."
			if path:sub(1, #prefix) == prefix then
				local cur: Instance? = layer
				for segment in string.gmatch(path:sub(#prefix + 1), "[^.]+") do
					cur = cur and cur:FindFirstChild(segment)
				end
				while cur and cur ~= layer do
					if cur:IsA("GuiObject") then
						cur.Visible = true
					end
					cur = cur.Parent
				end
			end
		end
		table.insert(layers, { root = root, layer = layer, rect = { lx, ly, lw, lh } })
	end

	gui.Parent = StarterGui
	task.wait()
	task.wait()
	for _, l in ipairs(layers) do
		local lx, ly, lw, lh = table.unpack(l.rect)
		-- Absolute positions are in the device frame, which sits at the screen origin.
		checkLayer(l.root, l.layer, device, checks, lx, ly, lw, lh)
	end
	gui:Destroy()
end

local ok, err = pcall(function()
	local roots = {}
	for _, path in ipairs(ARGS.roots or {}) do
		local root = resolve(path)
		assert(root:IsA("ScreenGui"), path .. " is not a ScreenGui")
		table.insert(roots, root)
	end
	assert(#roots > 0, "ARGS.roots is empty")
	for _, device in ipairs(DEVICES) do
		if wanted(ARGS.devices, device.name) then
			runDevice(device, roots, ARGS.checks, ARGS.show or {})
		end
	end
end)

local leftover = StarterGui:FindFirstChild("_UICheck")
if leftover then
	leftover:Destroy()
end
if not ok then
	error(err, 0)
end

local lines = {}
local counts = {}
for _, key in ipairs(order) do
	local f = findings[key]
	counts[f.kind] = (counts[f.kind] or 0) + 1
	if #lines < MAX_LINES then
		table.insert(lines, string.format("%-9s %s  %s  [%s]", f.kind, f.path, f.detail, table.concat(f.devices, ", ")))
	end
end
local summary = {}
for _, kind in ipairs({ "touch", "offscreen", "text", "overlap" }) do
	table.insert(summary, kind .. "=" .. (counts[kind] or 0))
end
local header = "check-ui: " .. table.concat(summary, " ")
if #order > MAX_LINES then
	header ..= string.format(" (showing %d of %d)", MAX_LINES, #order)
end
return header .. "\n" .. table.concat(lines, "\n")
