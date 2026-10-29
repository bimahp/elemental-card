-- ui-json.luau: exports a UI root to deterministic JSON, rebuilds one from JSON,
-- or verifies that a root survives the round trip. Edit mode only.
--
-- Prepend one ARGS line and send the file through execute_luau (see README.md):
--   local ARGS = { mode = "export", root = "StarterGui.MatchmakingUI" }
--   local ARGS = { mode = "verify", root = "StarterGui.MatchmakingUI" }
--   local ARGS = { mode = "import", json = [==[ ... ]==], parent = "ServerStorage" }
local ARGS = ARGS or {}

local HttpService = game:GetService("HttpService")

local FORMAT = "elemental-ui/1"

--------------------------------------------------------------------------------
-- Properties written per class. Only values that differ from a fresh
-- Instance.new(class) are exported. A class not listed here fails the export.

local GUI_OBJECT = {
	"Active", "AnchorPoint", "AutomaticSize", "BackgroundColor3", "BackgroundTransparency",
	"BorderColor3", "BorderMode", "BorderSizePixel", "ClipsDescendants", "Interactable",
	"LayoutOrder", "Position", "Rotation", "Selectable", "Size", "SizeConstraint",
	"Visible", "ZIndex",
}
local TEXT = {
	"FontFace", "LineHeight", "MaxVisibleGraphemes", "RichText", "Text", "TextColor3",
	"TextScaled", "TextSize", "TextStrokeColor3", "TextStrokeTransparency",
	"TextTransparency", "TextTruncate", "TextWrapped", "TextXAlignment", "TextYAlignment",
}
local BUTTON = { "AutoButtonColor", "InputSink", "Modal", "Selected" }
local IMAGE = {
	"Image", "ImageColor3", "ImageRectOffset", "ImageRectSize", "ImageTransparency",
	"ResampleMode", "ScaleType", "SliceCenter", "SliceScale", "TileSize",
}
local SCROLL = {
	"AutomaticCanvasSize", "BottomImage", "CanvasPosition", "CanvasSize", "ElasticBehavior",
	"HorizontalScrollBarInset", "MidImage", "ScrollBarImageColor3", "ScrollBarImageTransparency",
	"ScrollBarThickness", "ScrollingDirection", "ScrollingEnabled", "TopImage",
	"VerticalScrollBarInset", "VerticalScrollBarPosition",
}

local function join(...)
	local out = {}
	for _, list in ipairs({ ... }) do
		for _, name in ipairs(list) do
			table.insert(out, name)
		end
	end
	return out
end

local PROPS = {
	ScreenGui = {
		"ClipToDeviceSafeArea", "DisplayOrder", "Enabled", "IgnoreGuiInset", "ResetOnSpawn",
		"SafeAreaCompatibility", "ScreenInsets", "ZIndexBehavior",
	},
	Folder = {},
	Frame = join(GUI_OBJECT, { "Style" }),
	CanvasGroup = join(GUI_OBJECT, { "GroupColor3", "GroupTransparency" }),
	TextLabel = join(GUI_OBJECT, TEXT),
	TextButton = join(GUI_OBJECT, TEXT, BUTTON),
	TextBox = join(GUI_OBJECT, TEXT, {
		"ClearTextOnFocus", "MultiLine", "PlaceholderColor3", "PlaceholderText", "TextEditable",
	}),
	ImageLabel = join(GUI_OBJECT, IMAGE),
	ImageButton = join(GUI_OBJECT, IMAGE, BUTTON, { "HoverImage", "PressedImage" }),
	ScrollingFrame = join(GUI_OBJECT, SCROLL),
	UICorner = { "CornerRadius" },
	UIStroke = { "ApplyStrokeMode", "Color", "Enabled", "LineJoinMode", "Thickness", "Transparency" },
	UIGradient = { "Color", "Enabled", "Offset", "Rotation", "Transparency" },
	UIScale = { "Scale" },
	UIShadow = { "BlurRadius", "Color", "Offset", "Spread", "Transparency", "ZIndex" },
	UIPadding = { "PaddingBottom", "PaddingLeft", "PaddingRight", "PaddingTop" },
	UIListLayout = {
		"FillDirection", "HorizontalAlignment", "HorizontalFlex", "ItemLineAlignment", "Padding",
		"SortOrder", "VerticalAlignment", "VerticalFlex", "Wraps",
	},
	UIGridLayout = {
		"CellPadding", "CellSize", "FillDirection", "FillDirectionMaxCells", "HorizontalAlignment",
		"SortOrder", "StartCorner", "VerticalAlignment",
	},
	UIFlexItem = { "FlexMode", "GrowRatio", "ItemLineAlignment", "ShrinkRatio" },
	UIAspectRatioConstraint = { "AspectRatio", "AspectType", "DominantAxis" },
	UISizeConstraint = { "MaxSize", "MinSize" },
	UITextSizeConstraint = { "MaxTextSize", "MinTextSize" },
	StringValue = { "Value" },
	NumberValue = { "Value" },
	IntValue = { "Value" },
	BoolValue = { "Value" },
}

