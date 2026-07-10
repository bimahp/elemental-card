# PLAN_CARD_BATTLE_REVAMP — Battle Presentation Director + Full Mulligan

> Status: **complete** | Author: bimahp (with Claude) | Date: 2026-07-07 (implemented 2026-07-08, post-review fixes 2026-07-09)
>
> This plan is kept up to date through implementation — each phase's checklist
> line and Tests/Result are updated as it completes, mirroring how
> `PLAN_BATTLE_CHARGE.md`/`PLAN_BATTLE_CHARGE_V2.md` track their own rollout.

## Implementation Status

- [x] **Phase 0** — Baseline safety harness
- [x] **Phase 1** — Server: event log foundation (`Ops.recordAnim`)
- [x] **Phase 2** — Server: envelope events + broadcast wiring
- [x] **Phase 3** — Client: `BattleDirector` + `PhaseRegistry` skeleton
- [x] **Phase 4** — Client: port Draw/Play/Attack animations into the Director; delete diff heuristics
- [x] **Phase 5** — Client: turn-start banner phase
- [x] **Phase 6** — Client: cast-reveal + first VFX archetype (projectile)
- [x] **Phase 7** — Server: mulligan pre-battle stage
- [x] **Phase 8** — Client: mulligan UI
- [x] **Phase 9** — Regression pass + docs reconciliation

## Post-Review Fix Pass (2026-07-09)

Codex review found four implementation defects after the initial rollout. All
four were patched in live Studio on 2026-07-09:

1. **PvP mulligan timeout stall fixed.** `DuelSession.scheduleMulliganTimeout`
   now tracks timeout tokens per seat (`mull.timeoutTokens[seat]`) so scheduling
   the second human seat no longer invalidates the first seat's timer. Intended
   behavior remains: both players see mulligan simultaneously and unresolved
   seats auto-keep at timeout.
2. **Ordered `animEvents` replay fixed.** `BattleUIController.render()` now
   stages draw/play/cast/effect/attack work and queues phases from the full
   `state.animEvents` list in server order instead of independent one-off scans
   that break after the first attack or first local-player cast. NPC-turn
   batches can now enqueue later attacks/casts before the next turn banner.
3. **Skip/fast-forward cancellation fixed.** `BattleDirector` now gives phases
   cancellable context (`phase.cancelled`, tracked tweens/connections) and
   `skip()` clears queued work, cancels the active phase's tracked work, and
   unlocks input without starting queued phase handlers.
4. **`cast_reveal` restoration fixed.** `PhaseRegistry.cast_reveal` now
   saves/restores `Size` and `ZIndex` in addition to parent, anchor, position,
   and rotation, and uses cancellation-aware delayed callbacks/tween tracking.

### Draw/status polish follow-up (2026-07-09)

- **Draw visibility fixed:** `BattleUIController` now hides pending draw frames
  until `PhaseRegistry.draw` starts, preventing the "card appears instantly,
  then animates afterward as a duplicate" artifact on turn draws.
- **Initial hand reveal added:** the first active battle render after mulligan
  treats the current hand as a draw reveal, so pressing Battle no longer pops the
  starting hand into place with no animation.
- **Skip safety tightened:** queued draw phases expose hidden frames via
  `onCancel` when `BattleDirector.skip()` drops queued work before the draw
  phase starts.
- **Board status visuals clarified:** Stealth uses a cloud/fog icon, Taunt keeps
  its shield icon, and full-card dark dimming is reserved for sleeping/exhausted
  cards only.
- **Mulligan presentation ordering fixed:** `OfferMulligan` now makes
  `BattleUIController` enter the seated battle camera/lock state first, while
  `MulliganController` waits a short settle beat before showing First Draw. This
  prevents the mulligan dialog from appearing over the free-roam camera before
  the player visually sits/faces the opponent.
- **Stealth icon placement tuned:** the cloud/fog marker is centered over the
  artwork and enlarged so it reads like Taunt's shield marker instead of sitting
  small/off-center.

---

## Context

The battle screen's animation logic is currently a set of bespoke, hand-tuned
special cases bolted onto `BattleUIController.render()`: a hand-diff heuristic
for the Draw animation, a hand-diff heuristic for the Play animation, and a
board-diff heuristic (`detectCombatEvent`) for the one Attack animation —
explicitly gated to `state.lastAction=="attack"` because it can only recover
**one** attacker + one damaged target from a before/after snapshot. None of
this can express "this creature took damage because of *this* card's *this*
effect" — diffing only sees net HP deltas, so it can never distinguish a
`damage` action from a `heal` action from a `buff`, and it silently breaks on
any turn with more than one animatable event (an AOE hitting three creatures,
a spell plus a triggered ally-death heal, etc.).

The goal is real turn structure — a mulligan, "YOUR TURN"/"ENEMY TURN"
banners, a zoom-and-reveal beat when a spell is cast, and per-effect-type VFX
(fireball for a projectile, claw swipe for an AOE) — with the battle UI locked
to input while these play. Layering a nicer sequencer on top of the current
diffing would just relocate today's "one detectable event per turn" ceiling
into a fancier wrapper. The actual fix is architectural: the server emits an
**explicit ordered event log** per broadcast (what fired, on what, in what
order) instead of the client reverse-engineering intent from final state, and
the client gets a **single sequencer ("Director")** plus a **registry of
phase handlers keyed by event type** — mirroring the pattern the server
already uses for rules (`Effects/Actions` is a registry keyed by action verb)
and that the codebase *already proves works* for one resource: Charge.
`ChargeState.pendingChargeEvents` / `BattleRegistry.viewChargeEvents` /
`BattleController.broadcast`'s post-send clear is exactly this pattern,
already shipped and working for Charge-socket pop animations. This plan
generalizes that exact pattern to all actions, rather than inventing
something new.

**Decisions locked in:**
- Build the Director/event-log/phase-registry architecture, proven end-to-end
  with a turn-banner phase, the (ported) draw animation, and one cast-reveal
  archetype (single-target damage → projectile).
- Server-side event log: approved.
- Card VFX selection: default archetype inferred from the effect's
  `action`/`target`/`area`, with an optional per-card override — mechanism
  only in this plan; no cards need to author an override yet.
- **Mulligan is implemented fully in this plan, not stubbed** — a stub-now/
  rebuild-later mulligan would mean touching `DuelSession.start`'s pre-battle
  sequencing twice; doing it once is the better trade, even though it
  roughly doubles this plan's size (a new server pre-battle state machine,
  two new remotes, a new UI, PvP synchronization, and a timeout, on top of
  the Director/event-log work). PvP mulligan is synchronized/simultaneous.
- The only thing still explicitly deferred past this plan is the **broad VFX
  library** (archetypes beyond the one proof-of-concept, per-card overrides,
  sound) — see "Out of Scope" at the end.

A verified, non-obvious finding that shapes scope: **an NPC's entire turn
(every card play, every attack) currently produces exactly one client
broadcast**, sent only after `Logic.endTurn` finishes and the next seat's
turn has already started (`DuelSession.runNpcTurn` never calls `onBroadcast`
mid-turn; only `startSeatTurn` does, once, at the very end). Because the
event log accumulates every event that happened during that whole NPC turn
before the single broadcast fires, the Director can still replay the NPC's
entire turn as a full beat-by-beat sequence — it just all arrives and plays
back in one burst after the ~0.7s "thinking" delay, rather than animating in
real time as the NPC decides. That's an acceptable v1 trade-off (flagged in
"Out of Scope," not silently dropped), and it means this plan does **not**
need to restructure `NpcAI.takeTurn`'s broadcast cadence.

---

## Architecture

