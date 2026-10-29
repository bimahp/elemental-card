-- Shared Item Mall Developer Product catalog.
-- Developer Product IDs configured from Creator Dashboard on 2026-07-01.
local ShopConfig = {}

ShopConfig.Bundles = {
	{ id = "shards_50",   productId = 3607628806, shards = 50   },
	{ id = "shards_250",  productId = 3607628936, shards = 250  },
	{ id = "shards_500",  productId = 3607629100, shards = 500  },
	{ id = "shards_1000", productId = 3607629181, shards = 1000 },
}

function ShopConfig.byProductId(productId)
	if type(productId) ~= "number" or productId <= 0 then return nil end
	for _, bundle in ipairs(ShopConfig.Bundles) do
		if bundle.productId == productId then return bundle end
	end
	return nil
end

return ShopConfig
