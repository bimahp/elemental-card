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

**Status:** 🟢 Original backend phases complete. The later Battle Charge migration
(`PLAN_BATTLE_CHARGE.md`, 2026-06-23) superseded this plan's Crystal Core deck
identity: decks are now Core-free, profile schema is v1.3, and the Card Library has
My Cards plus a Core-free, Charge-aware Deck Builder. Remaining gates are full
2-player Local Server PVP and desktop/mobile Card Library navigation/editor polish.

---

## Scope (locked via Q&A 2026-06-20)

| # | Feature | Decision |
|---|---|---|
| 1 | BattleController production-readiness + refactor | Refactor into a server-owned, battleID-addressable model (Phases 1–3). |
| 2 | Server-owned battles by `battleID`; sit-to-play; spectator-ready | Same-server only. Cross-server MemoryStore matchmaking (IDEA_MATCHMAKING) **deferred**. Spectator **architected now, visuals deferred**. |
| 3 | Save system | **ProfileStore** (loleris) — session lock, auto-save, migration. Versioning + hard-reset wrap its migration model. |
| 4 | Card Library panel | Reads the saved collection, and now includes Deck Builder / saved deck management. |

**Entry model (locked):**
- **PvE:** the `Noob` NPC stands in the world. Interacting with it seats the player
  at a free Battle Table and **auto-starts** a duel (no Challenge button). Noob's
  deck is **randomized among the 3 starters** each match. NPC seats **never** touch
  the datastore.
- **PVP:** two players sit at the two chairs of one Battle Table; a lightweight
  ready/challenge handshake starts the duel.
- **New player** starts with one active valid `Mighty Starter` deck. Battle deck
  selection uses `activeDeckId`, not `archetype`; decks no longer store a Core.

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
second player joining. The old
`DuelTable`/`NPCChair`/`PlayerChair` test rig and the client-side `ChairInteraction`
seating are retired.

**Seating is physics-chained, never anchored.** A player's character is **client-owned**;
anchoring the `HumanoidRootPart` server-side fights that ownership and freezes the
player mid-teleport. Instead: `Seat:Sit` → **`awaitSeated`** (poll until the SeatWeld
has physically snapped the HRP into the chair, or timeout) → only *then* does the
caller proceed (start the battle / fire `BattleSeated`). The SeatWeld alone holds
position; jump-eject is blocked by disabling the `Jumping` humanoid state plus the
client ControlModule during loading, seated, and battle states. This chaining is the
race-free pattern PVP seating reuses.

### A4 — Module split (production-readiness, feature #1)
`BattleController` is now the thin remote-wiring script for remotes, battle start,
and player cleanup; ownership lives in the modules below:
```
ServerScriptService/
  BattleController.lua         ← thin: wires Remotes → systems; PlayerAdded/Removing
  Modules/
    BattleRegistry.lua         ← battle records, battleId, perspective translate/relabel
    TableManager.lua           ← table/seat ownership, states, RequestSit, NPC entry
    DuelSession.lua            ← per-battle turn loop: human + NPC seats, turn timer
    RewardService.lua          ← reward policy/payload builder (Phase 3), persistence-free
    SaveService.lua            ← ProfileStore wrapper (Phase 4)
  Packages/ProfileStore        ← vendored library (Phase 4)
```

---

## World / Instance Map (real, as of 2026-06-21)