```
Server (authoritative)                    Client (presentation)
─────────────────────                    ─────────────────────
Effects/Ops.lua                          BattleUIController.render(state)
  Ops.recordAnim(state, ev)  ──┐            └─ translateEventsToPhases(state.animEvents)
  (damage/heal/buff/summon/    │                 └─ Director.enqueue(phase...)
   bounce/kill/draw/armor)     │
                               │           BattleDirector.lua
BattleLogic.lua                │             - FIFO phase queue
  envelope events at           │             - isLocked() gate (single source of truth)
  playCard / attack /          ├──state.    - skip/fast-forward
  startTurn                    │  pendingAnimEvents
                               │
DuelSession.lua (new)          │           PhaseRegistry.lua (keyed by phase.type,
  pre-battle "mulligan" stage  │             mirrors server's Actions[action] registry)
  before the existing turn loop│              turn_banner / draw / mulligan (real UI) /
                               │              cast_reveal / effect (sub-keyed by action
BattleRegistry.viewFor         │              verb → visual archetype) / attack
  viewAnimEvents(state,my,enemy)◄─relabel
  → state.animEvents           │           EffectVisuals.lua
                               │             resolveVisualArchetype(entry, card)
BattleController.broadcast     ▼             default-from-schema + optional override
  clears pendingAnimEvents
  after send (like Charge)
```

Each server mutation that should be animatable records a lightweight event
(action verb, source, targets, value) onto `battle.state.pendingAnimEvents` —
one flat ordered list on the battle, not per-side, because ordering across
sides matters (a card resolves, damages an enemy, triggers a death, which
triggers an ally-death heal — all in one causal sequence). `BattleLogic.playCard`
and `BattleLogic.attack` additionally push an **envelope event** at the start
(`{type="cast", cardId, who, ...}` / `{type="attack", attackerSlot, who}`) so
the client knows "a new sequence is starting, zoom this card" before the
detail sub-events arrive tagged with the same envelope's sequence number.

`BattleRegistry.viewAnimEvents` relabels each event's `side`/target `side`
fields from canonical to the recipient's perspective, exactly like
`viewChargeEvents` already does. `BattleController.broadcast` clears
`pendingAnimEvents` after sending, exactly like it already clears
`pendingChargeEvents`.

On the client, `render()` stops doing heuristic diffing entirely. It keeps
its existing job of painting authoritative state, and separately walks
`state.animEvents` into an ordered list of phase descriptors, enqueued on
`BattleDirector`. The Director plays phases strictly in order and is the
**one** place that gates input (`Director.isLocked()`), replacing today's
scattered `handHoverDisabled`/`boardPreviewLocked` flags.

Mulligan is a genuine new pre-battle stage in the turn-loop state machine
(`battle.status = "mulligan"`, held before the existing `"active"` loop
begins), not merely a client-side phase.

---

## Phase 0 — Baseline Safety Harness

**Goal:** Establish a clean reference point before touching the animation
pipeline and the pre-battle turn-loop entry point.

**Steps:**
- Record current behavior: card draw fly-in, card play fly-in, attack Card
  Lunge, End Turn/Forfeit availability, in one PvE and one PvP smoke run.
- Confirm current headless specs / schema validation pass before any change.
- Confirm no uncommitted Studio changes get clobbered.

**Tests:** Studio Play smoke (both animations look/feel as documented in
`DESIGN_UI.md` today) + existing `TestService` specs pass.
**Result (2026-07-07):** All 3 `TestService` specs pass headless
(`GachaAcquisitionSpec`, `ShopTransactionSpec`, `GachaOddsSpec`). Card/Deck
schema validates clean at 133 total cards (`CardSchema.validate`/
`validateDecks`, no errors). Headless engine smoke with the real starter
decks (`Decks.mighty.cards`/`Decks.swift.cards`, shuffled): drawing 5 cards
leaves 25 in the player's deck with no Fatigue; `startTurn` for the NPC seat
draws cleanly (29 left, no errors); a drawn pure-Charge creature
(`rubyhide`) is correctly rejected by `playCard` with "Not enough Charge"
when the player has 0 Charge, confirming cost validation is intact before
any Phase 1 changes. Existing Draw/Play/Attack animation behavior (fly-in
tweens, Card Lunge timings) is documented from this session's earlier full
read of `BattleUIController`/`CardVisuals`/`TargetingSystem` and serves as
the "before" reference for Phase 4's parity check.

---

## Phase 1 — Server: Event Log Foundation

**Goal:** Add the generic animatable-event channel, independent of anything
that consumes it yet.

**Steps:**
- `ServerScriptService/Modules/Effects/Ops.lua` — add `Ops.recordAnim(state, ev)`
  mirroring `ChargeState.recordEvent`: stamps a monotonic `state.animSeq`,
  pushes to `state.pendingAnimEvents`.
- Call it from `damageHero`, `damageCreature`, `healHero`/`healCreature`,
  `buffCreature`, `killCreature` (death/rebirth), `drawCard`, `gainArmor`,
  `summon`, `bounce`, `returnFromGraveyard`. Charge mutations keep their
  existing separate `pendingChargeEvents` channel unchanged.
- `BattleLogic.newSide`/`newBattle` initialize `pendingAnimEvents = {}` and
  `animSeq = 0` on the battle state.

**Tests (headless via `execute_luau`, Edit mode):** damage/heal/buff/summon/
bounce/kill/draw/gain_armor each produce exactly one well-shaped event with a
strictly increasing `seq`; a no-op mutation (0 damage, full-HP heal) produces
no event or a clearly no-op-tagged event (decide and assert consistently).
**Result (2026-07-07):** Implemented `Ops.recordAnim` and wired it into
`damageHero`, `damageCreature`, `healHero`, `healCreature`, `gainArmor`,
`buffCreature`, `killCreature` (both the `death` and `rebirth` branches),
`drawCard` (success path only — the Fatigue path already gets a `damage`
event from `damageHero`, no separate `draw_card` event), `bounce`, `summon`,
and `returnFromGraveyard`. `BattleLogic.newBattle` now inits
`pendingAnimEvents = {}` / `animSeq = 0`.

Verified headless (`execute_luau`, Edit mode — required cloning `BattleLogic`
and `Ops` and temporarily swapping the clone into `Ops`'s slot, since this
session's `require()` cache still held the pre-edit modules from Phase 0's
baseline smoke; DataModel confirmed clean afterward, no leftover clones):
- `newBattle` initializes an empty `pendingAnimEvents` and `animSeq = 0`.
- A 2-damage hit on a healthy (20 HP) creature produces exactly one
  correctly-shaped `damage` event (`action/amount/target.side/target.slot/
  cardId`), with `seq` matching `state.animSeq`.
- A 0-damage hit produces no event (no-op guard confirmed).
- `gainArmor`, `buffCreature`, `healCreature`, `bounce`, `summon`, a
  successful `drawCard` each produce exactly one event.
- Lethal damage produces events in the correct causal order: `[damage,
  death]`.
- Lethal damage on a Rebirth creature produces `[damage, rebirth]` (no
  `death`), and the creature stays on board at full HP afterward.
- Drawing from an empty deck (Fatigue) produces exactly one `damage` event
  and no `draw_card` event.
- `seq` is strictly increasing across a 7-event mixed sequence.

---

## Phase 2 — Server: Envelope Events + Broadcast Wiring

**Goal:** Give the client a "new sequence started" signal and get the log
onto the wire, perspective-correct.

**Steps:**
- `BattleLogic.playCard` — push a cast envelope at the top (`cardId`, `who`,
  chosen target/zone) before resolving.
- `BattleLogic.attack` — push an attack envelope (`attackerSlot`, `who`).
- `BattleLogic.startTurn` — push a turn-start envelope (drives the banner).
- `BattleRegistry.lua` — add `viewAnimEvents(state, my, enemy)` alongside the
  existing `viewChargeEvents`; include as `animEvents` in `viewFor`'s return.
