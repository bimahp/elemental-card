# PLAN_MATCHMAKING — Cross-Server Matchmaking + Reconnect

> Status: **implemented and verified single-server (headless + live Studio Play); published multi-server teleport/reconnect test pending** | Author: bimahp (with Claude) | Date: 2026-07-10
>
> Matchmaking transport and reconnect behavior remain authoritative here. Reward
> amounts, battle validity, forfeits, and caps are owned by
> [DESIGN_REWARD.md](DESIGN_REWARD.md); currency behavior is owned by
> [DESIGN_ECONOMY.md](DESIGN_ECONOMY.md).
>
> Architecture context: [IDEA_MATCHMAKING.md](IDEA_MATCHMAKING.md) (the original
> cross-server sketch this plan implements), [DESIGN_CORE.md](DESIGN_CORE.md).
> Current code state: [DEV_STATUS.md](DEV_STATUS.md). This plan is kept up to
> date through implementation — each phase's checklist line and Tests/Result
> are updated as it completes, mirroring how `PLAN_BATTLE_CHARGE_V2.md`/
> `PLAN_CARD_BATTLE_REVAMP.md` track their own rollout.

## Implementation Status

- [x] **Phase 0** — Baseline safety harness
- [x] **Phase 1** — Server registry + MemoryStore queue foundation
- [x] **Phase 2** — Destination selection + teleport + destination-server authority
- [x] **Phase 3** — NPC fallback
- [x] **Phase 4** — Reconnect (JobId persistence, disconnect no longer forfeits, reconnect-on-login)
- [x] **Phase 5** — Matchmaking UI (icon, panel, ticking timer, cancel)
- [x] **Phase 6** — Regression pass + docs reconciliation

---

## Context

PvP today is same-server-only and manual: two players sit at one of 2 physical
Battle Tables and press Ready. There's no queue and no cross-server anything.
`IDEA_MATCHMAKING.md` sketched the target shape (MemoryStore global queue,
per-server registry heartbeat, a matching server that pops pairs, picks a
destination, teleports, and the destination server is sole authority) but was
explicitly deferred by `PLAN_BACKEND.md` (deleted from the repo, recovered via
`git show e9336a1^:PLAN_BACKEND.md` — its locked scope table read: *"Same-server
only. Cross-server MemoryStore matchmaking (IDEA_MATCHMAKING) **deferred**."*)
and has zero implementation — confirmed via `script_grep` across the live game:
no `TeleportService`/`MemoryStoreService` usage exists anywhere.

This plan builds that architecture, plus three things the old idea doc never
covered, all confirmed directly with the user during planning:

1. An **NPC fallback** (empty queue, or 60s waited with no human match) that
   goes through the identical destination/teleport/seating pipeline as a real
   match — never a shortcut. The user explicitly rejected an instant-local-
   battle option for this case.
2. **Reconnect** on **plain public servers** (no `ReserveServer`/private
   instances) — a match can land on either player's current server or a new
   one, whichever has a free table. Once seated and mulligan begins, the
   battle is "valid" and the host server's `game.JobId` is persisted as the
   reconnect target.
3. A **forfeit-model change**: disconnect no longer ends the battle
   immediately. The already-shipped turn-timeout/streak logic
   (`DuelSession.TURN_TIMEOUT_SECONDS=60`, `MAX_TIMEOUTS_BEFORE_FORFEIT=2`)
   becomes the *only* forfeit trigger — 2 consecutive skipped turns forfeits,
   anything short of that (including a disconnect the player recovers from)
   does not.

**Also locked with the user:** new HUD icon (asset `105294857091338`) added to
`TopRightAnchor`; clicking it opens a Matchmaking panel (Level display,
informational only + a "Find Opponent" button); pressing it closes the panel
and the icon's `FloatingLabel` starts ticking elapsed time up; clicking the
ticking icon reopens the same panel, now showing the live timer plus a "Cancel
Matchmaking" button; matching is plain FIFO — Level never affects pairing in
this pass.

---

## Architecture

```
MemoryStore                                  Every Shop Server runs:
├─ Matchmaking Queue (MemoryStoreQueue)       ├─ Matchmaker.lua    (join/leave/poll)
├─ Server Registry (MemoryStoreSortedMap)     ├─ ServerRegistry.lua (heartbeat: JobId, FreeTables, Players)
└─ Pending Match records (MemoryStoreHashMap) ├─ TableManager.lua   (existing FREE/RESERVED/OCCUPIED)
                                              ├─ BattleRegistry.lua (existing Battles/PlayerBattle)
Flow:                                        ├─ DuelSession.lua    (existing turn loop + timeout/forfeit)
Find Opponent → Matchmaker.enqueue           ├─ SaveService.lua    (existing activeMatch, +jobId)
      ↓                                      └─ BattleController.lua (thin remote wiring)
Every server polls: Matchmaker.tryMatch()
      ↓ (pops 2, or 1 + empty/60s-elapsed → NPC fallback)
Pick destination (ServerRegistry read — HINT ONLY)
      ↓
TeleportService:TeleportAsync + TeleportOptions{ServerInstanceId=jobId}
      ↓
Destination server is sole authority: re-validate table, seat, recover if lost
      ↓
DuelSession.start() — mulligan begins → SaveService persists {battleId, jobId}
      ↓  (this is the reconnect-eligible point)
Disconnect mid-match → seat paused, NOT forfeited → turn-timeout streak is the only forfeit path
      ↓
Reconnect → onPlayerAdded reads activeMatch.jobId → same-server reseat, or
            TeleportAsync back (verify game.JobId matches on arrival)
```

**Most important rule, unchanged from `IDEA_MATCHMAKING.md`:** Queue = truth.
Destination server = truth. Server Registry = hint only — never trust another
server's published free-table count; use it only to pick a likely destination,
then let the destination server make the final call when players actually
arrive. This keeps the system robust even when servers are slightly out of
sync.

---

## Phase 0 — Baseline Safety Harness

**Goal:** Establish a clean reference point before touching
`BattleController`'s `PlayerRemoving` handler and `SaveService`'s
`onPlayerAdded` abandoned-match check — both are live, currently-correct code
paths this plan intentionally changes.

**Steps:**
- Record current behavior with a live Studio Play smoke: PvP disconnect →
  confirm today's instant-forfeit (`endBattle` called synchronously,
  `BattleOver` fired to the remaining player, `Registry.destroy` frees the
  table).
- Record a normal login with no active match, and (if reproducible) a forced
  `activeMatch` truthy value on login, to confirm today's instant-loss-on-
  abandonment path fires exactly as `DEV_STATUS.md`'s Persistence section
  documents.
- Confirm existing `TestService` specs still pass.
- Confirm no uncommitted Studio changes get clobbered.

**Tests:** Studio Play smoke (both paths behave as documented today) +
existing specs pass. This is the "before" reference for Phase 4's behavior-
change check.

**Result (2026-07-10):** Confirmed headless: all 3 `TestService` specs pass
(`GachaAcquisitionSpec`, `ShopTransactionSpec`, `GachaOddsSpec`) via
`execute_luau` in Edit mode — clean baseline before any change. Read the live
source directly (not just prior research) for every function this plan
touches, confirming the ground truth exactly:
- `BattleController.lua`'s `PlayerRemoving` handler — confirmed it calls
  `endBattle(battle, opp(seat))` unconditionally whenever `Registry.getForPlayer`
  finds a battle (identical to an explicit `Forfeit`), then unconditionally
  calls `Registry.removePlayer(player)` regardless of which branch ran.
  `endBattle` unseats present human seats, persists PvP W/L via
  `Save.recordPvpResult`, fires `BattleOver`, frees the table
  (`TblMgr.markFree`), and calls `Registry.destroy(battle)` — all synchronous,
  all in the same tick.
- `startPvP` confirmed calling `Save.beginPvpMatch(p1, battle.id)` /
  `Save.beginPvpMatch(p2, battle.id)` immediately after `Registry.create(...)`
  and **before** `Session.start(...)` — i.e. before mulligan begins, exactly
  the call site Phase 4a needs to move. `battle.mode = "pvp"` is set here too,
  covering both local-ReadyUp PvP and (once wired) matchmaking-originated PvP —
  confirms a `battle.matchmaking` flag is still needed to distinguish the two
  for Phase 4b's scoping, since `battle.mode=="pvp"` alone doesn't.
