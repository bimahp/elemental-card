-- EffectVisuals: resolves which visual archetype animates a card's cast
-- effect. Default mapping inferred from the effect entry's action/target/area
-- (works for every card automatically); an optional per-card `card.vfx`
-- override wins if present. No card uses the override yet -- mechanism only
-- (PLAN_CARD_BATTLE_REVAMP.md Phase 6). Only "projectile" has a real
-- PhaseRegistry handler so far; the rest are reserved names for the future
-- VFX-library follow-up.
local EffectVisuals = {}

local DEFAULT_BY_ACTION = {
	damage = "projectile",
	heal = "heal_bloom",
	buff = "buff_pulse",
	gain_armor = "shield_pulse",
	summon = "summon_puff",
}

function EffectVisuals.resolveVisualArchetype(entry, card)
	if card and card.vfx then return card.vfx end
	if not entry then return nil end
	if entry.action == "damage" and (entry.area == "all" or entry.area == "split") then
		return "area_swipe"
	end
	return DEFAULT_BY_ACTION[entry.action]
end

return EffectVisuals
