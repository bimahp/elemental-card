-- CardCost — shared Energy + Charge cost helper (ReplicatedStorage; server + client).
-- NpcAI uses this for affordability scoring. Client uses it for display hints.
-- Server remains authoritative: BattleLogic.playCard re-validates and pays.
local CardCost = {}

-- Mirror of Ops.effectiveCost (Ops is SSS-only, unavailable in RS).
local function effectiveCost(side, cardId, baseCost)
	local cost = baseCost
	for _, mod in ipairs(side.costMods or {}) do
		if mod.ids and mod.ids[cardId] then
			if mod.kind == "set" then cost = mod.value
			elseif mod.kind == "reduce" then cost = cost - (mod.value or 0) end
		end
	end
	return math.max(0, cost)
end

-- Local charge availability check (mirrors ChargeState.canSpendCharge without
-- requiring SSS). Works for both live server state and client snapshot state.
local function canSpendCharge(side, battleType, amount)
	amount = amount or 1
	if amount <= 0 then return true end
	for _, slot in ipairs(side.chargeSlots or {}) do
		if slot.battleType == battleType and (slot.amount or 0) >= amount then
			return true
		end
	end
	return false
end

function CardCost.getEnergyCost(side, cardId, card)
	return effectiveCost(side, cardId, card.cost or 0)
end

function CardCost.getChargeCost(card)
	return card.chargeCost
end

local function effectiveChargeCost(side, cardId, rawCc)
	if not rawCc then return nil end
	local bonus = 0
	for _, mod in ipairs(side.chargeCostMods or {}) do
		if mod.cardId == cardId and (mod.remaining or 1) > 0 then bonus += (mod.value or 0) end
	end
	if bonus == 0 then return rawCc end
	return { battleType = rawCc.battleType, amount = rawCc.amount + bonus }
end

function CardCost.canPay(side, cardId, card)
	local energy = CardCost.getEnergyCost(side, cardId, card)
	if (side.energy or 0) < energy then return false end
	local cc = effectiveChargeCost(side, cardId, card.chargeCost)
	if cc and not canSpendCharge(side, cc.battleType, cc.amount) then return false end
	return true
end

-- Returns UI-ready cost parts:
--   Energy-only:  { energy = N }
--   Hybrid:       { energy = N, charge = { battleType, amount } }
--   Pure-charge:  { charge = { battleType, amount } }  (energy nil = hide badge)
function CardCost.getCostParts(side, cardId, card)
	local energy = CardCost.getEnergyCost(side, cardId, card)
	local cc = effectiveChargeCost(side, cardId, card.chargeCost)
	local isPureCharge = cc ~= nil and energy == 0
	local parts = {}
	if not isPureCharge then parts.energy = energy end
	if cc then parts.charge = { battleType = cc.battleType, amount = cc.amount } end
	return parts
end

function CardCost.failureReason(side, cardId, card)
	local energy = CardCost.getEnergyCost(side, cardId, card)
	if (side.energy or 0) < energy then return "Not enough Energy" end
	local cc = effectiveChargeCost(side, cardId, card.chargeCost)
	if cc and not canSpendCharge(side, cc.battleType, cc.amount) then
		return "Not enough " .. (cc.battleType or "?") .. " Charge"
	end
	return nil
end

return CardCost
