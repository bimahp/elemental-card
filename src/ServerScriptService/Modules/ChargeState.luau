-- ChargeState — authoritative two-slot hero Charge state machine (server).
--
-- Each side holds up to two Charge Types at once. Exactly one occupied slot is
-- "current". A freshly gained Charge always becomes current. Direct gainCharge
-- calls can replace the INACTIVE occupied slot with a third distinct type.
-- Board end-turn generation first checks canGainWithoutReplace and skips when
-- both slots are occupied by other types.
--
-- Per-side state shape (initialized by ChargeState.init):
--   chargeSlots = { {battleType=nil, amount=0}, {battleType=nil, amount=0} }
--   currentChargeSlot = nil        -- 1, 2, or nil when both slots are empty
--   chargeSeq = 0                  -- monotonic per-side event sequence
--   pendingChargeEvents = {}       -- ChargeChanged records, cleared on broadcast
--
-- Invariants (see normalizeSlots):
--   * at most two occupied Charge Types (two physical slots)
--   * no duplicate occupied Battle Type
--   * an occupied slot has amount > 0; an empty slot is {battleType=nil, amount=0}
--   * if one slot is occupied it is current
--   * if both slots are occupied exactly one is current
--   * NEUTRAL never occupies a slot
--
-- Energy, Armor, and HP are NOT stored here — Charge is its own resource.

local RS = game:GetService("ReplicatedStorage")
local ChargeConfig = require(RS.Modules.ChargeConfig)

local ChargeState = {}

local SLOTS = ChargeConfig.MAX_SLOTS

-- ── helpers ──────────────────────────────────────────────────────────────────

local function snap(slot)
	return { battleType = slot.battleType, amount = slot.amount }
end

local function isOccupied(slot)
	return slot.battleType ~= nil and (slot.amount or 0) > 0
end

local function findType(side, battleType)
	for i = 1, SLOTS do
		local s = side.chargeSlots[i]
		if s.battleType == battleType and isOccupied(s) then return i end
	end
	return nil
end

local function firstEmpty(side)
	for i = 1, SLOTS do
		if not isOccupied(side.chargeSlots[i]) then return i end
	end
	return nil
end

local function occupiedIndices(side)
	local out = {}
	for i = 1, SLOTS do
		if isOccupied(side.chargeSlots[i]) then out[#out + 1] = i end
	end
	return out
end

local function clearSlot(slot)
	slot.battleType = nil
	slot.amount = 0
end

local function recordEvent(side, ev)
	side.chargeSeq = (side.chargeSeq or 0) + 1
	ev.seq = side.chargeSeq
	side.pendingChargeEvents = side.pendingChargeEvents or {}
	side.pendingChargeEvents[#side.pendingChargeEvents + 1] = ev
	return ev
end

-- ── construction ─────────────────────────────────────────────────────────────

function ChargeState.init(side)
	side.chargeSlots = {
		{ battleType = nil, amount = 0 },
		{ battleType = nil, amount = 0 },
	}
	side.currentChargeSlot = nil
	side.chargeSeq = 0
	side.pendingChargeEvents = {}
	return side
end

-- ── normalization / invariant repair ─────────────────────────────────────────

-- Deterministically repairs a side's Charge state to satisfy every invariant.
-- Safe to call after any mutation or on a snapshot of unknown provenance.
function ChargeState.normalizeSlots(side)
	local slots = side.chargeSlots
	if not slots then return ChargeState.init(side) end

	-- 1) Clear malformed/empty slots (non-positive amount, NEUTRAL, or no type).
	for i = 1, SLOTS do
		local s = slots[i]
		if (s.amount or 0) <= 0 or s.battleType == nil or not ChargeConfig.isProducing(s.battleType) then
			clearSlot(s)
		end
	end

	-- 2) De-duplicate: merge a duplicated Battle Type into the lowest slot index.
	local seen = {}
	for i = 1, SLOTS do
		local s = slots[i]
		if isOccupied(s) then
			local first = seen[s.battleType]
			if first then
				slots[first].amount += s.amount
				clearSlot(s)
			else
				seen[s.battleType] = i
			end
		end
	end

	-- 3) Recompute current deterministically.
	local occ = occupiedIndices(side)
	if #occ == 0 then
		side.currentChargeSlot = nil
	elseif #occ == 1 then
		side.currentChargeSlot = occ[1]
	else
		local cur = side.currentChargeSlot
		local valid = (cur == occ[1] or cur == occ[2])
		if not valid then side.currentChargeSlot = occ[1] end
	end
	return side