```
Workspace/
  Battle Tables/ (Folder)
    Battle Table 1/ (Model)  Chair 1/Seat, Chair 2/Seat, <surface>/TablePrompt at runtime
    Battle Table 2/ (Model)  Chair 1/Seat, Chair 2/Seat, <surface>/TablePrompt at runtime
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
      server movement lock + client ControlModule lock.
- [x] **Table proximity prompt** (one per Battle Table, on table surface BasePart):
      "Sit" when a chair is free; **disabled** when OCCUPIED (battle) or both seated.
      No "Stand Up" prompt. Triggered server-side. The seated player's client locally
      suppresses table prompts while loading, seated, or in battle.
- [x] **Chained seating (race-free):** `Seat:Sit` → `awaitSeated` (poll HRP near seat) →
      then proceed. Movement lock = WalkSpeed/Jump 0 + jump-state-disable + client controls
      disabled during loading, seated, and battle states. `BattleSeated` shows the seated
      overlay and locks/suppresses local controls/prompts before the duel starts.
      `StandUp` RemoteEvent + auto-stand on disconnect. Standing force-breaks the
      SeatWeld.
- [x] **PvE entry:** `Noob.TalkPrompt.Triggered` → `handleTalkToNpc` → fire `BattleLoading`
      (client shows input-blocking "Finding Table..." overlay) → **await player seated** → **`spawnNpcAt`**
      (clone Noob, unanchor, seat at chair 2 as the bench opponent; await seated) →
      `Registry.create` + `Session.start`. Bench NPC destroyed in `markFree`. No Challenge
      UI; no `BattleSeated` (immediate start).
- [x] **PVP entry:** table prompt seats each player (awaited) → `BattleSeated` fires
      (shows Ready/Leave overlay, locks movement) → both fire `ReadyUp` → `handleReadyUp`
      → `startPvP` → `Session.start`. MIGHTY deck for both players (Phase 4: profile).
- [x] Retired: `DuelTable`/`NPCChair`/`PlayerChair` (destroyed), `NpcSit` (disabled),
      `ChairInteraction` (removed/missing in current place). `StartDuel`, `UseSkill`,
      and `UsePlayerSkill` remotes are kept as orphaned migration artifacts with no
      BattleController v5 handler; deletion is deferred.
      `Noob` model + all `BenchNpc` clones are anchored static (can't be pushed); Noob
      TalkPrompt `RequiresLineOfSight=false` (own body was blocking the LOS ray).
- [x] New remotes: `StandUp` (C→S), `ReadyUp` (C→S), `BattleSeated` (S→C),
      `BattleUnseated` (S→C), `BattleLoading` (S→C, PvE loading screen).
- [x] Client UI: `SeatedOverlay` (Ready + Leave Seat buttons, "Seated (chair N)…").
      `BattleLoadingOverlay` and full pre-battle control/prompt cleanup are implemented.
      Battle camera teardown guarded by a `battleEnded` flag so stray
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

- [x] **BattleLoading client path:** `BattleLoading` shows an input-blocking
      "Finding Table..." overlay for PvE and clears on `UpdateBattleState`,
      `BattleUnseated`, `BattleOver`, timeout, or character reset.
- [x] **Seated UX contract:** `BattleSeated` locks client controls, disables jump,
      shows Ready/Leave, and locally suppresses table prompts for the seated player.
      `BattleUnseated`, `UpdateBattleState`, `BattleOver`, Continue, timeout, and
      respawn restore the correct UI/control/prompt state.
- [x] **Workspace/table cleanup:** one stale edit-mode `SeatWeld` artifact was removed
      from `Battle Table 1 / Chair 1 / Seat`. Play smoke confirmed both Battle Tables
      have `BattleId=""`, disabled Seats, no occupants/SeatWelds, and exactly one
      runtime-created `TablePrompt` per table.
- [x] **Retired artifact decision:** `NpcSit` remains disabled, `ChairInteraction` is
      removed/missing in the current place, and `StartDuel`, `UseSkill`, `UsePlayerSkill`
      remain as orphaned migration remotes with no live BattleController v5 handler.
      Deletion is deferred to a later cleanup.
- [x] **Remote payload validation contract:** `PlayCard` and `DeclareAttack` now
      re-derive battle/seat/turn from the player, remap perspective targets, validate
      card-in-hand, numeric slots, descriptor shape, and target class, and reject malformed
      payloads by warning/broadcasting without throwing.
- [x] **Remote rate-limit contract:** battle remotes (`PlayCard`, `DeclareAttack`,
      `EndTurn`, `Forfeit`, `ReadyUp`, `StandUp`) have lightweight per-player cooldowns
      so rapid repeats are dropped before battle logic.
- [x] **Lifecycle cleanup contract:** current authoritative order is:
      forfeit/disconnect -> determine canonical loser/winner -> `endBattle`;
      `endBattle` marks `status="ending"` -> unseats human seats -> fires `BattleOver`
      -> `TableManager.markFree(tableId)` -> destroys bench NPC -> clears table
      `BattleId`/prompt state -> `Registry.destroy(battle)`; client `BattleOver`/Continue
      then clears overlays, camera, local prompt suppression, and control locks. Pre-battle
      `StandUp` only calls `TableManager.unseatPlayer` + `BattleUnseated`; it does not
      touch battle records because no battle exists yet.
- [x] **Smoke harness checklist:** before Phase 3, run: PvE Noob start -> duel ->
      battle over -> table free; PVP Local Server 2 players sit/ready/start; invalid
      remotes reject; no console errors; no locked controls or orphaned table `BattleId`.
- [x] **Doc reconciliation:** `DEV_STATUS.md`, `DESIGN_UI.md`, `DESIGN_ENGINE.md`,
      `README.md`, and this plan were reconciled after Phase 2.1.

**Verification performed 2026-06-21:**
- Fresh-source module require and targeting validation passed for `Effects.Targeting`
  after bypassing Roblox's edit-mode `require` cache with a cloned ModuleScript.
- Studio Play single-client smoke passed: TableManager registered 2 tables, BattleController
  loaded, Noob TalkPrompt wired, client `BattleUI`, `BattleLoadingOverlay`, and
  `SeatedOverlay` were present, runtime table prompt count = 2, and console output had
  no errors.
- Full Studio Local Server 2-player PVP smoke is still the next manual gate before
  Phase 3 implementation.

**Acceptance (testable milestone):**
- PvE Noob entry shows and clears the loading overlay correctly.
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

- [x] Two-human turn loop in `DuelSession`: per-perspective broadcast to each seat;
      each player may submit actions **only on their own seat's turn**; clean handoff
      with no NpcAI involved.
- [x] **Turn timer:** per-turn timeout → auto-`endTurn`; repeated timeout (idle
      player) → auto-forfeit. Timer values live in one config surface
      (`TURN_TIMEOUT_SECONDS`, `MAX_TIMEOUTS_BEFORE_FORFEIT`) so changing pacing does
      not require touching remote handlers or battle rules.
- [x] **Turn timer UI contract:** expose server-authoritative timer metadata through
      `UpdateBattleState` (`turnStartedAt`, `turnEndsAt`, `turnDuration`, and
      current timeout warning state if needed). `BattleUIController` renders a compact
      local countdown near the current-turn/End Turn HUD, resyncs on every state
      update, and never enforces timeouts client-side.
- [x] **Disconnect / leave mid-battle:** opponent wins, battle record GC'd, table
      released, both clients cleaned up — no orphaned battles or locked tables.
- [x] **Remote hardening audit:** Phase 2.1 added seat/turn/payload validation and
      lightweight rate limits. Phase 3 should re-test those guards under 2-player
      Local Server conditions and extend them only where the PVP turn timer/lifecycle
      introduces new remotes or edge cases.
- [x] **Reward policy split:** extract reward construction from `BattleController`
      into `RewardService` (or equivalent policy module). It should build reward
      payloads from `{mode="pve"|"pvp", battle, winnerSeat, recipientSeat}` and keep
      persistence out of Phase 3. Current policy target:
      - PvE human winner: existing EXP/gold/card-drop display payload.
      - PvE loser: no reward payload.
      - NPC seat: never receives rewards.
      - PVP winner/loser: explicit policy placeholder payloads, documented and easy
        to tune later without changing battle cleanup.
- [x] **Reward persistence handoff:** Phase 3 returns/display rewards only. Phase 4
      `SaveService` consumes the already-built reward payload and persists it; raw
      `SetAsync` remains removed.

**Verification performed 2026-06-21:**
- Fresh-source requires passed for `DuelSession`, `BattleRegistry`, `RewardService`,
  `BattleLogic`, and `TableManager`.
- Reward policy smoke passed: PvE winner returns EXP/gold/card-drop; PvE non-human
  recipient returns nil; PVP winner/loser return explicit placeholder messages.
- Isolated server timer simulation with shortened constants passed: timeout auto-ended
  turns and repeated idle timeout auto-forfeited via token-guarded callbacks.
- Studio Play single-client smoke passed: `BattleController v5` loaded, table prompts
  registered, Noob TalkPrompt wired, no console errors, and desktop/mobile timer labels
  existed in `PlayerGui`.
- Regression fixes landed after first Phase 3 smoke: timer UI no longer resets when
  `UXMode.Changed` re-renders the same `lastState`; `battleEnded` + `lastState=nil`
  prevent post-battle re-renders from re-arming the battle camera; `BattleLoading`
  now has both the server remote and an optimistic local Noob TalkPrompt fallback.
- Remaining gate: full Studio Local Server 2-player manual run for sit/ready/start,
  independent views, turn handoff, forfeit/disconnect cleanup, visible timer resync,
  post-battle camera recovery, and PvE loading overlay visibility.

**Acceptance (testable milestone):**
- Two real players complete a full PVP duel start→win with correct independent views
  (each sees own hand, opponent as count).
- Turn timer auto-ends a stalled turn; an idle player eventually auto-forfeits.
- Timer UI visibly counts down for both own and opponent turns, warning near expiry,
  and resyncs cleanly after actions, End Turn, timeout, and battle end.
- A mid-game disconnect ends the battle, declares the opponent winner, and frees the
  table with **zero console errors**.
- PvE and PVP reward payloads come from one reward policy module, not inline
  `BattleController` branching; changing timer values or reward contents is a
  config/policy edit, not a lifecycle rewrite.

**Depends on:** Phase 2.1. Completes feature #1 (production-readiness) and #2.

---

## Phase 4 — Save system (ProfileStore)

**Goal:** robust persistence meeting the stated requirements, replacing the naive
`GetAsync`/`SetAsync`.

- [x] Vendored **ProfileStore** (loleris/MAD STUDIO) into
      `ServerScriptService/Packages/ProfileStore`, pinned to commit `45c9847`
      (no tagged releases; provenance + raw copy kept in repo `vendor/`). Fetched into
      Studio directly via `HttpService` so the source is byte-identical (64 654 bytes).
- [x] `SaveService` (`SSS/Modules/SaveService`): load profile on `PlayerAdded`
      (session-locked via `StartSessionAsync` + `Cancel`), release on `PlayerRemoving`
      (`EndSession`); `OnSessionEnd` kicks on remote session steal. Connect-first /
      sweep-after with a `Loading` re-entrancy guard so a player joining during init is
      never missed and never double-loaded. Session lock is ProfileStore's exclusive
      write + heartbeat; same-server double-load throws ("already loaded in this session").
- [x] **Save schema v1.0 baseline** (mirrored in DEV_STATUS; upgraded to v1.1 below):
      ```
      Profile.Data = {
        _version = { major = 1, minor = 0 },
        archetype = "MIGHTY",          -- new player default
        collection = { cardId, … },    -- owned cards, a MULTISET (dups kept; Phase 5 stacks ×N)
        gold = 0, exp = 0,
      }
      ```
- [x] **Dirty-flag pooled autosave:** `applyRewards` marks dirty; a 60s loop flushes
      dirty profiles with `Profile:Save()`. ProfileStore's circular `AUTO_SAVE_PERIOD`
      (~300s) is the backstop. **Card drops force an immediate `:Save()`** (important event).
- [x] **Versioning + migration:** `migrate(data)` runs **before** `Reconcile` so an
      old/missing `_version` is still visible. `minor <` → ordered `MINOR_MIGRATIONS`
      table then bump; `major <` or missing → **guarded hard reset** (`ALLOW_MAJOR_RESET`)
      that wipes to a fresh starter; `version >` server → `"ahead"`, served as-is.
- [x] **New-player grant:** the schema-v1 `TEMPLATE` IS the grant — ProfileStore
      deep-copies it for first-time keys → archetype MIGHTY + the 30-card MIGHTY starter
      collection (built from `Decks.mighty.cards`).
- [x] Battle deck selection now reads `activeDeckId` via `SaveService.getActiveBattleDeck`
      in `startPvE`/`startPvP`. NPC seats never touch the datastore; Noob still randomizes
      among the three pure starter decks. The later Battle Charge migration removed
      Core assignment from NPC battle setup.
- [x] Wired into `BattleController.endBattle`: PvE `Save.applyRewards(player, rewards)` for
      present human winners.
- [x] **PvP W/L + anti rage-quit (schema v1.1, added 2026-06-21 after PVP testing).**
      *Decision reversed:* the earlier "ignore disconnected players" is replaced — a player
      who disconnects/forfeits to dodge a loss IS now penalized (alpha penalty = a recorded
      `pvp.losses`; tune later). **Reliable method (validated vs ProfileStore best practice
      + web search):** mark-in-match-at-start, resolve-on-next-load — never write at the
      disconnect moment.
      - `pvp = {wins,losses}` + `activeMatch` added to schema (minor bump 1.0→1.1; Reconcile
        backfills; first real minor migration).
      - `startPvP` → `SaveService.beginPvpMatch(p, battleId)` sets `activeMatch` and
        **force-saves** (durable before any disconnect).
      - `endBattle` (clean finish, incl. forfeit-while-present) → `recordPvpResult(p, won)`:
        W/L++ , clears `activeMatch`, force-saves; returns the record for the `BattleOver`
        "Victory!/Defeat. Record: XW/YL" message (replaces the old "pending ProfileStore").
      - `onPlayerAdded` (next login): a still-set `activeMatch` ⇒ abandoned match ⇒
        `pvp.losses++`, clear. Exactly one loss either path; survives rage-quit/crash/server
        crash. Headless-verified (flag persists across a session → loss on reload) + dev
        profile auto-migrated 1.0→1.1 in a live boot.

**Acceptance (testable milestone) — ALL VERIFIED 2026-06-21:**
- ✅ Join → profile loads (session-locked), schema-v1 starter granted (arch MIGHTY,
  30-card collection, gold/exp 0). Verified live in Studio Play via game-VM print.
- ✅ Win/reward → collection/gold/exp update, flushed (card drop forces immediate save),
  and **persist across a rejoin on the real DataStore** (applied +5 exp/+10 gold/+1 card,
  rejoined showing exactly that; then reset to clean starter).
- ✅ Migration: headless `execute_luau` against `SaveService.migrate` — `current` no-op,
  old-major + missing-`_version` → hard reset to starter, `version >` → `ahead`. Hard-reset
  also live-verified on the real store.
- ✅ Session lock: same-key double-load throws (guarded); mock load→save→rejoin round-trip
  (exp 50/gold 25/col 31) passed headlessly.

> **Tooling note (cost me a long misdiagnosis — recorded for future sessions):** MCP
> `execute_luau` runs in an **isolated plugin Luau VM**, NOT the running game server's VM.
> `require()` there returns a *separate* module copy and `_G` is separate, so you **cannot**
> introspect a live server's module state (e.g. `SaveService.Profiles`) from `execute_luau`
> during Play. Verify live server behavior with **in-script `print`s → `get_console_output`**
> instead. `execute_luau` is still correct for self-contained headless tests (Edit mode).

**Depends on:** Phase 3 (reward write path). Independent of Phases 1–3 otherwise —
can be done in parallel by a separate session.

---

## Phase 5 — Card Library panel

**Goal:** players can browse owned cards and manage saved decks from one Card Library
panel.

**Status:** 🟢 Implemented, live-captured, and reconciled against Studio. Crystal Core
deck selection was later removed by `PLAN_BATTLE_CHARGE.md`: the Deck Builder is now
Core-free and Charge-aware. Interactive filter/tap/close behavior was verified for My
Cards. The Deck Builder shell, deck remotes, and active-deck integration are implemented;
full desktop/mobile manual navigation and editor polish remain validation gates.

**UI conventions (locked with user 2026-06-21):**
- **Editor-first.** Static layout = real, named instances in StarterGui (adjustable in
  Studio). Code only does the dynamic/data parts (grid cells, fetch, filters, preview,
  visibility). The only runtime-built UI is the per-card grid cells (necessarily dynamic).
- **Top-right HUD anchor** (`StarterGui/Hud/TopRightAnchor`) hosts ALL world icons
  (Card Library now; Card List, Title Collection, … later) via a horizontal `UIListLayout`.
  `HudController` shows it in free-roam and hides the whole group during any battle state.
- **Icon outline** uses the layered technique (UIStroke can't trace image alpha): a
  slightly larger dark-tinted copy of the image behind the icon. Inventory icon asset =
  `rbxassetid://72487233066616` (a blue backpack; already has its own thin outline, so the
  extra layer is an outer halo).
