-- Pure validate-then-commit Developer Product transaction.
-- PurchaseId recording and Shard credit happen in one synchronous in-memory mutation.
local ShopTransaction = {}

function ShopTransaction.grant(data, purchaseId, productId, shardAmount)
	if type(data) ~= "table" then
		return { ok = false, error = "Profile not loaded" }
	end
	if type(purchaseId) ~= "string" or purchaseId == "" then
		return { ok = false, error = "Invalid PurchaseId" }
	end
	if type(productId) ~= "number" or productId <= 0 or productId % 1 ~= 0 then
		return { ok = false, error = "Invalid ProductId" }
	end
	if type(shardAmount) ~= "number" or shardAmount <= 0 or shardAmount % 1 ~= 0 then
		return { ok = false, error = "Invalid Shard amount" }
	end

	local history = data.purchaseHistory
	if type(history) ~= "table" then history = {} end
	local shards = tonumber(data.crystalShards) or 0
	if history[purchaseId] == true then
		data.purchaseHistory = history
		return {
			ok = true,
			alreadyGranted = true,
			crystalShards = shards,
			purchaseId = purchaseId,
			productId = productId,
		}
	end

	history[purchaseId] = true
	data.purchaseHistory = history
	data.crystalShards = shards + shardAmount
	return {
		ok = true,
		alreadyGranted = false,
		crystalShards = data.crystalShards,
		shardsGranted = shardAmount,
		purchaseId = purchaseId,
		productId = productId,
	}
end

return ShopTransaction