end

-- ── queries ──────────────────────────────────────────────────────────────────

function ChargeState.canSpendCharge(side, battleType, amount)
	amount = amount or 1
	if amount <= 0 then return true end
	local idx = findType(side, battleType)
	if not idx then return false end
	return side.chargeSlots[idx].amount >= amount
end

-- Returns true when battleType can gain Charge without displacing an existing slot.
function ChargeState.canGainWithoutReplace(side, battleType)
	if not ChargeConfig.isProducing(battleType) then return false end
	if findType(side, battleType) then return true end
	if firstEmpty(side) then return true end
	return false
end

function ChargeState.bothSlotsOccupied(side)
	return #occupiedIndices(side) >= 2
end

-- ── mutations ────────────────────────────────────────────────────────────────

-- Gain `amount` Charge of `battleType` for state[who]. A gained Charge always
-- becomes current. Returns the recorded ChargeChanged event, or nil for a no-op
-- (non-producing type or non-positive amount).
function ChargeState.gainCharge(state, who, battleType, amount, sourceInfo)
	amount = amount or 1
	if amount <= 0 or not ChargeConfig.isProducing(battleType) then return nil end
	local side = state[who]
	local slots = side.chargeSlots
	sourceInfo = sourceInfo or {}

	local ev = {
		side = who,
		reason = sourceInfo.reason or "effect_gain",
		battleType = battleType,
		amount = amount,
		cardId = sourceInfo.cardId,
		sourceSlot = sourceInfo.sourceSlot,
		replacement = false,
	}

	local existing = findType(side, battleType)
	if existing then
		ev.changedSlot = existing
		ev.prev = snap(slots[existing])
		slots[existing].amount += amount
		side.currentChargeSlot = existing            -- matching gain becomes/stays current
		ev.final = snap(slots[existing])
	else
		local empty = firstEmpty(side)
		if empty then
			ev.changedSlot = empty
			ev.prev = snap(slots[empty])
			slots[empty].battleType = battleType
			slots[empty].amount = amount
			side.currentChargeSlot = empty
			ev.final = snap(slots[empty])
		else
			-- Both slots occupied with other types: replace the INACTIVE one.
			local occ = occupiedIndices(side)
			local inactive = (side.currentChargeSlot == occ[1]) and occ[2] or occ[1]
			ev.changedSlot = inactive
			ev.prev = snap(slots[inactive])
			ev.replacement = true
			ev.replacedType = slots[inactive].battleType
			ev.replacedAmount = slots[inactive].amount
			slots[inactive].battleType = battleType
			slots[inactive].amount = amount
			side.currentChargeSlot = inactive            -- new type becomes current
			ev.final = snap(slots[inactive])
		end
	end

	ChargeState.normalizeSlots(side)
	ev.currentSlot = side.currentChargeSlot
	return recordEvent(side, ev)
end

-- Spend `amount` Charge of `battleType` from state[who]. Spending does not move
-- the current slot unless the spent slot reaches zero. Returns true,event on
-- success; false,reason otherwise.
function ChargeState.spendCharge(state, who, battleType, amount, sourceInfo)
	amount = amount or 1
	local side = state[who]
	if amount <= 0 then return true end
	if not ChargeState.canSpendCharge(side, battleType, amount) then
		return false, "Not enough Charge"
	end
	sourceInfo = sourceInfo or {}
	local idx = findType(side, battleType)
	local slots = side.chargeSlots

	local ev = {
		side = who,
		reason = sourceInfo.reason or "spend",
		battleType = battleType,
		amount = amount,
		cardId = sourceInfo.cardId,
		sourceSlot = sourceInfo.sourceSlot,
		replacement = false,
		changedSlot = idx,
		prev = snap(slots[idx]),
	}

	slots[idx].amount -= amount
	if slots[idx].amount <= 0 then
		clearSlot(slots[idx])
	end
	-- normalize moves current off an emptied slot; an untouched current is preserved
	ChargeState.normalizeSlots(side)
	ev.final = snap(slots[idx])
	ev.currentSlot = side.currentChargeSlot
	return true, recordEvent(side, ev)