- **Dialog layout:** one reusable `InventoryUI` dialog with a shared header/back button
  and page stack: Home, My Cards, Deck List, Deck Editor. The former Core Select page
  was removed by the Battle Charge migration.

- [x] `GetInventory` **RemoteFunction** + `ServerScriptService/InventoryService`: returns
      the player's `collection` (cardId multiset) from `SaveService`; client resolves defs
      via `CardData`/`CardVisuals`. NPC/no-profile → empty list.
- [x] `StarterGui/InventoryUI/` panel: scrollable `Grid` (UIGridLayout) of owned cards
      built with `CardVisuals.buildCardFrame(..,"full")` + `updateCardFrame`; opened by the
      HUD inventory icon, closed via the X button or scrim click.
- [x] **Filters** are **tap dropdowns** (header button → option list; tap a row to select;
      finger-sized rows, long Cost list scrolls). Editor-first: each dropdown's `List`
      (ScrollingFrame) + `RowTemplate` are authored instances; the controller clones one row
      per value, sizes the list to fit, and toggles visibility. Combine with AND; empty
      result shows the `EmptyState` label. Verified in the live Studio scripts/UI:
      "Type: NEUTRAL" → only the 4 NEUTRAL cards.
      - `battleType` — All / MIGHTY / SWIFT / VITAL / NEUTRAL
      - `cardType` — All / creature / spell
      - `cost` — All / 0…10
