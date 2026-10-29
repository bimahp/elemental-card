-- ChargeConfig — shared Battle Type / Charge configuration (single source of truth).
--
-- Charge is a hero resource separate from Energy. A successful card play grants
-- +1 "normal" Charge of the card's Battle Type when that type is Charge-producing
-- (see BattleLogic.playCard, Phase 2). NEUTRAL never produces or occupies Charge.
--
-- This module is the canonical home for the Battle Type color palette too, so the
-- server (Charge producing rules) and the client (battle UI, deck-builder warning)
-- read one source. CardVisuals.TC_type references ChargeConfig.Colors.

local ChargeConfig = {}

-- Canonical Battle Type colors (hex in comments). Reused by CardVisuals.TC_type.
ChargeConfig.Colors = {
	MIGHTY  = Color3.fromRGB(165, 14, 14),   -- #A50E0E
	SWIFT   = Color3.fromRGB(13, 101, 45),   -- #0D652D
	VITAL   = Color3.fromRGB(23, 78, 166),   -- #174EA6
	NEUTRAL = Color3.fromRGB(154, 160, 166), -- #9AA0A6
}

-- Charge-producing Battle Types in canonical display order. NEUTRAL is absent
-- on purpose: it never produces Charge and never occupies a hero Charge Slot.
ChargeConfig.ProducingOrder = { "MIGHTY", "SWIFT", "VITAL" }

local PRODUCING = {}
for _, bt in ipairs(ChargeConfig.ProducingOrder) do PRODUCING[bt] = true end

-- Maximum number of distinct Charge Types a hero can hold at once (two slots).
ChargeConfig.MAX_SLOTS = 2

-- True only for Battle Types that generate/occupy Charge (MIGHTY/SWIFT/VITAL).
function ChargeConfig.isProducing(battleType)
	return PRODUCING[battleType] == true
end

-- Color for a Battle Type, falling back to NEUTRAL for unknown values.
function ChargeConfig.color(battleType)
	return ChargeConfig.Colors[battleType] or ChargeConfig.Colors.NEUTRAL
end

return ChargeConfig
