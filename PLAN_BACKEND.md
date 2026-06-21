# PLAN_BACKEND — Server-Owned Battles, PVP, Persistence, Inventory

> Phased, multi-session build plan to take the alpha from "single-player vs NPC,
> tested only with AI" to a **production-ready, server-authoritative** game with
> same-server PVP, persistent saves, and an inventory panel.
>
> Architecture context: [DESIGN_ENGINE.md](DESIGN_ENGINE.md),
> [DESIGN_CORE.md](DESIGN_CORE.md), [IDEA_MATCHMAKING.md](IDEA_MATCHMAKING.md).
> Current code state: [DEV_STATUS.md](DEV_STATUS.md). The alpha card/engine build
> plan ([PLAN.md](PLAN.md)) is complete; this is the next plan.
>
> **How to use:** work phases in order; each has an Acceptance gate (a testable
> milestone) that must pass before the next. Check boxes as you go. This file is the
> cross-session progress tracker — update Status and checkboxes as work lands.

**Status:** 🟡 Phase 2 functionally built (2026-06-21). Phase 2.1 cleanup/hardening next.

---

## Scope (locked via Q&A 2026-06-20)

| # | Feature | Decision |
|---|---|---|
| 1 | BattleController production-readiness + refactor | Refactor into a server-owned, battleID-addressable model (Phases 1–3). |
| 2 | Server-owned battles by `battleID`; sit-to-play; spectator-ready | Same-server only. Cross-server MemoryStore matchmaking (IDEA_MATCHMAKING) **deferred**. Spectator **architected now, visuals deferred**. |
| 3 | Save system | **ProfileStore** (loleris) — session lock, auto-save, migration. Versioning + hard-reset wrap its migration model. |
| 4 | Inventory panel | Reads the saved collection; filters by battleType, cardType, cost. Deck builder is a **later** plan. |

**Entry model (locked):**
- **PvE:** the `Noob` NPC stands in the world. Interacting with it seats the player
  at a free Battle Table and **auto-starts** a duel (no Challenge button). Noob's
  deck is **randomized among the 3 starters** each match. NPC seats **never** touch
  the datastore.
- **PVP:** two players sit at the two chairs of one Battle Table; a lightweight
  ready/challenge handshake starts the duel.
- **New player** always starts as **MIGHTY** (for now). Player's battle deck = the
  30-card starter for their archetype.

---

## Architecture Decisions (locked)

### A1 — Perspective-remap boundary (the spine)
The engine keeps **two opaque internal seat labels** (`"player"` / `"npc"` retained
as the canonical keys to avoid a deep engine rename) but **no layer below the
controller may assume either seat is human or AI.** All "me vs them" translation
happens at the `BattleController` ↔ client boundary:

- **Egress (broadcast):** each recipient gets a view where **their own seat is
  relabelled `"player"` and the opponent `"npc"`**, including `currentTurn`,
  board/hand visibility, and combat-event sides. The opponent's hand is sent as a
  count only.
- **Ingress (remotes):** an action from player P is resolved to **P's canonical
  seat** in P's battle, and any `side`/`target` descriptor in the payload
  (`{side="npc", slot=…}`) is translated from P's perspective to canonical sides,
  then re-validated server-side.

**Consequence:** the existing client (BattleUIController / TargetingSystem, which
hardwire `player`=me, `npc`=enemy) needs **no perspective rework**. PvE, PVP, and
spectating differ only in *who drives each seat* and *which perspective is rendered*.

### A2 — Battle ownership
A `BattleRegistry` owns all live battles keyed by `battleId` (string). Players index
into it, not the reverse:
```
Battles[battleId] = {
  id, tableId,
  seats = { player = <SeatRef>, npc = <SeatRef> },  -- canonical seat labels
  state = <engine state>,                            -- BattleLogic battle
  status = "active" | "ending",
  spectators = { [userId] = true },                  -- architected now
}
SeatRef = { kind = "human", player = <Player> } | { kind = "npc", ai = NpcAI, deck }
PlayerBattle[userId] = battleId                       -- reverse index
```
Remotes carry **no battleId from the client** for actions — the server derives it
from `PlayerBattle[player]` (anti-spoof). `battleId` is used server-side and for the
(deferred) spectator subscribe path.