- [x] Counts: multiset collapsed to unique cards with an **×N** badge per stack.
- [x] Deck remotes + `ServerScriptService/DeckService`: `GetDecks`, `CreateDeck`,
      `SaveDeckCards`, `RenameDeck`, `DeleteDeck`, `SetActiveDeck`.
- [x] Deck Builder pages: create decks directly (Core-free after the Battle Charge
      migration), edit cards, save drafts, rename, delete, and set active only through
      server validation.

**Acceptance (testable milestone):**
- ✅ Opening the inventory shows the player's owned cards (live: 30-card MIGHTY starter →
  16 unique stacks with ×N badges), rendered with stats/text/type badges (art still
  placeholder — see Known Issues). Right pane previews the tapped card large.
- ✅ Each filter narrows the grid; combined filters AND together (verified: NEUTRAL filter
  → 4 cards). Dropdown open/select validated via capture.

**Polish — DONE / LIVE-VERIFIED (2026-06-21):**
- ✅ Top-right overlap: `HudController` disables the default player-list CoreGui
  (`SetCoreGuiEnabled(PlayerList, false)`) so the HUD owns the corner. Reversible (set true).
- ✅ Preview emblem overhang: `renderPreview` reserves room for the ~5% left stat-cluster
  overhang and shifts the card right so card+emblems read centered.
