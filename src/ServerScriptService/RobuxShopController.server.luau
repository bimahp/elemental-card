-- RobuxShopController: policy-gated Developer Product catalog and receipt processing.
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local PolicyService = game:GetService("PolicyService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SSS = game:GetService("ServerScriptService")

local SaveService = require(SSS.Modules.SaveService)
local ShopConfig = require(ReplicatedStorage.Modules.ShopConfig)
local QuestConfig = require(ReplicatedStorage.Modules.QuestConfig)
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local GetMonetizationPolicy = Remotes:WaitForChild("GetMonetizationPolicy")
local QuestStateChanged = Remotes:WaitForChild("QuestStateChanged")

SaveService.init()

local policyCache = {}
local policyLastCall = {}
local processingReceipt = {}

local function policyFor(player)
	local cached = policyCache[player]
	if cached then return cached end
	local ok, info = pcall(function()
		return PolicyService:GetPolicyInfoForPlayerAsync(player)
	end)
	if not ok or type(info) ~= "table" then
		warn("[RobuxShopController] Policy lookup failed for " .. player.Name .. ": " .. tostring(info))
		return {
			ok = false,
			itemMallAllowed = false,
			error = "Purchase policy unavailable",
		}
	end
	local restricted = info.ArePaidRandomItemsRestricted == true
	local result = {
		ok = true,
		itemMallAllowed = not restricted,
		arePaidRandomItemsRestricted = restricted,
	}
	policyCache[player] = result
	return result
end

GetMonetizationPolicy.OnServerInvoke = function(player)
	local now = os.clock()
	if now - (policyLastCall[player] or -math.huge) < 0.5 then
		return policyCache[player] or {
			ok = false,
			itemMallAllowed = false,
			error = "Policy lookup is still loading",
		}
	end
	policyLastCall[player] = now
	return policyFor(player)
end

local function fireCurrencySnapshot(player)
	local snap = SaveService.getFullSnapshot(player)
	if not snap then return end
	local quest = snap.quests[QuestConfig.IDs.ONBOARDING] or { stage = "complete" }
	QuestStateChanged:FireClient(player, {
		stage = quest.stage,
		chosenArchetype = quest.archetype,
		level = snap.level,
		crystalShards = snap.crystalShards,
		cardFragments = snap.cardFragments,
	})
end

local function processReceipt(receipt)
	local bundle = ShopConfig.byProductId(receipt.ProductId)
	if not bundle then
		warn(string.format(
			"[RobuxShopController] Unhandled ProductId %s for PurchaseId %s; receipt left pending",
			tostring(receipt.ProductId),
			tostring(receipt.PurchaseId)
		))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	if not player or not SaveService.getProfile(player) then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	if processingReceipt[player] then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	processingReceipt[player] = receipt.PurchaseId
	local ok, result = xpcall(function()
		return SaveService.applyDeveloperProductReceipt(
			player,
			tostring(receipt.PurchaseId),
			receipt.ProductId,
			bundle.shards
		)
	end, debug.traceback)
	processingReceipt[player] = nil

	if not ok then
		warn("[RobuxShopController] Receipt crashed: " .. tostring(result))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if type(result) ~= "table" or not result.ok or not result.persisted then
		warn("[RobuxShopController] Receipt deferred: " .. tostring(result and result.error))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	fireCurrencySnapshot(player)
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

MarketplaceService.ProcessReceipt = processReceipt

Players.PlayerRemoving:Connect(function(player)
	policyCache[player] = nil
	policyLastCall[player] = nil
	processingReceipt[player] = nil
end)

print("[RobuxShopController] policy gate and ProcessReceipt wired")