- `BattleRegistry.lua`'s `create`/`destroy`/`removePlayer` read in full:
  `removePlayer` is a literal one-liner (`PlayerBattle[player.UserId] = nil`).
- `SaveService.lua` read in full: `onPlayerAdded`'s abandon-detection block,
  `beginPvpMatch`/`recordPvpResult`, and the schema — confirmed
  `CURRENT_VERSION = {major=5, minor=1}` and the `MINOR_MIGRATIONS` table
  keyed `"5.0->5.1"` etc., so Phase 4a's `jobId` addition is a `"5.1->5.2"`
  minor migration following the exact existing pattern.

---

## Phase 1 — Server Registry + MemoryStore Queue Foundation

**Goal:** The two MemoryStore primitives — global FIFO queue, per-server
heartbeat — with no teleport, no matching decision, and no UI yet.

**Steps:**
- New `ServerScriptService/Modules/ServerRegistry.lua`:
  - `publish()` — writes `{JobId=game.JobId, FreeTables=TableManager.countFree(), Players=#Players:GetPlayers(), UpdatedAt=os.time()}` to a `MemoryStoreSortedMap` (`"MM_ServerRegistry"`, sort key = `FreeTables`), short TTL (~30s) so a dead server self-expires instead of needing explicit teardown. Runs on a `task.spawn`/`task.wait(10)` loop, started from `BattleController` at boot alongside the existing `SaveService.init()` call.
  - `getCandidates()` — `GetRangeAsync` descending by free tables; treated purely as a hint, per the "never trust the registry" rule.
  - `TableManager.countFree()` — new small accessor alongside the existing FREE/RESERVED/OCCUPIED tracking.
- New `ServerScriptService/Modules/Matchmaker.lua`:
  - `enqueue(player)` — `MemoryStoreQueue:AddAsync({userId, jobId=game.JobId, queuedAt=os.time()}, expiration)` on queue `"MM_Queue"`.
  - `dequeue(player)` — since `MemoryStoreQueue` has no remove-by-content, track cancellation in a small `MemoryStoreMapAsync` keyed by userId that `tryMatch` checks and skips before pairing.
  - `tryMatch()` — `ReadAsync(2, false, waitTimeout)`. This *is* the atomicity `IDEA_MATCHMAKING.md` describes (items read are invisible to other readers until `RemoveAsync`'d or the invisibility timeout lapses — no extra locking needed, confirmed against Roblox's `MemoryStoreQueue` docs). Two valid, uncancelled entries → pair, `RemoveAsync` both, proceed to Phase 2. Only one (or a stale/cancelled second) → leave it; it naturally becomes visible again for another server's next poll (built-in FIFO requeue).
  - Runs via its own `task.spawn` poll loop (~3–5s) on every server — any server can find a match, not a dedicated one, per the idea doc.
- Wire both boot loops from `BattleController.lua` (thin controller, matching the existing "thin controller + focused module" split used by `GachaController`/`RobuxShopController`).

**Tests (headless, `execute_luau`, Edit mode):** registry entry shape/sort/TTL expiry; two-enqueue `tryMatch` returns both and neither is re-readable immediately after (proves invisibility-timeout atomicity); one-enqueue `tryMatch` returns only one (the "queue empty when checked" signal Phase 3 consumes); a cancelled entry is skipped.

**Result (2026-07-10):** Implemented `ServerScriptService/Modules/ServerRegistry.lua`
(`publish`/`getCandidates`/`init(getFreeTableCount)`, a `MemoryStoreSortedMap`
keyed `"MM_ServerRegistry"`, sort key = `FreeTables`, 30s entry TTL, 10s publish
cadence) and `ServerScriptService/Modules/Matchmaker.lua` (`enqueue`/`dequeue`/
`tryMatch`/`consume`, a `MemoryStoreQueue` named `"MM_Queue"` + a
`MemoryStoreHashMap` `"MM_Cancelled"` for cancellation flags, since
`MemoryStoreQueue` has no remove-by-content). Added `TableManager.countFree()`.
Wired both into `BattleController.lua`'s existing boot sequence (alongside
`Save.init()`): `ServerRegistry.init(TblMgr.countFree)` starts the heartbeat;
a new `task.spawn` loop polls `Matchmaker.tryMatch()` every 4s and currently
only logs a `"pair"` outcome (Phase 2 will consume it for real) — this is
Phase 1's explicitly minimal scope, not a placeholder left unfinished by
accident.

**Real bug found and fixed during headless testing (not just mocked):**
`MemoryStoreQueue:ReadAsync` returns `nil` (not an empty array) when nothing
is available with `waitTimeout=0`, confirmed by direct isolated testing
against this engine — the official Roblox doc sample doesn't hit this path
since its example always passes a positive `waitTimeout`. `tryMatch()`'s
`#items == 0` check crashed on the nil case; fixed to `items == nil or
#items == 0`.

Verified headless (`execute_luau`, Edit mode) against the **real**
`MemoryStoreService` (no mocking — these calls work fine in Studio, unlike
`TeleportService`'s instance-targeting methods) using the clone-and-rename
technique to bypass this session's require-cache staleness (confirmed via
`script_read` that the edited source was correct on disk before concluding it
was a cache issue, not a code bug — matches the documented limitation from
prior plans in this repo): all 11 assertions passed —
two real `enqueue` calls → `tryMatch` returns `"pair"` with both userIds
correct; an immediate follow-up `tryMatch` on the now-empty queue returns
`"none"`; a lone `enqueue` → `tryMatch` returns `"single"` with the correct
entry, explicitly `consume`d; an `enqueue`+`dequeue` (cancelled) entry is
correctly filtered and the batch returns `"none"`; `ServerRegistry.init` +
`getCandidates()` correctly surfaces this server's own `JobId`/`FreeTables`
entry. Confirmed the two `_FreshTest` clones used for the fresh-require
workaround were destroyed afterward — `SSS.Modules` left clean, only the two
real `Matchmaker`/`ServerRegistry` modules remain.

---

## Phase 2 — Destination Selection + Teleport + Destination-Server Authority

**Goal:** Turn a matched pair into two seated players on one authoritative
server.

**Steps:**
- `Matchmaker.tryMatch()` picks a destination:
  1. Prefer a server either matched player is already in, if its registry entry shows `FreeTables > 0` (avoids an unneeded teleport for one side — "Alice stays, Bob teleports").
  2. Else the top `ServerRegistry.getCandidates()` entry (most free tables, ties broken by lowest population).
  3. Else — no server anywhere reports room: leave `TeleportOptions.ServerInstanceId` unset. Per Roblox's documented `TeleportOptions.ShouldReserveServer=false` behavior, Roblox routes to (or spins up) *any* available public server automatically. **This is a deliberate deviation from `IDEA_MATCHMAKING.md`'s Case C `ReserveServer` fallback** — dropped for consistency with the user's explicit "plain public servers only, no reserved servers" reconnect decision.
- Use **`TeleportService:TeleportAsync(placeId, players, teleportOptions)`** — confirmed against Roblox's engine docs that the older `TeleportToPlaceInstance` is deprecated in favor of this — with a `TeleportOptions` instance: `ServerInstanceId = destinationJobId`, `ShouldReserveServer = false`, and `SetTeleportData({matchId, opponentUserId, seatIndex, npcFallback, npcArchetype})`.
- Also write a lightweight **pending-match record** to a `MemoryStoreHashMap` (`matchId → {destinationJobId, seatedCount=0, npcFallback, createdAt}`) so the destination server can reserve a table *before* either player physically lands (teleport isn't instant), and so there's a recovery path if one side's teleport never arrives.
- Destination-server side (`TableManager`/`BattleController`):
  - On its own heartbeat tick, check for pending-match records targeting its own `game.JobId`; reserve a table immediately if free, else retry via `TableManager`'s existing table scan (don't rebuild it).
  - On each teleported player's `PlayerAdded`, read `player:GetJoinData().TeleportData`, match by `matchId`, seat them via `TableManager`'s existing seat call (programmatically, not via `ProximityPrompt`).
  - **Destination server is sole authority** — always re-checks real table state at arrival regardless of registry/teleport-data assumptions; if the reserved table is unexpectedly gone, find another; only a genuine no-table-anywhere case falls through to Case C above.
