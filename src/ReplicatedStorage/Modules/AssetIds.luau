-- ── AssetIds ─────────────────────────────────────────────────────────────
-- Single source of truth for every gameplay image asset the client renders.
-- All IDs verified Image-type and owned by the place creator (audit 2026-06-22).
local AssetIds = {}

AssetIds.LoadingBackground = "rbxassetid://99142567993225"

AssetIds.ArchetypeBG = {
	MIGHTY  = "rbxassetid://115543591799677",
	SWIFT   = "rbxassetid://115543591799677",
	VITAL   = "rbxassetid://115543591799677",
	NEUTRAL = "rbxassetid://115543591799677",
}

AssetIds.CardArt = {
	scrappy_squire    = "rbxassetid://87808815304512",
	ironclad_sentinel = "rbxassetid://83417712038719",
	skyreach_wyrm     = "rbxassetid://81113477305401",
}

local CardDefinitions = require(game:GetService("ReplicatedStorage"):WaitForChild("Definitions"):WaitForChild("Cards"))
local function normalizeImageAsset(value)
	if type(value) == "number" then return "rbxassetid://" .. tostring(value) end
	if type(value) ~= "string" or value == "" then return nil end
	if value:match("^rbxassetid://%d+$") then return value end
	if value:match("^%d+$") then return "rbxassetid://" .. value end
	return nil
end
for cardId, card in pairs(CardDefinitions) do
	local image = normalizeImageAsset(card.image_asset)
	if image then AssetIds.CardArt[cardId] = image end
end

AssetIds.SpellArtPlaceholder = "rbxassetid://127780045941863"
AssetIds.Icons = {
	ATK    = "rbxassetid://139799158026059",
	HP     = "rbxassetid://113514992851320",
	ENERGY         = "rbxassetid://114305689596215",
	CRYSTAL_SHARD  = "rbxassetid://103621750170047",
	-- Card Fragments (DESIGN_ECONOMY.md) has no dedicated art yet -- reuses the
	-- former Crystal Dust icon asset (retired currency) as a placeholder,
	-- same convention as PackArt.standard reusing CardBackTexture below.
	CARD_FRAGMENT  = "rbxassetid://118745543637085",
	MATCHMAKING    = "rbxassetid://105294857091338",
}
AssetIds.CardBackTexture = "rbxassetid://78840923284579"
AssetIds.ChargeEmblems = {
	MIGHTY = "rbxassetid://113714129038997",
	SWIFT  = "rbxassetid://85144869902707",
	VITAL  = "rbxassetid://130762135310785",
}
AssetIds.EnergyIconAlt = "rbxassetid://129230024133869"
AssetIds.InventoryIcon = "rbxassetid://116636880497611"
AssetIds.ItemMallIcon = "rbxassetid://120259957052835"
AssetIds.VendingIcon = "rbxassetid://133767745946129"
AssetIds.PackArt = {
	standard = AssetIds.CardBackTexture, -- placeholder until dedicated pack art exists
}

local function appendUnique(list, seen, id)
	if type(id) == "string" and id ~= "" and not seen[id] then
		seen[id] = true
		list[#list + 1] = id
	end
end

local function appendShared(list, seen)
	for _, id in pairs(AssetIds.ArchetypeBG) do appendUnique(list, seen, id) end
	for _, id in pairs(AssetIds.Icons) do appendUnique(list, seen, id) end
	appendUnique(list, seen, AssetIds.SpellArtPlaceholder)
	appendUnique(list, seen, AssetIds.CardBackTexture)
	appendUnique(list, seen, AssetIds.EnergyIconAlt)
	appendUnique(list, seen, AssetIds.InventoryIcon)
	appendUnique(list, seen, AssetIds.ItemMallIcon)
	appendUnique(list, seen, AssetIds.VendingIcon)
	for _, id in pairs(AssetIds.PackArt) do appendUnique(list, seen, id) end
	for _, id in pairs(AssetIds.ChargeEmblems) do appendUnique(list, seen, id) end
end

-- Small login gate: only shared art needed immediately by common UI and pack reveals.
function AssetIds.startupList()
	local list, seen = {}, {}
	appendShared(list, seen)
	return list
end

-- Exact reveal gate: shared card chrome plus only the cards the server just rolled.
function AssetIds.revealList(cardResults)
	local list, seen = {}, {}
	appendShared(list, seen)
	for _, result in ipairs(cardResults or {}) do
		local cardId = type(result) == "table" and result.cardId or nil
		local card = cardId and CardDefinitions[cardId] or nil
		appendUnique(list, seen, cardId and AssetIds.CardArt[cardId] or nil)
		if card and not AssetIds.CardArt[cardId] then
			if card.cardType == "SPELL" then
				appendUnique(list, seen, AssetIds.SpellArtPlaceholder)
			else
				appendUnique(list, seen, AssetIds.ArchetypeBG[card.battleType] or AssetIds.ArchetypeBG.NEUTRAL)
			end
		end
	end
	return list
end

-- Full library list retained for audits/tools; it is deliberately NOT the login gate.
function AssetIds.criticalList()
	local list, seen = {}, {}
	appendShared(list, seen)
	for _, id in pairs(AssetIds.CardArt) do appendUnique(list, seen, id) end
	return list
end

return AssetIds
