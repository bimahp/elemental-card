local RS  = game:GetService("ReplicatedStorage")
local Cards    = require(RS.Definitions.Cards)
local CardCost = require(RS.Modules.CardCost)
local NpcAI    = {}

local JITTER = { noob = 5, pro = 0.5 }

local function atkOf(c)  return (c.atk or 0) + (c.tempAtk or 0) end
local function hasKw(c, kw) for _,k in ipairs(c.keywords or {}) do if k==kw then return true end end return false end
local function emptySlot(side) for i=1,3 do if not side.board[i] then return i end end end
local function anyCreature(side) for i=1,3 do if side.board[i] then return true end end return false end
local function boardCount(side) local n=0; for i=1,3 do if side.board[i] then n+=1 end end return n end

local function bestEnemyTarget(oppSide, atkBudget)
	local kill, killScore, big, bigScore
	for i=1,3 do
		local c = oppSide.board[i]
		if c and not hasKw(c,"stealth") then
			if atkBudget and c.hp <= atkBudget then
				local s = atkOf(c)+c.hp
				if not kill or s>killScore then kill={side="__opp",slot=i}; killScore=s end
			end
			local s2 = atkOf(c)+c.hp
			if not big or s2>bigScore then big={side="__opp",slot=i}; bigScore=s2 end
		end
	end
	return kill or big
end

local function mostDamagedFriendly(side)
	local best, bestMiss
	for i=1,3 do local c=side.board[i]; if c then local m=c.maxHp-c.hp; if m>0 and (not best or m>bestMiss) then best={side="__me",slot=i}; bestMiss=m end end end
	return best
end
local function biggestFriendly(side)
	local best, bestScore
	for i=1,3 do local c=side.board[i]; if c then local s=atkOf(c)+c.hp; if not best or s>bestScore then best={side="__me",slot=i}; bestScore=s end end end
	return best
end
local function fix(t, who, opp) if not t then return nil end return {side=(t.side=="__me")and who or opp, slot=t.slot} end

local function chooseTarget(state, who, opp, card)
	local side, oppSide = state[who], state[opp]
	for _,e in ipairs(card.effects or {}) do
		if (e.area or "single")=="single" then
			if e.target=="enemy_creature" or e.target=="any_creature" then
				return fix(bestEnemyTarget(oppSide), who, opp)
			elseif e.target=="enemy_target" then
				return fix(bestEnemyTarget(oppSide),who,opp) or {side=opp,slot=0}
			elseif e.target=="friendly_creature" then
				return fix((e.action=="heal") and mostDamagedFriendly(side) or biggestFriendly(side), who, opp)
			end
		end
	end
end

local function handHasChainCard(side)
	local seen = {}
	for _,id in ipairs(side.hand) do
		if not seen[id] then seen[id]=true
			local c=Cards[id]; if c then for _,e in ipairs(c.effects or {}) do if e.trigger=="chain" then return true end end end
		end
	end
	return false
end

local function detectNpcArchetype(state, who)
	local counts, side = {}, state[who]
	local function tally(bt) if bt and bt~="NEUTRAL" then counts[bt]=(counts[bt] or 0)+1 end end
	for _,id in ipairs(side.deck or {}) do local c=Cards[id]; if c then tally(c.battleType) end end
	for _,id in ipairs(side.hand or {}) do local c=Cards[id]; if c then tally(c.battleType) end end
	for i=1,3 do local c=side.board[i]; if c then tally(c.battleType) end end
	local best, bestN = "MIGHTY", 0
	for bt,n in pairs(counts) do if n>bestN then best,bestN=bt,n end end
	return best
end

local function healScore(hp, maxHp)
	maxHp = maxHp or 30
	if hp >= maxHp-2 then return -2 end
	if hp < maxHp*0.4 then return 4 end
	if hp < maxHp*0.65 then return 2 end
	return 0
end

