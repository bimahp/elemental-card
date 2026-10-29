-- BattleRegistry: owns all live battles keyed by battleId.
-- Enforces the A1 perspective-remap boundary: nothing below BattleController
-- may assume which canonical seat ("player"|"npc") is human or AI.
--
-- Battles[battleId] = {
--   id, tableId, status="active"|"ending",
--   seats = { player=SeatRef, npc=SeatRef },
--   state = <BattleLogic battle>,
--   spectators = { [userId]=true },
-- }
-- SeatRef = { kind="human", player=<Player> }
--         | { kind="npc" }

local BattleRegistry = {}

local Battles      = {}   -- [battleId] = BattleRecord
local PlayerBattle = {}   -- [userId]   = battleId
local nextId       = 0

local function opp(seat) return seat == "player" and "npc" or "player" end

local function densify(board)
	return { board[1] or false, board[2] or false, board[3] or false }
end

-- Flatten both sides' pending ChargeChanged events into one list, relabelling
-- each event's canonical `side` to the recipient's perspective (own -> "player",
-- opponent -> "npc"). Events are shallow-copied so the relabel never mutates state.
local function viewChargeEvents(state, my, enemy)
	local out = {}
	local function add(srcSide, viewSide)
		for _, ev in ipairs(state[srcSide].pendingChargeEvents or {}) do
			local e = {}
			for k, v in pairs(ev) do e[k] = v end
			e.side = viewSide
			out[#out + 1] = e
		end
	end
	add(my, "player")
	add(enemy, "npc")
	return out
end

-- Relabel one canonical side ("player"|"npc") to the recipient's perspective;
-- passes through anything else (e.g. slot=0 for hero, or an already-relabeled value).
local function relabelSide(canonicalSide, my, enemy)
	if canonicalSide == my then return "player"
	elseif canonicalSide == enemy then return "npc"
	else return canonicalSide end
end

-- Flatten the battle's single ordered pendingAnimEvents log into a per-recipient
-- view: relabels `who` and `target.side` from canonical to "player"/"npc" from
-- the recipient's perspective. Read-only -- does not mutate or drain state;
-- BattleController.broadcast clears pendingAnimEvents after every recipient
-- has been sent their view, mirroring viewChargeEvents' lifecycle.
local function viewAnimEvents(state, my, enemy)
	local out = {}
	for _, ev in ipairs(state.pendingAnimEvents or {}) do
		local e = {}
		for k, v in pairs(ev) do e[k] = v end
		if e.who then e.who = relabelSide(e.who, my, enemy) end
		if type(e.target) == "table" then
			e.target = { side = relabelSide(e.target.side, my, enemy), slot = e.target.slot }
		end
		out[#out + 1] = e
	end
	return out
end

-- ── Creation / lookup ────────────────────────────────────────────────────────

function BattleRegistry.create(state, seats, tableId)
	nextId += 1
	local id = "battle_" .. nextId
	local record = {
		id         = id,
		tableId    = tableId or nil,
		seats      = seats,
		state      = state,
		status     = "active",
		spectators = {},
	}
	Battles[id] = record
	for _, ref in pairs(seats) do
		if ref.kind == "human" then
			PlayerBattle[ref.player.UserId] = id
		end
	end
	return record
end

function BattleRegistry.get(battleId)
	return Battles[battleId]
end

function BattleRegistry.getForPlayer(player)
	local id = PlayerBattle[player.UserId]
	return id and Battles[id]
end

-- Returns the canonical seat label ("player"|"npc") for this player.
function BattleRegistry.canonicalSeat(player, battle)
	for label, ref in pairs(battle.seats) do
		if ref.kind == "human" and ref.player == player then
			return label
		end
	end
	return nil
end

-- PLAN_MATCHMAKING Phase 4: like canonicalSeat, but matches by UserId instead
-- of Player-instance identity. Needed for reconnect -- after a disconnect the
-- seat's stored ref.player is a stale/destroyed Player object (Phase 4b
-- deliberately never clears it), so identity comparison would never match
-- the new Player instance a rejoining user gets. UserId is stable across a
-- disconnect/rejoin for the same account.
function BattleRegistry.canonicalSeatByUserId(battle, userId)
	for label, ref in pairs(battle.seats) do
		if ref.kind == "human" and ref.player and ref.player.UserId == userId then
			return label
		end
	end
	return nil
end

-- PLAN_MATCHMAKING Phase 4: swaps a seat's stale Player reference for the
-- Player object a reconnecting user got on rejoin. PlayerBattle[userId] is
-- keyed by UserId already (survives the disconnect unchanged, per Phase 4b),
-- so this only needs to fix up battle.seats[seat].player -- everything else
-- (canonicalSeat's identity check, FireClient targets) depends on that
-- reference being live.
function BattleRegistry.reconnectSeat(battle, seat, newPlayer)
	local ref = battle.seats[seat]
	if not ref or ref.kind ~= "human" then return false end
	ref.player = newPlayer
	PlayerBattle[newPlayer.UserId] = battle.id
	return true
end

-- ── Ingress remap (client perspective → canonical sides) ─────────────────────

-- Remap opts.target.side from the acting player's client-perspective to
-- canonical engine sides. Returns a new table; never mutates opts.
function BattleRegistry.remapOpts(recipientSeat, opts)
	if not opts or recipientSeat == "player" then return opts end
	local out = {}
	for k, v in pairs(opts) do out[k] = v end
	if type(out.target) == "table" and out.target.side then
		out.target = { side = opp(out.target.side), slot = out.target.slot }
	end
	return out
end

-- ── Egress views (canonical state → per-recipient payload) ──────────────────

-- Build the broadcast payload for one recipient.
-- The client always treats itself as "player" and the opponent as "npc".
function BattleRegistry.viewFor(recipientSeat, battle, lastAction)
	local state   = battle.state
	local my      = recipientSeat
	local enemy   = opp(recipientSeat)
	local viewTurn = (state.currentTurn == my) and "player" or "npc"
	local timeoutStreaks = state.timeoutStreaks or {}

	return {
		lastAction = lastAction or "other",
		player = {
			hand                = state[my].hand,
			board               = densify(state[my].board),
			heroHp              = state[my].heroHp,
			maxHeroHp           = state[my].maxHeroHp,
			armor               = state[my].armor,
			energy              = state[my].energy,
			energyCap           = state[my].energyCap,
			fatigue             = state[my].fatigue,
			cardsPlayedThisTurn = state[my].cardsPlayedThisTurn,
			deckCount           = #state[my].deck,
			discardCount        = #state[my].discard,
			lastDiscard         = state[my].discard[#state[my].discard],
			costMods            = state[my].costMods,
			chargeCostMods      = state[my].chargeCostMods,
			chargeSlots         = state[my].chargeSlots,
			currentChargeSlot   = state[my].currentChargeSlot,
			chargeSeq           = state[my].chargeSeq,
		},
		npc = {
			handCount = #state[enemy].hand,
			board     = densify(state[enemy].board),
			heroHp    = state[enemy].heroHp,
			maxHeroHp = state[enemy].maxHeroHp,
			armor     = state[enemy].armor,
			energy    = state[enemy].energy,
			energyCap = state[enemy].energyCap,
			fatigue   = state[enemy].fatigue,
			chargeSlots       = state[enemy].chargeSlots,
			currentChargeSlot = state[enemy].currentChargeSlot,
			chargeSeq         = state[enemy].chargeSeq,
		},
		currentTurn    = viewTurn,
		turnNumber     = state.turnNumber,
		serverNow      = os.clock(),
		turnStartedAt  = state.turnStartedAt,
		turnEndsAt     = state.turnEndsAt,
		turnDuration   = state.turnDuration,
		timeoutStreaks = {
			player = timeoutStreaks[my] or 0,
			npc = timeoutStreaks[enemy] or 0,
		},
		log            = state.log,
		discardHistory = state.discardHistory,
		warnings       = state.warnings or {},
		tauntRedirect  = state.lastTauntRedirect or false,
		chargeEvents   = viewChargeEvents(state, my, enemy),
		animEvents     = viewAnimEvents(state, my, enemy),
	}
end

-- Spectator view: both hands hidden (wired to a remote in Phase 2+).
function BattleRegistry.viewForSpectator(battle)
	local state = battle.state
	return {
		lastAction = "other",
		player = {
			handCount = #state.player.hand, board = densify(state.player.board),
			heroHp = state.player.heroHp,   maxHeroHp = state.player.maxHeroHp,
			armor  = state.player.armor,    energy    = state.player.energy,
			energyCap = state.player.energyCap,
			chargeSlots = state.player.chargeSlots, currentChargeSlot = state.player.currentChargeSlot,
		},
		npc = {
			handCount = #state.npc.hand, board = densify(state.npc.board),
			heroHp = state.npc.heroHp,   maxHeroHp = state.npc.maxHeroHp,
			armor  = state.npc.armor,    energy    = state.npc.energy,
			energyCap = state.npc.energyCap,
			chargeSlots = state.npc.chargeSlots, currentChargeSlot = state.npc.currentChargeSlot,
		},
		currentTurn = state.currentTurn,
		turnNumber  = state.turnNumber,
		serverNow   = os.clock(),
		turnStartedAt = state.turnStartedAt,
		turnEndsAt = state.turnEndsAt,
		turnDuration = state.turnDuration,
		log         = state.log,
		chargeEvents = viewChargeEvents(state, "player", "npc"),
		animEvents   = viewAnimEvents(state, "player", "npc"),
	}
end

-- ── Cleanup ──────────────────────────────────────────────────────────────────

function BattleRegistry.destroy(battle)
	for _, ref in pairs(battle.seats) do
		if ref.kind == "human" then
			PlayerBattle[ref.player.UserId] = nil
		end
	end
	Battles[battle.id] = nil
end

-- Purge the reverse index for a player (safe to call even if already destroyed).
function BattleRegistry.removePlayer(player)
	PlayerBattle[player.UserId] = nil
end

return BattleRegistry
