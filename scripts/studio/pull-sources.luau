-- pull-sources.luau: returns every script the repo owns, for scripts/pull-sources.ps1
-- to write into src/. Edit mode only; changes nothing.
--
--   local ARGS = { chunk = 1 }   -- then 2, 3, … up to the "chunks=" count in the header
--
-- Each script is "=== <path> <class> <enabled> <byte length>\n<source>\n". The byte
-- length makes the stream safe for any source text. Results come in chunks of at most
-- 90,000 bytes, cut on a UTF-8 boundary, and are padded so the MCP saves them to a file.
local ARGS = ARGS or {}

-- What src/ mirrors. Workspace is left out: it holds only free-model leftovers.
local ROOTS = {
	"ReplicatedFirst",
	"ReplicatedStorage",
	"ServerScriptService",
	"ServerStorage",
	"StarterGui",
	"StarterPlayer",
	"TestService",
}
local CHUNK = 90000

local entries = {}
for _, serviceName in ipairs(ROOTS) do
	for _, item in ipairs(game:GetService(serviceName):GetDescendants()) do
		if item:IsA("LuaSourceContainer") then
			local enabled = true
			if item:IsA("BaseScript") then
				enabled = item.Enabled
			end
			table.insert(entries, { path = item:GetFullName(), class = item.ClassName, enabled = enabled, source = item.Source })
		end
	end
end
table.sort(entries, function(a, b)
	return a.path < b.path
end)

local parts = {}
for _, e in ipairs(entries) do
	assert(not e.path:find(" "), "a space in a script path breaks the header: " .. e.path)
	table.insert(parts, string.format("=== %s %s %s %d\n", e.path, e.class, tostring(e.enabled), #e.source))
	table.insert(parts, e.source)
	table.insert(parts, "\n")
end
local text = table.concat(parts)

-- Chunk boundaries are computed the same way on every run, so chunks can be pulled in any order.
local bounds = {}
local start = 1
while start <= #text do
	local stop = math.min(#text, start + CHUNK - 1)
	-- never end inside a multi-byte character
	while stop < #text do
		local nextByte = string.byte(text, stop + 1)
		if nextByte < 0x80 or nextByte >= 0xC0 then
			break
		end
		stop -= 1
	end
	table.insert(bounds, { start, stop })
	start = stop + 1
end

local n = ARGS.chunk or 1
local from, to = bounds[n][1], bounds[n][2]
return string.format("#chunk %d %d %d scripts=%d chunks=%d\n", from, to, #text, #entries, #bounds)
	.. text:sub(from, to)
	.. "\n#end\n"
	.. string.rep("#pad\n", 20000)