### A3 — Tables are server-owned resources
`TableManager` owns the two `Workspace.Battle Tables.*` models. Table states:
`FREE` → `RESERVED` → `OCCUPIED` → `FREE`.

**Seating is never native.** Each chair `Seat` is **disabled** (`Seat.Disabled =
true`) so players cannot physics-sit or be ejected — no seat-ownership races. All
seating/spectating is driven by a **table-level proximity trigger** (a single
`ProximityPrompt` per Battle Table) whose `E` action is **state-dependent**:

| Table state | `E` action | Effect |
|---|---|---|
| An empty chair exists, no game | **Sit** | Server picks the empty chair and script-seats the player (`Seat:Sit` works on a Disabled seat). |
| Both chairs full, game **not** started | *(prompt disabled)* | Transient state — nothing to do. |
| Game in progress at this table | *(prompt disabled)* | Spectator ("Watch") deferred; prompt is disabled during a battle. |

Seating is **server-validated** — the prompt only *requests*; the server re-checks
state before seating. There is **no "Stand Up" prompt**: a seated player stands via
the **Leave Seat** button (`StandUp` remote) or by ending the battle. Target behavior:
the seated player's own client suppresses the table prompt (ProximityPrompt has no
per-player visibility) so it never reads "Sit" to them, while remaining enabled for a
second player joining. That local suppression is completed in Phase 2.1. The old
`DuelTable`/`NPCChair`/`PlayerChair` test rig and the client-side `ChairInteraction`
seating are retired.

**Seating is physics-chained, never anchored.** A player's character is **client-owned**;
anchoring the `HumanoidRootPart` server-side fights that ownership and freezes the
player mid-teleport. Instead: `Seat:Sit` → **`awaitSeated`** (poll until the SeatWeld
has physically snapped the HRP into the chair, or timeout) → only *then* does the
caller proceed (start the battle / fire `BattleSeated`). The SeatWeld alone holds
position; jump-eject is blocked by disabling the `Jumping` humanoid state. Full
client-side ControlModule lock while seated is a Phase 2.1 cleanup item. This
chaining is the race-free pattern PVP seating reuses.

### A4 — Module split (production-readiness, feature #1)
`BattleController` is currently a 187-line monolith mixing remotes, NPC loop,
seating, save, and rewards. Split:
```
ServerScriptService/
  BattleController.lua         ← thin: wires Remotes → systems; PlayerAdded/Removing
  Modules/
    BattleRegistry.lua         ← battle records, battleId, perspective translate/relabel
    TableManager.lua           ← table/seat ownership, states, RequestSit, NPC entry
    DuelSession.lua            ← per-battle turn loop: human + NPC seats, turn timer
    SaveService.lua            ← ProfileStore wrapper (Phase 4)
  Packages/ProfileStore        ← vendored library (Phase 4)
```

---

## World / Instance Map (real, as of 2026-06-20)

```
Workspace/
  Battle Tables/ (Folder)
    Battle Table 1/ (Model)  Chair 1/Seat, Chair 2/Seat, <surface>/TablePrompt
    Battle Table 2/ (Model)  Chair 1/Seat, Chair 2/Seat, <surface>/TablePrompt
  Noob/ (Model)              ← standing PvE NPC; anchored; HRP/TalkPrompt (E, range 10, no LOS)
  (BenchNpc)                 ← transient Noob clone seated at chair 2 during a PvE battle
```
Two tables ⇒ up to **2 concurrent battles per server**. The old `DuelTable`/`NPCChair`/
`PlayerChair` rig was destroyed in Phase 2.

---

## Feature → Phase map

| Feature | Phases |
|---|---|
| #1 BattleController production refactor | 1 (split + ownership) · 2.1 (cleanup contracts) · 3 (hardening) |
| #2 Server-owned battles, sit-to-play, spectator-ready | 1 (battleId + spectator arch) · 2 (tables/entry) · 2.1 (entry hardening) · 3 (PVP) |
| #3 Save system (ProfileStore) | 4 |
| #4 Inventory panel | 5 |

---

## Phase 0 — Groundwork

**Goal:** remove blockers and lock naming before refactoring.

- [x] Regenerate `ReplicatedStorage/Definitions/Decks.lua` from the **updated**
      `deck_starter.json` (now **30 cards each**: 15 unique × 2). Replaces the stale
      36/37/34 decks. Confirmed via `CardSchema.validateDecks`: `decks_valid=true, 0 errors,
      mighty=30, swift=30, vital=30`.