end

-- Resolve an ordered list of explicit gains one event at a time.
-- orderedGains = { {battleType=, amount=}, ... }
function ChargeState.gainChargesOrdered(state, who, orderedGains, sourceInfo)
	local events = {}
	for _, g in ipairs(orderedGains or {}) do
		local ev = ChargeState.gainCharge(state, who, g.battleType, g.amount, g.sourceInfo or sourceInfo)
		if ev then events[#events + 1] = ev end
	end
	return events
end

-- Drain and return this side's pending events (Phase 4 broadcasts then clears).
function ChargeState.drainEvents(side)
	local ev = side.pendingChargeEvents or {}
	side.pendingChargeEvents = {}
	return ev
end

-- Lowest-amount occupied slot index; tie-break: inactive first, then lower index.
local function lowestOccupiedIndex(side)
	local occ = occupiedIndices(side)
	if #occ == 0 then return nil end
	local best = occ[1]
	for _, i in ipairs(occ) do
		if i == best then continue end
		local bs = side.chargeSlots[best]
		local cs = side.chargeSlots[i]
		local bInactive = (best ~= side.currentChargeSlot)
		local cInactive = (i   ~= side.currentChargeSlot)
		if cs.amount < bs.amount
			or (cs.amount == bs.amount and cInactive and not bInactive)
			or (cs.amount == bs.amount and cInactive == bInactive and i < best)
		then best = i end
	end
	return best
end

-- Destroy a Charge slot by selector ("lowest" | "current"). Returns event or nil.
function ChargeState.destroySlot(state, who, selector, sourceInfo)
	local side = state[who]
	local targetIdx = (selector == "current") and side.currentChargeSlot or lowestOccupiedIndex(side)
	if not targetIdx then return nil end
	local slot = side.chargeSlots[targetIdx]
	if not isOccupied(slot) then return nil end
	sourceInfo = sourceInfo or {}
	local ev = {
		side = who, reason = sourceInfo.reason or "destroy_slot",
		battleType = slot.battleType, amount = slot.amount,
		cardId = sourceInfo.cardId, changedSlot = targetIdx,
		prev = snap(slot), destroyed = true,
	}
	clearSlot(slot)
	ChargeState.normalizeSlots(side)
	ev.final = snap(side.chargeSlots[targetIdx])
	ev.currentSlot = side.currentChargeSlot
	return recordEvent(side, ev)
end

-- Drain `amount` from a slot by selector. Empties the slot if amount reaches 0.
function ChargeState.drainCharge(state, who, selector, amount, sourceInfo)
	amount = amount or 1
	if amount <= 0 then return nil end
	local side = state[who]
	local targetIdx = (selector == "current") and side.currentChargeSlot or lowestOccupiedIndex(side)
	if not targetIdx then return nil end
	local slot = side.chargeSlots[targetIdx]
	if not isOccupied(slot) then return nil end
	sourceInfo = sourceInfo or {}
	local drain = math.min(amount, slot.amount)
	local ev = {
		side = who, reason = sourceInfo.reason or "drain",
		battleType = slot.battleType, amount = drain,
		cardId = sourceInfo.cardId, changedSlot = targetIdx,
		prev = snap(slot),
	}
	slot.amount -= drain
	if slot.amount <= 0 then clearSlot(slot) end
	ChargeState.normalizeSlots(side)
	ev.final = snap(side.chargeSlots[targetIdx])
	ev.currentSlot = side.currentChargeSlot
	return recordEvent(side, ev)
end

return ChargeState