--------------------------------------------------------------------------------
-- Values

local function colorValue(c: Color3)
	local r, g, b = c.R * 255, c.G * 255, c.B * 255
	local function exact(x)
		return math.abs(x - math.round(x)) < 1e-3
	end
	if exact(r) and exact(g) and exact(b) then
		return c:ToHex():upper()
	end
	return { c.R, c.G, c.B }
end

local function encodeValue(v)
	local t = typeof(v)
	if t == "boolean" or t == "string" or t == "number" then
		return v
	elseif t == "EnumItem" then
		return { t = "Enum", v = tostring(v):sub(6) }
	elseif t == "Color3" then
		return { t = "Color3", v = colorValue(v) }
	elseif t == "UDim2" then
		return { t = "UDim2", v = { v.X.Scale, v.X.Offset, v.Y.Scale, v.Y.Offset } }
	elseif t == "UDim" then
		return { t = "UDim", v = { v.Scale, v.Offset } }
	elseif t == "Vector2" then
		return { t = "Vector2", v = { v.X, v.Y } }
	elseif t == "Vector3" then
		return { t = "Vector3", v = { v.X, v.Y, v.Z } }
	elseif t == "Rect" then
		return { t = "Rect", v = { v.Min.X, v.Min.Y, v.Max.X, v.Max.Y } }
	elseif t == "Font" then
		return { t = "Font", family = v.Family, weight = v.Weight.Name, style = v.Style.Name }
	elseif t == "NumberRange" then
		return { t = "NumberRange", v = { v.Min, v.Max } }
	elseif t == "ColorSequence" then
		local keys = {}
		for _, k in ipairs(v.Keypoints) do
			table.insert(keys, { k.Time, colorValue(k.Value) })
		end
		return { t = "ColorSequence", v = keys }
	elseif t == "NumberSequence" then
		local keys = {}
		for _, k in ipairs(v.Keypoints) do
			table.insert(keys, { k.Time, k.Value, k.Envelope })
		end
		return { t = "NumberSequence", v = keys }
	end
	error("unsupported value type " .. t)
end

local function decodeColor(v)
	if type(v) == "string" then
		return Color3.fromHex(v)
	end
	return Color3.new(v[1], v[2], v[3])
end

local function decodeValue(e)
	if type(e) ~= "table" then
		return e
	end
	local t, v = e.t, e.v
	if t == "Enum" then
		local enumName, itemName = string.match(v, "^([^.]+)%.(.+)$")
		return (Enum :: any)[enumName][itemName]
	elseif t == "Color3" then
		return decodeColor(v)
	elseif t == "UDim2" then
		return UDim2.new(v[1], v[2], v[3], v[4])
	elseif t == "UDim" then
		return UDim.new(v[1], v[2])
	elseif t == "Vector2" then
		return Vector2.new(v[1], v[2])
	elseif t == "Vector3" then
		return Vector3.new(v[1], v[2], v[3])
	elseif t == "Rect" then
		return Rect.new(v[1], v[2], v[3], v[4])
	elseif t == "Font" then
		return Font.new(e.family, (Enum.FontWeight :: any)[e.weight], (Enum.FontStyle :: any)[e.style])
	elseif t == "NumberRange" then
		return NumberRange.new(v[1], v[2])
	elseif t == "ColorSequence" then
		local keys = {}
		for _, k in ipairs(v) do
			table.insert(keys, ColorSequenceKeypoint.new(k[1], decodeColor(k[2])))
		end
		return ColorSequence.new(keys)
	elseif t == "NumberSequence" then
		local keys = {}
		for _, k in ipairs(v) do
			table.insert(keys, NumberSequenceKeypoint.new(k[1], k[2], k[3]))
		end
		return NumberSequence.new(keys)
	end
	error("unsupported encoded type " .. tostring(t))
end

--------------------------------------------------------------------------------
-- Deterministic JSON: sorted keys, one property per line, small values inline.

local NODE_KEYS = { "class", "name", "skipped", "props", "attrs", "children" }

local function jsonString(s: string)
	s = s:gsub('[%c"\\]', function(c)
		if c == '"' then return '\\"' end
		if c == "\\" then return "\\\\" end
		if c == "\n" then return "\\n" end
		if c == "\r" then return "\\r" end
		if c == "\t" then return "\\t" end
		return string.format("\\u%04x", string.byte(c))
	end)
	return '"' .. s .. '"'
