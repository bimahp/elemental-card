-- VendorController: validates Card Merchant proximity and safely serializes Craft/Buy/Destroy.
-- Mirrors GachaController.lua's shape exactly.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players           = game:GetService("Players")
local SSS               = game:GetService("ServerScriptService")

local VendorService = require(SSS.Modules.VendorService)
local SaveService    = require(SSS.Modules.SaveService)
local Config         = require(ReplicatedStorage.Modules.VendorConfig)
local remotes        = ReplicatedStorage:WaitForChild("Remotes")
local GetVendorStock = remotes:WaitForChild("GetVendorStock")
local CraftCard      = remotes:WaitForChild("CraftCard")
local BuyCard        = remotes:WaitForChild("BuyCard")
local DestroyCards   = remotes:WaitForChild("DestroyCards")

local vendor = workspace:WaitForChild("Card Merchant")
local anchor = vendor:WaitForChild("HumanoidRootPart")

local ROLL_COOLDOWN_SECONDS = 0.5
local busy = {}
local lastActionAt = {}

local function isNearVendor(player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then return false end
	local allowed = Config.MAX_ACTIVATION_DISTANCE + Config.SERVER_DISTANCE_TOLERANCE
	return (root.Position - anchor.Position).Magnitude <= allowed
end

local function throttle(player)
	local userId = player.UserId
	local now = os.clock()
	if now - (lastActionAt[userId] or -math.huge) < ROLL_COOLDOWN_SECONDS then
		return false
	end
	lastActionAt[userId] = now
	return true
end

GetVendorStock.OnServerInvoke = function(player)
	if not isNearVendor(player) then
		return { ok = false, error = "Move closer to the Card Merchant" }
	end
	local ownedCounts = SaveService.getCollectionCounts(player)
	if not ownedCounts then return { ok = false, error = "Profile not loaded" } end
	local stockCardIds = VendorService.getCurrentStock()
	return {
		ok = true,
		stock = VendorService.buildStockView(stockCardIds, ownedCounts),
		nextRotationAt = VendorService.getNextRotationTime(),
	}
end

-- requireProximity=true for Craft/Buy (must be at the Vendor NPC). Destroy is a collection-
-- management action surfaced in InventoryController and reachable from anywhere -- it does
-- NOT require standing near the Vendor.
local function guardedAction(player, requireProximity, fn)
	local userId = player.UserId
	if requireProximity and not isNearVendor(player) then
		return { ok = false, error = "Move closer to the Card Merchant" }
	end
	if busy[userId] then
		return { ok = false, error = "Another transaction is already in progress" }
	end
	if not throttle(player) then
		return { ok = false, error = "Please wait before trying again" }
	end
	busy[userId] = true
	local ok, result = xpcall(fn, debug.traceback)
	busy[userId] = nil
	if not ok then
		warn("[VendorController] action failed for " .. player.Name .. ": " .. tostring(result))
		return { ok = false, error = "Vendor service temporarily unavailable" }
	end
	if type(result) ~= "table" then
		warn("[VendorController] action returned invalid result for " .. player.Name)
		return { ok = false, error = "Vendor service temporarily unavailable" }
	end
	return result
end

CraftCard.OnServerInvoke = function(player, cardId)
	return guardedAction(player, true, function()
		return VendorService.craftCard(player, cardId)
	end)
end

BuyCard.OnServerInvoke = function(player, cardId)
	return guardedAction(player, true, function()
		return VendorService.buyCard(player, cardId)
	end)
end

DestroyCards.OnServerInvoke = function(player, requests)
	return guardedAction(player, false, function()
		return SaveService.applyCardDestroy(player, requests)
	end)
end

Players.PlayerRemoving:Connect(function(player)
	busy[player.UserId] = nil
	lastActionAt[player.UserId] = nil
end)

print("[VendorController] GetVendorStock/CraftCard/BuyCard/DestroyCards wired with proximity and error guards")
