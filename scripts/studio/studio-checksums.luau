-- studio-checksums.luau: one line per script the repo owns, in the format of
-- scripts/checksums.ps1. Edit mode only; changes nothing. The result is padded so
-- the MCP saves it to a file for `checksums.ps1 -StudioFile`.
local ROOTS = {
	"ReplicatedFirst",
	"ReplicatedStorage",
	"ServerScriptService",
	"ServerStorage",
	"StarterGui",
	"StarterPlayer",
	"TestService",
}

-- FNV-1a 32-bit; hash * 16777619 written as (hash << 24) + hash * 403 to stay exact.
local function fnv1a32(text: string): number
	local hash = 2166136261
	for i = 1, #text do
		hash = bit32.bxor(hash, string.byte(text, i))
		hash = (bit32.lshift(hash, 24) + hash * 403) % 4294967296
	end
	return hash
end

local lines = {}
for _, serviceName in ipairs(ROOTS) do
	for _, item in ipairs(game:GetService(serviceName):GetDescendants()) do
		if item:IsA("LuaSourceContainer") then
			local enabled = true
			if item:IsA("BaseScript") then
				enabled = item.Enabled
			end
			local source = item.Source
			table.insert(lines, string.format("%s %s %s %d %d", item:GetFullName(), item.ClassName, tostring(enabled), #source, fnv1a32(source)))
		end
	end
end
table.sort(lines)
return table.concat(lines, "\n") .. "\n" .. string.rep("#pad\n", 20000)