- Card outer border now colored by `battleType` (the bug fix — `updateCardFrame` doesn't
  set it; controller does, matching the battle preview).

Remaining nicety (optional): icon/outline thickness tuning is a constant in `Hud`.

**Depends on:** Phase 4 (collection data).

---

## Deferred / Future (out of scope for this plan)

- **Cross-server matchmaking** (MemoryStore queue, server registry, teleport,
  reservations) per IDEA_MATCHMAKING — its same-server table-ownership pieces are
  built here; the cross-server layer is a later plan.
- **Spectator visuals:** 3D cards laid on the physical table + bystander battle-UI.
  The battleId/spectator *data path* is architected in Phase 1; rendering is deferred.
- **Deck builder** is no longer deferred; it is implemented as part of Card Library.
  Remaining work is manual mobile/desktop polish and fuller automated UI-helper tests.
- **Reconnect into an in-progress battle** (currently a disconnect ends the match).

---

## Open questions (resolve before the relevant phase)

- **PVP handshake exact shape (Phase 2): RESOLVED** — explicit mutual `ReadyUp`
  starts the duel after both players are seated.
- **Seating mechanism (Phase 2): RESOLVED** — native `Seat` disabled; **one** state-driven
  table `ProximityPrompt` per table (server auto-picks the empty chair), server-validated
  (A3). No "Stand Up" prompt; seated player uses the Leave Seat button. Seating is chained
  via `awaitSeated` (no anchoring).
- **Turn timer length (Phase 3): RESOLVED** — default `TURN_TIMEOUT_SECONDS = 60`;
  `MAX_TIMEOUTS_BEFORE_FORFEIT = 2`. Both live in `DuelSession` as config constants.
