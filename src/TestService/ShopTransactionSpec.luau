-- Deterministic pure transaction coverage for Developer Product grants.
local SSS = game:GetService("ServerScriptService")
local Transaction = require(SSS.Modules.ShopTransaction)
local SaveService = require(SSS.Modules.SaveService)

local Spec = {}

function Spec.run()
	local data = { crystalShards = 25, purchaseHistory = {} }
	local first = Transaction.grant(data, "purchase_A", 101, 50)
	assert(first.ok and not first.alreadyGranted, first.error)
	assert(data.crystalShards == 75, "Fresh receipt must grant exact Shard amount")
	assert(data.purchaseHistory.purchase_A == true, "Fresh receipt must record PurchaseId")

	local duplicate = Transaction.grant(data, "purchase_A", 101, 50)
	assert(duplicate.ok and duplicate.alreadyGranted, "Duplicate receipt must be acknowledged")
	assert(data.crystalShards == 75, "Duplicate receipt must not grant twice")

	local before = data.crystalShards
	local badAmount = Transaction.grant(data, "purchase_B", 102, -1)
	assert(not badAmount.ok and data.crystalShards == before, "Bad amount must be atomic")
	assert(data.purchaseHistory.purchase_B == nil, "Bad amount must not record PurchaseId")

	local badId = Transaction.grant(data, "", 102, 50)
	assert(not badId.ok and data.crystalShards == before, "Bad PurchaseId must be atomic")

	local v50 = { _version = { major = 5, minor = 0 }, crystalShards = 10 }
	local migration = SaveService.migrate(v50)
	assert(migration == "minor_upgraded", "v5.0 profile must migrate non-destructively")
	assert(type(v50.purchaseHistory) == "table", "v5.1 migration must add purchaseHistory")
	assert(v50.crystalShards == 10, "v5.1 migration must preserve currency")

	return {
		crystalShards = data.crystalShards,
		duplicateProtected = true,
		atomicValidation = true,
		migrationVerified = true,
	}
end

return Spec