end

local function jsonNumber(n: number)
	if n ~= n or n == math.huge or n == -math.huge then
		error("non-finite number")
	end
	if n == math.floor(n) and math.abs(n) < 1e15 then
		return string.format("%d", n)
	end
	return string.format("%.7g", n)
end

local function depth(v)
	if type(v) ~= "table" then
		return 0
	end
	local d = 0
	for _, x in pairs(v) do
		d = math.max(d, depth(x))
	end
	return d + 1
end

local function isArray(t)
	local n = 0
	for _ in pairs(t) do
		n += 1
	end
	return n == #t
end

local function sortedKeys(t)
	if t.class ~= nil then
		local keys = {}
		for _, k in ipairs(NODE_KEYS) do
			if t[k] ~= nil then
				table.insert(keys, k)
			end
		end
		return keys
	end
	local keys = {}
	for k in pairs(t) do
		table.insert(keys, k)
	end
	table.sort(keys)
	return keys
end

local function encodeJson(v, indent: string): string
	local tv = type(v)
	if tv == "string" then
		return jsonString(v)
	elseif tv == "number" then
		return jsonNumber(v)
	elseif tv == "boolean" then
		return tostring(v)
	elseif tv ~= "table" then
		error("cannot encode " .. tv)
	end

	local inline = v.class == nil and depth(v) <= 2
	local inner = indent .. "  "
	local parts = {}
	if isArray(v) then
		for _, x in ipairs(v) do
			table.insert(parts, encodeJson(x, inner))
		end
		if inline then
			return "[" .. table.concat(parts, ", ") .. "]"
		end
		return "[\n" .. inner .. table.concat(parts, ",\n" .. inner) .. "\n" .. indent .. "]"
	end
	for _, k in ipairs(sortedKeys(v)) do
		table.insert(parts, jsonString(k) .. ": " .. encodeJson(v[k], inner))
	end
	if inline then
		return "{" .. table.concat(parts, ", ") .. "}"
	end
	return "{\n" .. inner .. table.concat(parts, ",\n" .. inner) .. "\n" .. indent .. "}"
end

--------------------------------------------------------------------------------
-- Export

local defaults = {}
local function defaultOf(className: string)
	if not defaults[className] then
		defaults[className] = Instance.new(className)
	end
	return defaults[className]
end

local function sortedChildren(inst: Instance)
	local kids = inst:GetChildren()
	local index = {}
	for i, c in ipairs(kids) do
		index[c] = i
	end
	table.sort(kids, function(a, b)
		if a.Name ~= b.Name then
			return a.Name < b.Name
		end
		if a.ClassName ~= b.ClassName then
			return a.ClassName < b.ClassName
		end
		return index[a] < index[b]
	end)
	return kids
end

local function exportNode(inst: Instance, problems, stats)
	stats.count += 1
	if inst:IsA("LuaSourceContainer") then
		stats.skipped += 1
		return { class = inst.ClassName, name = inst.Name, skipped = "code" }
	end
	local list = PROPS[inst.ClassName]
	if not list then
		table.insert(problems, "unsupported class " .. inst.ClassName .. " at " .. inst:GetFullName())
		return { class = inst.ClassName, name = inst.Name, skipped = "unsupported" }
	end

	local node: any = { class = inst.ClassName, name = inst.Name }
	local base = defaultOf(inst.ClassName)
	local props = {}
	for _, prop in ipairs(list) do
		local ok, value = pcall(function()
			return (inst :: any)[prop]
		end)
		if not ok then
			table.insert(problems, "missing property " .. inst.ClassName .. "." .. prop)
			continue
		end
		local encoded = encodeValue(value)
		local baseEncoded = encodeValue((base :: any)[prop])
		if encodeJson(encoded, "") ~= encodeJson(baseEncoded, "") then
			props[prop] = encoded
		end
	end
	if next(props) then
		node.props = props
	end

	local attrs = {}
	for name, value in pairs(inst:GetAttributes()) do
		local ok, encoded = pcall(encodeValue, value)
		if ok then
			attrs[name] = encoded
		else
			table.insert(problems, "unsupported attribute " .. name .. " at " .. inst:GetFullName())
		end
	end
	if next(attrs) then
		node.attrs = attrs
	end

	local children = {}
	for _, child in ipairs(sortedChildren(inst)) do
		table.insert(children, exportNode(child, problems, stats))
	end
	if #children > 0 then
		node.children = children
	end
	return node
end

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

local function exportRoot(root: Instance, path: string)
	local problems, stats = {}, { count = 0, skipped = 0 }
	local tree = exportNode(root, problems, stats)
	if #problems > 0 then
		error("export failed:\n" .. table.concat(problems, "\n"))
	end
	local doc = { format = FORMAT, root = path, tree = tree }
	return encodeJson(doc, "") .. "\n", stats