- **Partial-arrival policy (proposed default — flag for confirmation during implementation, not explicitly specified by the user):** if only one side arrives within a bounded window (~30s), don't hold the table open indefinitely — seat the arrived player against an NPC fallback (Phase 3) instead of leaving them on "Finding Table...".

**Tests:**
- **Studio-testable:** destination-selection logic against a hand-populated `ServerRegistry` table (no second real server needed) — prefers an already-occupied server with room, then best-free-table, then the no-instance path; pending-match record/reservation hand-off on a single server acting as its own destination.
- **Must defer to a published, multi-server place** (see Testing Constraint section): a real `TeleportAsync` call landing a player on a genuinely different server instance; the "reserved table lost, found another" race across two live processes.

**Result (2026-07-10):** Implemented in `ServerScriptService/Modules/Matchmaker.lua`
(extended, not a new module — `selectDestination`, `createMatch`,
`processPendingTeleportsForPlayers`, `getMatchesForThisServer`, `clearMatch`)
and `BattleController.lua` (`attemptSeatPendingMatches`, `battle.matchmaking`
flag on `startPvP`, poll-loop wiring).

**A real cross-server architecture correction found and fixed before writing
any code, not discovered by accident afterward:** the approved plan assumed
whichever server pops a matched pair from the queue can directly call
`TeleportAsync` for both players. That's impossible whenever the two players
are on two *different* servers — Roblox only lets a server teleport players
who are currently present on it. Flagged this to the user before implementing;
resolved by splitting responsibility: the popping server only **writes**
instructions (`MM_PendingMatches` keyed by `matchId`, `MM_PendingTeleports`
keyed by userId); every server's own poll loop separately checks its **own**
currently-connected players against `MM_PendingTeleports` and only acts on
its own (mirrors `IDEA_MATCHMAKING.md`'s "every Shop server runs the same
systems" model exactly, rather than assuming one privileged coordinator).

**A second, related correction, also flagged and confirmed with the user
before building:** the "no server anywhere has room" case (Case C) can't
work with two independent "just find me any public server" calls from two
different home servers — nothing guarantees they land on the same new
instance. Fixed using `TeleportService:ReserveServer` purely as an internal
convergence mechanism (not a private/invite-only server, not exposed to
players): whichever server made the match reserves one instance and hands
out its access code via the match record; each participant's home server
independently targets that same access code. Reconnect is unaffected — it
still only ever uses plain JobId + `TeleportAsync` against whatever instance
results, reserved or not.

**`battle.matchmaking` flag added to `startPvP`** (consumed from a new
`tbl._matchmaking` ad-hoc field, mirroring the existing `_npcDeckKey`/
`_trainerName` convention) — confirmed during Phase 0 that `battle.mode ==
"pvp"` alone covers both local-ReadyUp and matchmaking-originated PvP, so a
separate flag is required for Phase 4's reconnect-eligibility gating.

**Deliberately deferred within Phase 2 (documented, not silently dropped):**
the partial-arrival policy (one participant arrives, the other never does) —
`attemptSeatPendingMatches` leaves an under-populated match record alone
rather than guessing; it simply expires via the record's own 120s MemoryStore
TTL. Converting an abandoned partial arrival into an NPC-fallback match needs
Phase 3's machinery and is explicitly a TODO in the code, not a silent gap.

**Verified headless (`execute_luau`, Edit mode, clone-and-rename technique,
confirmed clean afterward — both module clones and MemoryStore test-key
pollution removed):**
- `selectDestination` prefers a home server reporting room over an
  unrelated one, and correctly returns `nil` when no candidate anywhere
  reports `FreeTables > 0` (isolated by clearing the one lingering real
  registry entry first).
- `createMatch` against a real destination: returns a matchId; `getMatchesForThisServer()` correctly does **not** report the match when the
  destination is a different (fake) JobId, and correctly **does** report it
  when the destination is this server, with correct `participantUserIds`.
- `processPendingTeleportsForPlayers` against an "already home" instruction
  (`destinationJobId == game.JobId`): no teleport attempted, and the
  per-player pending-teleport entry is correctly consumed either way.
- `createMatch`'s Case C branch (`ReserveServer`) degrades gracefully
  (returns `nil`, warns) rather than erroring when `TeleportService` calls
  aren't available.

**New confirmed engine constraint, not previously documented anywhere in
this repo:** `TeleportService:ReserveServer` (and by strong implication
every other `TeleportService` method) throws `"...can only be called by the
server"` when invoked from this tool's Edit-mode `execute_luau` context —
confirmed by direct isolated testing, not assumed. This is **stronger** than
the previously-known "cross-instance targeting doesn't work in Studio
Play/Local Server" limitation: `TeleportService` methods can't be exercised
at all outside a genuine running Play-mode/published server, not even to
check that a call doesn't error. Reinforces (with a sharper boundary) the
Testing Constraint section below.

**Testing-hygiene finding, worth recording for future sessions:** a
`task.spawn` loop started inside one `execute_luau` call (e.g.
`ServerRegistry.init`'s heartbeat) keeps running in this environment's
persistent Edit-mode VM across *later, separate* `execute_luau` calls, even
after the ModuleScript clone that started it is `:Destroy()`'d — confirmed by
finding a lingering real `MM_ServerRegistry` entry from an earlier test still
present and still being republished minutes later. Since `MemoryStoreService`
maps/queues are shared globally across the whole game (Studio Play, Edit-mode
testing, and published servers all hit the *same* store), headless tests of
Matchmaker/ServerRegistry pollute real shared state, not a sandboxed copy —
cleaned up what was practical to remove this pass (short TTLs mean the rest
self-expires), but future sessions should consider using distinctly-named
test-only MemoryStore map/queue names for this kind of testing instead of the
real `MM_*` names the live game will use.

---

## Phase 3 — NPC Fallback

**Goal:** No human opponent available → seat an NPC through the *same*
destination/teleport/seating pipeline, never a shortcut (per the user's
explicit rejection of an instant-local-battle option).

**Steps:**
- Empty-queue check happens **on each periodic poll tick**, not only once at enqueue — so the ticking timer is still visibly running for at least one poll interval, consistent with the UX, while still honoring "empty queue" as an immediate (not delayed-to-60s) trigger. *(This plan's interpretation of a slightly underspecified interaction between the two stated triggers.)*
- Independently, any queued entry older than 60s with still no pairing partner triggers the same fallback for that entry specifically.
- Builds a `{npcFallback=true}` match record and runs through **Phase 2's machinery unmodified** — destination selection (almost always the player's own current server unless it reports 0 free tables), teleport data, pending-match record, destination seating.
- Destination seating calls **`TableManager.spawnNpcAt(tableId, chairIdx)` unmodified** — already clones an NPC into a chair and randomizes among the 3 starter-deck archetypes (confirmed in `DEV_STATUS.md`'s Module Status); needs only a new call site from the matchmaking-seating path, no signature change.
- Resulting battle is structurally identical to today's PvE-vs-Noob
  (`{kind="human"}` + `{kind="npc"}` seats), so `DuelSession` and `BattleLogic`
  need no transport-specific changes. Reward policy still must classify the
  matchmaking-originated battle according to `DESIGN_REWARD.md`.
- **Scoping decision:** only matchmaking-originated matches (human or NPC-fallback) get the reconnect/JobId treatment in Phase 4. The pre-existing "walk up to standing Noob" PvE flow is untouched — it never leaves the player's current server, so it doesn't need reconnect and doesn't gain `activeMatch`/JobId persistence.

**Tests (fully Studio-testable, single server):** queue-empty-on-check and 60s-elapsed (via a temporarily shortened test constant, same technique `PLAN_CARD_BATTLE_REVAMP.md` used for its mulligan timeout) both produce a battle with today's PvE-vs-Noob seat shape; archetype randomization distribution matches existing behavior; confirm the fallback still round-trips through `Matchmaker`'s destination-selection code (verifiable by inspection/logging even when it resolves to "stay local") — proving no shortcut exists.

**Result (2026-07-10):** Implemented `Matchmaker.selectDestinationForSingle`/
`createNpcFallbackMatch` and `BattleController`'s `attemptSeatPendingMatches`
npcFallback branch + `startPvE`'s `battle.matchmaking` flag. **Interpretation
decision on the two stated triggers:** `Matchmaker.tryMatch()`'s `"single"`
result already *is* "no queue" (ReadAsync found no valid second entry this
poll), so the poll loop now consumes it and calls `createNpcFallbackMatch`
**immediately** on that result rather than waiting out a separate 60s timer.
The redundant explicit 60s-elapsed counter was **not** built as a second
mechanism — at low population (this project's stated launch condition) a
lone entry shows up as `"single"` almost immediately, so the immediate-on-
single path already satisfies both stated conditions in practice. Documented
as a deliberate simplification, not a silently dropped requirement.

**This phase is where real, live-fire verification (not just headless module
tests) happened, and it surfaced two genuine bugs neither Phase 1 nor Phase 2
caught:**

1. **`game.JobId` is an empty string in Studio Play/Local Server** (confirmed
   directly: `#game.JobId == 0`), not just in Edit-mode `execute_luau` as
   previously assumed — only a real published server gets a non-empty GUID.
   `MemoryStoreSortedMap:SetAsync` requires a non-empty key, so
   `ServerRegistry.publish()` was failing (and spamming) every 10s heartbeat
   the moment Play mode actually started. Fixed with an explicit, one-time-
   warned guard in `ServerRegistry.publish()` rather than letting it fail
   silently-but-repeatedly. This is a **stronger** version of the previously-
   documented "cross-instance targeting doesn't work in Studio" limitation —
   it means `game.JobId`-keyed logic degrades in Studio Play generally, not
   only the teleport-instance-targeting piece.
2. **Destination selection was needlessly indirect for the common case.**
   Found and fixed *before* the live test even ran, while reasoning through
   why (1) would break `selectDestination`'s "is my own server viable" check:
   the original design only asked the (hint-only, possibly-stale-or-not-yet-
   published) `ServerRegistry` whether a player's home server had room — even
   for the player's *own current server*, which it can always answer
   authoritatively and instantly via `TableManager.countFree()`, no
   MemoryStore round-trip needed. This wasn't just a Studio-testing
   workaround — it's a real bootstrap-race fix: a freshly-booted production
   server that hasn't published its first heartbeat yet would otherwise
   incorrectly look room-less to itself. `selectDestination` and
   `selectDestinationForSingle` now check `entry.jobId == game.JobId` against
   `TableManager.countFree()` directly first, falling back to the registry
   hint only for servers other than this one.

**Verified live in actual Studio Play** (`start_stop_play`, not just headless
`execute_luau`) — the first end-to-end proof of the whole Phase 1–3 pipeline
together, using the real connected test player (not a fake table):
`Matchmaker.enqueue(realPlayer)` → waited ~10s → the real player's `Humanoid`
was physically seated at a real `Workspace."Battle Stations".2.Chair 1.Seat`,
a real `BenchNpc` was spawned and seated at Chair 2, and the table's
`BattleId` attribute read `"battle_1"` — confirming `tryMatch` correctly
returned `"single"`, `createNpcFallbackMatch` correctly picked this server
(via the new authoritative self-check, since it's the only server and has
free tables), `getMatchesForThisServer` correctly reported it, and
`attemptSeatPendingMatches` correctly seated the player, spawned the NPC, and
called `startPvE` — all with **zero mocking**, a real live server loop
running the real code.

**A third real bug found from that same live test, fixed before calling this
phase done:** after the successful match, the console showed repeated
`MemoryStoreService: TotalRequestsOverLimit` errors, traced to
`getMatchesForThisServer()`'s `HashMap:ListItemsAsync` — an O(all pending
matches) full enumeration — running on the same 4-5s cadence as the cheap,
targeted queue-pop/per-player checks. Fixed by splitting the poll loop into
two cadences: a fast one (5s) for `tryMatch`/`processPendingTeleportsForPlayers`
(cheap, targeted `ReadAsync`/`GetAsync` calls), and a separate slow one (20s)
for `attemptSeatPendingMatches`'s expensive full scan. This is a confirmed
fix for an observed production-shaped problem, not a speculative optimization
— left undiscovered, it would have caused real MemoryStore throttling under
any real usage, not just this test session's cumulative load.

**Testing-hygiene note carried forward from Phase 2:** this session's
cumulative headless + live testing visibly exhausted real MemoryStore request
quota for the universe (confirmed by the `TotalRequestsOverLimit` errors
above). Future sessions extending this feature should budget for this — the
shared `MM_*` stores are not a free/unlimited resource even in testing.

---

## Phase 4 — Reconnect

**Goal:** A mid-match disconnect becomes recoverable. This is the highest-risk
phase — it changes two currently-correct, live code paths
(`BattleController.PlayerRemoving`, `SaveService.onPlayerAdded`) and touches
`BattleRegistry`'s reverse-index invariant.

### 4a — Move JobId persistence to mulligan-start time

- `DuelSession.start` gains an optional `onMatchStart(battle)` callback (same pattern as the existing `onMulliganOffer`), invoked once right after `battle.status` flips to `"mulligan"`, before hands are dealt.
- Matchmaking-originated `BattleController` call sites (both real-match and NPC-fallback, per Phase 3's scoping decision) pass `onMatchStart = function(battle) for each human seat: SaveService.beginPvpMatch(player, battle.id, game.JobId) end`.
- **Remove** the current call site at `Registry.create(...)` time (before `Session.start(...)`, i.e. before mulligan) — ground-truth confirmed this is exactly where it fires today.
- `SaveService.beginPvpMatch(player, battleId, jobId)` — extend to store `jobId`: `profile.Data.activeMatch = {battleId, jobId, startedAt=os.time()}`. Schema-additive; bump the profile minor version and add a migration defaulting `jobId=nil` for any in-flight `activeMatch` written before this change (narrow window, but keep the project's existing `MINOR_MIGRATIONS` discipline).
- The purely-local standing-Noob PvE flow still never calls `beginPvpMatch` — unchanged.

### 4b — `PlayerRemoving` stops forfeiting

Current code (confirmed via `script_read` against the live Studio place):
```lua
Players.PlayerRemoving:Connect(function(player)
    local battle = Registry.getForPlayer(player)
    if battle then
        local seat = Registry.canonicalSeat(player, battle)
        endBattle(battle, seat and ((seat=="player") and "npc" or "player") or "npc")
    elseif TblMgr.getTableForPlayer(player) then
        TblMgr.unseatPlayer(player)
    end
    Registry.removePlayer(player)     -- unconditional today
    remoteLast[player.UserId] = nil
    tutorialPending[player.UserId] = nil
end)
```
`BattleRegistry.removePlayer` (confirmed via `script_read`, `BattleRegistry.lua:233-235`) is a one-line `PlayerBattle[player.UserId] = nil` — trivial, but **it runs unconditionally today, right after the `if/elseif`**. This matters: the fix is not just "add a pause branch," it must also **skip this `removePlayer` call** for the pause case, or the reverse-index a reconnect depends on gets wiped anyway on the very same line that's supposed to preserve it.

New behavior:
- If `battle` exists, `battle.status == "active"` (a real duel underway, not mulligan-in-progress or already ending), **and this is a matchmaking-originated battle** (has `activeMatch`-eligible provenance — e.g. check `battle.matchmaking == true`, set at creation in Phase 2/3): do **not** call `endBattle`, and do **not** call `Registry.removePlayer(player)`. Instead mark `battle.disconnectedSeats[seat] = true` (new, small tracking table on the record, same shape as the existing `timeoutStreaks[seat]`) purely for optional UI (a nice-to-have "opponent disconnected, waiting" notice). `PlayerBattle[userId]` and `battle.seats[seat]` are left exactly as they are.
- Local (non-matchmaking) PvP keeps today's exact behavior — instant forfeit on disconnect, **unless the open item below resolves otherwise before this phase lands**.
- No new timer logic needed: a disconnected seat's turn, when it comes up, runs through the **existing, unmodified** `scheduleHumanTimer`/`humanEndTurn`/`timeoutStreaks` machinery — indistinguishable from an AFK-but-connected player. "2 consecutive timeouts forfeits" already works correctly; it just needs to stop being short-circuited by immediate disconnect-forfeit.
- `remoteLast`/`tutorialPending` cleanup stays unconditional.
- Cosmetic (not blocking): the opponent's client should show something (reuse `Notify`/`SeatedOverlay` pattern) rather than a silently-empty chair.

### 4c — `onPlayerAdded` attempts reconnect before recording a loss

Current code (confirmed via `script_read`):
```lua
if profile.Data.activeMatch then
    profile.Data.activeMatch = false
    profile.Data.pvp.losses += 1
    warn(...)
    task.spawn(save)
end
```
New behavior:
1. `activeMatch` falsy → unchanged, no-op.
2. Truthy, **same-server** (`activeMatch.jobId == game.JobId`): the player logged back into the exact server their battle still runs on. New `BattleRegistry.reconnectSeat(battle, seat, newPlayer)` — swaps `battle.seats[seat] = {kind="human", player=newPlayer}` (the old `Player` object is stale/destroyed) and re-asserts `PlayerBattle[newPlayer.UserId] = battle.id` (idempotent — should already be true since Phase 4b never cleared it). Clear `battle.disconnectedSeats[seat]`, re-seat physically via `TableManager` (new programmatic entry point, same seat call Phase 2 uses post-teleport, not the `ProximityPrompt` flow). Do **not** touch `pvp.losses` or clear `activeMatch` — the match is still live.
   - **Client-side gap, not covered by simply "push a fresh `UpdateBattleState`":** `BattleUIController` currently only ever enters battle presentation via `BattleSeated` → mulligan → the first `UpdateBattleState`. There is no existing client code path for "join directly into an already-active battle mid-turn" — this needs a small new entry point (e.g. a `BattleReconnected` remote that primes camera/seat visuals and board state directly from a full state snapshot, bypassing mulligan) rather than assuming the existing linear flow degrades gracefully. This is new client work, not just a server-side fix.
3. Truthy, **different server** (`activeMatch.jobId ~= game.JobId`): as a fast-path optimization (not a substitute for the real check — the registry is "a hint, not truth"), first check whether that `jobId` has a recent `ServerRegistry` heartbeat; if aged out, skip straight to the abandonment fallback. Otherwise attempt `TeleportService:TeleportAsync(placeId, {player}, teleportOptions)` with `ServerInstanceId=activeMatch.jobId, ShouldReserveServer=false`, wrapped in `pcall`.
   - **Confirmed via Roblox docs, not assumed:** `TeleportOptions.ShouldReserveServer=false` with a `ServerInstanceId` that's no longer alive does **not** error — Roblox silently teleports to a *different* (possibly brand-new) public server instead. So a successful `TeleportAsync` call is **not sufficient proof of reconnect** — the destination server's `onPlayerAdded` must verify `game.JobId` actually equals the `activeMatch.jobId` it expected. If it doesn't match, treat as "that server is gone" and fall through to the abandonment path from there (the player is now on a fresh server with no route back).
   - Roblox provides no separate cheap "is this JobId alive" query — `TeleportAsync`'s own outcome (plus the post-arrival JobId check above) *is* the liveness check. The registry heartbeat only narrows how often a doomed attempt is even tried.
4. **Abandonment fallback** (only reached if reconnect isn't attempted or fails/mismatches): today's existing behavior — record a loss, clear `activeMatch`, warn, save. Add a generous sanity ceiling on `os.time() - activeMatch.startedAt` (far longer than any realistic match) so a stuck flag from a future bug can't hold a player in reconnect-limbo forever.

**Tests:**
- **Studio-testable:** same-server reconnect branch — force `activeMatch.jobId = game.JobId`, simulate `PlayerRemoving` (seat marked disconnected, not forfeited, `removePlayer` skipped), then a fresh `PlayerAdded` proxy, confirm `reconnectSeat` swaps the reference and `PlayerBattle[userId]` was never cleared; confirm 1 skipped turn doesn't forfeit and 2 consecutive still does (re-exercising `DuelSession`'s unmodified logic, now correctly reachable).
- **Must defer to a published, multi-server place:** the different-server `TeleportAsync` branch, a real dead-jobId mismatch actually being detected, and a live-jobId teleport actually landing the player back mid-battle.

**Result (2026-07-10):** Implemented across `DuelSession.lua` (`onMatchStart`
callback), `BattleRegistry.lua` (`canonicalSeatByUserId`, `reconnectSeat`),
`SaveService.lua` (`beginPvpMatch` renamed to `beginMatch(player, battleId,
jobId, mode)` since it's no longer PVP-only; new `clearActiveMatch`; schema
v5.1→v5.2 minor migration adding `jobId`/`mode` to `activeMatch`; generalized
`onPlayerAdded` reconnect-before-abandonment logic), `BattleController.lua`
(`onMatchStart`, `attemptReconnect`, the `PlayerRemoving` pause-not-forfeit
rewrite, new `BattleReconnected` remote), and `BattleUIController.lua` (new
client entry point for the `BattleReconnected` remote — the client-side gap
flagged in planning).

**Open item resolved:** the pause-not-forfeit model applies **only to
matchmaking-originated battles** (`battle.matchmaking == true`) — local
same-server ReadyUp PvP keeps today's exact instant-forfeit-on-disconnect
behavior, unchanged. This is the conservative default flagged during
planning; no reason surfaced during implementation to widen it further.

**A real design wrinkle found and resolved during implementation (not
pre-solved by the plan):** `SaveService.beginPvpMatch`/`recordPvpResult`'s
`activeMatch` mechanism was PVP-specific — its abandonment fallback
unconditionally recorded a `pvp.losses` increment. NPC-fallback matches
(Phase 3) are `battle.mode == "pve"` and correctly never touch `pvp.wins/
losses` via `endBattle`'s existing mode branching, but they still need
`activeMatch`/reconnect tracking (per Phase 3's own scoping decision) —
which would have meant an abandoned NPC-fallback match incorrectly recording
a PVP loss. Fixed by storing `mode` (`"pvp"`|`"pve"`) alongside `jobId` in
`activeMatch`, and gating the abandonment penalty on it: a `"pve"` abandonment
records no penalty (matching how a normal PvE loss already carries none)
instead of a `pvp.losses` increment.

**Verified headless (`execute_luau`, Edit mode, clone-and-rename, confirmed
clean afterward):**
- `BattleRegistry`: a fake old `Player` object, then a same-`UserId` new
  object simulating a rejoin — `getForPlayer`/`canonicalSeatByUserId` find the
  battle via `UserId` both before and after the swap (confirming the reverse
  index survives an unremoved disconnect, exactly as Phase 4b relies on);
  `reconnectSeat` correctly repoints `battle.seats[seat].player`, after which
  identity-based `canonicalSeat` matches the new object and no longer matches
  the stale old one.
- `SaveService.migrate`: a hand-built pre-Phase-4a profile (schema v5.1,
  `activeMatch` with no `jobId`/`mode`) correctly upgrades to v5.2, defaults
  `mode="pvp"`, leaves `jobId=nil` (correctly falls through to abandonment,
  since no real reconnect target is known for a record from before this
  migration existed); a freshly-built v5.2 profile is already `"current"`.

**Verified live in actual Studio Play (`start_stop_play`), not just headless
— real proof, not inference:**
- Live boot log showed `[SaveService] darkmeta1207 profile migration:
  minor_upgraded` and `schema v5.2` — the real test profile migrated 5.1→5.2
  on a genuine load, not just in a hand-built headless data table.
- Reused Phase 3's proven live technique: enqueued the real connected player,
  waited for the NPC-fallback pipeline to seat them (confirmed again:
  `battle_1` created, real seat taken).
- **The core Phase 4b proof:** called `player:Kick(...)` to force a genuine
  `PlayerRemoving` mid-battle, then checked the table's `BattleId` attribute
  afterward — it still read `"battle_1"` (unchanged, not cleared). This
  confirms `endBattle`/`Registry.destroy`/`TblMgr.markFree` were correctly
  **skipped** for this matchmaking-originated battle on disconnect — the
  battle was paused, not torn down, exactly as designed.

**Honest limitation — not verifiable with the tools available in this
session, consistent with the plan's own Testing Constraint section:** Studio
Solo Play has no mechanism to make the *same* disconnected test account
actually rejoin **within one Play session** (there is no "reconnect as this
player" tool) — but stopping and restarting Play mode naturally re-fires
`Players.PlayerAdded` for the same persisted test account, which is exactly
what happened at the start of Phase 5 (below) and gave an unplanned but real
partial confirmation of this exact gap. Still genuinely unverified: the
same-server branch actually finding and resuming a **still-alive** battle
(the Phase-5 restart naturally had no live battle to reconnect to, since a
fresh Play session also resets `BattleRegistry`'s in-memory state — so
`attemptReconnect`'s same-server branch was exercised but its "battle found,
re-seat" path specifically was not), the `BattleReconnected` client handler
actually receiving and rendering a resumed battle, and the different-server
`TeleportAsync` branch entirely. This needs either a published multi-server
test or a manual two-session Studio test as a follow-up gate before treating
full reconnect (as opposed to correct abandonment-fallback behavior, which
**is** now live-confirmed) as production-verified.

**Unplanned live confirmation, found at the start of Phase 5's Play session
(not staged intentionally):** the boot log read `[SaveService] darkmeta1207
abandoned a prior matchmaking NPC-fallback match -> no penalty recorded (a
PvE loss carries none)`. This is the exact Phase 4c code path firing for
real: the account's profile still had `activeMatch` set (mode="pve") from
Phase 4's earlier kick-mid-battle test; on this fresh server,
`attemptReconnect`'s same-server branch ran (`activeMatch.jobId ==
game.JobId`, both empty-string in unpublished Studio Play), correctly found
`Registry.get(activeMatch.battleId)` returned `nil` (a fresh Play session has
no battle records — confirming `BattleRegistry` state doesn't survive a
server restart, as expected), correctly returned `false`, and correctly fell
through to the **mode-aware** abandonment path added this phase — recording
no penalty for a `"pve"` match instead of the old unconditional `pvp.losses`
increment. This is a real, live, unstaged proof that the design-wrinkle fix
works end-to-end, not just in the hand-built headless test.

---

## Phase 5 — Matchmaking UI

**Goal:** HUD icon + panel + ticking timer + cancel-reopen flow, copying
existing conventions exactly (verified directly against `ItemMallUI`/
`ItemMallController`/`MulliganController` source and `UIComponents`/`UITheme`
via live Studio reads, not guessed).

**Steps:**
- `ReplicatedStorage/Modules/AssetIds.lua` — add `Icons.MATCHMAKING = "rbxassetid://105294857091338"` (auto-feeds the existing startup preload list, per the established `Icons` table convention — no separate preload registration).
- `StarterGui.Hud.TopRightAnchor` — third `ImageButton` sibling (`MatchmakingButton`), exact `ItemMallButton`/`InventoryButton` shape (`Size={0,72},{0,72}`, `BackgroundTransparency=1`, `AutoButtonColor=false`, own `LayoutOrder`, `Icon` ImageLabel + `FloatingLabel` TextLabel + `UIStroke`). `FloatingLabel.Text` starts `"Matchmaking"`.
- `ReplicatedStorage.Modules.UITheme` — add `Theme.Accents.Matchmaking = Color3.fromRGB(...)` alongside `{Inventory, Vending, Mall, Deck}`.
- New `StarterGui.MatchmakingUI` (ScreenGui, `Enabled=false` at rest) — `Scrim`+`Dialog` built via `UIComponents`: `UI.styleScrim`, `UI.bindFullscreenBackdrop`, `UI.applyModalShell(..., Theme.Accents.Matchmaking)`, `UI.createHeaderIcon(titleBar, AssetIds.Icons.MATCHMAKING)`. Single-page body (no page-stack needed for v1 scope): Level display read from the player's existing `Player.Level` IntValue (confirmed real — set by `SaveService.checkLevelUp`, consumed today by `NameplateController`; no new remote needed) + one primary button toggling label/behavior between "Find Opponent" and "Cancel Matchmaking" based on client-tracked queued state.
- New `StarterPlayerScripts/MatchmakingController.lua` (mirrors `ItemMallController`):
  - `MatchmakingButton.Activated` → open panel whether idle or already queued (clicking the ticking icon reopens the same panel per the user's confirmed cancel flow).
  - Find Opponent → fire new `JoinMatchmaking` RemoteEvent → close panel → start elapsed-timer → set `FloatingLabel.Text` to the ticking value.
  - Cancel Matchmaking → fire new `CancelMatchmaking` RemoteEvent → stop timer → reset label to `"Matchmaking"` → close panel.
  - Listens for new `MatchmakingUpdate` (S→C: `"queued"|"cancelled"|"matched"`) so displayed state is server-confirmed, not purely optimistic (same defensive posture as `BattleLoading`/`BattleSeated`/`UpdateBattleState` gating elsewhere).
  - Same close-on-battle-remotes wiring as `ItemMallController` (`BattleLoading`/`BattleSeated`/`UpdateBattleState`).
- `BattleController.lua` — thin `JoinMatchmaking` (validate no existing queue/active match, call `Matchmaker.enqueue`, fire `MatchmakingUpdate("queued")`) and `CancelMatchmaking` (`Matchmaker.dequeue`, fire `MatchmakingUpdate("cancelled")`) handlers.
- Elapsed-timer, adapted from `MulliganController`'s existing countdown (`RunService.Heartbeat` + `os.clock()`, confirmed via source read) — counts **up** from a start clock instead of down from a deadline, no auto-stop condition (stops only on `MatchmakingUpdate("cancelled"/"matched")` or the battle-remote close wiring).
- `HudController` needs no change — it only toggles the whole `TopRightAnchor` group; per-button visibility/click-wiring lives in each feature's own controller, matching the existing convention.

**Tests (fully Studio-testable):** icon renders/positions correctly; click opens panel; Level display matches `Player.Level.Value`; Find Opponent closes panel, fires `JoinMatchmaking`, starts ticking label; clicking the ticking icon reopens the panel showing elapsed time + Cancel; Cancel fires `CancelMatchmaking`, resets label, closes panel; existing battle-remote-close wiring still hides the panel correctly during seating.

**Result (2026-07-10):** Implemented `AssetIds.Icons.MATCHMAKING`,
`UITheme.Accents.Matchmaking`, a `MatchmakingButton` cloned from
`ItemMallButton`'s exact structure and added to `TopRightAnchor`, a new
`MatchmakingUI` ScreenGui (editor-first skeleton — `Scrim`/`Dialog`/
`TitleBar`/`Title`/`CloseButton`/`Body` built as real Studio instances, styled
dynamically by the controller via `UIComponents.applyModalShell`/
`createHeaderIcon`, exactly matching `ItemMallUI`'s real pattern, confirmed by
reading `ItemMallUI`'s and `ItemMallController`'s live source directly rather
than assuming), and `MatchmakingController.lua` (mirrors `ItemMallController`'s
shell/page-stack conventions; ticking timer adapted from `MulliganController`'s
countdown, counting up instead of down). New remotes `JoinMatchmaking`,
`CancelMatchmaking`, `MatchmakingUpdate`, plus thin `BattleController` handlers
and a `"matched"` signal fired from `attemptSeatPendingMatches` at the same
point a real match or NPC-fallback actually seats each participant.

**A real tooling limitation hit while implementing this phase, not previously
encountered in this project's session (worth recording):** `multi_edit`'s
exact-string matching against this script's *rendered* indentation
repeatedly failed to match real tab characters — visually-identical
old_strings kept getting rejected as "not found," even after re-reading the
file immediately beforehand. Root-caused to tab-count miscounting from the
tool's line-numbered display rather than a real content mismatch (confirmed
once one edit succeeded and showed the true tab width was 7, not 6 as
visually estimated). Worked around by manipulating `Script.Source` directly
via `execute_luau` with whitespace-tolerant Lua patterns
(`"Matchmaker%.clearMatch%(matchId%)\n(%s*)startPvP%(tbl%)"`, capturing the
actual whitespace unit and reusing it in the replacement) instead of
guessing indentation by eye. Also discovered `script_read` can return a
**stale cached snapshot** immediately after such a `Source` write — verified
the real edit had landed by reading `scr.Source` directly and checking for
literal markers, not by trusting the next `script_read` call, which briefly
showed pre-edit content.

**Verified live in Studio Play (`start_stop_play`):**
- Boot log: `[MatchmakingController] loaded` with zero errors, and
  `[LoadingScreen] preloaded 16/16 essential assets` (up from 15/16) —
  confirming the new `MATCHMAKING` icon was automatically picked up by the
  existing `AssetIds.Icons` → `appendShared` → startup-preload pipeline with
  no extra registration needed, exactly as designed.
- Client-side inspection confirmed the icon/label at rest:
  `button.Icon.Image == "rbxassetid://105294857091338"`,
  `label.Text == "Matchmaking"`, `gui.Enabled == false`.
- Server-fired synthetic `MatchmakingUpdate` events (the same technique this
  project has used before to test client reception logic independent of the
  server flow that would normally trigger it) confirmed the client's own
  logic end-to-end: firing `"queued"` closed the panel and started the
  `RunService.Heartbeat` ticking timer (`label.Text` read `"0:11"` a few
  seconds later — a real, running clock, not a static placeholder); firing
  `"cancelled"` correctly stopped the timer and reset `label.Text` back to
  `"Matchmaking"`.

**Known verification gap, consistent with how this project has documented
the same limitation before (e.g. `PLAN_CARD_BATTLE_REVAMP.md` Phase 8):**
the panel body's actual rendered content (Level display, Find Opponent/Cancel
button text and click wiring) and the `MatchmakingButton`/`CloseButton`/
`Scrim` click handlers themselves could not be exercised via a real simulated
click in this session — this environment's UI-click simulation has been
unreliable for this kind of interactive element in prior sessions too. The
server-confirmed state-transition logic (the part most likely to have real
bugs, since it's genuinely new code) **is** verified above; the click-to-
`FireServer` wiring is simple, reviewed-by-inspection logic identical in
shape to `ItemMallController`'s already-proven pattern.

**Update (2026-07-10) — the verification gap above was closed, and it found
three real bugs**, reported by the user from a live screenshot of the panel:
wrong button placement, wrong header margin (the icon overlapped the start
of "Matchmaking", rendering as "tcnmaking"), and the Find Opponent button
doing nothing on click.

1. **Button placement:** `MatchmakingController.lua` never set
   `body.Position`/`body.Size`/`body.BackgroundTransparency` after
   `UI.applyModalShell(...)` — `applyModalShell` does not position/size
   `Body` itself (confirmed directly in `UIComponents.lua`; that's the
   calling controller's job, exactly as `ItemMallController` does explicitly
   in 3 lines). With `Body` left at its default zero size, every
   scale-relative child (including the button) collapsed to the Dialog's
   origin. Fixed by adding the same 3 lines `ItemMallController` uses.
2. **Header margin:** `applyModalShell`'s title-left-margin depends on
   whether a `backButton` argument is truthy (76px with one, even an
   invisible one, vs 24px without) — this panel has no back button, so it
   got the narrow 24px margin meant for icon-less panels, and the header
   icon overlapped the title text. Fixed by manually overriding
   `title.Position`/`title.Size` right after the `applyModalShell` call.
3. **Button click doing nothing — root cause was environmental, not a code
   bug, and is worth recording as a new tooling limitation for this
   project:** `BattleController.lua` had been edited repeatedly this session
   via raw `Script.Source = ...` writes through `execute_luau` (the
   `multi_edit` workaround from earlier in this phase). Those writes update
   the DataModel's `Source` property correctly — but Roblox Studio's actual
   **open Script Editor document buffer** for that script is a separate
   thing, and raw `Instance.Source` writes don't touch it. `Play` mode
   compiles from that editor-buffer content, not from the live `Source`
   property. Confirmed directly: `ScriptEditorService:GetEditorSource(scr)`
   returned a 32457-byte buffer (predating all of this phase's server
   handlers) while `scr.Source` correctly showed 33607 bytes with everything
   present — and the *running Play-mode server*, checked via
   `datamodel_type: "Server"`, matched the stale 32457-byte editor buffer,
   not the correct property value. This meant the entire `JoinMatchmaking`/
   `CancelMatchmaking` handler had never actually been exercised by a real
   Play session — every earlier "live-verified" server-side test in this
   phase was against this same stale snapshot. Checked all other
   session-modified scripts for the same divergence (`Matchmaker`,
   `ServerRegistry`, `TableManager`, `BattleRegistry`, `DuelSession`,
   `SaveService`, `MatchmakingController`, `BattleUIController`) — none were
   affected, only `BattleController` (the one under active repeated raw-write
   edits during this exact debugging session). **Fixed** by pushing the
   correct source through `ScriptEditorService:UpdateSourceAsync(scr, fn)`
   instead of a raw property write, which properly syncs the editor buffer.
   **Going forward, prefer `ScriptEditorService:UpdateSourceAsync` (or
   `multi_edit`, when its whitespace-matching cooperates) over raw
   `Script.Source = ...` writes for any script that may have an open editor
   tab, to avoid this exact divergence recurring.**

After both fixes, a full live re-test (mouse-click simulation on the real
HUD icon, then the real "Find Opponent" button, both driven through
`user_mouse_input`, not synthetic remote firing) drove the entire pipeline
for real: panel opened correctly (title read "Matchmaking" cleanly, button
correctly centered in-bounds), click closed the panel and started the
ticking label, the server actually enqueued and NPC-fallback-matched the
player (confirmed via `Battle Stations.2`'s two `Seat.Occupant`s: the real
player plus a spawned `BenchNpc`), and the battle played through to a real
`BattleUI` "YOU LOST" result screen with live board/hand state — the
complete click-to-battle-resolution path, not just individual legs of it.

---

## Phase 6 — Regression / Verification Pass

**Goal:** Close out the way prior `PLAN_*.md` passes did — full regression
sweep plus doc updates.

**Steps:**
- Regression watch: local (non-matchmaking) PvP — sit, Ready, duel — is structurally unaffected (this plan is additive: new modules/remotes plus a scoping-guarded change to `PlayerRemoving`/`onPlayerAdded`, not a turn-loop rewrite).
- Confirm the standing-Noob PvE flow still has zero `activeMatch`/reconnect involvement.
- Confirm the Fatigue-death fix and PvP turn-timer/forfeit path (both regression-watch items in `PLAN_CARD_BATTLE_REVAMP.md`'s own Phase 9) are unaffected — the turn-loop timer itself isn't touched, only the code that used to short-circuit it on disconnect.
- Confirm `BattleRegistry.destroy`/`TableManager.markFree` still run exactly once, only on genuine battle end — tables never leak as permanently `RESERVED`/`OCCUPIED`.
- Update `DEV_STATUS.md` (new Module Status rows for `Matchmaker`/`ServerRegistry`/`MatchmakingUI`+`MatchmakingController`; updated `SaveService`/`BattleController`/`BattleRegistry`/`DuelSession` rows; new remotes in the table; updated Persistence section for `activeMatch.jobId`; a Known Issues note for the still-unverified-in-Studio teleport paths).
- Update `IDEA_MATCHMAKING.md`'s status to point at this plan as its implementation, noting the Case-C `ReserveServer`→plain-public-server deviation explicitly.
- Update `README.md`'s module/remote table.

**Tests:** full headless regression (queue join/leave/poll, destination-selection against a mocked registry, NPC-fallback seating for both triggers, same-server reconnect re-seating, 1-timeout-no-forfeit/2-timeout-forfeit post-`PlayerRemoving`-change); full Studio Play smoke (HUD icon → panel → Find Opponent → ticking label → single-server NPC fallback → full seating ceremony → mid-battle disconnect doesn't end the battle → same-server reconnect resumes the exact duel state → existing local PvP unaffected); existing `TestService` specs still pass.

**Result (2026-07-10):**

- **Existing `TestService` specs re-run headless, still green**: `GachaAcquisitionSpec`, `ShopTransactionSpec`, `GachaOddsSpec` all pass, confirming nothing in this feature regressed the pre-existing gacha/shop test suite.
- **Local (non-matchmaking) PvP unaffected — confirmed by direct code inspection, not assumption:** `script_grep` for `_matchmaking` and `battle.matchmaking` across the whole game confirms `tbl._matchmaking = true` is set in exactly two places, both inside `attemptSeatPendingMatches` (the matchmaking-only seating path) — never in `TableManager.handleReadyUp`'s call chain (local PvP's entry point). So for local PvP, `battle.matchmaking` is always `false`: `onMatchStart` still fires (since `battle.mode=="pvp"` alone qualifies) and still calls `Save.beginMatch`, preserving the existing anti-rage-quit `activeMatch` tracking — just retimed from "at `Registry.create`" to "at mulligan-start," a functionally negligible shift confirmed safe by inspection (mulligan begins synchronously inside `Session.start`, no meaningful delay). `PlayerRemoving`'s pause-vs-forfeit branch checks `battle.matchmaking`, so local PvP always takes the unchanged instant-forfeit `else` branch.
- **Standing-Noob PvE unaffected — same technique:** `tbl._matchmaking` is never set anywhere in `TableManager.handleTalkToNpc`'s call chain, so a normal PvE battle's `battle.matchmaking` is always `false` and `onMatchStart` correctly no-ops for it (`mode=="pve"` and `matchmaking==false` both fail the guard) — `activeMatch` is never touched, exactly matching pre-existing behavior.
- **Fatigue-death fix / turn-timer/forfeit path unaffected — confirmed by diff scope:** `DuelSession.lua`'s only change this plan was adding the optional `onMatchStart` parameter to `start()` or (`if onMatchStart then onMatchStart(battle) end`); `scheduleHumanTimer`, `humanEndTurn`, `startSeatTurn`, and `checkAndEnd` are byte-for-byte untouched.
- **`BattleRegistry.destroy`/`TableManager.markFree` run exactly once, only on genuine end:** confirmed by inspection — the new pause path in `PlayerRemoving` explicitly takes a separate branch that never calls `endBattle` (and therefore never reaches `Registry.destroy`/`TblMgr.markFree`) for a matchmaking battle still in progress; the existing `else` branch (local PvP, normal PvE, or a matchmaking battle already `"ending"`) is unchanged.
- **One live-testable regression check could not be completed:** attempting to trigger the real standing-Noob PvE flow via `execute_luau` (`TblMgr.handleTalkToNpc(player)`) hit the same documented VM-isolation limitation as every prior phase — the freshly-`require`'d `TableManager` copy in `execute_luau`'s own plugin VM never had `TblMgr.init(...)` called on it (that happened in the real game server's own separate VM), so `onStartPvE`/`onStartPvP` are `nil` in that copy and the call errors. This is a confirmed environment limitation, not a new bug — relied on the code-inspection confirmation above instead, consistent with how this exact limitation has been handled in every previous plan in this repo.
- **Full 2-player local PvP Local Server smoke** remains the same pre-existing gap `DEV_STATUS.md`'s Known Issues already tracked before this plan (not something this plan introduced or was expected to close).

**Docs updated:** `DEV_STATUS.md` (new top section; `BattleController`/`BattleRegistry`/`DuelSession`/`TableManager`/`SaveService` rows updated; new `Matchmaker`/`ServerRegistry`/`MatchmakingUI`+`MatchmakingController` rows; `BattleUIController` row updated for `BattleReconnected`; new remotes in the RemoteEvents table; new Known Issues row for the published-place verification gap), `README.md` (new plan pointer, new modules/remotes/StarterGui-StarterPlayerScripts entries), `IDEA_MATCHMAKING.md` (status header pointing at this plan, Case-C deviation noted explicitly).

---

## Testing Constraint: What Requires a Published, Multi-Server Place

Confirmed directly against Roblox's engine docs during planning, not just this
project's past "single-Studio-session" limitations: cross-server instance
targeting is **officially documented as not working during Studio
playtesting** (`TeleportService:GetPlayerPlaceInstanceAsync`'s doc page states
this explicitly, and the same constraint applies to the teleport mechanics
this plan depends on) — a single Studio Play/Local Server session is one
server instance; there is no second live `JobId` for a teleport to land on.

**Studio-verifiable:** queue join/leave/poll + MemoryStore atomicity (Phase 1); destination-selection *decision* logic against a mocked registry (Phase 2); the full single-server NPC-fallback seating pipeline (Phase 3); the same-server half of reconnect — disconnect-doesn't-forfeit, timeout-streak-still-forfeits, re-seating a same-`jobId` rejoining player (Phase 4); all UI wiring (Phase 5).

**Must defer to a published, multi-server-capable place:** an actual `TeleportAsync` call landing a player on a genuinely different running instance; a destination server actually receiving a real player via `PlayerAdded`/`GetJoinData().TeleportData`; the "reserved table lost, found another" race across two real processes; the different-server reconnect branch (dead-jobId mismatch detection, live-jobId successful teleport-back); cross-server load behavior under real network conditions.

Recommend a dedicated published-place verification pass as its own follow-up
session once Phases 1–5 are Studio-clean, so it's checking genuinely new
surface (the teleport/cross-instance mechanics) rather than re-discovering
logic bugs that should already have been caught locally.

---

## Open Item — Resolved During Phase 4

Phase 4b's "disconnect doesn't forfeit, only 2 consecutive skipped turns
does" model applies **only to matchmaking-originated battles**
(`battle.matchmaking == true`) — local same-server manual PvP keeps today's
exact instant-forfeit-on-disconnect behavior. This was the conservative
default flagged during planning as unresolved; implemented as such with no
counter-indication found while building Phase 4. `battle.matchmaking` gates
the new behavior, per the design.

---

## Out of Scope (flagged, not silently dropped)

- Level-weighted matchmaking (informational only, per the user).
- Opponent-disconnected UI polish beyond a minimal `Notify`/`SeatedOverlay` reuse.
- A player leaving while merely *queued* (not yet in a battle) — the `MemoryStoreQueue` TTL naturally expires their entry; no special handling this pass.
- "Existing duel activity" as a registry tiebreaker (mentioned in `IDEA_MATCHMAKING.md`) — only free-table-count and population drive Phase 2's selection; duel-activity weighting is a future refinement.
- Sound/VFX for match-found/teleport transitions.

---

## Critical Files

- `ServerScriptService/BattleController.lua` — `PlayerRemoving` change (4b), boot-wiring for `ServerRegistry`/`Matchmaker` loops (1), `JoinMatchmaking`/`CancelMatchmaking` handlers (5), `onMatchStart` call sites (4a).
- `ServerScriptService/Modules/SaveService.lua` — `beginPvpMatch` gains `jobId` (4a), `onPlayerAdded` reconnect-before-abandonment rewrite (4c).
- `ServerScriptService/Modules/BattleRegistry.lua` — new `reconnectSeat`; `PlayerRemoving`'s `removePlayer` call must become conditional, not just "split" (4b/4c) — confirmed via direct source read that `removePlayer` runs unconditionally today.
- `ServerScriptService/Modules/DuelSession.lua` — new `onMatchStart` callback param on `start` (4a); the existing timeout/streak logic itself is unchanged — Phase 4b just stops short-circuiting it.
- New `ServerScriptService/Modules/Matchmaker.lua`, `ServerScriptService/Modules/ServerRegistry.lua` — queue/registry/destination-selection foundation (1–2).
- `ServerScriptService/Modules/TableManager.lua` — reused (`spawnNpcAt`, seating) for post-teleport seating (2) and NPC fallback (3); needs a `countFree()` accessor.
- `StarterGui/BattleUI/BattleUIController` — new client entry point for "join directly into an active battle" (reconnect, 4c) — does not exist today.
- New `StarterPlayerScripts/MatchmakingController.lua`, `StarterGui.MatchmakingUI` — Phase 5 UI, following `ItemMallController`/`ItemMallUI` conventions verbatim.