- [x] Confirmed the two `Battle Table` models are structurally identical (58 descendants
      each; Chair 1/Chair 2 each contain a `Seat`). Added `BattleId=""` attribute to both
      table Models; added `SeatIndex=1/2` attribute to each Chair; all 4 `Seat` objects
      set `Disabled=true` (no native sitting).
- [x] `ProximityPrompt` ("TalkPrompt", ActionText="Talk", E key, range=8) added to
      `Workspace.Noob.HumanoidRootPart`. Wired to a battle in Phase 2.
- [x] Doc-hygiene debt noted. `DESIGN_BALANCE.md` was removed on 2026-06-21; remaining
      legacy Invoker UI residue is tracked for cleanup.

**Acceptance:** `require(Decks)` → 3 decks of exactly **30** cards; schema validates
clean; world instances named per the convention above.
**Depends on:** none.

---

## Phase 1 — Battle-ownership refactor (the foundation)

**Goal:** every existing PvE-vs-Noob battle runs through a server-owned,
battleId-addressable model with the A1 perspective boundary — **with zero client
changes** — and the controller is split per A4.

- [x] `BattleRegistry` (`SSS/Modules/BattleRegistry.lua`): create/lookup/destroy battle
      records; `battleId` generation ("battle_N"); `PlayerBattle` reverse index;
      `spectators` set; `viewFor`/`viewForSpectator`/`remapOpts`.
- [x] Perspective layer: `viewFor(recipientSeat, battle, lastAction)` → relabelled
      payload (own seat → `player`, opponent → `npc`, hand count-only for opponent);
      `remapOpts(recipientSeat, opts)` flips `target.side` for non-"player" seats.
      **12/12 assertions passed** (HP, turn, hand visibility, count, both remap directions).
- [x] Re-keyed storage to `Battles[battleId]`; NPC stored as `{kind="npc"}` SeatRef,
      never a Player object.
- [x] Action guards now check `battle.state.currentTurn ~= seat` (canonical seat),
      not `currentTurn ~= "player"`.
- [x] `DuelSession` (`SSS/Modules/DuelSession.lua`): `start`, `afterHumanAction`,
      `humanEndTurn`; internal `runNpcTurn` task.spawn; PVP branch in `humanEndTurn`
      (human-to-human handoff, Phase 3 completes it).
- [x] `BattleController` v4: thin remote-wiring; `BattleRegistry`+`DuelSession` replace
      the inline 187-line monolith; `DataStoreService` require and raw SetAsync/GetAsync
      removed; rewards are computed for display but not persisted (Phase 4 stub).
- [x] Spectator architecture: `spectators` set on record + `viewForSpectator`
      (both hands as counts). No remote/UI yet.

**Acceptance (testable milestone):**
1. PvE Noob-entry path → battle in `Battles[battleId]`; existing client plays full
   PvE duel with no console errors. `StartDuel` is now orphaned and has no handler
   in BattleController v5.
2. ✅ Headless 2-AI sim: 20 games, **0 errors**, 11/9 win split (symmetric AI ≈ 50/50),
   avg 24.6 turns/game.
3. ✅ Perspective-remap: **12/12 assertions** — HP, turn, hand visibility, count,
   both remapOpts directions all correct.
4. ✅ `battles[player]` pattern confirmed gone from live BattleController source
   (v4 source verified at 7 666 chars, starts "BattleController v4").

**Depends on:** Phase 0.

---

## Phase 2 — Table system & battle entry

**Goal:** server-owned tables; both entry flows (NPC auto-start, PVP sit) work on the
real Battle Tables.

- [x] `TableManager` (`SSS/Modules/TableManager`): enumerates `Workspace.Battle Tables.*`;
      FREE/RESERVED/OCCUPIED state machine; writes `battleId` attribute. `seatPlayerAt`
      (chained via `awaitSeated`), `unseatPlayer`, `spawnNpcAt`, `markOccupied`, `markFree`,
      `findFreeTable`, `handleTalkToNpc`, `handleReadyUp`, `handleStandUp`.
