local SSS   = game:GetService("ServerScriptService")
local Logic = require(SSS.Modules.BattleLogic)
local NpcAI = require(SSS.Modules.NpcAI)

local DuelSession = {}
DuelSession.TURN_TIMEOUT_SECONDS     = 60
DuelSession.MAX_TIMEOUTS_BEFORE_FORFEIT = 2
DuelSession.MULLIGAN_TIMEOUT_SECONDS = 30

local function opp(seat) return seat=="player" and "npc" or "player" end

local function ensureSession(battle)
	battle.session = battle.session or {}
	battle.session.turnToken      = battle.session.turnToken or 0
	battle.session.timeoutStreaks = battle.session.timeoutStreaks or {player=0,npc=0}
	return battle.session
end

local function invalidateTimer(battle)
	local session=ensureSession(battle); session.turnToken+=1
end

local function checkAndEnd(battle, onBattleEnd)
	local winner=Logic.checkWin(battle.state)
	if winner then onBattleEnd(battle,winner); return true end
	return false
end

local startSeatTurn

local function appendWarning(state, msg)
	local w=state.warnings or {}; w[#w+1]=msg; state.warnings=w
end

local function scheduleHumanTimer(battle, seat, onBroadcast, onBattleEnd)
	local session=ensureSession(battle)
	local state=battle.state
	local now=os.clock()
	session.turnToken+=1
	local token=session.turnToken
	state.turnStartedAt=now
	state.turnDuration=DuelSession.TURN_TIMEOUT_SECONDS
	state.turnEndsAt=now+DuelSession.TURN_TIMEOUT_SECONDS
	state.timeoutStreaks=session.timeoutStreaks

	task.delay(DuelSession.TURN_TIMEOUT_SECONDS, function()
		if battle.status~="active" then return end
		if not battle.session or battle.session.turnToken~=token then return end
		if battle.state.currentTurn~=seat then return end
		local streaks=session.timeoutStreaks
		streaks[seat]=(streaks[seat] or 0)+1
		state.timeoutStreaks=streaks
		if streaks[seat]>=DuelSession.MAX_TIMEOUTS_BEFORE_FORFEIT then
			Logic.log(state,seat.." timed out twice and forfeits")
			onBattleEnd(battle,opp(seat),"forfeit"); return -- 2 consecutive AFK timeouts == a forfeit for reward purposes
		end
		Logic.log(state,seat.." timed out; turn auto-ended")
		appendWarning(state,"Turn timed out")
		DuelSession.humanEndTurn(battle,seat,onBroadcast,onBattleEnd,{timeout=true})
	end)
end

local function clearTimerFields(state)
	state.turnStartedAt=nil; state.turnDuration=nil; state.turnEndsAt=nil
end

local function runNpcTurn(battle, npcSeat, onBroadcast, onBattleEnd)
	if battle.status~="active" then return end
	task.wait(0.7)
	if battle.status~="active" or battle.state.currentTurn~=npcSeat then return end
	NpcAI.takeTurn(battle.state, Logic, npcSeat, battle.difficulty or "noob")
	if checkAndEnd(battle,onBattleEnd) then return end
	Logic.endTurn(battle.state,npcSeat)
	-- turn_end effects / board Charge generation can deal lethal damage; re-check.
	if checkAndEnd(battle,onBattleEnd) then return end
	local nextSeat=opp(npcSeat)
	battle.state.currentTurn=nextSeat
	battle.state.turnNumber+=1
	startSeatTurn(battle,nextSeat,onBroadcast,onBattleEnd,"start_turn")
end

startSeatTurn = function(battle, seat, onBroadcast, onBattleEnd, lastAction)
	if battle.status~="active" then return end
	local state=battle.state
	local ref=battle.seats[seat]; if not ref then return end
	state.currentTurn=seat
	Logic.startTurn(state,seat)
	-- The draw step can deal Fatigue damage (or worse, on an already-critical hero);
	-- without this check a hero can sit at lethal HP until the next PlayCard/
	-- DeclareAttack happens to route through afterHumanAction's checkAndEnd.
	if checkAndEnd(battle,onBattleEnd) then return end
	if ref.kind=="human" then scheduleHumanTimer(battle,seat,onBroadcast,onBattleEnd)
	else invalidateTimer(battle); clearTimerFields(state) end
	onBroadcast(battle,lastAction or "start_turn")
	if ref.kind=="npc" then task.spawn(runNpcTurn,battle,seat,onBroadcast,onBattleEnd) end
end

function DuelSession.cancel(battle)
	if battle then invalidateTimer(battle) end
end

-- ── Mulligan (pre-battle stage; PLAN_CARD_BATTLE_REVAMP.md Phase 7) ─────────
-- battle.status is "mulligan" from DuelSession.start until both seats have
-- resolved (confirmed a redraw or timed out), at which point the Coin is
-- granted to the second player and the real turn loop begins via the
-- existing startSeatTurn. Deliberately does NOT call onBroadcast (the normal
-- UpdateBattleState path) during this window -- the client's mulligan UI
-- (Phase 8) is driven by the separate OfferMulligan remote instead, so a
-- half-dealt hand never reaches the regular battle UI.
local function ensureMulligan(battle)
	battle.mulligan = battle.mulligan or { done = {}, redrawn = {}, timeoutToken = 0 }
	return battle.mulligan
end

-- Grants the Coin to the second player (never a redraw candidate, since it
-- doesn't exist in anyone's hand until this point) and starts the real turn
-- loop. Called once both seats have resolved their mulligan.
local function beginRealBattle(battle, onBroadcast, onBattleEnd)
	local state = battle.state
	local mull = battle.mulligan
	battle.status = "active"
	-- Dealing the opening hands and any mulligan redraw produced draw_card
	-- anim events that were never broadcast (mulligan never calls
	-- onBroadcast) -- drop them here so the real battle's first broadcast
	-- only contains genuinely-live events, not a burst of already-rendered
	-- pre-battle draws replaying as a fake Draw animation.
	state.pendingAnimEvents = {}
	table.insert(state[mull.secondSeat].hand, "the_coin")
	Logic.log(state, "Coin flip: "..mull.firstSeat.." goes first!")
	startSeatTurn(battle, mull.firstSeat, onBroadcast, onBattleEnd, "start_turn")
end

-- Marks a seat's mulligan resolved (via ConfirmMulligan or timeout); begins
-- the real battle once both seats are done. Idempotent.
local function resolveMulliganSeat(battle, seat, onBroadcast, onBattleEnd)
	local mull = battle.mulligan
	if not mull or mull.done[seat] then return end
	mull.done[seat] = true
	if mull.done.player and mull.done.npc then
		beginRealBattle(battle, onBroadcast, onBattleEnd)
	end
end

-- Auto-keeps the dealt hand if a human seat never responds, so an AFK/
-- disconnected player can't stall the match -- same anti-stall philosophy as
-- the existing PvP anti-rage-quit flag (see SaveService.beginPvpMatch).
local function scheduleMulliganTimeout(battle, seat, onBroadcast, onBattleEnd)
	local mull = ensureMulligan(battle)
	mull.timeoutTokens = mull.timeoutTokens or {}
	mull.timeoutTokens[seat] = (mull.timeoutTokens[seat] or 0) + 1
	local token = mull.timeoutTokens[seat]
	task.delay(DuelSession.MULLIGAN_TIMEOUT_SECONDS, function()
		if battle.status ~= "mulligan" then return end
		if not mull.timeoutTokens or mull.timeoutTokens[seat] ~= token then return end
		if mull.done[seat] then return end
		Logic.log(battle.state, seat.." didn't respond to mulligan in time; keeping dealt hand")
		resolveMulliganSeat(battle, seat, onBroadcast, onBattleEnd)
	end)
end

-- PLAN_MATCHMAKING Phase 4a: onMatchStart (optional) fires once, right after
-- battle.status flips to "mulligan" -- this is the reconnect-eligible point
-- ("once seated and mulligan begins, the battle counts as valid"), not
-- Registry.create time. BattleController uses it to persist activeMatch/jobId.
function DuelSession.start(battle, onBroadcast, onBattleEnd, onMulliganOffer, onMatchStart)
	local state=battle.state
	ensureSession(battle)
	battle.status = "mulligan"
	if onMatchStart then onMatchStart(battle) end
	Logic.shuffle(state.player.deck)
	Logic.shuffle(state.npc.deck)
	for _=1,5 do Logic.drawCard(state,"player"); Logic.drawCard(state,"npc") end
	local firstSeat =(math.random(2)==1) and "player" or "npc"
	local secondSeat=opp(firstSeat)
	local mull = ensureMulligan(battle)
	mull.firstSeat, mull.secondSeat = firstSeat, secondSeat

	for _, seat in ipairs({"player","npc"}) do
		local ref = battle.seats[seat]
		if ref and ref.kind == "human" then
			if onMulliganOffer then onMulliganOffer(battle, seat, state[seat].hand) end
			scheduleMulliganTimeout(battle, seat, onBroadcast, onBattleEnd)
		else
			-- NPC seat: auto-resolves instantly, keeps its dealt hand (no redraw heuristic yet).
			resolveMulliganSeat(battle, seat, onBroadcast, onBattleEnd)
		end
	end
end

-- Human player redraws exactly one card from their dealt hand, in real time
-- (not deferred to confirmMulligan/Battle) -- the client shows the real new
-- card immediately rather than just marking the old one. Swaps the hand slot
-- in place (the drawn card lands back at the same index) so the client can
-- replace that specific tile without reshuffling the row. Deliberately
-- bypasses Ops.drawCard/recordAnim -- this is pre-battle hand setup, not a
-- live gameplay draw, and must not leave a stray draw_card event sitting in
-- pendingAnimEvents for the real battle's first broadcast to misplay. At
-- most one redraw per seat per mulligan, enforced here regardless of how
-- many times this is invoked.
function DuelSession.redrawMulliganCard(battle, seat, idx)
	if battle.status ~= "mulligan" then return false, "Not in mulligan" end
	local mull = ensureMulligan(battle)
	if mull.done[seat] then return false, "Already resolved" end
	if mull.redrawn[seat] then return false, "Already redrawn" end
	local state = battle.state
	local side = state[seat]
	idx = tonumber(idx)
	if not (idx and idx % 1 == 0 and idx >= 1 and idx <= #side.hand) then
		return false, "Invalid card"
	end
	if #side.deck == 0 then return false, "Deck is empty" end
	mull.redrawn[seat] = true
	local oldCardId = table.remove(side.hand, idx)
	table.insert(side.deck, oldCardId)
	Logic.shuffle(side.deck)
	local newCardId = table.remove(side.deck, 1)
	table.insert(side.hand, idx, newCardId)
	Logic.log(state, seat.." redraws a card")
	return true, newCardId
end

-- Human player finalizes their mulligan (taps Battle). Any redraw already
-- happened via DuelSession.redrawMulliganCard; this just locks the seat in.
function DuelSession.confirmMulligan(battle, seat, onBroadcast, onBattleEnd)
	if battle.status ~= "mulligan" then return false, "Not in mulligan" end
	local mull = ensureMulligan(battle)
	if mull.done[seat] then return false, "Already resolved" end
	resolveMulliganSeat(battle, seat, onBroadcast, onBattleEnd)
	return true
end

function DuelSession.afterHumanAction(battle, lastAction, onBroadcast, onBattleEnd)
	if checkAndEnd(battle,onBattleEnd) then return false end
	local session=ensureSession(battle)
	local seat=battle.state.currentTurn
	if battle.seats[seat] and battle.seats[seat].kind=="human" then
		session.timeoutStreaks[seat]=0
		battle.state.timeoutStreaks=session.timeoutStreaks
	end
	onBroadcast(battle,lastAction or "other")
	return true
end

function DuelSession.humanEndTurn(battle, humanSeat, onBroadcast, onBattleEnd, opts)
	if battle.status~="active" then return end
	local state=battle.state
	if state.currentTurn~=humanSeat then return end
	local session=ensureSession(battle)
	local nextSeat=opp(humanSeat)
	local nextRef=battle.seats[nextSeat]; if not nextRef then return end
	invalidateTimer(battle)
	if not (opts and opts.timeout) then
		session.timeoutStreaks[humanSeat]=0
		state.timeoutStreaks=session.timeoutStreaks
	end
	Logic.endTurn(state,humanSeat)
	-- turn_end effects / board Charge generation can deal lethal damage; re-check.
	if checkAndEnd(battle,onBattleEnd) then return end
	state.currentTurn=nextSeat
	state.turnNumber+=1
	onBroadcast(battle,(opts and opts.timeout) and "timeout" or "end_turn")
	startSeatTurn(battle,nextSeat,onBroadcast,onBattleEnd,"start_turn")
end

return DuelSession
