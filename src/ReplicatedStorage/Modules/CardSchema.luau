-- Validates the card database against the alpha schema (DESIGN_DATABASE.md).
local ChargeConfig = require(game:GetService("ReplicatedStorage").Modules.ChargeConfig)
local CardSchema = {}

local function set(t) local s={} for _,v in ipairs(t) do s[v]=true end return s end

local TRIGGERS   = set({"emerge","shatter","chain","resonance","cast","turn_end","attacked","deal_damage","ally_death","passive","take_damage"})
local ACTIONS    = set({"damage","gain_armor","heal","buff","draw_card","destroy","grant_keyword","summon","bounce","return_from_graveyard","reduce_cost","set_cost","gain_energy","gain_charge","corrupted","destroy_charge_slot","drain_charge","disable_shatter","add_additional_charge_cost_to_player_hand"})
local TARGETS    = set({"enemy_creature","friendly_creature","any_creature","enemy_target","self","own_hero","random_friendly","random_enemy","all_friendly","random","hand","drawn_cards","returned_card"})
local AREAS      = set({"single","all","split"})
local CONDITIONS = set({"damaged","target_undamaged","attack_gte","attack_lte","friendly_damaged_exists","chain","two_charge_slots_occupied"})
local KEYWORDS   = set({"taunt","charge","stealth","quickstrike","lifesteal","rebirth"})
local CARDTYPES  = set({"creature","spell"})
local BATTLETYPES= set({"MIGHTY","SWIFT","VITAL","NEUTRAL"})
local RARITIES     = set({"common","rare","epic"})
local PLAY_TARGETS = set({"friendly_creature","enemy_creature","friendly_character","enemy_character","any_creature","own_hero","enemy_hero","own_board","enemy_board","battle_board","own_side","enemy_side"})

local CHOSEN_TARGET_PLAY_TARGETS = {
	friendly_creature = {friendly_creature=true,any_creature=true},
	enemy_creature = {enemy_creature=true,any_creature=true},
	enemy_target = {enemy_character=true,enemy_hero=true},
	any_creature = {any_creature=true},
}

local AREA_PLAY_TARGETS = {
	enemy_creature = {enemy_board=true,battle_board=true},
	friendly_creature = {own_board=true,battle_board=true},
	any_creature = {battle_board=true},
}

local RESOLVED_TARGET_PLAY_TARGETS = {
	own_hero = {own_hero=true,friendly_character=true,own_side=true},
	all_friendly = {own_side=true},
	random_friendly = {own_board=true,own_side=true,battle_board=true},
	random_enemy = {enemy_board=true,enemy_side=true,battle_board=true},
}

local function compatiblePlayTarget(card)
	local pt = card.playTarget
	if not PLAY_TARGETS[pt] then return true end

	local chosen = {}
	for _, e in ipairs(card.effects or {}) do
		local area = e.area or "single"
		if area == "single" and CHOSEN_TARGET_PLAY_TARGETS[e.target] then
			chosen[e.target] = true
		end
	end
	for target in pairs(chosen) do
		if not CHOSEN_TARGET_PLAY_TARGETS[target][pt] then
			return false, "playTarget '"..pt.."' incompatible with chosen target '"..target.."'"
		end
	end
	if next(chosen) ~= nil then return true end

	for _, e in ipairs(card.effects or {}) do
		local area = e.area or "single"
		local allowed
		if area == "all" or area == "split" then
			allowed = AREA_PLAY_TARGETS[e.target]
		else
			allowed = RESOLVED_TARGET_PLAY_TARGETS[e.target]
		end
		if allowed and not allowed[pt] then
			return false, "playTarget '"..pt.."' incompatible with effect target '"..tostring(e.target).."'"
		end
	end
	return true
end