end

--------------------------------------------------------------------------------
-- Import

-- placeholders: verify mode builds empty scripts so the rebuilt tree exports the same.
local function buildNode(node, report, placeholders: boolean?)
	if node.skipped then
		if placeholders and node.skipped == "code" then
			local stub = Instance.new(node.class)
			stub.Name = node.name
			return stub
		end
		table.insert(report, "skipped " .. node.class .. " " .. node.name .. " (" .. node.skipped .. ")")
		return nil
	end
	local inst = Instance.new(node.class)
	inst.Name = node.name
	for prop, encoded in pairs(node.props or {}) do
		(inst :: any)[prop] = decodeValue(encoded)
	end
	for name, encoded in pairs(node.attrs or {}) do
		inst:SetAttribute(name, decodeValue(encoded))
	end
	for _, childNode in ipairs(node.children or {}) do
		local child = buildNode(childNode, report, placeholders)
		if child then
			child.Parent = inst
		end
	end
	return inst
end

local function importDoc(json: string, parent: Instance, name: string?, placeholders: boolean?)
	local doc = HttpService:JSONDecode(json)
	if doc.format ~= FORMAT then
		error("unknown format " .. tostring(doc.format))
	end
	local report = {}
	local inst = buildNode(doc.tree, report, placeholders)
	if name then
		inst.Name = name
	end
	inst.Parent = parent
	return inst, report
end

--------------------------------------------------------------------------------

local mode = ARGS.mode or "export"

local function cleanupDefaults()
	for _, inst in pairs(defaults) do
		inst:Destroy()
	end
end

local function verifyRoot(path: string)
	local root = resolve(path)
	local a, stats = exportRoot(root, path)
	local scratch = Instance.new("Folder")
	scratch.Name = "_UIJsonVerify"
	scratch.Parent = game:GetService("ServerStorage")
	local rebuilt = importDoc(a, scratch, root.Name, true)
	local b = select(1, exportRoot(rebuilt, path))
	scratch:Destroy()
	if a == b then
		return string.format("OK %s: %d instances (%d code skipped), %d bytes", path, stats.count, stats.skipped, #a)
	end
	local la, lb = string.split(a, "\n"), string.split(b, "\n")
	for i = 1, math.max(#la, #lb) do
		if la[i] ~= lb[i] then
			return string.format("MISMATCH %s at line %d:\n  export: %s\n  rebuilt: %s", path, i, tostring(la[i]), tostring(lb[i]))
		end
	end
	return "MISMATCH " .. path .. " (length only)"
end

-- execute_luau truncates results near 100,000 characters, so a long export comes
-- back in chunks: the first line is "#chunk <from> <to> <total>", and the caller
-- reruns with ARGS.offset = <to> + 1 until <to> equals <total>.
local CHUNK = 90000

local function chunked(text: string)
	local from = ARGS.offset or 1
	if from == 1 and #text <= CHUNK then
		return text
	end
	local to = math.min(#text, from + CHUNK - 1)
	return string.format("#chunk %d %d %d\n", from, to, #text) .. text:sub(from, to)
end

-- ARGS.roots (a list) exports or verifies several roots in one run. Exports are
-- separated by "=== <root path>" lines; README.md shows how to split them into ui/.
local ok, result = pcall(function()
	local roots = ARGS.roots or { ARGS.root }
	if mode == "export" then
		local out = {}
		for _, path in ipairs(roots) do
			table.insert(out, "=== " .. path .. "\n" .. exportRoot(resolve(path), path))
		end
		-- "#end" marks the real end; the padding makes the MCP save even a small export to a file.
		return chunked(table.concat(out)) .. "\n#end\n" .. string.rep("#pad\n", 20000)
	elseif mode == "verify" then
		local out = {}
		for _, path in ipairs(roots) do
			local okRoot, line = pcall(verifyRoot, path)
			table.insert(out, okRoot and line or ("FAIL " .. path .. ": " .. tostring(line)))
		end
		return table.concat(out, "\n")
	elseif mode == "import" then
		local parent = resolve(ARGS.parent or "ServerStorage")
		local inst, report = importDoc(ARGS.json, parent, ARGS.name)
		return "imported " .. inst:GetFullName() .. "\n" .. table.concat(report, "\n")
	end
	error("unknown mode " .. tostring(mode))
end)

cleanupDefaults()
local leftover = game:GetService("ServerStorage"):FindFirstChild("_UIJsonVerify")
if leftover then
	leftover:Destroy()
end
if not ok then
	error(result, 0)
end
return result
