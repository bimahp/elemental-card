# PLAN_ECONOMY_REVAMP — Card Fragments, Battle Rewards, Result UI

> Status: **implemented and verified** (headless for every pure ModuleScript; live Studio Play / real remotes for profile- and client-dependent pieces — one full multi-turn battle playthrough remains unverified, see Phase 6) | Author: bimahp (with Claude) | Date: 2026-07-10
>
> Implements [DESIGN_ECONOMY.md](../archive/DESIGN_ECONOMY.md) (Card Fragments / Crystal
> Shards separation, Crystal Dust removal, vending machine currency) and
> [DESIGN_REWARD.md](../archive/DESIGN_REWARD.md) (per-mode battle rewards, validity
> gate, forfeit rules, daily caps) end-to-end. Daily quests are explicitly
> **out of scope** — next step once this lands. DESIGN_REWARD §11
> abuse-monitoring metrics are explicitly deferred (TODO left in code).

## Implementation Status

- [x] **Phase 0** — Tracking doc + shared `RewardConfig.lua`
- [x] **Phase 1** — SaveService schema v5.2 → v5.3
- [x] **Phase 2** — RewardService rewrite + BattleController wiring
- [x] **Phase 3** — Vending machine: Card Fragments instead of Crystal Shards
- [x] **Phase 4** — Remove Crystal Dust everywhere + Fragments HUD badge
- [x] **Phase 5** — Post-battle Result UI (shared modal shell + EXP bar)
- [x] **Phase 6** — Regression pass + docs

## Post-Ship Fix (2026-07-10)