- `BattleController.lua` — `broadcast()` clears `battle.state.pendingAnimEvents`
  after sending, same spot that already clears `pendingChargeEvents`.

**Tests (headless):** play a single-target damage spell and assert
`pendingAnimEvents` contains the expected ordered shape (cast envelope, then
a `damage` event with correct source/target); attack and assert an attack
envelope plus damage events on both sides; start a turn and assert a
turn-start envelope; assert `viewAnimEvents` relabels `side` fields correctly
per recipient; assert `pendingAnimEvents` is empty immediately after a
broadcast.
**Result (2026-07-07):** Envelope events added: `startTurn` pushes
`turn_start` (who, turnNumber) before any mutation; `playCard` pushes `cast`
(who, cardId, cardType, target/zone) before spending resources, and for
creatures a `summon` detail event right after board placement (playing a
creature from hand didn't go through `Ops.summon`, so this was added
separately to keep the event vocabulary consistent); `attack` pushes an
`attack` envelope (who, attackerSlot, target) right after the attacker is
marked as having attacked, before any damage resolves. `BattleRegistry` gets
a private `viewAnimEvents(state, my, enemy)` (mirrors `viewChargeEvents`,
relabels `who`/`target.side` from canonical to the recipient's perspective),
wired into both `viewFor` and `viewForSpectator` as `animEvents`.
`BattleController.broadcast` clears `state.pendingAnimEvents` after sending,
in the same spot it already clears the Charge events.

Verified headless (`execute_luau`, Edit mode, same clone/restore technique as
Phase 1 — `BattleLogic`, `Ops`, and `BattleRegistry` clones, DataModel
confirmed clean afterward):
- `startTurn` on a fresh side produces `[turn_start, draw_card]`, in that
  order, with correct `who`/`turnNumber` on the envelope.
- Playing a creature card produces `[cast, summon, ...]`, in that order.
- A successful attack's first new event is a correctly-shaped `attack`
  envelope (`who`, `attackerSlot`, `target.side`, `target.slot`).
- `BattleRegistry.viewFor("npc", ...).animEvents` correctly relabels a
  canonical-`player` `who` to that recipient's own `"npc"`, and a
  canonical-`npc` `target.side` to that recipient's own `"player"`.
- `viewFor("player", ...)` (the acting side's own view) keeps canonical
  labels as-is (identity case).
- Both recipients' views contain the same event count as the underlying log
  — `viewAnimEvents` never drops or duplicates events, only relabels.

---

## Phase 3 — Client: `BattleDirector` + `PhaseRegistry` Skeleton

**Goal:** Build the sequencer and registry with no real phases wired yet.

**Steps:**
- New `StarterGui/BattleUI/Modules/BattleDirector.lua` — FIFO phase queue,
  `isLocked()`, `enqueue`/`enqueueMany`, per-phase max-duration timeout
  (safety net so a buggy handler can't hang the queue forever), skip/
  fast-forward input that collapses remaining queued phases to their
  instant end-state.
- New `StarterGui/BattleUI/Modules/PhaseRegistry.lua` — empty handler table
  keyed by phase type, to be filled in by later phases.
- Wire `Director.isLocked()` into `TargetingSystem.beginDrag`/
  `beginAttackDrag` and the End Turn button (early-return when locked) —
  this replaces `handHoverDisabled`/`boardPreviewLocked` as the single gate.

**Tests:** Studio Play manual smoke — enqueue a fake 2-second phase and
confirm hand drag/attack drag/End Turn are all blocked for exactly that
window and unblocked immediately after; confirm skip collapses it instantly.
**Result (2026-07-07):** Built `BattleDirector.lua` (FIFO queue, `isLocked()`,
`enqueue`/`enqueueMany`, per-phase `maxDuration` safety-net timeout via
`task.delay` + `pcall`-wrapped handler dispatch, `skip()` that force-completes
the active phase and drains the rest back-to-back) and an empty
`PhaseRegistry.lua` handler table. Wired `BattleDirector.isLocked()` into
`TargetingSystem.beginDrag`/`beginAttackDrag` (both early-return when locked)
and both the desktop and mobile End Turn button handlers.

Verified headless (`execute_luau`, Edit mode — these are pure client-logic
modules with no `Player`/`PlayerGui` dependency at load time, so no clone
trick was needed, just a direct fresh `require`; confirmed `PhaseRegistry` was
left empty afterward, no test-only keys leaked): starts unlocked; a single
async fake phase locks immediately and only unlocks after its own completion;
a two-phase queue runs the first phase and leaves the second queued behind
it; `skip()` force-completes both back-to-back and unlocks immediately; an
unknown phase type warns and auto-completes instead of hanging the queue; a
handler that never calls `done()` gets force-completed by the `maxDuration`
timeout safety net. All 13 assertions passed.

Since nothing in the real game yet calls `Director.enqueue` (that starts in
Phase 4), a live interactive "dragging is actually blocked mid-battle" check
isn't meaningful yet — deferred to Phase 4's Studio Play test, once
`render()` is actually enqueuing real phases.

---

## Phase 4 — Client: Port Draw/Play/Attack Into the Director

**Goal:** Retire the diff-heuristic animation code entirely — one pipeline,
not two running in parallel.

**Steps:**
- Relocate the Draw fly-in tween body into `PhaseRegistry.draw`.
- Relocate the Play fly-in tween body into `PhaseRegistry.cast_reveal` (or a
  `play` phase, reused by `cast_reveal` in Phase 6).
- Relocate `playCardLunge` into `PhaseRegistry.attack`.
- `BattleUIController.render()` — delete `detectCombatEvent`,
  `findAttackerSlot`, `findDamagedTarget`, `snapshotState`, `snapBoard`;
  translate `state.animEvents` into a phase list and call
  `Director.enqueueMany` instead.
- Mobile parity: phase handlers resolve board/hero frames through the same
  desktop/mobile frame-set switch `TargetingSystem.applyTargetingMode`
  already uses — no hardcoded desktop-only frames.

**Tests:** Studio Play — Draw animation looks identical to the Phase 0
baseline; Play animation (creature summon / spell to grave) looks identical;
Attack Card Lunge looks identical, now driven by the event log (confirm the
deleted diff functions are actually gone, not just unused); multi-kill AOE
(if any current card qualifies) now animates each affected target instead of
only the first diff-detected one — this is the concrete proof the rewrite
was worth it. Mobile smoke for all three.
**Result (2026-07-07):** This was the largest and riskiest phase — a full
restructure of `BattleUIController`'s animation pipeline. Deleted
`detectCombatEvent`/`findAttackerSlot`/`findDamagedTarget`/`snapshotState`/
`snapBoard` and moved `popDamage`/`popTaunted`/`impactPunch`/`playCardLunge`
into `PhaseRegistry` (`attack`, `play`, `draw` handlers, each now taking
`(phase, done)` and calling `done()` on completion — `attack`'s completion
point is a new unconditional `task.delay(windup+lunge+impact+ret, done)`,
since the old function had no overall completion signal). Added
`activeFrames()` to `BattleUIController` (desktop vs mobile board/hero frame
resolution, mirroring `TargetingSystem.applyTargetingMode`) and rewired:
- Combat-event detection now walks `state.animEvents` for an `attack`
  envelope and pattern-matches BattleLogic.attack's fixed event order
  (defender damage[+death], then attacker retaliation damage[+death]) instead
  of diffing board snapshots — and is driven directly by the event's
  presence, so (unlike the old `state.lastAction=="attack"` gate) it can't
  misfire.
- Play-animation setup now finds the played card via the broadcast's `cast`
  event's `cardId` instead of a multiset diff against `prevHandIds`.
- Draw animation now counts `draw_card` events (mine) and takes the last N
  hand/`hCards` entries (drawn cards are always appended server-side), instead
  of diffing `prevHandIds`.
- Hero HP/Armor/Charge update functions (`updateNpcHero`/`updatePlayerHero`)
  now update both desktop and mobile hero cells together, gated by a single
  mode-aware deferred-vs-immediate decision (`frames.eHero`/`frames.pHero`) —
  previously the mobile hero cells updated unconditionally immediately,
  regardless of whether they were the live combat target, so a mobile
  hero-target lunge never actually deferred its HP update. Board-fill loops
  gained the same active-frame exclusion check for mobile that desktop
  already had (previously mobile board slots always painted instantly,
  never animated, regardless of the active attacker/target/play-destination).

Verified in a **live Play session** (not just headless) via a technique that
sidesteps this environment's unreliable `ProximityPrompt` input simulation:
fired synthetic `UpdateBattleState` payloads directly from the server to the
client with realistic `animEvents`, exercising the real `render()` code path
without needing a full battle to be running.
- First synthetic push (an attack + death): zero console errors; the target
  slot correctly showed the post-impact data once the deferred update fired.
- Second synthetic push (a spell cast + kill + card draw, in one broadcast,
  with self-consistent final board/hand state): zero errors;
  `BattleDirector.isLocked()` correctly went back to `false` after both queued
  phases (draw then play) finished; the enemy board slot was correctly empty
  in **both** the desktop and the (actually visible) mobile board frames;
  hand card count matched exactly (cast card removed, drawn card added); the
  Grave panel's big card correctly showed the played spell's name ("Sudden
  Death") — confirming the `play` phase's `onLand` callback fired.
- Confirmed this session's `UXMode.Current == "Mobile"` and
  `mobileRoot.Visible == true`, and that the mobile enemy board slots
  reflected the correct final state — closing the loop on the mobile-parity
  fix specifically (previously mobile boards were never animated and never
  frame-matched against the active combat target/play destination).
- `[UXMode] initial mode: Mobile` printing on script boot (deep in
  `BattleUIController`'s top-level code) was itself confirmation the edited
  script parsed and initialized without a syntax error before any interactive
  testing began.

---

## Phase 5 — Client: Turn-Start Banner

**Goal:** First genuinely new phase, proving the registry is easy to extend.

**Steps:**
- `PhaseRegistry.turn_banner` — "YOUR TURN"/"ENEMY TURN" banner (pure UI per
  `DESIGN_UI.md` panel conventions, no new image assets), locks input for its
  duration, then completes.
- Enqueued from the turn-start envelope added in Phase 2.

**Tests:** Studio Play — banner shows at the start of both my turn and the
NPC's turn, input stays locked for its duration, unlocks immediately after.
**Result (2026-07-07):** Added `PhaseRegistry.turn_banner` (fade+scale in,
0.15s / hold 0.6s / fade out 0.15s, `Back`/`Quad` easing) and a persistent
`TurnBannerLabel` created once in `BattleUIController` (before `render`'s
definition, since it's captured as an upvalue) so the handler stays a pure
tween executor with no GUI-hierarchy knowledge, matching the Phase 4
handlers. Wired the enqueue at the very top of `render()`, before the Draw
phase, so a turn-start broadcast (which always also draws a card) shows the
banner first.

Verified in a live Play session with synthetic `turn_start` pushes (same
technique as Phase 4): zero console errors for both `who="player"` ("YOUR
TURN") and `who="npc"` ("ENEMY TURN") variants; both correctly set the
label's text; `BattleDirector.isLocked()` was back to `false` and the label
correctly reset to `Visible=false`/`BackgroundTransparency=1` after each
sequence completed (the round-trip between tool calls in this environment
consistently exceeded the ~0.9s banner duration, so the "locked mid-animation"
snapshot wasn't caught directly — Phase 3's synthetic fake-phase tests already
cover that general locking mechanism; what mattered here was the new
tween/handler code itself completing cleanly, which it did both times).

---

## Phase 6 — Client: Cast-Reveal + First VFX Archetype (Projectile)

**Goal:** Prove the per-effect-verb visual archetype system end-to-end with
one real example, per the "default + override" decision.

**Steps:**
- New `StarterGui/BattleUI/Modules/EffectVisuals.lua` —
  `resolveVisualArchetype(effectEntry, card)`: default mapping from
  `(action, target, area)` → archetype; checks an optional `card.vfx`
  override first if present (unused this pass, mechanism only).
- `PhaseRegistry.cast_reveal` — card zooms center-screen briefly (reusing
  `CardVisuals.buildCardFrame` at a larger scale) before the effect plays.
- `PhaseRegistry.effect` — sub-dispatches on the event's action verb;
  implement only `"projectile"` (single-target `damage`) for real this pass —
  a traveling particle/image from caster to target, then existing
  `impactPunch`/`popDamage` feedback (already built, reused as-is).

**Tests:** Studio Play — casting a single-target damage spell shows
zoom → projectile travel → impact, with input locked until it resolves and
unlocked immediately after.
**Result (2026-07-07):** New `EffectVisuals.resolveVisualArchetype(entry,
card)` (default-from-action table, `card.vfx` override checked first,
mechanism only — no card uses it yet). New `PhaseRegistry.cast_reveal` (zoom
the hand-card frame to 1.8x center-screen, hold, shrink back, then restores
its exact original anchor/position/parent before calling `done()` so the
subsequent `play` phase — reusing the same frame reference — picks it up
clean) and `PhaseRegistry.effect` (sub-dispatch on `phase.archetype`; only
`"projectile"` is real — a `AssetIds.Icons.ENERGY` bolt tinted by the card's
Battle Type color travels from the caster's hero frame to the target, then
calls the existing `impactPunch`/`popDamage` helpers; any other archetype
completes instantly instead of hanging the queue). In `BattleUIController`,
the existing cast-event lookup (already used for the Play animation) now
also looks up the card's first `trigger="cast"` effect entry, resolves an
archetype, and — only for `"projectile"` with a resolvable target frame —
enqueues `cast_reveal` then `effect` *before* the existing `play` enqueue, so
the sequence is zoom → projectile → impact → fly-to-grave. Every other card
(creatures, non-damage spells) is completely unaffected — falls straight
through to the unchanged Play animation, matching Phase 4 exactly.

Verified in a live Play session with `needle_step` (a real single-target
damage spell, `value=2`, `target=enemy_creature`): the first attempt used a
fresh session with no prior render, so `prevHandIds` was empty and the
cast-lookup correctly found no old frame and no-opped the whole
cast_reveal/effect block rather than erroring — confirming the nil-guard
works, though it meant that run didn't exercise the new code. Redone with a
baseline push first (establishing `prevHandIds`) then the cast push, matching
the two-push technique from Phase 4: zero console errors; the enemy
creature's HP correctly read 3 (5 − 2); hand card count correctly dropped
from 2 to 1 (the cast spell removed, the untouched creature remained); the
Grave panel correctly showed "Needle Step"; the projectile `ImageLabel` was
destroyed with no leftover instance; `BattleDirector.isLocked()` was `false`
after the full cast_reveal → effect → play sequence completed.

---

## Phase 7 — Server: Mulligan Pre-Battle Stage

**Goal:** Real gameplay feature — a new pre-battle rules step, not an
animation.

**Steps:**
- New battle status `"mulligan"`, distinct from `"active"`, set right after
  `BattleRegistry.create`, held until every human seat finishes.
- `DuelSession.start` restructured into **deal** (shuffle both decks, deal
  the current 5-card opening hand) then **mulligan window** before the
  existing turn loop begins. The Coin moves to being granted to the second
  player only *after* their mulligan resolves (never a redraw candidate) —
  currently added to hand immediately in `DuelSession.start`.
- Per-battle mulligan-completion tracker, `battle.mulliganDone =
  {player=false, npc=false}`, analogous to the existing `battle.session`/
  `timeoutStreaks` bookkeeping.
- NPC seat: auto-resolves instantly (v1: keep dealt hand as-is).
- New remotes: `OfferMulligan` (S→C: dealt hand), `ConfirmMulligan` (C→S:
  indices to replace). Server validates seat/status, returns replaced cards
  to the deck, reshuffles, draws replacements, marks the seat done.
- Timeout (recommend 30s): mirrors `DuelSession.scheduleHumanTimer` — auto-
  keep the dealt hand if a player doesn't respond, so an AFK/disconnected
  player can't stall the match (same anti-stall philosophy as the existing
  PvP anti-rage-quit flag).
- PvP synchronization: the real first turn (`startSeatTurn`) only fires once
  **both** human seats are done or timed out — mirrors the existing PVP
  ready-up handshake (`ReadyUp`/`BattleSeated`).
- Spectator/opponent "waiting for opponent" signal while one side is still
  mulliganing, reusing the shape of `BattleSeated`/`SeatedOverlay`.
- `BattleController` — new `ConfirmMulligan` handler (validate seat + status,
  delegate to `DuelSession`).

**Tests (headless):** a replaced card returns to the deck (not lost) and the
deck reshuffles before drawing a replacement; hand size unchanged after
mulligan; timeout auto-keeps the dealt hand; the Coin is never a redraw
candidate and is only granted after mulligan resolves; PvP does not start the
real first turn until both seats are done or timed out.
**Result (2026-07-07):** Created two new `RemoteEvent`s under
`ReplicatedStorage.Remotes`: `OfferMulligan` (S→C, the dealt hand) and
`ConfirmMulligan` (C→S, 1-based indices to replace). `DuelSession.start` now
sets `battle.status = "mulligan"` immediately, deals the (unchanged) 5-card
opening hands, then for each seat either fires `onMulliganOffer` +
`scheduleMulliganTimeout` (human) or auto-resolves instantly (NPC, keeps its
dealt hand — no redraw heuristic yet). New `DuelSession.confirmMulligan`
validates/de-duplicates the requested indices (removing highest-index-first
so earlier indices don't shift), shuffles the replaced cards back into the
deck, redraws the same count, and resolves the seat. `resolveMulliganSeat`
begins the real battle (grants the Coin to the second seat, calls the
existing `startSeatTurn` for the first) once **both** seats are resolved —
this is the same call path for PvE (NPC auto-resolves instantly, so only the
human's confirm/timeout gates it) and PvP (both humans must confirm or time
out). Deliberately does **not** call the normal `onBroadcast`/
`UpdateBattleState` path during the mulligan window — Phase 8's mulligan UI
will be driven by `OfferMulligan` alone, so a half-dealt hand never reaches
the regular battle UI before it exists to gate it. `BattleController` wires
`ConfirmMulligan` (rate-limited 0.5s, validates `battle.status == "mulligan"`
and a valid seat) and passes a new `onMulliganOffer` callback (fires
`OfferMulligan` to the human) into `Session.start` for both `startPvE` and
`startPvP`. The existing `PlayCard`/`DeclareAttack`/`EndTurn` handlers already
guard on `battle.status ~= "active"`, so they correctly reject any action
attempted during the mulligan window with zero changes needed there.

Verified headless (`execute_luau`, Edit mode, clone/rename technique for
`Ops`+`BattleLogic`+`DuelSession`, confirmed clean afterward) across several
rounds — the first round surfaced a real puzzle (hand size came out as 6, not
5, after a 2-card mulligan) that traced back to correct behavior, not a bug:
confirming the *last* pending seat synchronously cascades into
`beginRealBattle` (grants the Coin to the second seat) and `startSeatTurn`
(draws one card for the first seat) within the same call, so the *net*
hand-size change depends on whether the confirming seat is first or second —
the mulligan redraw itself is exactly net-zero in isolation. Traced this by
monkey-patching `Ops.drawCard` (safe since `require()` returns the same cached
table `DuelSession`'s own upvalue points to) to log every draw with live
hand-size snapshots, which made the Coin-insertion line in `beginRealBattle`
the obvious culprit. Final corrected assertions, all passing:
- 4 trials across both random `firstSeat` outcomes: final hand size exactly
  matches `5 + (startTurn draw if first) + (Coin if second)`, and total
  cards (hand + deck, +1 only if the Coin landed in that side's hand) is
  conserved — no card lost or duplicated.
- Invalid indices (`99`, `-1`, `"x"`, `2.5`, and a duplicate `1`) are safely
  filtered; only the one genuinely valid index is replaced.
- A second `confirmMulligan` for an already-resolved-but-still-pending-overall
  seat (PvP-shaped, other seat not yet confirmed) is rejected with "Already
  resolved"; a `confirmMulligan` after the battle has already gone `"active"`
  is rejected with "Not in mulligan".
- Timeout: with `MULLIGAN_TIMEOUT_SECONDS` temporarily set to `0.1` for the
  test, an unresponsive seat auto-resolves and the battle proceeds.
- PvP synchronization: confirming only one of two human seats leaves
  `battle.status == "mulligan"`; confirming the second flips it to `"active"`.

---

## Phase 8 — Client: Mulligan UI

**Goal:** Wire the real mulligan UI onto the Phase 7 server stage and the
Phase 3 Director.

**Steps:**
- New `MulliganUI` (ScreenGui, editor-built — reuse the `Dialog`/`Scrim`
  shell conventions from `InventoryUI`/`ItemMallUI`): dealt hand as
  tap-to-toggle "will replace" cards, Confirm button, countdown mirroring the
  server timeout.
- New `MulliganController`: `OfferMulligan` → show UI → selection state →
  `ConfirmMulligan` on confirm.
- `PhaseRegistry.mulligan` drives `MulliganUI` for real and only resolves
  (unlocks the Director queue) once the player confirms or times out.
- "Dealt hand" reveal beat (cards flying from the deck position into the
  mulligan tray), reusing the Phase 4 draw fly-in tween style.
- PvP "Waiting for opponent to mulligan…" overlay, reusing `SeatedOverlay`.

**Tests:** Studio Play (PvE) — mulligan UI appears at battle start, redraw
and keep both work, confirming proceeds to the turn-start banner (Phase 5).
Studio Play (PvP, two clients) — both players see the mulligan window
simultaneously; one player deliberately not responding confirms the timeout
auto-keeps their hand and the match proceeds without stalling the other
player; the waiting overlay shows correctly for whichever side finishes
first. Mobile smoke for the mulligan UI.
**Result (2026-07-08):** Built `MulliganUI` (new `ScreenGui` under `StarterGui`,
editor-built following `DESIGN_UI.md` panel conventions — dark navy `Dialog`
body, rounded corners, thick navy stroke, FredokaOne display font, plus a
`Scrim`): `TitleBar`/`Title`/`Subtitle`, a live `TimerLabel` counting down from
the server's mulligan timeout, a `CardRow` (`UIListLayout`) that holds one
tile per dealt card, a hidden `WaitingLabel` for the PvP "waiting on
opponent" state, and a `ConfirmBtn`. New `MulliganController` (LocalScript
under `StarterPlayerScripts`): listens for `OfferMulligan`, builds a tile per
card via the existing `CardVisuals` card-frame builder, toggles a "REPLACE"
badge per tile on click (tracked in a local `marked` set), collects marked
indices and fires `ConfirmMulligan` on Confirm, and listens for
`UpdateBattleState` to `closeUI()`/`clearTiles()` once the real battle begins
(covers both the "I confirmed" and "opponent's timeout resolved the last
pending seat" cases without needing its own separate close signal).

Verified in a live Play session:
- `OfferMulligan` fired from the server with 5 real card IDs correctly
  populated the UI end-to-end: `guiEnabled=true`, `cardRowVisible=true`,
  `waitingVisible=false`, `confirmVisible=true`, `tileCount=5`, correct card
  names in order, and a correctly ticking `TimerLabel`.
- A real `UpdateBattleState` broadcast (matching what `startSeatTurn`'s
  `onBroadcast` sends once mulligan resolves) correctly triggered
  `MulliganController`'s listener: `closeUI()` ran (`guiEnabled=false`),
  `clearTiles()` removed all 5 tiles (`tileCount=0`), and all sub-elements
  reset to their pre-offer default visibility — with zero console errors
  from either this controller or `BattleUIController.render()` processing
  the same broadcast.
- **Known verification gap:** the tile-click (`setMarked`/"REPLACE" badge
  toggle) and the Confirm button's click handler could **not** be exercised
  via a real simulated click — `user_mouse_input` (`moveTo` and
  `mouseButtonClick`, tried 3 times, including a bare `moveTo` alone)
  consistently timed out (`MCP error -32603`) in this environment, the same
  category of limitation already hit with `ProximityPrompt`/keyboard input
  earlier in this session. This is a tooling limitation, not a suspected
  code defect: the click handlers are simple, reviewed-by-inspection logic
  (a boolean toggle per tile; a table iteration over `marked` gathering
  1-based indices on Confirm), and the remote payload they produce
  (`ConfirmMulligan:FireServer(indices)`) was already exhaustively verified
  server-side in Phase 7's headless tests (dedup, invalid-index filtering,
  reshuffle-and-redraw correctness). An earlier attempt to manually mutate
  the UI's visible properties and fire the remote directly to "simulate" a
  click was deliberately discarded as invalid — it exercised nothing of the
  controller's own code — and the UI was reset before the checks above.
- **Scope simplification:** the "dealt hand flies in from the deck position"
  reveal beat from this phase's original plan text was **not** implemented —
  `MulliganController` currently just instantiates tiles directly via
  `buildTile()` with no entrance animation. Deferred as a polish item
  alongside the rest of the VFX-library follow-up (see "Out of Scope"); the
  mulligan UI is otherwise fully functional without it.

**Post-completion fix pass (2026-07-08):** A live-session screenshot after
Phase 9 closed surfaced five real bugs/UX issues, all fixed:
1. The "Finding Table..." loading overlay (`BattleUIController`'s
   `showBattleLoading`) was showing behind the mulligan dialog — it's only
   ever cleared on `UpdateBattleState`, `BattleOver`, or Continue, none of
   which fire during the mulligan window by design (Phase 7). Fixed by
   hiding it directly on `OfferMulligan` (`BattleUIController.lua`).
2. **Design change:** mulligan now allows redrawing **at most one card**, not
   any number — a deliberate scope-down from this plan's original "Hearthstone-
   style" full mulligan. `DuelSession.confirmMulligan` (`DuelSession.lua`) now
   scans `replaceIndices` for the first valid index only and ignores the rest,
   so a modified client sending multiple indices still can't redraw more than
   one card. `DESIGN_CORE.md`'s Mulligan section and `DESIGN_UI.md`'s Mulligan
   section updated accordingly.
3. `MulliganController.lua` rebuilt around this: each card gets its own
   "Re-draw" `TextButton` parented directly to the card's own frame (moves
   with it, no row-level layout coordination needed). Picking one is final —
   `pickRedraw(idx)` destroys every Re-draw button across all tiles
   (including the picked card's own) the instant a choice is made, leaving
   only a "REPLACE" badge on the chosen card. The old toggle-any-card /
   `setMarked` logic is gone.
4. Dialog title: "Mulligan" → **"First Draw"**.
5. Button label: "Confirm" → **"Battle"**.

Verified in a live Play session with a real simulated click this time (not
the manual-property-mutation substitute from Phase 8's original pass) —
`user_mouse_input` succeeded via `instance_path` targeting instead of raw
screen coordinates, closing Phase 8's earlier known verification gap:
- Screenshot after `OfferMulligan`: no loading overlay, title reads "First
  Draw", each card has its own visible "Re-draw" button below it, "Battle"
  button present.
- A real click on the first card's `RedrawBtn` correctly destroyed all 5
  `RedrawBtn` instances (`hasRedrawBtn=false` on every tile, checked via
  `execute_luau` Client mode) and left `ReplaceBadge.Visible=true` on only the
  picked card.
- A real click on "Battle" correctly transitioned to the waiting state
  (`cardRow.Visible=false`, `"Waiting for opponent..."` shown), with zero
  console errors from the `ConfirmMulligan:FireServer()` call.
- Headless (`execute_luau`, Edit mode, same clone/rename fresh-require
  technique used throughout this plan): a PvP-shaped battle (both seats
  human, so confirming one seat doesn't cascade into `beginRealBattle` and
  mask the result) sending `{1, 2, 3}` as `replaceIndices` confirmed only
  index `1` was applied — hand size stayed at 5, deck size was net-zero, and
  `battle.status` correctly stayed `"mulligan"` (the other seat hadn't
  resolved).

**Second fix pass (2026-07-08):** live testing of the first fix pass surfaced
two more real bugs:
1. Redraw was still client-visual-only — picking a card badged it "REPLACE"
   locally and deferred the actual hand mutation to the Battle press. Not
   what "instant real-time redraw" means. Fixed by adding a new
   `RedrawMulliganCard` RemoteFunction and `DuelSession.redrawMulliganCard`
   (server): the swap happens the instant a card is picked, in place (the
   drawn card lands back at the same hand index so the client can replace
   that exact tile without reshuffling the row), enforced to at most one
   success per seat regardless of how many times it's invoked.
   `DuelSession.confirmMulligan` dropped its `replaceIndices` parameter
   entirely — it now only finalizes the seat, since any redraw already
   happened. `MulliganController.lua` was restructured with forward-declared
   `buildTile`/`pickRedraw` locals (they call each other: a pick rebuilds the
   tile, the tile's button calls back into pick) — `pickRedraw` now invokes
   the RemoteFunction and, on success, destroys the old tile and rebuilds it
   with the real new card via `buildTile`, then destroys every `RedrawBtn`.
   The old `ReplaceBadge` overlay is gone entirely — the real new card *is*
   the confirmation.
2. A duplicate-looking Draw animation played right as the real battle began:
   dealing the opening 5-card hands in `DuelSession.start` calls
   `Logic.drawCard`, which records a `draw_card` anim event exactly like any
   live draw (Phase 1) — but mulligan never broadcasts (Phase 7), so those 10
   events (5 per side) sat unflushed in `state.pendingAnimEvents` until the
   real battle's first broadcast. The client's Draw-phase logic (Phase 4,
   which counts `draw_card` events to decide how many cards to animate flying
   in from the deck) misread this backlog as 5-6 fresh draws and replayed a
   fly-in over cards that were already sitting statically in hand — the
   reported "cards already drawn, then animation played" glitch. Fixed with
   one line: `beginRealBattle` now clears `state.pendingAnimEvents = {}`
   immediately after setting `battle.status = "active"`, before
   `startSeatTurn` pushes the real `turn_start`/`draw_card` pair — so the
   first real broadcast contains only genuinely-live events again.

Verified headless (`execute_luau`, Edit mode, same clone/rename technique):
redrawing slot 2 changed only that slot (verified against a captured
before-snapshot) while leaving slots 1/3/4/5 untouched and hand size at 5; a
second redraw attempt on the same seat was rejected with `"Already
redrawn"`; `pendingAnimEvents` held all 10 deal-draw events right after the
redraw (expected — not yet cleared) but dropped to exactly 2 real events
(`turn_start`, `draw_card`, for whichever seat went first) immediately after
`confirmMulligan` triggered `beginRealBattle`. Verified live in Play mode: a
real click on a card's `RedrawBtn` this time correctly hit the "no real
battle exists for this synthetic test" guard (`Registry.getForPlayer`
returns nil, exactly as designed) — confirming the server-side guard itself
works — and, isolating the client-only rebuild logic by temporarily stubbing
`RedrawMulliganCard.OnServerInvoke` to always return a fixed card, a real
click showed the tile flip to a genuinely different card ("Sparkhide", real
stats/ability text/race) with all Re-draw buttons gone — not a label over
the old art.

> **Environment note for future sessions:** temporarily overriding a shared
> `RemoteFunction.OnServerInvoke`/`RemoteEvent` callback via `execute_luau`
> to isolate client-only behavior works, but "restoring" it afterward by
> reassigning the callback from another `execute_luau` call does **not**
> restore the real live wiring — `execute_luau` requires run in an isolated
> plugin VM (see `DEV_STATUS.md`'s Persistence section note), so the
> "restored" closure captures fresh, disconnected module copies instead of
> the live game's real `Registry`/`Session` tables, silently breaking that
> remote for the rest of the Play session. The only reliable fix is to stop
> and restart Play mode, which re-runs the real script fresh.

---

## Phase 9 — Regression Pass + Docs Reconciliation

**Goal:** Close out the plan the way prior `PLAN_BATTLE_CHARGE*` passes did —
full regression sweep plus doc updates.

**Steps:**
- Regression watch: Charge socket pop animations (separate, untouched
  channel) still fire correctly; Grave panel updates unaffected; PvP turn
  timer/forfeit flow unaffected; the Fatigue-death fix (checkAndEnd after
  startTurn/endTurn, landed earlier this session) still fires correctly with
  the new event log and mulligan stage in place; existing players' migrated
  saves still enter a battle correctly (mulligan is a new pre-battle stage,
  not a save-schema change — verify this is actually a no-op for
  `SaveService`).
- Update `DEV_STATUS.md`, `DESIGN_UI.md` (turn banner + mulligan sections),
  `DESIGN_CORE.md` (mulligan as part of turn structure), `README.md` (new
  modules/remotes table).

**Tests:** full PvE + PvP smoke covering everything in Phases 0–8 in one
continuous session; existing `TestService` specs still pass.
**Result (2026-07-08):** Ran a fresh headless regression pass (`execute_luau`,
Edit mode, clone/rename technique for `Ops`/`BattleLogic`/`NpcAI`/
`BattleRegistry`/`DuelSession` — this session's long-running Studio Edit VM
still held a **pre-Phase-7 cached `DuelSession`** despite the source being
correctly edited, re-confirming the require-cache-staleness limitation
documented throughout Phases 1–7; verified by printing
`DuelSession.confirmMulligan ~= nil` before/after the clone swap) covering a
real `BattleRegistry.create` → `DuelSession.start` → `confirmMulligan` →
`beginRealBattle` battle built the same way `TableManager.handleTalkToNpc`
builds one, not a synthetic broadcast:
- **Charge channel isolation:** `state.player.pendingChargeEvents` and
  `state.npc.pendingChargeEvents` are confirmed separate, untouched tables —
  the new `pendingAnimEvents` channel never interferes with Charge-socket pop
  animations.
- **Event log correctness post-mulligan:** after both seats resolve, the log
  contains a correctly-shaped `turn_start` envelope (event field is `.action`,
  matching every other event in the log — verified directly, not assumed).
- **Discard/graveyard regression:** casting an affordable spell still grows
  `state[seat].discard` by one and records a matching `cast` envelope
  (`ev.action=="cast"` with the correct `cardId`) in `pendingAnimEvents`.
- **Fatigue-death fix, re-verified through the new mulligan + event-log
  stack:** forced an empty deck + 1 HP on the player, drove the NPC's
  `DuelSession.humanEndTurn` (the exported turn-handoff function — used here
  directly rather than waiting on the real async NPC turn, since the NPC's
  `task.spawn`/`task.wait(0.7)` turn cadence doesn't fit a synchronous
  headless script) to hand the turn to the player, and confirmed: `onBattleEnd`
  fired with the NPC as winner, no further `start_turn` broadcast was ever
  sent for the fatigued-out player, `pendingAnimEvents` recorded the fatal
  `damage` event, and `heroHp` read `<= 0`. The original bug (`FOUND_BUGS.md`)
  stays fixed with the mulligan stage and event log both now sitting in front
  of it.
- **Migrated-save no-op confirmed by inspection:** `script_grep "mulligan"`
  across the whole game shows every mulligan reference confined to
  `MulliganController`, `MulliganUI`, `BattleController`, and `DuelSession` —
  `SaveService` has no mulligan-related code path, so mulligan is a pure
  battle-transient stage with zero save-schema interaction, matching the
  Phase 7 assumption.
- **PvP turn timer/forfeit path:** confirmed unchanged by direct source
  reading of `DuelSession.lua` — `scheduleHumanTimer`/`humanEndTurn`'s timeout
  branch/`MAX_TIMEOUTS_BEFORE_FORFEIT` logic are untouched by any Phase 1–8
  edit; the mulligan stage only wraps the entry point (`DuelSession.start`)
  and doesn't alter the turn-loop timer code at all.

A full live two-client PvP smoke and a live PvE run driven by actual
`ProximityPrompt` interaction were **not** performed this pass — this
environment's `user_mouse_input`/`user_keyboard_input` tools reliably time
out on Roblox `ProximityPrompt`/button interaction (the same limitation
recorded in every earlier phase of this plan), and `execute_luau` runs in an
isolated plugin VM that cannot observe or drive the live running server's
actual instantiated battle state (confirmed again this pass: a direct
`require(TableManager).handleTalkToNpc(player)` call against the live Play
session's real modules hit a `nil` dependency, because the tool's VM has its
own separate `require` cache from the live game's VM — this is the existing,
previously-documented `execute_luau` VM-isolation limitation, not a new bug).
Phases 4–8 already covered live-session verification via synthetic
server→client broadcasts exercising the real client render/Director code
paths; this phase's headless pass instead exercised the real *server-side*
turn-loop/mulligan/event-log functions end-to-end, which is the piece those
earlier phases didn't yet re-verify together in combination.

Docs updated: `DEV_STATUS.md` (new top section + Module Status rows for
`BattleDirector`/`PhaseRegistry`/`EffectVisuals`/`MulliganUI`+
`MulliganController`/updated `DuelSession` row + `OfferMulligan`/
`ConfirmMulligan` in the RemoteEvents table), `DESIGN_UI.md` (new Mulligan,
Turn Banner, and Cast Reveal & Effect VFX sections), `DESIGN_CORE.md` (new
Mulligan section under Turn Structure), `README.md` (new modules/remotes,
plan pointer marked implemented instead of planning).

---

## Out of Scope — VFX Library (the actual next step after this plan)

Nothing in this plan strictly requires new art beyond what Phase 6 needs —
this separates "ship with placeholder/reused assets" from "the full VFX
library," so this plan doesn't silently block on asset production.

**What this plan needs (Phase 6 minimum):**
- **Cast-reveal card zoom**: no new asset — reuses `CardVisuals.buildCardFrame`.
- **Projectile VFX**: one traveling particle/image (glowing bolt/orb).
  Recommend reusing an existing asset as a placeholder — e.g. the Energy icon
  (`AssetIds.Icons.ENERGY`) tinted by the card's Battle Type color
  (`CardVisuals.TC_type`), or the particle already built for the Crystal-burst
  gacha reveal (`PackRevealController`). Bespoke "fireball" art is follow-up
  polish, not a blocker.
- **Impact feedback**: already exists (`impactPunch` + `popDamage`) — no new
  asset needed.
- **Turn banner**: pure UI, zero new image assets required.
- **Mulligan UI**: reuses existing card frames + the `Dialog`/`Scrim` shell —
  no new image assets needed.
- **Sound**: recommend deferring entirely to the VFX-library follow-up. If
  wanted now, the minimum set is one cast "whoosh," one impact "hit," one
  turn-start "chime," and one card-deal whoosh (can reuse the Draw sound) —
  four `rbxassetid://` sounds to source or generate.

**Full VFX library (the real next step), one image/particle asset *and* one
sound effect per archetype:**

| Archetype | Used by (action) | Image/particle need | Sound need |
|---|---|---|---|
| `projectile` | single-target `damage` | traveling bolt/orb, Battle-Type tinted | cast whoosh + impact hit |
| `area_swipe` | `damage` with `area="all"`/board zone | a claw-slash or burst sprite spanning the enemy board row | AOE swipe/roar |
| `heal_bloom` | `heal` | soft green/blue upward sparkle bloom | gentle chime/bloom |
| `buff_pulse` | `buff` | glowing upward ring/aura pulse on the target | soft power-up sting |
| `shield_pulse` | `gain_armor` | shimmering shield/barrier flash | metallic clink |
| `summon_puff` | `summon` | poof/smoke puff, tinted by summoned creature's Battle Type | pop/puff |
| `shatter` (death) | creature death / `killCreature` | crumble or crystal-shatter particle (ties to the "Shatter" trigger name and crystal-fantasy art language in `DESIGN_ART.md`) | crumble/shatter crack |
| `rebirth` | Rebirth keyword resurrection | resurrection burst/glow, brighter/more magical than a normal summon | revive chime, distinct from summon pop |

### VFX Asset Generation Prompts

Use the following prompts for the default archetype sprites. Keep each asset
neutral enough for Roblox `ImageColor3` tinting unless the prompt calls for a
specific accent color. Preserve generous transparent padding so glow and
particles are not clipped in motion.

#### `projectile`

**Subject:** A compact faceted crystal-energy bolt with a brilliant white core, a pointed leading edge, and a short trail of sparkling gemstone fragments.

**Style:** Polished fantasy card-game VFX, luminous crystal magic, crisp readable silhouette, near-white grayscale values designed for clean Battle-Type color tinting, no realism, no fire or smoke.

**Composition:** Isolated side-view projectile traveling left to right, centered horizontally, brightest at the front, tapered trail behind it, generous empty transparent space around the full glow.

**Output:** One 1024x1024 transparent PNG sprite, straight alpha, no background, no border, no text, no watermark, no cropped glow or particles.

#### `area_swipe`

**Subject:** Three sweeping claw-like arcs made from fractured crystal light, followed by a broad burst of tiny faceted shards.

**Style:** Polished fantasy card-game VFX, sharp magical energy rather than a literal animal claw, high contrast, near-white grayscale values suitable for Battle-Type color tinting.

**Composition:** Wide horizontal slash spanning most of the canvas from lower left to upper right, three clearly separated arcs, shard burst concentrated near the center, transparent negative space above and below.

**Output:** One 1536x768 transparent PNG sprite, straight alpha, no background, no creatures, no text, no watermark, no cropped trails or glow.

#### `heal_bloom`

**Subject:** A gentle bloom of crystal petals opening upward around a small radiant heart of light, with soft rising motes and tiny restorative sparkles.

**Style:** Serene crystal-fantasy healing magic, soft luminous edges, elegant and reassuring, white-to-pale-cyan grayscale base that remains tintable, distinct from an explosive impact.

**Composition:** Symmetrical upward bloom centered in the lower-middle of the canvas, petals forming a shallow cup, particles drifting vertically, open transparent space around the aura.

**Output:** One 1024x1024 transparent PNG sprite, straight alpha, no background, no character, no text, no watermark, no cropped bloom or motes.

#### `buff_pulse`

**Subject:** An ascending ring of crystalline energy surrounding a bright four-point star, with small arrow-like shards rising to communicate increased power.

**Style:** Confident fantasy card-game power-up VFX, faceted gemstone language, bold readable shapes, near-white grayscale values designed for Battle-Type tinting, energetic without looking like healing.

**Composition:** Circular pulse centered on the canvas, one strong outer ring, star at the core, shards and light streaks moving upward, balanced transparent padding on all sides.

**Output:** One 1024x1024 transparent PNG sprite, straight alpha, no background, no numbers, no text, no watermark, no cropped ring or glow.

#### `shield_pulse`

**Subject:** A translucent faceted crystal shield forming from interlocking gemstone plates, with a bright rim flash and a restrained halo pulse.

**Style:** Protective crystal-fantasy barrier VFX, sturdy and magical, clean silhouette, near-white and pale-silver grayscale base suitable for Battle-Type tinting, visually distinct from a weapon impact.

**Composition:** Front-facing shield centered on the canvas, slightly wider at the top, complete unbroken outline, subtle radial ring behind it, a few small shards locking into place.

**Output:** One 1024x1024 transparent PNG sprite, straight alpha, no background, no crest, no text, no watermark, no cropped shield, halo, or glow.

#### `summon_puff`

**Subject:** A playful magical arrival puff made of rounded crystal dust clouds, small faceted shards, and a bright starburst at the center.

**Style:** Charming fantasy card-game summon VFX, punchy and readable at small UI scale, soft cloud shapes mixed with crystalline accents, near-white grayscale base for Battle-Type tinting.

**Composition:** Compact circular burst centered low on the canvas as if a creature is appearing above it, cloud lobes spreading sideways, shards and sparkles rising, clear transparent center space for the summoned card.

**Output:** One 1024x1024 transparent PNG sprite, straight alpha, no background, no creature, no text, no watermark, no cropped cloud or particles.

#### `shatter`

**Subject:** A crystal creature silhouette breaking apart into angular gemstone fragments, dust flecks, and fading slivers of magical light.

**Style:** Dramatic but family-friendly crystal-fantasy destruction VFX, clean faceted debris, sharp readable fragments, near-white grayscale values for Battle-Type tinting, no gore, no flames.

**Composition:** Explosion radiating outward from the center with a hollowed core, larger shards close to center and smaller fragments farther out, roughly square footprint, ample transparent margin for outward motion.

**Output:** One 1024x1024 transparent PNG sprite, straight alpha, no background, no intact character, no text, no watermark, no cropped debris or glow.

#### `rebirth`

**Subject:** A brilliant crystal phoenix-like flare rising from a ring of broken shards, with a vertical pillar of light and newly re-forming gemstone fragments.

**Style:** Majestic crystal-fantasy resurrection VFX, more radiant and sacred than the summon puff, layered white-gold light with a tintable near-white crystal structure, triumphant but not visually noisy.

**Composition:** Strong vertical silhouette centered on the canvas, broken-shard ring at the base, wings of light opening in the middle, narrow beam and sparks rising above, generous transparent padding around the full aura.

**Output:** One 1024x1024 transparent PNG sprite, straight alpha, no background, no literal creature body, no text, no watermark, no cropped wings, beam, ring, or particles.

Everything above should stay inside the established crystal-fantasy visual
language documented in `DESIGN_ART.md` (glowing crystal energy, faceted
gemstone structures, Battle-Type color identity: MIGHTY `#A50E0E`, SWIFT
`#0D652D`, VITAL `#174EA6`, NEUTRAL `#9AA0A6`) rather than generic stock VFX.
Per-card VFX *overrides* are lowest priority and should only be authored
after the default archetypes above are in place and proven.

Also out of scope (see per-phase notes above): rebirth-specific animation,
NPC-turn real-time broadcast granularity, skip/pacing UX tuning, final art
for the turn banner and mulligan tray.
