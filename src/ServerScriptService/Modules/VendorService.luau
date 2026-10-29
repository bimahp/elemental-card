-- VendorService: deterministic rotating Card Merchant stock + Craft/Buy entry points.
-- Persistence commits atomically inside SaveService, mirroring GachaService's shape.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SSS               = game:GetService("ServerScriptService")

local SaveService = require(SSS.Modules.SaveService)
local Cards       = require(ReplicatedStorage.Definitions.Cards)
local Config      = require(ReplicatedStorage.Modules.VendorConfig)

local VendorService = {}

local pool = {}
for rarity in pairs(Config.STOCK_RARITY_SPREAD) do pool[rarity] = {} end
for cardId, card in pairs(Cards) do
	if card.collectible ~= false and pool[card.rarity] then
		local bucket = pool[card.rarity]
		bucket[#bucket + 1] = cardId
	end
end
for _, bucket in pairs(pool) do table.sort(bucket) end

local RARITY_ORDER = {}
for rarity in pairs(Config.STOCK_RARITY_SPREAD) do RARITY_ORDER[#RARITY_ORDER + 1] = rarity end
table.sort(RARITY_ORDER)

-- Epoch-aligned bucket, e.g. 8h buckets land exactly on 00:00/08:00/16:00 server time with
-- zero persisted state -- every server computes the identical bucket independently, same
-- principle as SaveService.dayBucket().
function VendorService.getRotationBucket(now)
	now = now or os.time()
	return math.floor(now / Config.ROTATION_INTERVAL_SECONDS)
end

function VendorService.getNextRotationTime(now)
	now = now or os.time()
	return (VendorService.getRotationBucket(now) + 1) * Config.ROTATION_INTERVAL_SECONDS
end

-- Pure function of the bucket number -- deterministic across every server without any
-- persisted/synced state. Picks STOCK_RARITY_SPREAD unique cards per rarity.
function VendorService.getStockCardIds(bucket)
	local rng = Random.new(bucket)
	local stock = {}
	for _, rarity in ipairs(RARITY_ORDER) do
		local n = Config.STOCK_RARITY_SPREAD[rarity] or 0
		local source = pool[rarity]
		if n > 0 and source and #source > 0 then
			-- Partial Fisher-Yates over a copy so the shared pool table is never mutated.
			local shuffled = table.clone(source)
			local count = math.min(n, #shuffled)
			for i = 1, count do
				local j = rng:NextInteger(i, #shuffled)
				shuffled[i], shuffled[j] = shuffled[j], shuffled[i]
				stock[#stock + 1] = shuffled[i]
			end
		end
	end
	return stock
end

function VendorService.getCurrentStock()
	return VendorService.getStockCardIds(VendorService.getRotationBucket())
end

-- Enrich a stock card-id list with rarity/prices/owned/maxed for client display.
-- Pure function of (stockCardIds, ownedCounts) -- testable headlessly without a player.
function VendorService.buildStockView(stockCardIds, ownedCounts)
	ownedCounts = type(ownedCounts) == "table" and ownedCounts or {}
	local view = {}
	for _, cardId in ipairs(stockCardIds) do
		local card = Cards[cardId]
		if card then
			local owned = ownedCounts[cardId] or 0
			view[#view + 1] = {
				cardId = cardId,
				rarity = card.rarity,
				craftCost = Config.CRAFT_COST_BY_RARITY[card.rarity],
				buyCost = Config.BUY_COST_BY_RARITY[card.rarity],
				owned = owned,
				maxed = owned >= Config.MAX_USEFUL_COPIES,
			}
		end
	end
	return view
end

local function inStock(cardId)
	for _, id in ipairs(VendorService.getCurrentStock()) do
		if id == cardId then return true end
	end
	return false
end

function VendorService.craftCard(player, cardId)
	if not inStock(cardId) then
		return { ok = false, error = "Card is not in today's stock" }
	end
	local card = Cards[cardId]
	local cost = card and Config.CRAFT_COST_BY_RARITY[card.rarity]
	if not cost then
		return { ok = false, error = "Unsupported rarity" }
	end
	return SaveService.applyCardCraft(player, cardId, cost)
end

function VendorService.buyCard(player, cardId)
	if not inStock(cardId) then
		return { ok = false, error = "Card is not in today's stock" }
	end
	local card = Cards[cardId]
	local cost = card and Config.BUY_COST_BY_RARITY[card.rarity]
	if not cost then
		return { ok = false, error = "Unsupported rarity" }
	end
	return SaveService.applyCardBuy(player, cardId, cost)
end

return VendorService
