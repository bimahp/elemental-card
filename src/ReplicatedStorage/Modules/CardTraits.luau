-- CardTraits — checks for permanent card traits encoded as effects[] entries.
-- Traits use { trigger = "passive", action = <traitName> } and are never
-- dispatched by fireEvent — they are purely declarative flags checked at
-- play time by BattleLogic and at render time by CardVisuals / CardCost.
local CardTraits = {}

function CardTraits.has(card, trait)
	for _, e in ipairs((card and card.effects) or {}) do
		if e.action == trait then return true end
	end
	return false
end

return CardTraits