- [x] **Chair Seats disabled** (Phase 0). `Seat:Sit(hum)` works scripted; the **SeatWeld
      positions the character — no HRP anchoring** (anchoring fights client ownership and
      freezes the player mid-teleport). Jump-eject blocked via `Jumping` state-disable +
      server movement lock; full seated client ControlModule lock is Phase 2.1 cleanup.
- [x] **Table proximity prompt** (one per Battle Table, on table surface BasePart):
      "Sit" when a chair is free; **disabled** when OCCUPIED (battle) or both seated.
      No "Stand Up" prompt. Triggered server-side. Local prompt suppression for the
      seated player is Phase 2.1 cleanup.
- [x] **Chained seating (race-free):** `Seat:Sit` → `awaitSeated` (poll HRP near seat) →
      then proceed. Movement lock = WalkSpeed/Jump 0 + jump-state-disable + client controls
      disabled once battle state arrives. `BattleSeated` currently shows the seated
      overlay but does not fully lock client controls; Phase 2.1 completes that.
      `StandUp` RemoteEvent + auto-stand on disconnect. Standing force-breaks the
      SeatWeld.
- [x] **PvE entry:** `Noob.TalkPrompt.Triggered` → `handleTalkToNpc` → fire `BattleLoading`
      (remote exists; client overlay pending Phase 2.1) → **await player seated** → **`spawnNpcAt`**
      (clone Noob, unanchor, seat at chair 2 as the bench opponent; await seated) →
      `Registry.create` + `Session.start`. Bench NPC destroyed in `markFree`. No Challenge
      UI; no `BattleSeated` (immediate start).
- [x] **PVP entry:** table prompt seats each player (awaited) → `BattleSeated` fires
      (shows Ready/Leave overlay, locks movement) → both fire `ReadyUp` → `handleReadyUp`
      → `startPvP` → `Session.start`. MIGHTY deck for both players (Phase 4: profile).