**User-reported crash:** `ServerScriptService.BattleController:724: attempt
to index nil with 'player'` on every `PlayCard`/`DeclareAttack` in a real
battle. Root cause: the Phase 2 edit that initializes
`battle.meaningfulActions = { player = 0, npc = 0 }` in `startPvE`/`startPvP`
was applied via `multi_edit`'s `replace_all: true` (targeting the shared
`local battle = Registry.create(...)` line, identical in both functions).
The tool reported "2 edits applied" but **zero** of the two occurrences
actually landed — confirmed by reading the real `Script.Source` directly,
which showed the insertion present nowhere. Every battle therefore had
`battle.meaningfulActions == nil`, and the first `PlayCard`/`DeclareAttack`
crashed indexing `nil[seat]`. This is the exact same failure mode already
seen once in Phase 3 (`VendingMachineController`'s `replace_all` edit also
silently no-op'd) — now confirmed as a repeatable `multi_edit` `replace_all`
bug, not a one-off, and written up as
[[reference_multiedit_replaceall_unreliable]] for future sessions.

**Fix:** re-applied via the established direct-`Script.Source`-`gsub`
workaround (not `multi_edit`), inserting the initializer after both
occurrences of `local battle = Registry.create(state, seats, tbl.tableId)`.
Verified via `Script.Source` pattern count (2 of 2, matching `startPvE` and
`startPvP`) and a clean Play-mode boot with zero errors afterward.

**Audited every other Phase 2 edit for the same failure class** (the two
`endBattle(..., "forfeit")` call sites, the `onBattleEnd` 3-arg wrapper,
`registerEarlyForfeit`, `getMatchmakingCooldownRemaining`, and
`DuelSession`'s forfeit-reason passthrough) — all confirmed present exactly
once via direct `Script.Source` pattern match. This was the only casualty;
every other edit in this plan used a unique (non-`replace_all`) `old_string`
and landed correctly.

**Still not confirmed:** a full real battle played end-to-end via simulated
clicks. Attempts this session to reach the standing Noob (`character_navigation`
to its position/`HumanoidRootPart`, then a held `E` keypress) did not
reliably close the distance inside `MaxActivationDistance=10` (measured
21–24 studs away despite "Success" navigation results), and a
matchmaking-queue NPC-fallback attempt never seated within several minutes —
plausibly `MemoryStoreQueue` quota exhaustion from this project's own
cumulative testing (a pre-existing, documented constraint, not a new bug).
The fix itself is verified correct by direct inspection of the exact crash
site (the reported error precisely matches "index nil with the seat-string
key," and the initializer is now confirmed present at the one place that
must run before any `PlayCard`/`DeclareAttack` handler executes) — but a
real click-driven playthrough remains the one genuinely unverified piece,
carried forward from Phase 6's own known gap.

---

## Reward math (locked)

Every battle is classified into one **category** from `battle.mode` +
`battle.matchmaking`:

| `mode` | `matchmaking` | Category | Table |
|---|---|---|---|
| `"pvp"` | `true` | **Matchmaking** | win 3 / loss 1 / early-forfeit-win 2 / early-forfeiter 0 |
| `"pve"` | `true` (NPC-fallback) | **Matchmaking** | same table as above (confirmed with user: NPC-fallback pays matchmaking rate, not NPC rate) |
| `"pvp"` | `false` | **Local** | win 1 / loss 0 |
| `"pve"` | `false` (Trainer / standing Noob) | **NPC** | win 1 (repeat) or 50 (first clear, **tracked per opponent archetype** MIGHTY/SWIFT/VITAL) / loss 0 |

**Validity gate (Matchmaking category only):** a recipient's own outcome only
counts if `battle.state.turnNumber >= 4 OR` that seat performed `>= 2`
meaningful actions this battle (a successful `PlayCard` or `DeclareAttack`,
tracked per seat). Otherwise 0, regardless of win/loss.

**Forfeit (Matchmaking category only):** explicit `Forfeit` or a
2-consecutive-timeout AFK-forfeit is *early* if the forfeiting seat hadn't
reached validity yet; otherwise *late* (treated as a normal loss/win, 1/3).
Early forfeits increment a daily counter driving a cooldown ladder gating
`JoinMatchmaking`: 1st = warning, 2nd = 2min, 3rd = 5min, 4th = 15min,
5th+ = 30min, resets daily.

**Daily caps:** Matchmaking + Local + repeat-NPC share a 200 Fragments/day
cap; repeat-NPC wins additionally share their own 10/day sub-cap. First-clear
bonuses (and later, quest rewards) bypass both caps.

**EXP:** `exp = fragmentsActuallyGranted * RewardConfig.EXP_PER_FRAGMENT`
(15), computed after capping/first-clear, so it always tracks what was
actually granted.

**Assumption (flagged, not challenged before implementation):** NPC-fallback
(Matchmaking-rate) does not additionally grant the archetype first-clear
bonus — that stays an NPC Battle-category concept only.

---

## Phase 0 — Tracking doc + shared config

**Steps:** this doc; new `ReplicatedStorage/Modules/RewardConfig.lua` with
`MATCHMAKING`/`LOCAL`/`NPC` tables, `GLOBAL_DAILY_CAP`, `NPC_DAILY_SUBCAP`,
`EXP_PER_FRAGMENT`, `VALID_TURN`, `VALID_ACTIONS`,
`FORFEIT_COOLDOWN_LADDER`/`forfeitCooldownSeconds()`.

**Result (2026-07-10):** Implemented `ReplicatedStorage/Modules/RewardConfig.lua`
(`MATCHMAKING`/`LOCAL`/`NPC` tables, both daily caps, `EXP_PER_FRAGMENT=15`,
`VALID_TURN=4`/`VALID_ACTIONS=2`, `FORFEIT_COOLDOWN_LADDER`/
`forfeitCooldownSeconds()`) and this tracking doc.

---

## Phase 1 — Schema (SaveService v5.2 → v5.3)

**Result (2026-07-10):** `TEMPLATE` gains `cardFragments`, `dailyRewards`,
`matchmakingCooldownUntil`, `pveFirstClear`; `crystalDust` removed. New
`MINOR_MIGRATIONS["5.2->5.3"]` backfills the new fields and nils out
`crystalDust`. `CURRENT_VERSION` bumped to `{5,3}`. Every `QuestStateChanged`/
`GetFullSnapshot` payload in this file now sends `cardFragments` instead of
`crystalDust` (BattleController's `GetQuestSnapshot`, `RobuxShopController`,
`QuestService`, and the client display sites are still on the old field —
tracked for Phase 3/4). New `SaveService.dayBucket()`, `ensureDailyReset()`
(local), `getExpProgress(player)`, `getMatchmakingCooldownRemaining(player)`.
`applyRewards`'s `crystalShards`/`cardDrop` branches are untouched for now —
removed in Phase 2 when its only caller (`BattleController.endBattle`)
switches to the new `applyBattleRewards`.

Verified headless (`execute_luau`, Edit mode, clone-and-rename technique to
dodge this environment's known require-cache staleness — confirmed via
`script_read` that the edited source was already correct before concluding
it was a cache issue, not a code bug): fresh-profile defaults for all four
new fields, `_version` bumped to 5.3; a hand-built v5.2 profile with
`crystalDust=42` migrates to `minor_upgraded`, backfills all four new fields,
and drops `crystalDust`; `dayBucket()` returns a sane positive integer. Test
clone destroyed afterward, no leftover instances.

## Phase 2 — Reward engine

**Result (2026-07-10):** `RewardService.lua` rewritten as a pure classifier
(no profile access, matching its original design intent) — `category()`
(`matchmaking`/`local`/`npc` from `battle.mode`+`battle.matchmaking`),
`isValid()` (turn-4-or-2-actions gate, Matchmaking only), `npcArchetype()`
(reads `seats.npc.deckKey`, works uniformly across standing-Noob/Trainer/
tutorial). `buildBattleRewards(ctx)` now takes `reason` (`"win"`|`"forfeit"`)
and returns an unpersisted plan (`category`, `outcome`, `forfeited`,
`earlyForfeit`, `valid`, `baseCardFragments`, `archetype`) instead of a
ready-to-apply payload. Removed `pveDropPool`/fixed-card-drop entirely
(DESIGN_REWARD §4.3).

New `SaveService.applyBattleRewards(player, rewardPlan)` is the sole place a
plan becomes a real mutation: resolves the NPC per-archetype first-clear
bonus (bypasses both caps), clamps against the 200/day global and 10/day
NPC sub-caps, commits `cardFragments`, computes `exp = granted *
EXP_PER_FRAGMENT` and runs `checkLevelUp`, force-saves (same
immediate-flush-on-important-event convention the old `cardDrop` path used).
New `SaveService.registerEarlyForfeit(player)` drives the cooldown ladder.
The old `SaveService.applyRewards` (crystalShards/cardDrop grant) is deleted
— its only caller is replaced.

`BattleController.lua`: `endBattle(battle, winner, reason)` gains the third
param; `Forfeit` and the non-matchmaking `PlayerRemoving` disconnect branch
pass `"forfeit"`; `DuelSession.lua`'s 2-consecutive-timeout AFK-forfeit
(`scheduleHumanTimer`) now passes `"forfeit"` through `onBattleEnd` too, one
line. `battle.meaningfulActions = {player=0, npc=0}` initialized in both
`startPvE`/`startPvP`; `PlayCard`/`DeclareAttack` handlers increment the
acting seat's counter on a successful `Logic.playCard`/`Logic.attack`. PvP
battles now call `Save.applyBattleRewards` too (previously PvP earned
nothing at all). `BattleOver`'s payload gains `exp` (`Save.getExpProgress`).
`JoinMatchmaking` rejects with a `Notify` toast when
`Save.getMatchmakingCooldownRemaining(player) > 0`. A
`TODO(DESIGN_REWARD.md §11)` comment marks the deliberately-deferred
abuse-monitoring metrics at the cooldown-ladder call site.

Verified headless (`execute_luau`, Edit mode, clone-and-rename technique):
14 assertions across `RewardService.buildBattleRewards` — Matchmaking normal
win/loss at turn 5, invalid-recipient-gets-0 at turn 2 with 0 actions,
valid-via-2-actions before turn 4, early forfeit (forfeiter 0 / opponent 2),
late forfeit (forfeiter 1 / opponent 3, i.e. treated as a normal loss/win),
Local win=1/loss=0 ignoring turn/actions entirely, NPC win=1+archetype vs.
loss=0+no-archetype, NPC-fallback (`pve`+`matchmaking=true`) correctly
classified as `matchmaking` category (not `npc`) per the locked decision, and
the `seatHasHuman` guard returning `nil` for a bot recipient. All passed;
test clone destroyed afterward.

**Known verification gap, consistent with this project's testing-constraint
conventions elsewhere:** `SaveService.applyBattleRewards`/
`registerEarlyForfeit`/`getExpProgress`/`getMatchmakingCooldownRemaining` all
key off the private `Profiles[player]` table, which only a real connected
`Player` populates (`onPlayerAdded`) — there is no way to fake a `Player`
instance in Edit mode, so the cap/first-clear/EXP arithmetic inside
`applyBattleRewards` is verified by code review here, not headless execution.
Deferred to Phase 6's live Studio Play pass, which exercises this exact path
with the real connected test player.

## Phase 3 — Vending machine currency swap

**Result (2026-07-10):** `GachaConfig.lua`: `COST_CRYSTAL_SHARDS=50` →
`COST_CARD_FRAGMENTS=160` (Standard Pack price; archetype Core Packs stay 200); `DUPE_DUST`
removed. `GachaTransaction.apply()` now checks/deducts `data.cardFragments`;
the duplicate-protection *cap* logic (GachaService's `eligibleBucket` already
excludes a >=2-owned card until the whole rarity pool is capped) is
untouched, but the *consequence* of rolling a dupe changed: it's now added to
the collection uncapped with `isDupe=true` and zero currency, instead of
being blocked from the collection and converted to Dust (DESIGN_ECONOMY
§12.4 — dupes are allowed through once protection is exhausted; manual
destroy-for-Shards crafting doesn't exist yet, see Next Steps).
`GachaService.roll()` passes the new cost constant.

`VendingMachineController.lua`: balance display is Fragments-only now
(dropped the dual "Shards | Dust" display — Shards aren't relevant to pack
purchases per DESIGN_ECONOMY's currency separation); button labels and the
open-button icon (`AssetIds.Icons.CARD_FRAGMENT`, new) updated; the
duplicate-protection info-panel copy rewritten to describe the new
no-currency-on-dupe behavior instead of "converts to Crystal Dust". (One
`replace_all` edit silently no-opped on 2 of 3 occurrences despite the tool
reporting success — caught by verifying `Script.Source` directly rather than
trusting the tool's report or `script_grep`/`script_read`, and fixed via a
direct `Script.Source` string-pattern replacement, this project's established
workaround for this exact tooling gap per `PLAN_MATCHMAKING.md`.)

`PackRevealController.lua` (the post-purchase reveal screen) also referenced
Dust and would have silently shown "Converted to +0 Dust" for every
duplicate once the field disappeared — a real regression, not just a
missed-file completeness gap. Fixed: `_statusFor` now reports "Duplicate"
instead of a dust amount; the summary's dust-total label now counts and
reports duplicate cards added instead of Dust awarded.

`ReplicatedStorage/Modules/AssetIds.lua`: new `Icons.CARD_FRAGMENT`, reusing
the former `CRYSTAL_DUST` asset id as an explicit placeholder (no dedicated
Fragment art exists yet, same "known gap" class as missing card art) —
auto-feeds the startup preload list via the existing `Icons` table
convention, no separate registration needed.

`TestService/GachaAcquisitionSpec` rewritten for the new transaction shape
(cardFragments cost/balance, uncapped-dupe-add-with-isDupe-flag instead of
Dust conversion).

Verified headless (`execute_luau`, Edit mode, clone-and-rename technique —
required fresh even for `GachaConfig` alone, since a plain `require` on the
real path returned a stale cached copy missing the new field entirely,
caught by an assertion failure rather than silently passing): a 5-card
"pack" purchase against a starting 1-owned-copy collection deducts exactly
160 Fragments, adds all 5 rolled cards unconditionally (6 total copies,
matching the new no-cap-at-transaction-level behavior), correctly marks the
1st result "Added Copy" and the remaining 4 `isDupe=true`; a fresh card is
marked `isNew`; insufficient-Fragments and invalid-card purchases both fail
atomically with zero mutation; `GachaConfig.COST_CARD_FRAGMENTS==160` and
`DUPE_DUST==nil` confirmed directly. `Script.Source` string checks confirmed
zero remaining `COST_CRYSTAL_SHARDS`/`dustAwarded`/"Converted to +" text
anywhere in the touched client scripts. All test clones destroyed afterward.

## Phase 4 — Crystal Dust removal + Fragments HUD badge

**Result (2026-07-10):** Removed the remaining `crystalDust` references:
`RobuxShopController.lua`/`QuestService.lua`'s `QuestStateChanged` broadcasts
now send `cardFragments`. `StarterGui.Hud.CurrencyBar`'s `DustBadge` Studio
instance renamed in place to `FragmentsBadge` (editor-first — kept its
existing `UICorner`/`UIStroke`/`Icon`/`Count` children rather than building a
new instance at runtime; its `Icon.Image` already pointed at the same
placeholder asset id now reused for `AssetIds.Icons.CARD_FRAGMENT`, so no
image change was needed). `CurrencyBarController.lua` updated to reference
`FragmentsBadge`/`cardFragments` and a new `Theme.Colors.Fragment` warm-gold
accent (`RGB(255,196,60)`, added to `UITheme.lua` — DESIGN_UI.md specifies
"Card Fragments warm gold" and no existing token matched; the old `Dust`
token is kept since it's still used as the epic-rarity accent color
elsewhere, unrelated to the currency). `ShardsBadge` is untouched — Shards
still matter for the Robux shop and future crafting.

Verified: `Script.Source` string checks (not `script_grep`/`script_read`,
per the caching lesson from Phase 3) confirm zero `crystalDust` occurrences
in every touched client/server script; `SaveService.lua` correctly still
has exactly the two expected occurrences (the migration's `data.crystalDust
= nil` cleanup, and the pre-existing dead/unreachable `4.0->4.1` migration
entry — unreachable because `ALLOW_MAJOR_RESET` hard-resets any profile
below major version 5 before minor migrations ever run, confirmed by
re-reading `migrate()`'s branching; left alone as harmless historical
residue, out of scope to "fix" here since it predates this plan entirely).

## Phase 5 — Post-battle Result UI

**Result (2026-07-10):** New `Components.createProgressBar(parent, opts)` in
`StarterGui.SharedUI.UIComponents` — generic rounded/stroked track+fill
primitive (`track, fill, setProgress(fraction, tweenTime?)`), reusable by any
future meter, not tied to this one screen.

`StarterGui.BattleUI.PostBattle` restructured as real Studio instances
(editor-first, via the Studio MCP tools — not runtime `Instance.new` in Lua):
resized/recentered to the standard modal convention; new `PostBattleScrim`
sibling under the BattleUI ScreenGui; new `TitleBar`/`Title`/`CloseButton`
children; new `Body` frame housing the reparented `ResultLabel`/
`RewardLabel`/`ContinueBtn` alongside two new static instances — `LevelLabel`
and `ExpBarTrack` (+ `Fill` child) for the EXP bar. `ResultLabel` ("YOU
WON!"/"YOU LOST.") deliberately stays large/prominent inside `Body` rather
than shrinking into the title bar, preserving its visual impact; the title
bar instead just carries a generic "Battle Result" title, background-tinted
Success/Danger per outcome at runtime.

Because `PostBattle` lives inside the always-on `BattleUI` ScreenGui (not its
own dedicated ScreenGui like every other panel), `UI.bindFullscreenBackdrop`'s
`ScreenGui.Enabled`-driven convention doesn't apply — `PostBattleScrim`'s
`Visible` is instead hand-synced to `post.Visible` at all 4 call sites
(`UpdateBattleState`, `BattleOver`, the new shared `dismissPostBattle`
function, `BattleReconnected`). One accepted, documented limitation:
`UI.applyModalShell`'s slide-in entrance tween is driven by the ancestor
ScreenGui's `Enabled` toggle, which for `PostBattle` doesn't correspond to
its own show/hide moment — so the panel renders correctly but skips the
entrance animation other panels get. Not worth changing the shared
`bindModalEntrance` helper's contract for one caller.

`BattleUIController.lua`: new `UI`/`Theme` requires; `BattleOver` handler
rewritten to consume the new payload shape (`data.rewards.message/
cardFragments/firstClear/exp`, `data.exp.into/needed/level`) instead of the
old `crystalShards`/`cardDrop` fields, builds the reward text as a list of
present, non-zero lines (record message, Fragments, first-clear bonus, EXP)
so it degrades cleanly for zero-reward outcomes (early forfeit, invalid
battle) instead of showing stale/wrong currency; sets the EXP bar fill via
`exp.into/needed` and a "Level N" label. `ContinueBtn`'s handler extracted
into a named `dismissPostBattle` function shared with the new `CloseButton`,
both now also clearing `postScrim.Visible`.

**A real bug caught mid-implementation, not just a completeness gap:** my
first attempt defined `dismissPostBattle` immediately after `post`'s
declaration near the top of the file (~line 65), before `hideBattleLoading`/
`clearTurnTimer`/`setBattleControlsLocked`/`setTablePromptsSuppressed`/
`clearHand`/`stopCam` exist as locals (`local function`s declared much later,
~line 2180+) — Lua locals aren't hoisted, so this would have thrown a nil-
global-call error the first time a player dismissed the panel. Caught before
any live test by reasoning through Lua's lexical scoping, not discovered by
trial and error; fixed by keeping the shared dismiss function at its original
call site (~line 2340s) where every dependency is already in scope, wiring
both buttons to it there instead.

Verified via direct `Script.Source` pattern checks (established as more
reliable than `script_grep`/`script_read` immediately after an edit, per the
Phase 3 lesson): exact expected occurrence counts for `postScrim.Visible=
true/false` across all 4 sync sites, `postTitleBar.BackgroundColor3`,
`dismissPostBattle` (definition + 2 connections), zero remaining
`crystalShards`/`cardDrop` references in the reward-text logic, and a
function/`end` keyword balance sanity count (127/474, consistent with correct
nesting). **Full behavioral verification (the panel actually rendering
correctly, the EXP bar filling, styling matching other panels) is deferred to
Phase 6's live Studio Play pass** — a `LocalScript`'s correctness can't be
proven by a headless `require`, unlike the `ModuleScript`s in earlier phases.

## Phase 6 — Regression pass + docs

**Result (2026-07-10):** Live Studio Play pass (`start_stop_play`, real
connected test player `darkmeta1207`), following this project's convention
of proving things live, not just headless.

**A real bug found and fixed before this phase could even begin:** the very
first Play-mode boot threw `Out of local registers when trying to allocate
hideBattleLoading: exceeded limit 200` and `BattleUIController.lua` failed to
load entirely. Phase 5's Studio-instance wiring added ~12 new top-level
`local`s (`UI`, `Theme`, `postScrim`, `postTitleBar`, ...) to a script that
was already near Luau's 200-local-register-per-chunk ceiling. Fixed by
grouping every `PostBattle` sub-reference into a single `Post` table (one
top-level local instead of ten) and scoping the one-time `UI`/`Theme`
requires and setup temporaries inside a `do...end` block so their registers
free up afterward instead of persisting for the script's whole lifetime.
Re-verified clean boot with zero errors after the fix.

**Verified live, with real evidence, not just absence-of-errors:**
- `Remotes.GetQuestSnapshot:InvokeServer()` fired from the real client round-
  trips through the real running `BattleController`/`SaveService` and
  returns `{"cardFragments":0,"crystalShards":1675,...}` — no `crystalDust`
  field, confirming the schema/snapshot changes work against a real migrated
  profile (console also showed `[SaveService] darkmeta1207 profile
  migration: minor_upgraded` and `schema v5.3` on boot).
- The HUD's currency bar visibly rendered "0 Fragments" / "1.7K Shards" in a
  real screenshot, confirming `CurrencyBarController`'s `FragmentsBadge`
  rewiring end-to-end.
- `Remotes.OpenCardPack:InvokeServer()` fired for real returned `{"ok":false,
  "error":"Move closer to the Card Vending Machine"}` — the authoritative
  proximity gate in `GachaController` still works correctly, unaffected by
  the currency swap underneath it.
- Firing a real `Remotes.BattleOver:FireClient(player, {...})` at the real
  client and then directly inspecting `PostBattle`'s Instance properties
  (not a screenshot — see the Known Issue below) confirmed: `post.Visible`,
  `Post.scrim.Visible`, correct `AbsolutePosition`/`AbsoluteSize`, opaque
  `BackgroundTransparency=0`, and `resultLabel.Text=="YOU WON!"` — proving
  the rewritten `BattleOver` handler runs end-to-end without error and
  correctly populates every new UI element.
- `SaveService.applyBattleRewards`'s cap/first-clear/EXP arithmetic — the one
  piece Phase 2 flagged as impossible to test headlessly (needs a real
  `Player`) — turned out to be **also impossible via `execute_luau`'s
  `datamodel_type="Server"`**: even during real Play, that tool runs an
  isolated VM with its own `require` cache, separate from the actual running
  server threads, so `Save.getProfile(player)` returned `nil` for a
  genuinely connected player. This is a new, previously-undocumented
  extension of this project's known Edit-mode `execute_luau` isolation
  limitation (see `reference_execute_luau_vm_isolation` memory) to Play mode
  too. Worked around by exercising the real reward path indirectly through
  the real `GetQuestSnapshot`/`OpenCardPack` remotes above instead of trying
  to call `applyBattleRewards` directly.

**Known verification gap, honestly unresolved this pass:** no full multi-turn
battle was played to a real win/loss through simulated clicks
(`user_mouse_input`/`user_keyboard_input` through mulligan → turns → attack)
end-to-end through the real `endBattle`. Attempting to trigger the standing
Noob's `ProximityPrompt` programmatically via a simulated `E` keypress did
not fire it (character navigation landed within ~1 stud but the prompt never
triggered — likely a hold-duration or focus requirement, not investigated
further given time). The `screen_capture` tool also did not render any
`PlayerGui` `ScreenGui` content at all in this session — not even the
pre-existing, unmodified `Hud` ScreenGui, confirmed `Enabled=true` at the
time — so this is a capture-tool limitation in this session, not evidence of
a `PostBattle`-specific rendering bug (which the direct property inspection
above independently rules out). A follow-up session should attempt a real
click-driven battle playthrough, the same way `PLAN_CARD_BATTLE_REVAMP.md`'s
Phase 8 eventually did for the mulligan UI.

Docs: this file's Implementation Status and every phase's Result section
updated throughout implementation (not just at the end, matching
`PLAN_MATCHMAKING.md`'s documentation discipline); `DEV_STATUS.md`'s
"Economy and rewards" section replaced with a full implementation summary,
its Module Status rows updated for every touched module
(`RewardService`/`SaveService`/`GachaConfig`/`GachaTransaction`/
`GachaService`/`GachaController`/`VendingMachineController`/`CurrencyBar`/
`GachaAcquisitionSpec`/`BattleController`/`BattleUIController`), and two new
Known Issues rows added (the live-verification gap above, and the reused
placeholder Fragment icon).

---

## Next Steps (explicitly out of scope this pass)

- Daily quests (3×30 Card Fragments) — per user instruction, not touched here.
- Full 4-pack DESIGN_ECONOMY catalog (Core Mighty/Swift/Vital + Standard) —
  only one Standard-equivalent pack exists today; this plan only retargets
  its currency.
- Manual "Destroy Card → Crystal Shards" crafting (DESIGN_ECONOMY §9-10) —
  Crystal Shards have no gameplay income source until this exists (Robux +
  fixed quest rewards only).
- DESIGN_REWARD §11 abuse-monitoring metrics (forfeiter/winner suspicious-
  pattern tracking) — explicit TODO left in `BattleController.lua`.
- Same-opponent reward cooldown — deferred by DESIGN_REWARD itself, post-alpha.