local function scoreCard(state, who, opp, card, archetype, difficulty)
	local side, oppSide = state[who], state[opp]
	local isPro = difficulty == "pro"
	local opts  = {}

	if card.cardType == "creature" then
		local slot = emptySlot(side); if not slot then return -100 end
		opts.slot = slot
		opts.target = chooseTarget(state, who, opp, card)
		local s = (card.atk or 0)+(card.hp or 0)+1
		if hasKw(card,"taunt")     then s += 2 end
		if hasKw(card,"charge")    then s += 2 end
		if hasKw(card,"lifesteal") then s += 2 end
		if card.battleType and card.battleType ~= "NEUTRAL" then
			local match=false
			for _,sl in ipairs(side.chargeSlots or {}) do if sl.battleType==card.battleType then match=true;break end end
			s += match and 2 or 1
		end
		if isPro then
			if archetype == "MIGHTY" then
				if boardCount(side) < 3 then
					s += hasKw(card,"taunt") and 5 or 3
				end
				if hasKw(card,"taunt") then
					for i=1,3 do local c=side.board[i]; if c and hasKw(c,"taunt") then s -= 4; break end end
				end
			elseif archetype == "SWIFT" then
				if hasKw(card,"stealth") then s += 2 end
				if hasKw(card,"charge")  then s += 1 end
			elseif archetype == "VITAL" then
				if hasKw(card,"lifesteal") then s += 3 end
				if hasKw(card,"rebirth") then
					local threat=false
					for i=1,3 do local c=oppSide.board[i]; if c and atkOf(c)>0 then threat=true;break end end
					s += threat and 3 or 1
				end
			end
		end
		return s, opts
	end

	-- spell
	opts.target = chooseTarget(state, who, opp, card)
	local s         = 0
	local heroHp    = side.heroHp or 30
	local maxHeroHp = side.maxHeroHp or 30
	local heroMiss  = maxHeroHp - heroHp
	local cardsPlayed   = state[who].cardsPlayedThisTurn or 0
	local hasChainInHand = isPro and archetype=="SWIFT" and handHasChainCard(side)

	for _,e in ipairs(card.effects or {}) do
		local act, trigger = e.action, e.trigger
		local chainBonus = 0
		if isPro and archetype=="SWIFT" and trigger=="chain" and cardsPlayed>=1 then chainBonus=4 end

		if act=="damage" then
			if e.target=="enemy_creature" and not anyCreature(oppSide) then s -= 8
			else s += (e.value or 1)*((e.area=="all" or e.area=="split") and 2 or 1)+3 end
		elseif act=="destroy" then
			s += anyCreature(oppSide) and 9 or -8
		elseif act=="heal" then
			if e.target=="own_hero" then
				if isPro and archetype=="VITAL" then
					s += healScore(heroHp, maxHeroHp)
				elseif difficulty=="noob" and archetype=="VITAL" then
					s += 1
				else
					local df=mostDamagedFriendly(side)~=nil
					s += (heroMiss>0 or df) and (e.value or 2) or -4
				end
			else
				local df=mostDamagedFriendly(side)~=nil
				if isPro and archetype=="VITAL" and (e.area=="all" or e.area=="split") then
					local dmgCount=0; for i=1,3 do local c=side.board[i]; if c and c.hp<c.maxHp then dmgCount+=1 end end
					s += dmgCount>=2 and (3+(e.value or 1)) or (df and (e.value or 2) or -4)
				else
					s += (heroMiss>0 or df) and (e.value or 2) or -4
				end
			end
		elseif act=="buff" then
			local base = anyCreature(side) and ((e.atk or 0)+(e.hp or 0)+1) or -8
			if isPro and archetype=="MIGHTY" and anyCreature(side) then
				base += boardCount(side)>=2 and 2 or 0
			end
			s += base
		elseif act=="draw_card" then
			if isPro and archetype=="SWIFT" then
				local hs=#side.hand
				s += hs<=3 and ((e.value or 1)*2+2) or (hs>=6 and -1 or (e.value or 1)*2)
			else
				s += (#side.hand<8) and ((e.value or 1)*2) or -2
			end
		elseif act=="gain_armor" then
			if isPro and archetype=="MIGHTY" then
				s += heroHp < (maxHeroHp-2) and 4 or -2
			else
				s += (e.value or 0)*0.4
			end
		elseif act=="summon" then s += 3
		elseif act=="bounce" then s += anyCreature(oppSide) and 3 or -4
		elseif act=="grant_keyword" then
			if isPro and archetype=="SWIFT" and e.keyword=="stealth" then
				s += anyCreature(side) and 5 or -5
			else
				s += anyCreature(side) and 2 or -5
			end
		elseif act=="return_from_graveyard" then
			local grave=(#(side.deadAllies or {}))+(#(side.discard or {}))
			if isPro and archetype=="VITAL" then s += grave>0 and 5 or -6
			else s += grave>0 and 3 or -4 end
		elseif act=="reduce_cost" then
			if isPro and archetype=="SWIFT" then s += hasChainInHand and 3 or 1
			else s += 1 end
		elseif act=="gain_energy" then s += 1
		elseif act=="gain_charge" then s += 2
		elseif act=="destroy_charge_slot" then
			local owner=(e.chargeOwner=="enemy") and opp or who
			local occ=0; for _,sl in ipairs(state[owner].chargeSlots or {}) do if sl.battleType then occ+=1 end end
			s += (occ>=2) and 6 or -5
		elseif act=="drain_charge" then
			local has=false; for _,sl in ipairs(state[opp].chargeSlots or {}) do if sl.battleType then has=true;break end end
			s += has and 4 or -3
		elseif act=="disable_shatter" then
			local found=false
			for i=1,3 do
				local ec=state[opp].board[i]
				if ec then for _,eff in ipairs(ec.effects or {}) do if eff.trigger=="shatter" then found=true;break end end end
				if found then break end
			end
			s += found and 5 or -6
		elseif act=="add_additional_charge_cost_to_player_hand" then s += 3
		else s += 1 end

		s += chainBonus
	end

	if isPro and archetype=="VITAL" then
		for _,e in ipairs(card.effects or {}) do if e.lifesteal then s+=2 end end
	end

	return s, opts
end

local function aiAttackNoob(state, who, Logic)
	local opp=Logic.opp(who); local oppSide=state[opp]
	for i=1,3 do
		local a=state[who].board[i]
		if a and not a.attackedThisTurn and not a.summonedThisTurn and atkOf(a)>0 then
			local taunt
			for j=1,3 do local e=oppSide.board[j]; if e and hasKw(e,"taunt") then taunt=j;break end end
			if taunt then Logic.attack(state,who,i,taunt)
			else
				local targets={0}
				for j=1,3 do if oppSide.board[j] then table.insert(targets,j) end end
				Logic.attack(state,who,i,targets[math.random(#targets)])
			end
		end
	end
end

local function aiAttackPro(state, who, Logic, archetype)
	local opp=Logic.opp(who); local oppSide=state[opp]
	for i=1,3 do
		local a=state[who].board[i]
		if a and not a.attackedThisTurn and not a.summonedThisTurn and atkOf(a)>0 then
			local taunt
			for j=1,3 do local e=oppSide.board[j]; if e and hasKw(e,"taunt") then taunt=j;break end end
			if taunt then Logic.attack(state,who,i,taunt); continue end

			local target=0
			-- Swift: quickstrike favors trading into threats that would kill us otherwise
			if archetype=="SWIFT" and hasKw(a,"quickstrike") then
				for j=1,3 do
					local e=oppSide.board[j]
					if e and atkOf(e)>=a.hp and e.hp<=atkOf(a) then target=j;break end
				end
			end
			-- Lethal clean kill (kill without dying)
			if target==0 then
				for j=1,3 do
					local e=oppSide.board[j]
					if e and e.hp<=atkOf(a) and atkOf(e)<a.hp then target=j;break end
				end
			end
			-- Even trade (kill enemy, take damage)
			if target==0 then
				for j=1,3 do
					local e=oppSide.board[j]
					if e and e.hp<=atkOf(a) then target=j;break end
				end
			end
			-- Mighty: prefer attacking dangerous enemy creatures over face
			if target==0 and archetype=="MIGHTY" then
				for j=1,3 do local e=oppSide.board[j]; if e and atkOf(e)>0 then target=j;break end end
			end
			Logic.attack(state,who,i,target)
		end
	end
end

function NpcAI.takeTurn(state, Logic, who, difficulty)
	who        = who or "npc"
	difficulty = difficulty or "noob"
	local opp       = Logic.opp(who)
	local side      = state[who]
	local archetype = detectNpcArchetype(state, who)
	local jitter    = JITTER[difficulty] or JITTER.noob

	-- Swift Pro chain pre-pass: play cheapest non-chain enabler first to unlock chain
	if difficulty=="pro" and archetype=="SWIFT" and (state[who].cardsPlayedThisTurn or 0)==0 then
		if handHasChainCard(side) then
			local enablerId, enablerCost = nil, math.huge
			local seen0={}
			for _,id in ipairs(side.hand) do
				if not seen0[id] then seen0[id]=true
					local c=Cards[id]; if c then
						local isChain=false
						for _,e in ipairs(c.effects or {}) do if e.trigger=="chain" then isChain=true;break end end
						if not isChain and CardCost.canPay(side,id,c) then
							local cost=c.cost or 0
							if cost<enablerCost then enablerCost=cost; enablerId=id end
						end
					end
				end
			end
			if enablerId then
				local ec=Cards[enablerId]; local eopts={}
				if ec.cardType=="creature" then
					eopts.slot=emptySlot(side)
					if eopts.slot then Logic.playCard(state,who,enablerId,eopts) end
				else
					eopts.target=chooseTarget(state,who,opp,ec)
					Logic.playCard(state,who,enablerId,eopts)
				end
			end
		end
	end

	-- Main play loop
	for _=1,40 do
		local best, bestScore, bestOpts
		local seen={}
		for _,cardId in ipairs(side.hand) do
			if not seen[cardId] then seen[cardId]=true
				local card=Cards[cardId]; if card then
					if CardCost.canPay(side,cardId,card) then
						local sc,opts=scoreCard(state,who,opp,card,archetype,difficulty)
						if sc then sc=sc+(math.random()*2-1)*jitter end
						if sc and sc>(bestScore or 0.5) then best,bestScore,bestOpts=cardId,sc,opts end
					end
				end
			end
		end
		if not best then break end
		if not Logic.playCard(state,who,best,bestOpts) then break end
	end

	if difficulty=="noob" then aiAttackNoob(state,who,Logic)
	else aiAttackPro(state,who,Logic,archetype) end
end

return NpcAI