- [x] Retired: `DuelTable`/`NPCChair`/`PlayerChair` (destroyed), `NpcSit` (disabled),
      `ChairInteraction` (disabled). `StartDuel` remote kept (orphan, no handler in v5).
      `Noob` model + all `BenchNpc` clones are anchored static (can't be pushed); Noob
      TalkPrompt `RequiresLineOfSight=false` (own body was blocking the LOS ray).
- [x] New remotes: `StandUp` (C→S), `ReadyUp` (C→S), `BattleSeated` (S→C),
      `BattleUnseated` (S→C), `BattleLoading` (S→C, PvE loading screen).
- [x] Client UI: `SeatedOverlay` (Ready + Leave Seat buttons, "Seated (chair N)…").
      `BattleLoadingOverlay` and full pre-battle control/prompt cleanup are Phase 2.1
      items. Battle camera teardown guarded by a `battleEnded` flag so stray
      post-battle `render()` calls (e.g. `UXMode.Changed`) can't re-arm the scriptable cam.

**Acceptance (testable milestone):**
- Interacting with Noob seats the player at a real Battle Table and auto-starts a PvE
  duel; Noob's deck varies across runs.
- Two players (Studio **Local Server, 2 players**) can each sit at the two chairs of
  one table and start a PVP duel via the handshake.
- Table states are correct throughout (FREE→RESERVED→OCCUPIED→FREE); sitting at an
  occupied seat is rejected; standing/leaving frees the table.

**Depends on:** Phase 1.

---

## Phase 2.1 — Entry cleanup, remote safety, and pre-PVP readiness

**Goal:** make Phase 2 truthful, repeatable, and hard enough that Phase 3 can focus
on the two-human duel loop, turn timers, and production battle lifecycle instead
of cleaning entry-flow debt.

- [ ] **BattleLoading client path:** implement or explicitly retire the
      `BattleLoading` client overlay contract. If kept, `BattleLoading` shows a
      short input-blocking "Finding Table..." state for PvE and always clears on
      `UpdateBattleState`, `BattleUnseated`, `BattleOver`, timeout, or character reset.
- [ ] **Seated UX contract:** `BattleSeated` locks client controls, disables jump,
      shows Ready/Leave, and locally suppresses table prompts for the seated player;
      `BattleUnseated`, `UpdateBattleState`, `BattleOver`, and respawn restore the
      correct UI/control state.
- [ ] **Workspace/table cleanup:** clear stale `SeatWeld`/occupant artifacts in edit
      state; confirm both Battle Tables have `BattleId=""`, `SeatIndex=1/2`, disabled
      Seats, and exactly one runtime-created `TablePrompt` per table in play.
- [ ] **Retired artifact decision:** confirm `StartDuel`, `UseSkill`, `UsePlayerSkill`,
      `ChairInteraction`, and `NpcSit` are either intentionally kept as disabled/orphaned
      migration artifacts or removed in a later cleanup. Document the decision in
      `DEV_STATUS.md`.
- [ ] **Remote payload validation contract:** define and then implement a server-side
      validator for `PlayCard` and `DeclareAttack`: action player owns the battle,
      owns the canonical seat, it is their turn, card exists in hand, slot is numeric
      and in range, target side/slot is valid after perspective remap, target class
      matches the card's schema, and malformed payloads reject without throwing.
- [ ] **Remote rate-limit contract:** add a lightweight per-player rate-limit plan for
      battle remotes (`PlayCard`, `DeclareAttack`, `EndTurn`, `Forfeit`, `ReadyUp`,
      `StandUp`) so abuse is rejected quietly before Phase 3 multiplayer testing.
- [ ] **Lifecycle cleanup contract:** write the authoritative cleanup order for
      forfeit, disconnect, stand-up, battle end, table release, bench NPC destroy,
      control unlock, and registry destroy. Phase 3 should implement against this
      contract, not invent cleanup order ad hoc.
- [ ] **Smoke harness checklist:** document the minimum manual/Studio checks before
      entering Phase 3: PvE Noob start → duel → battle over → table free; PVP Local
      Server 2 players sit/ready/start; invalid remotes reject; no console errors;
      no locked controls or orphaned table `BattleId`.
- [ ] **Doc reconciliation:** update `DEV_STATUS.md`, `DESIGN_UI.md`, and this plan
      after the cleanup lands so "complete" only means verified behavior.

**Acceptance (testable milestone):**
- PvE Noob entry either shows and clears the loading overlay correctly, or the
  `BattleLoading` remote/overlay contract is intentionally retired from docs and code.
- A seated player cannot move/jump, sees only the seated overlay actions, and recovers
  controls on leave, battle start, battle end, and respawn.
- Both tables return to a clean `FREE` state after PvE, PVP pre-battle leave, forfeit,
  and disconnect tests.
- Malformed `PlayCard`/`DeclareAttack` payloads are rejected without server errors.
- `DEV_STATUS.md` and `DESIGN_UI.md` match the verified behavior.

**Depends on:** Phase 2. Required before Phase 3.

---

## Phase 3 — PVP duel loop + production hardening

**Goal:** two humans complete robust duels; the controller is production-grade.

- [ ] Two-human turn loop in `DuelSession`: per-perspective broadcast to each seat;
      each player may submit actions **only on their own seat's turn**; clean handoff
      with no NpcAI involved.
- [ ] **Turn timer:** per-turn timeout → auto-`endTurn`; repeated timeout (idle
      player) → auto-forfeit. (A human can otherwise stall forever — production gap.)
- [ ] **Disconnect / leave mid-battle:** opponent wins, battle record GC'd, table
      released, both clients cleaned up — no orphaned battles or locked tables.
- [ ] **Remote hardening:** every battle remote re-derives the battle from the player,
      re-validates seat/turn/target, and is rate-limited; reject (not error) on abuse.
- [ ] Reward write on win goes through `SaveService` (stubbed until Phase 4; raw
      `SetAsync` removed). NPC matches award nothing to the NPC seat.

**Acceptance (testable milestone):**
- Two real players complete a full PVP duel start→win with correct independent views
  (each sees own hand, opponent as count).
- Turn timer auto-ends a stalled turn; an idle player eventually auto-forfeits.
- A mid-game disconnect ends the battle, declares the opponent winner, and frees the
  table with **zero console errors**.

**Depends on:** Phase 2.1. Completes feature #1 (production-readiness) and #2.

---

## Phase 4 — Save system (ProfileStore)

**Goal:** robust persistence meeting the stated requirements, replacing the naive
`GetAsync`/`SetAsync`.

- [ ] Vendor **ProfileStore** into `ServerScriptService/Packages/ProfileStore`.
- [ ] `SaveService` wrapper: load profile on `PlayerAdded` (session-locked), release
      on `PlayerRemoving`. **Session lock** (exclusive write, heartbeat, release on
      disconnect, stale-timeout takeover) is provided by ProfileStore — verify the
      timeout/steal behavior matches the requirement.
- [ ] **Save schema v1** (document it here and in DEV_STATUS):
      ```
      Profile.Data = {
        _version = { major = 1, minor = 0 },
        archetype = "MIGHTY",          -- new player default
        collection = { cardId, … },    -- owned cards (inventory source)
        gold = 0, exp = 0,
      }
      ```
- [ ] **Dirty-flag pooled autosave:** mutations set a dirty flag; a ~60s loop flushes
      dirty profiles (ProfileStore auto-save covers the periodic write; the dirty flag
      avoids redundant work and forces a flush on important events like a card drop).
- [ ] **Versioning + migration:** `_version.major/minor`; a migration table upgrades
      old data on load; a **major-version bump = hard reset/wipe** path (documented,
      guarded).
- [ ] **New-player grant:** fresh profile → archetype MIGHTY + the MIGHTY starter
      collection.
- [ ] Battle deck selection reads `archetype` from the profile (still MIGHTY); NPC
      seats remain datastore-free.

**Acceptance (testable milestone):**
- Join → profile loads (locked); a second server/session cannot write the same key
  (lock proven); leave → released.
- Win a match → collection/gold/exp update, flushed within the pool interval and on
  rejoin persist.
- A simulated old-format record migrates on load; a major bump triggers the documented
  reset path. (Verified headlessly via `execute_luau` against `SaveService`.)

**Depends on:** Phase 3 (reward write path). Independent of Phases 1–3 otherwise —
can be done in parallel by a separate session.

---

## Phase 5 — Inventory panel

**Goal:** players can browse their owned cards with filters. (Deck builder is a later
plan — this is read-only collection viewing.)

- [ ] `GetInventory` remote (or reuse a data-sync remote): server returns the player's
      `collection` from `SaveService` (resolved to full card defs client-side via the
      existing `CardData`/`CardVisuals` shim).
- [ ] `StarterGui/InventoryUI/` panel: a scrollable grid of owned cards using the
      existing `CardVisuals` card frames (full mode); open/close button in the HUD.
- [ ] **Filters** (dropdown selection):
      - `battleType` — MIGHTY / SWIFT / VITAL / NEUTRAL (+ All)
      - `cardType` — creature / spell (+ All)
      - `cost` — 0,1,2,…,10 (+ All)
      - Filters combine (AND); empty result shows an empty-state.
- [ ] Counts: show duplicates as a stack with an ×N badge (collection is a multiset).

**Acceptance (testable milestone):**
- Opening the inventory shows exactly the player's owned cards (matches the profile
  collection) rendered with correct art/stats/text.