function CardSchema.validate(Cards)
	local errs = {}
	local function err(id, msg) errs[#errs+1] = "["..tostring(id).."] "..msg end
	for key, c in pairs(Cards) do
		if c.id ~= key then err(key, "id mismatch ('"..tostring(c.id).."')") end
		for _, f in ipairs({"id","name","pack","battleType","cardType","rarity"}) do
			if c[f] == nil then err(key, "missing field '"..f.."'") end
		end
		if type(c.cost) ~= "number" then err(key, "cost must be a number") end
		if not CARDTYPES[c.cardType] then err(key, "bad cardType '"..tostring(c.cardType).."'") end
		if not BATTLETYPES[c.battleType] then err(key, "bad battleType '"..tostring(c.battleType).."'") end
		if not RARITIES[c.rarity] then err(key, "bad rarity '"..tostring(c.rarity).."'") end
		if c.cardType == "creature" then
			if type(c.atk) ~= "number" then err(key, "creature needs atk") end
			if type(c.hp) ~= "number" then err(key, "creature needs hp") end
			if c.playTarget ~= nil then err(key, "creature must not have playTarget") end
		elseif c.cardType == "spell" then
			if not PLAY_TARGETS[c.playTarget] then
				err(key, "spell missing valid playTarget '"..tostring(c.playTarget).."'")
			else
				local ok, msg = compatiblePlayTarget(c)
				if not ok then err(key, msg) end
			end
		end
		if c.chargeCost ~= nil then
			local cc = c.chargeCost
			if type(cc) ~= "table" then
				err(key, "chargeCost must be a table")
			else
				if not ChargeConfig.isProducing(cc.battleType) then err(key, "chargeCost bad battleType '"..tostring(cc.battleType).."'") end
				if type(cc.amount) ~= "number" or cc.amount <= 0 then err(key, "chargeCost amount must be a positive number") end
			end
		end
		if c.keywords then
			for _, k in ipairs(c.keywords) do if not KEYWORDS[k] then err(key, "bad keyword '"..tostring(k).."'") end end
		end
		if c.effects then
			for i, e in ipairs(c.effects) do
				local tag = "effect#"..i
				if not TRIGGERS[e.trigger] then err(key, tag.." bad trigger '"..tostring(e.trigger).."'") end
				if not ACTIONS[e.action] then err(key, tag.." bad action '"..tostring(e.action).."'") end
				if e.action == "corrupted" then
					if e.trigger ~= "passive" then err(key, tag.." corrupted trait must use trigger='passive'") end
				else
					if e.target ~= nil and not TARGETS[e.target] then err(key, tag.." bad target '"..tostring(e.target).."'") end
					if e.area ~= nil and not AREAS[e.area] then err(key, tag.." bad area '"..tostring(e.area).."'") end
					if e.condition then
						if not CONDITIONS[e.condition.type] then err(key, tag.." bad condition '"..tostring(e.condition.type).."'") end
					end
					if e.action == "grant_keyword" and not KEYWORDS[e.keyword] then err(key, tag.." bad grant keyword '"..tostring(e.keyword).."'") end
					if e.action == "gain_charge" then
						if not ChargeConfig.isProducing(e.battleType) then err(key, tag.." gain_charge bad battleType '"..tostring(e.battleType).."'") end
						if e.valueFrom == nil and type(e.value) ~= "number" then err(key, tag.." gain_charge needs numeric value") end
					end
					if e.action == "summon" then
						if not e.cardId then err(key, tag.." summon missing cardId")
						elseif not Cards[e.cardId] then err(key, tag.." summon unknown cardId '"..tostring(e.cardId).."'") end
					end
					if e.action == "destroy_charge_slot" or e.action == "drain_charge" then
						local validOwners = {self=true,enemy=true}
						local validSelectors = {lowest=true,current=true}
						if not validOwners[e.chargeOwner] then err(key, tag.." "..e.action.." bad chargeOwner '"..tostring(e.chargeOwner).."'") end
						if not validSelectors[e.selector] then err(key, tag.." "..e.action.." bad selector '"..tostring(e.selector).."'") end
						if e.action == "drain_charge" and type(e.value) ~= "number" then err(key, tag.." drain_charge needs numeric value") end
					end
					if e.action == "add_additional_charge_cost_to_player_hand" then
						local validPlayers = {self=true,enemy=true}
						local validSelectors = {all=true,random=true}
						if not validPlayers[e.targetPlayer] then err(key, tag.." add_additional_charge_cost bad targetPlayer '"..tostring(e.targetPlayer).."'") end
						if not validSelectors[e.selector] then err(key, tag.." add_additional_charge_cost bad selector '"..tostring(e.selector).."'") end
						if type(e.value) ~= "number" then err(key, tag.." add_additional_charge_cost needs numeric value") end
					end
				end
			end
		end
	end
	return (#errs == 0), errs
end

function CardSchema.validateDecks(Cards, Decks)
	local errs = {}
	for key, d in pairs(Decks) do
		for _, id in ipairs(d.cards) do
			if not Cards[id] then errs[#errs+1] = "[deck:"..key.."] unknown card '"..tostring(id).."'" end
		end
	end
	return (#errs == 0), errs
end

return CardSchema
