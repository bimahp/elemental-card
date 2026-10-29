-- Renders card ability text and target classification from the effects[] schema.
-- Replaces the old in-CardData getAbilityDisplay. Used by the Battle UI via a shim.
local Cards = require(script.Parent.Parent.Definitions.Cards)
local CardText = {}

local TRIGGER_LABEL = {
	emerge = "Emerge", shatter = "Shatter", chain = "Chain",
	turn_end = "Turn End", attacked = "When attacked", resonance = "Aura",
	deal_damage = "On damage", ally_death = "On ally death", cast = "",
	passive = "", take_damage = "On damage taken",
}
local KW_LABEL = {
	taunt="Taunt", charge="Charge", stealth="Stealth",
	quickstrike="Quickstrike", lifesteal="Lifesteal", rebirth="Rebirth",
}

local function tgtText(e)
	local area = e.area or "single"
	if area == "all" then
		if e.target == "enemy_creature" then return "all enemy creatures" end
		if e.target == "friendly_creature" then return "all friendly creatures" end
	elseif area == "split" then
		return "random enemy creatures"
	end
	local map = {
		enemy_creature="an enemy creature", enemy_target="an enemy", any_creature="a creature",
		friendly_creature="a friendly creature", own_hero="your hero", self="this",
		all_friendly="all friendly characters", random_enemy="a random enemy creature",
		random_friendly="a random friendly creature",
	}
	return map[e.target] or "a target"
end

local function valText(e)
	if e.valueFrom == "drawn_card_cost" then return "the drawn card's cost" end
	return tostring(e.value or 0)
end

-- Suffix for target-level conditions (appended to the target phrase).
local function condText(c)
	if not c then return "" end
	if c.type == "damaged" then return " that is damaged"
	elseif c.type == "attack_gte" then return " with " .. (c.value or 0) .. "+ Attack"
	elseif c.type == "attack_lte" then return " with " .. (c.value or 0) .. " or less Attack" end
	return ""
end

-- Prefix for spell-level prerequisite conditions ("If …, ").
local PREREQ_TEXT = {
	friendly_damaged_exists = "If you have a wounded ally, ",
	target_undamaged        = "If target is undamaged, ",
	chain                   = "Chain: ",
}
local function prereqText(c)
	if not c then return "" end
	return PREREQ_TEXT[c.type] or ""
end

local function actionText(e)
	local a = e.action
	local life = e.lifesteal and " (Lifesteal)" or ""
	if a == "damage" then
		if e.valueFrom then return "Deal damage equal to " .. valText(e) .. " to " .. tgtText(e) .. life end
		return "Deal " .. valText(e) .. " to " .. tgtText(e) .. life
	elseif a == "heal" then return "Restore " .. valText(e) .. " Health to " .. tgtText(e)
	elseif a == "gain_armor" then return "Gain " .. valText(e) .. " Armor"
	elseif a == "buff" then
		local s = (e.atk and e.hp) and ("+" .. e.atk .. "/+" .. e.hp)
			or (e.atk and ("+" .. e.atk .. " Attack")) or ("+" .. (e.hp or 0) .. " Health")
		return "Give " .. tgtText(e) .. " " .. s
	elseif a == "draw_card" then
		local f = e.filter and e.filter.race and (" " .. e.filter.race) or ""
		return "Draw " .. valText(e) .. f .. " card(s)"
	elseif a == "destroy" then return "Destroy " .. tgtText(e) .. condText(e.condition)
	elseif a == "grant_keyword" then return "Give " .. tgtText(e) .. " " .. (KW_LABEL[e.keyword] or e.keyword)
	elseif a == "summon" then
		local def = Cards[e.cardId]; return "Summon " .. (e.count or 1) .. " " .. (def and def.name or e.cardId)
	elseif a == "bounce" then return "Return " .. tgtText(e) .. " to hand"
	elseif a == "return_from_graveyard" then return "Return a random card from your graveyard to your hand"
	elseif a == "reduce_cost" then return "Reduce cost of cards in your " .. (e.target or "hand") .. " by " .. valText(e)
	elseif a == "set_cost" then return "Set the " .. (e.target == "returned_card" and "returned card's" or "drawn cards'") .. " cost to " .. valText(e)
	elseif a == "gain_energy" then return "Gain " .. valText(e) .. " Energy this turn"
	elseif a == "corrupted" then return "Corrupted: This card does not generate Battle Charge when played."
	elseif a == "destroy_charge_slot" then return "Destroy your lowest Charge slot. Requires two Charge slots."
	elseif a == "drain_charge" then return "Enemy loses " .. (e.value or 1) .. " Charge from their current slot."
	elseif a == "disable_shatter" then return "Disable Shatter on " .. tgtText(e) .. "."
	elseif a == "add_additional_charge_cost_to_player_hand" then
		return "Enemy Charge-cost cards in hand cost +" .. (e.value or 1) .. " more Charge."
	end
	return a
end

-- (label, body) for the card's ability panel. label = keywords; body = effect lines.
function CardText.getAbilityDisplay(cardId)
	local card = Cards[cardId]
	if not card then return "", "" end
	local label = ""
	if card.keywords and #card.keywords > 0 then
		local parts = {}
		for _, k in ipairs(card.keywords) do parts[#parts+1] = KW_LABEL[k] or k end
		label = table.concat(parts, ", ")
	end
	local lines = {}
	for _, e in ipairs(card.effects or {}) do
		local trig = TRIGGER_LABEL[e.trigger] or ""
		local pre  = prereqText(e.condition)
		local txt  = pre .. actionText(e)
		lines[#lines+1] = (trig ~= "") and ("<b>" .. trig .. ":</b> " .. txt) or txt
	end
	return label, table.concat(lines, "\n")
end

-- Explicit play-target for the UI drag system.
-- Returns the card's playTarget field for spells, or "empty_slot" for creatures.
function CardText.playTarget(card)
	if card.cardType == "creature" then return "empty_slot" end
	return card.playTarget
end

return CardText