- Each filter narrows the grid correctly; combined filters AND together; clearing
  restores the full set. Verified in play mode with a seeded collection.

**Depends on:** Phase 4 (collection data).

---

## Deferred / Future (out of scope for this plan)

- **Cross-server matchmaking** (MemoryStore queue, server registry, teleport,
  reservations) per IDEA_MATCHMAKING — its same-server table-ownership pieces are
  built here; the cross-server layer is a later plan.
- **Spectator visuals:** 3D cards laid on the physical table + bystander battle-UI.
  The battleId/spectator *data path* is architected in Phase 1; rendering is deferred.
- **Deck builder** (custom decklists from the collection) — the next plan after this.
- **Reconnect into an in-progress battle** (currently a disconnect ends the match).
- Doc reconciliation after Phase 2.1 implementation: keep `DEV_STATUS.md`,
  `DESIGN_UI.md`, and this plan aligned with verified behavior.

---

## Open questions (resolve before the relevant phase)

- **PVP handshake exact shape (Phase 2):** auto-start when both seated, or explicit
  mutual `ReadyUp`? Defaulting to mutual ready; confirm before building.
- **Seating mechanism (Phase 2): RESOLVED** — native `Seat` disabled; **one** state-driven
  table `ProximityPrompt` per table (server auto-picks the empty chair), server-validated
  (A3). No "Stand Up" prompt; seated player uses the Leave Seat button. Seating is chained
  via `awaitSeated` (no anchoring).
- **Turn timer length (Phase 3):** pick a value (e.g. 60–90s) and the auto-forfeit
  threshold (e.g. 2 consecutive timeouts).
