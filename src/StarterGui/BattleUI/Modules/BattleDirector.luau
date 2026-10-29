-- BattleDirector: single sequencer for battle presentation phases (PLAN_CARD_BATTLE_REVAMP).
-- Owns the one phase queue and the one input-lock gate (Director.isLocked())
-- that TargetingSystem/End Turn/etc. check, replacing the scattered ad-hoc
-- lock flags (handHoverDisabled/boardPreviewLocked) that predate this system.
-- Phase handlers live in PhaseRegistry, keyed by phase.type -- mirrors the
-- server's Effects/Actions registry pattern (one handler per verb/type,
-- no mega-switch).
local PhaseRegistry = require(script.Parent.PhaseRegistry)

local BattleDirector = {}

local DEFAULT_MAX_DURATION = 3.0 -- safety net: force-complete a phase that never calls done()

local queue = {}       -- FIFO list of phase descriptors
local playing = false  -- true while the queue has an active or pending phase
local currentDone = nil
local currentTimeoutThread = nil
local currentPhase = nil

function BattleDirector.isLocked()
	return playing
end

local function cancelPhaseWork(phase)
	if not phase then return end
	phase.cancelled = true
	if phase.onCancel then pcall(phase.onCancel) end
	if phase._trackedTweens then
		for _, tw in ipairs(phase._trackedTweens) do
			pcall(function() tw:Cancel() end)
		end
	end
	if phase._trackedConnections then
		for _, conn in ipairs(phase._trackedConnections) do
			pcall(function() conn:Disconnect() end)
		end
	end
end

local function playNext()
	if #queue == 0 then
		playing = false
		currentDone = nil
		currentPhase = nil
		return
	end
	playing = true
	local phase = table.remove(queue, 1)
	currentPhase = phase
	phase.cancelled = false
	phase._trackedTweens = {}
	phase._trackedConnections = {}
	function phase.trackTween(tw)
		if tw then table.insert(phase._trackedTweens, tw) end
		return tw
	end
	function phase.trackConnection(conn)
		if conn then table.insert(phase._trackedConnections, conn) end
		return conn
	end
	local handler = PhaseRegistry[phase.type]
	local finished = false
	local function done()
		if finished then return end
		finished = true
		cancelPhaseWork(phase)
		if currentTimeoutThread then task.cancel(currentTimeoutThread); currentTimeoutThread = nil end
		if currentPhase == phase then currentPhase = nil end
		playNext()
	end
	currentDone = done
	local maxDuration = phase.maxDuration or DEFAULT_MAX_DURATION
	currentTimeoutThread = task.delay(maxDuration, function()
		currentTimeoutThread = nil
		warn("[BattleDirector] phase '" .. tostring(phase.type) .. "' exceeded " .. maxDuration .. "s, force-completing")
		done()
	end)
	if handler then
		local ok, err = pcall(handler, phase, done)
		if not ok then
			warn("[BattleDirector] phase '" .. tostring(phase.type) .. "' handler errored: " .. tostring(err))
			done()
		end
	else
		warn("[BattleDirector] no PhaseRegistry handler for phase type '" .. tostring(phase.type) .. "'")
		done()
	end
end

-- Enqueue one phase descriptor ({type=..., ...fields the handler needs}).
function BattleDirector.enqueue(phase)
	table.insert(queue, phase)
	if not playing then playNext() end
end

-- Enqueue several phase descriptors, preserving order.
function BattleDirector.enqueueMany(phases)
	for _, p in ipairs(phases) do table.insert(queue, p) end
	if not playing and #queue > 0 then playNext() end
end

-- Fast-forward: cancel the active phase and drop queued phases so no delayed
-- callbacks/tweens from skipped presentation work can mutate UI after input
-- unlocks. The next server render paints the authoritative end-state.
function BattleDirector.skip()
	for _, phase in ipairs(queue) do cancelPhaseWork(phase) end
	queue = {}
	cancelPhaseWork(currentPhase)
	if currentTimeoutThread then task.cancel(currentTimeoutThread); currentTimeoutThread = nil end
	currentDone = nil
	currentPhase = nil
	playing = false
end

return BattleDirector
