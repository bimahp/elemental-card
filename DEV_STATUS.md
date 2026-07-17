# DEV_STATUS — Elemental TCG: Implementation State

> Last updated: 2026-07-11 (Card Vendor NPC — Craft/Buy/Destroy — implemented and verified)

## Card Vendor NPC — Craft/Buy + Destroy-for-Shards (PLAN_CARD_VENDOR.md, 2026-07-11)

Closes a real gap left by the economy revamp: Crystal Shards had **no
free-to-play income path** (Robux only). Adds the missing `SaveService`-
authoritative destroy-for-Shards system, plus a new "Card Vendor" NPC (the
user placed `Workspace.Card Vendor` already) selling a rotating stock of
specific cards two ways: **Craft** (Card Fragments, new pricing) and **Buy**
(Crystal Shards, DESIGN_ECONOMY.md §10.1 rates x2). Full pricing tables,
locked decisions, and phase-by-phase detail live in `PLAN_CARD_VENDOR.md`;
new numbers are the source of truth in `DESIGN_ECONOMY.md` §10.4.

**Phase 0/1 done (2026-07-11):** `GachaConfig.COST_CARD_FRAGMENTS` fixed
160→200 to match the already-updated Standard Pack price. New
`ReplicatedStorage/Modules/VendorConfig.lua` (all rates), new
`ServerScriptService/Modules/VendorTransaction.lua` (pure craft/buy/destroy
mutations, mirrors `GachaTransaction.lua`), new
`ServerScriptService/Modules/VendorService.lua` (epoch-aligned deterministic
rotation — `getRotationBucket()`/`getStockCardIds()`, zero persisted state,
lands exactly on 00:00/08:00/16:00 across every server independently), and
three new `SaveService` functions (`applyCardCraft`/`applyCardBuy`/
`applyCardDestroy`) mirroring `applyCardPackPurchase`'s shape. No schema
version bump needed — only mutates fields already in v5.3. Verified via
direct `script_read`/`script_grep` after each edit (SaveService's own
`script_grep` line numbers were found to be unreliable for this file this
session — see PLAN_CARD_VENDOR.md Phase 1 for the workaround).

**Phase 2/3/4 done (2026-07-11):** 4 new `RemoteFunction`s
(`GetVendorStock`/`CraftCard`/`BuyCard`/`DestroyCards`) under
`ReplicatedStorage.Remotes`, new `ServerScriptService/VendorController.lua`
(mirrors `GachaController.lua`'s proximity/rate-limit shape; caught and
fixed a real bug before shipping — `DestroyCards` must NOT require Vendor-
NPC proximity since it's reachable from `InventoryController` anywhere, only
Craft/Buy do). New `StarterGui.VendorUI` (cloned from `ItemMallUI`'s shell)
+ new `StarterPlayer.StarterPlayerScripts.VendorUIController.lua` combining
the Card Vendor's dialogue trigger (reuses the existing generic
`DialogueController`, zero changes to it or to `TrainerInteraction.lua`) and
the Stock→Detail shop UI (reuses `CardVisuals`/`InventoryController`'s card-
rendering pattern). New `UITheme.Accents.Vendor`. Fixed the Card Vendor
NPC's stale `TalkPrompt.ObjectText="Noob"` (cloned-from-Noob leftover).

**Phase 5/6 done (2026-07-11):** `InventoryController.lua`'s "My Cards" card-
select handler gained a "Destroy 1 Copy (+N Shards)" button (fires
`DestroyCards`, only spawns when copies exceed `DESTROY_PROTECTED_COPIES`
for that rarity; one copy per click, not a quantity stepper — a disclosed
scope simplification). Headless: 27/27 assertions across `VendorConfig`
rates, `VendorService` rotation determinism, and `VendorTransaction`
craft/buy/destroy atomicity. Live Studio Play (real connected test player,
persisted across a session restart): real dialogue→shop flow, a real Craft
failure (insufficient Fragments) and a real Buy success (Shards deducted,
card added, confirmed maxed at 2 copies), a real Destroy success + a real
protected-copy rejection, and confirmation that `DestroyCards` works from
~111 studs away while `CraftCard`/`BuyCard` correctly require Vendor
proximity. **A real bug found and fixed live:** the client's post-purchase
Detail-page refresh re-rendered from a stale cached stock snapshot instead
of re-fetching, so Craft/Buy buttons stayed wrongly enabled after a card
became maxed — fixed by re-fetching stock before the refresh; the server-
side max-copies gate itself was confirmed correct throughout (this was a
client display bug only). **Known gap:** the Destroy button's positive case
(spawning + being clicked for real inside `InventoryUI`) wasn't exercised —
the test profile ran out of 3+-copy cards and had too few Fragments to roll
more; the underlying remote it calls was independently verified multiple
times. See `PLAN_CARD_VENDOR.md` for full detail. `DESIGN_ECONOMY.md` §10.4
is now the source of truth for every Vendor rate.

**Post-ship fix (2026-07-11):** the Card Vendor had no floating name/title
nameplate like every other NPC — `NameplateController.lua`'s `NPC_DATA`
table and NPC-scan simply never included it. Added `"Card Vendor"` →
`{displayName="Card Vendor", title="Card Merchant"}` (same role-name-as-
display-name pattern Noob uses) and a matching `suppressDisplay` call in
`NameplateService.lua`. Live-verified: registered NPC count went 4→5, and
direct inspection confirmed the real nameplate text and suppressed default
Humanoid display match every other NPC exactly.

---

## Cross-Server Matchmaking + Reconnect (PLAN_MATCHMAKING.md, 2026-07-10)

All 6 phases implemented and verified — headless (`execute_luau`, Edit mode)
where the code permits, and live in actual Studio Play (`start_stop_play`)
with a real connected test player for everything that requires an actual
running server (MemoryStore calls, real seating/teleport-adjacent logic).
See `PLAN_MATCHMAKING.md` for full phase-by-phase detail, including two real
architecture corrections found and fixed *during* implementation (not
anticipated by the approved plan) and three real engine bugs found via live
testing, not just inferred.

**New cross-server queue + registry** (`ServerScriptService/Modules/
Matchmaker.lua`, `ServerRegistry.lua`): a `MemoryStoreQueue`-backed global
FIFO queue and a `MemoryStoreSortedMap`-backed per-server free-table
heartbeat. Any server can pop a match; the popping server never assumes it
can directly teleport either player (a server can only `TeleportAsync` a
`Player` who is actually present on it) — it only writes instructions
(`MM_PendingMatches` per matchId, `MM_PendingTeleports` per userId), and
every server's own poll loop separately teleports only its own present
players and seats only its own inbound matches. Destination selection checks
a player's own current server directly via `TableManager.countFree()`
(authoritative, instant) before falling back to the registry hint for other
servers. The rare "no server anywhere has room" case uses
`TeleportService:ReserveServer` purely as an internal convergence mechanism
(not a private/invite-only server) so two independently-teleporting home
servers land on the same new instance.

**NPC fallback** (empty queue, or effectively immediate since `tryMatch`'s
`"single"` result already *is* the empty-queue signal): goes through the
identical destination/teleport/seating pipeline as a real match — no
shortcut — reusing `TableManager.spawnNpcAt` and `startPvE` unmodified.

**Reconnect**: disconnect no longer instantly forfeits a matchmaking-
originated battle (`battle.matchmaking == true`) — `BattleController`'s
`PlayerRemoving` now pauses it instead (skips `endBattle`/
`Registry.removePlayer`, so `PlayerBattle[userId]` survives). The existing,
unmodified turn-timeout/streak machinery (`DuelSession.TURN_TIMEOUT_SECONDS`,
`MAX_TIMEOUTS_BEFORE_FORFEIT=2`) becomes the only forfeit trigger. On
rejoin, `SaveService.onPlayerAdded` attempts `attemptReconnect` (same-server:
direct `BattleRegistry` lookup + `reconnectSeat`; different-server:
`TeleportAsync` toward the stored `jobId`) before falling through to a
**mode-aware** abandonment penalty (`"pvp"` records a loss; `"pve"`
NPC-fallback records none, matching how a normal PvE loss already carries
none) — live-confirmed firing correctly for real during Phase 5 testing, not
just headless. Local (non-matchmaking) PvP keeps today's exact
instant-forfeit-on-disconnect behavior, unchanged. `BattleUIController`
gained a new `BattleReconnected` client entry point since the existing
client only ever knew how to enter a battle via `BattleSeated` → mulligan →
first `UpdateBattleState`.

**Matchmaking UI**: new `MatchmakingButton` HUD icon (asset
`105294857091338`) added to `TopRightAnchor`, a new `MatchmakingUI` panel
(Level display + Find Opponent/Cancel Matchmaking, following the
`ItemMallUI`/`ItemMallController` shell pattern exactly), and a ticking
elapsed-time icon label (adapted from `MulliganController`'s countdown
pattern, counting up instead of down) driven by new `JoinMatchmaking`/
`CancelMatchmaking`/`MatchmakingUpdate` remotes.

**Real bugs found and fixed via live testing (not hypothetical):**
`game.JobId` is an empty string in unpublished Studio Play (only a real
published server gets a GUID), which broke `ServerRegistry.publish()`'s
`MemoryStoreSortedMap` key — fixed with a one-time-warned guard.
`getMatchesForThisServer()`'s full `HashMap:ListItemsAsync` scan running on
the same fast cadence as cheap targeted queue/teleport checks hit a real
`TotalRequestsOverLimit` MemoryStore throttle during live testing — fixed by
splitting the poll loop into a fast (5s) and slow (20s) cadence.
`TeleportService:ReserveServer` (and by extension every `TeleportService`
method) throws `"...can only be called by the server"` when invoked from
Edit-mode `execute_luau` — a stronger constraint than the previously-known
"cross-instance targeting doesn't work in Studio Play" limitation.

**What remains genuinely unverified** (see `PLAN_MATCHMAKING.md`'s Testing
Constraint section): a real `TeleportAsync` call actually landing a player
on a different running server instance, a destination server receiving a
real player via `PlayerAdded`/`GetJoinData().TeleportData` from another live
server, and the different-server reconnect branch. These require a
published, multi-server-capable place to verify — recommended as a dedicated
follow-up session.

---

## Battle Presentation Director + Full Mulligan (PLAN_CARD_BATTLE_REVAMP.md, 2026-07-08)

All 9 phases implemented and verified (headless + live Studio Play). A
2026-07-09 implementation review found four defects, now fixed in live Studio:
PvP mulligan timeout tokening, full ordered `animEvents` replay, cancellable
skip/fast-forward, and `cast_reveal` state restoration. See
`PLAN_CARD_BATTLE_REVAMP.md` → "Post-Review Fix Pass (2026-07-09)" for details.

The implemented revamp replaces
the old before/after-snapshot diffing (hand-diff heuristics for Draw/Play,
one board-diff heuristic gated to `state.lastAction=="attack"` for Attack)
with an explicit server-emitted **animatable event log** and a client
**Director + phase-registry** sequencer, and adds a full pre-battle
**mulligan** stage.

**Server:** `Effects/Ops.recordAnim(state, ev)` stamps a monotonic `animSeq`
and appends to `state.pendingAnimEvents` from every animatable mutation
(damage/heal/buff/summon/bounce/kill/draw/gain_armor). `BattleLogic.playCard`/
`attack`/`startTurn` additionally push envelope events (`cast`, `attack`,
`turn_start`) so the client knows a new sequence started before detail events
arrive. `BattleRegistry.viewAnimEvents` relabels perspective exactly like the
existing `viewChargeEvents`; `BattleController.broadcast` clears
`pendingAnimEvents` after sending, same spot it already clears
`pendingChargeEvents` — a fully separate, untouched channel.

Mulligan is a genuine new pre-battle rules stage: `battle.status = "mulligan"`
(distinct from `"active"`) holds the real turn loop until every human seat
confirms a redraw selection or times out (30s, auto-keeps the dealt hand).
NPC seats auto-resolve instantly. The Coin is granted to the second seat only
after both seats resolve — it was never a redraw candidate. New remotes:
`OfferMulligan` (S→C, dealt hand), `RedrawMulliganCard` (RemoteFunction, C→S
index → S→C ok/newCardId, swaps in real time), `ConfirmMulligan` (C→S,
finalizes the seat — no payload, since any redraw already happened via
`RedrawMulliganCard`).

**Client:** new `BattleDirector` (FIFO phase queue, single `isLocked()` input
gate replacing the old scattered `handHoverDisabled`/`boardPreviewLocked`
flags, per-phase timeout safety net, skip/fast-forward) and `PhaseRegistry`
(handler-per-phase-type, mirroring the server's `Effects/Actions` registry):
`draw`, `play`, `attack`, `turn_banner`, `cast_reveal`, `effect`. New
`EffectVisuals.resolveVisualArchetype` maps an effect's action/target/area to
a visual archetype (default + optional future per-card override); only the
`projectile` archetype (single-target damage) is built for real this pass —
zoom → traveling bolt → existing impact/damage-pop feedback. New `MulliganUI`
+ `MulliganController` drive the mulligan window on the shared `Dialog`/
`Scrim` shell.

**Draw/status polish fix pass (2026-07-09):** hand draw frames are now hidden
until their `PhaseRegistry.draw` phase begins, so a drawn card no longer appears
instantly in hand and then animates afterward as a duplicate/afterimage. The
first active battle render after mulligan also reveals the starting hand via the
same deck-to-hand draw phase instead of popping the full hand in place. If the
player skips before a queued draw starts, `BattleDirector.skip()` runs queued
phase cleanup hooks so hidden draw frames are safely revealed. Board status
treatment was also clarified: Taunt keeps the shield icon, Stealth now uses a
cloud/fog icon, and the dark full-card overlay is reserved for sleeping /
exhausted cards only. Follow-up tuning: `OfferMulligan` now enters the seated
battle camera/lock state before First Draw appears, and `MulliganController`
delays the dialog briefly so the player is visually seated/facing the opponent;
the Stealth cloud icon is now larger and centered over the artwork.

**Post-completion fix pass (2026-07-08):** a live-session screenshot surfaced
five issues, all fixed: the "Finding Table..." loading overlay showing behind
the mulligan dialog (now cleared on `OfferMulligan`); mulligan redesigned to
allow **at most one card redraw** (not any number), enforced both client-side
(one "Re-draw" button per card, parented to the card so it moves with it —
picking one is final and instantly removes every Re-draw button) and
server-side (`DuelSession.confirmMulligan` only honors the first valid index);
the dialog retitled "Mulligan" → "First Draw"; the button relabeled "Confirm"
→ "Battle". This pass also closed the earlier click-simulation gap —
`user_mouse_input` succeeded via `instance_path` targeting (previously only
raw screen coordinates had been tried), verifying the real Re-draw and Battle
click handlers end-to-end instead of by code inspection alone. The "dealt
hand flies in" reveal beat from the original Phase 8 scope still isn't
built — deferred as a polish item alongside the rest of the VFX library.

**Second fix pass (2026-07-08):** two more issues from live testing. (1) Redraw
was client-visual-only — picking a card just badged it "REPLACE" and deferred
the actual swap to the Battle press. Now real-time: a new `RedrawMulliganCard`
RemoteFunction swaps the hand slot in place on the server the instant a card
is picked (`DuelSession.redrawMulliganCard`, enforced to at most one redraw
per seat regardless of call count) and the client rebuilds that tile with the
real new card immediately, not a label. `DuelSession.confirmMulligan` (Battle)
now just finalizes the seat — the swap already happened. (2) A duplicate-
looking Draw animation played on entering the real battle: dealing the
opening hands during mulligan calls `Logic.drawCard`, which records
`draw_card` anim events same as any live draw, but mulligan never broadcasts
— so those 10 stray events (5 per side) sat in `pendingAnimEvents` until the
real battle's first broadcast, where the client's Draw-phase logic (which
counts `draw_card` events to decide how many cards to fly in) misread them as
a fresh draw and replayed a fly-in over cards that were already sitting there
statically. Fixed by clearing `state.pendingAnimEvents` in `beginRealBattle`
right before the real turn starts, so only the genuinely-live turn_start/draw
survive into that first broadcast. Verified headless (redraw swaps in place,
rejects a second attempt, and the anim log drops from 10+ events to exactly
the real turn's own event) and live (a stubbed `RedrawMulliganCard` response
confirmed the client swaps in a real, different card with real stats —
verified via a genuine simulated click, not code inspection).

Full regression pass (headless, `execute_luau` Edit mode): mulligan → active
transition, envelope/event-log shape, the Charge event channel confirmed
structurally separate and untouched, spell-cast discard/graveyard growth
with a matching `cast` envelope, and — critically — the Fatigue-death fix
(`checkAndEnd` after `startTurn`/`endTurn`, `FOUND_BUGS.md`) still fires
correctly through the new mulligan stage and event log: a fatigued-out hero
still ends the battle immediately with no further broadcast for the dead
side. SaveService has no mulligan-related code path — confirmed a no-op for
migrated saves.

Full VFX library (AOE swipe, heal bloom, buff pulse, shield pulse, summon
puff, shatter, rebirth) and per-card VFX overrides remain a follow-up pass;
see PLAN_CARD_BATTLE_REVAMP.md's "Out of Scope" section for the asset list.

---

## Economy revamp — Card Fragments, battle rewards, Result UI (PLAN_ECONOMY_REVAMP.md, 2026-07-10)

All 6 phases implemented and verified — headless (`execute_luau`, Edit mode,
clone-and-rename technique) for every pure `ModuleScript`, and live in actual
Studio Play (`start_stop_play`, real connected test player) for the pieces
that touch a real `Player`/profile or client rendering. See
`PLAN_ECONOMY_REVAMP.md` for full phase-by-phase detail, including a real
Luau compiler bug found and fixed during implementation (not anticipated by
the approved plan) and a newly-confirmed `execute_luau` isolation constraint.

**New `cardFragments` currency** (`SaveService` schema **v5.3**) replaces
`crystalDust` everywhere — free gameplay currency, random packs only, per
`DESIGN_ECONOMY.md`. `crystalShards` is unchanged (paid/destroy/quest only)
but battle rewards no longer grant it or a fixed card drop (`DESIGN_REWARD.md`
§4.3). New per-profile fields: `dailyRewards` (day-bucketed
`battleFragments`/`npcFragments`/`forfeitCount`, reset via
`SaveService.dayBucket()`/`ensureDailyReset`), `matchmakingCooldownUntil`
(epoch seconds, early-forfeit cooldown ladder), `pveFirstClear` (per-archetype
MIGHTY/SWIFT/VITAL booleans).

**Reward engine.** New `ReplicatedStorage/Modules/RewardConfig.lua` centralizes
every DESIGN_REWARD.md constant (Matchmaking `3/1/2/0`, Local `1/0`, NPC
`1/0/50`, both daily caps, `EXP_PER_FRAGMENT=15`, the turn-4-or-2-actions
validity gate, the 5-tier forfeit cooldown ladder). `RewardService.lua`
rewritten as a pure classifier (`battle.mode`+`battle.matchmaking` →
Matchmaking/Local/NPC category, `reason="win"|"forfeit"` → early/late forfeit
split) with zero profile access. New `SaveService.applyBattleRewards` is the
sole place a reward plan becomes a real mutation: resolves the NPC
per-archetype first-clear bonus (bypasses both caps), clamps against the
200/day global and 10/day NPC sub-caps, computes `exp = granted *
EXP_PER_FRAGMENT` from the post-cap amount, force-saves. New
`SaveService.registerEarlyForfeit` drives the cooldown ladder, checked by
`JoinMatchmaking` (rejects with a `Notify` toast while active). PvP battles
now earn rewards too (previously earned nothing). Confirmed with the user:
NPC-fallback matchmaking (no human found) pays Matchmaking rates, not NPC
rates. DESIGN_REWARD.md §11 abuse-monitoring metrics are an explicit `TODO`
in `BattleController.lua`, not built this pass.

**Vending machine + Crystal Dust removal.** `GachaConfig`/`GachaTransaction`/
`GachaService` retarget the pack-purchase currency to `cardFragments`
(`COST_CARD_FRAGMENTS=160`, Standard Pack price; archetype Core Packs stay 200); a
duplicate roll is now added to the collection uncapped with `isDupe=true` and
no currency compensation (DESIGN_ECONOMY §12.4), instead of being blocked and
converted to Dust. `PackRevealController`'s summary screen (previously showed
"Converted to +N Dust") now reports duplicate counts instead — a real
regression caught and fixed, not just a missed file. `crystalDust` removed
from every remaining site (`RobuxShopController`, `QuestService`,
`CurrencyBarController`); the HUD's `DustBadge` Studio instance renamed
in-place to `FragmentsBadge` (editor-first) with a new `Theme.Colors.Fragment`
warm-gold accent.

**Post-battle Result UI.** `StarterGui.BattleUI.PostBattle` restructured as
real Studio instances onto the shared modal-panel language every other panel
uses (`Scrim`/`TitleBar`/`Body`, `UIComponents.applyModalShell`), tinted
Success/Danger per outcome, plus a new EXP progress bar (`LevelLabel` +
`ExpBarTrack`/`Fill`) driven by a new generic
`UIComponents.createProgressBar` primitive. `BattleUIController.lua`'s
`BattleOver` handler consumes the new reward-plan shape and renders a reward
line list (record message / Fragments / first-clear bonus / EXP) that
degrades cleanly to "No reward this time." for zero-reward outcomes.

**Real bugs found and fixed via live testing, not just inferred:** a Luau
compiler "Out of local registers" crash (200-local-per-chunk ceiling) in
`BattleUIController.lua` from adding ~12 new top-level locals to an
already-large script — fixed by grouping the new Post-battle instance refs
into one table and scoping one-time setup temporaries (`UI`/`Theme`) inside a
`do...end` block instead of leaving them as persistent top-level locals.
`multi_edit`'s `replace_all` silently no-op'd on 2 of 3 identical occurrences
in `VendingMachineController.lua` despite reporting success — caught by
verifying `Script.Source` directly rather than trusting the tool's report,
and fixed via a direct `Script.Source` pattern replacement (this project's
established workaround for this class of tooling gap). A previously-unknown
`execute_luau` constraint: even `datamodel_type: "Server"` during real Studio
Play runs in an isolated VM with its own `require` cache, separate from the
actual running server threads — `Save.getProfile(player)` returns `nil`
there even for a genuinely connected player, since that VM's `SaveService`
module was never populated via a real `onPlayerAdded`. Worked around by
exercising the real reward/currency paths through actual remotes
(`GetQuestSnapshot`, `OpenCardPack`) fired from the real client instead.

**What remains genuinely unverified:** a full multi-turn battle played to a
real win/loss through simulated clicks (mulligan → turns → attack) end-to-end
through `endBattle`/`applyBattleRewards` with a live profile — the equivalent
server-side reward math was instead verified by calling
`RewardService.buildBattleRewards` headlessly (14/14 assertions) and by
confirming the real `GetQuestSnapshot`/`OpenCardPack` remotes round-trip
correctly against the real live profile. The redesigned Result panel's exact
on-screen visual layout was not confirmed via screenshot — the `screen_capture`
tool did not render any `PlayerGui` `ScreenGui` content in this session (not
even the pre-existing, unmodified HUD), a capture-tool limitation rather than
a `PostBattle`-specific issue; confirmed instead via direct Instance-property
inspection (`gui.Enabled`, `post.Visible`, `AbsolutePosition`/`AbsoluteSize`,
`BackgroundTransparency`, `resultLabel.Text`) after firing a real `BattleOver`
remote at the real connected client.

Migration work still deferred (see `PLAN_ECONOMY_REVAMP.md`'s Next Steps):
daily quests (3×30 Fragments, explicitly out of scope this pass); the full
4-pack DESIGN_ECONOMY catalog (only one Standard-equivalent pack exists
today); manual "Destroy Card → Crystal Shards" crafting (Shards have no
gameplay income source until this exists); DESIGN_REWARD §11 abuse-monitoring
metrics.

---

## Targeting Revamp — Explicit playTarget (PLAN_BATTLE_TARGET.md, 2026-06-25)

All changes from PLAN_BATTLE_TARGET implemented. Schema validation passes with 133 cards and 0 errors.

**Removed:** `CardText.targetClass(card)`, `CardText.canHitFace(card)`, and all call sites in CardData and TargetingSystem.

**Added:** `CardText.playTarget(card)` — returns the card's explicit `playTarget` field for spells or `"empty_slot"` for creatures. CardData re-exports `playTarget`.

**playTarget values and count (50 pack spells + the_coin):**

| Value | Spells |
|---|---|
| `own_hero` | bristleplate, unbroken_guard, mistmend, renew, soul_recovery, moonpool_rite, crystal_vent |
| `own_side` | defiant_roar, clan_memory, clan_rally, den_reserves, hunting_instinct, emerald_rush, pack_tactics, nine_lives, sapphire_waters, grave_call, the_coin |
| `own_board` | bristle_banner, crimson_overrun, predators_assault, eternal_rebirth |
| `enemy_hero` | — (reserved for future cards) |
| `enemy_side` | shadow_smoke |
| `enemy_board` | thunderous_roar, last_stand, greenveil_ambush, memory_shards, spirit_harvest, essence_tide |
| `enemy_creature` | maulers_finish, crush_the_mighty, needle_step, glassfang_seal, apex_hunt, sudden_death, spirit_crush |
| `enemy_character` | vangorn_slam, fleetpaw_strike, twinclaw, sapphire_leech |
| `friendly_creature` | thickpelt_oath, clanhide_rite, vangorn_charge, whisker_reflex, emerald_claws, vanishing_pounce, spirit_touch, moonpool_blessing, spirit_bloom, rebirth_charm, crystal_growth |
| `battle_board` | — (reserved for future cards) |
| `any_creature` | — (reserved for future cards) |
| `friendly_character` | — (reserved for future cards) |

**CardSchema:** `PLAY_TARGETS` set enforced; spells without a valid `playTarget` fail validation; creatures with a `playTarget` field fail validation; spell `playTarget` is validated for compatibility with declared effects.

**TargetingSystem rewrite:**
- `computeDropZones(card)` now drives zones from `playTarget`; zone-drop targets (`own_board`, `enemy_board`, `battle_board`, `own_side`, `enemy_side`) add all relevant slot/hero frames with `kind="zoneDrop"`.
- `applyDragHighlights()` rewritten: zone-drops highlight without dimming (no single chosen target); chosen targets dim invalid slots normally.
- `dragHintText()` returns correct hint per playTarget value.
- `endDrag()` sends `opts.zone = "..."` for zone-drop kinds, chosen-target opts unchanged.

**BattleController (server):**
- `VALID_ZONES` table and `zoneCanonical()` added.
- `validateChosenTarget` now rejects stealthed enemy creatures for targeted spells.
- `validatePlayCard` accepts `opts.zone` for zone-drop spells: validates against `card.playTarget`, rejects mismatches, sets `opts.chosenZone = zoneCanonical(zone, who)`.

**BattleLogic:** `chosenZone = opts.chosenZone` threaded through all three `baseCtx` calls in `playCard` (emerge, playBlock, cast) for future zone-aware action resolution.

---

## Board-Generated Charge and New Card Actions (PLAN_BATTLE_CHARGE_V2.md, 2026-06-25)

All 8 phases of PLAN_BATTLE_CHARGE_V2 implemented. Post-review fixes on 2026-06-25 aligned invalid Shatter targeting, duplicate hand-tax behavior, NPC Crystal Vent scoring, the disabled-Shatter board marker, and docs/source JSON drift.

**Charge source change:** Normal +1 Charge from playing a MIGHTY/SWIFT/VITAL card is removed. Charge is now generated only by board creatures at end of turn. Each non-NEUTRAL creature on board at end of turn grants +1 Charge of its type to the owning slot (matching → stack; empty slot → create; both slots occupied off-type → skip). Board generation never displaces an occupied slot.

**Four new card actions (Effects/Actions, CardSchema, CardText):**

| Action | Trigger | Effect |
|---|---|---|
| `destroy_charge_slot` | cast | Destroys own lowest-amount Charge slot. Requires `two_charge_slots_occupied`. |
| `drain_charge` | cast | Removes N Charge from target player's current (or lowest) slot. Empties slot on zero. |
| `disable_shatter` | cast | Marks an enemy creature with Shatter as `shatterDisabled=true`; its Shatter effects do not fire while marked. Invalid on creatures with no Shatter. Cleared on bounce/death. |
| `add_additional_charge_cost_to_player_hand` | cast | Applies a +N Charge cost increase to matching Charge-cost card copies currently in the target's hand. Uses a remaining-copy count so later same-id draws do not extend the modifier. Selector: `"all"` or `"random"`. |

**New condition:** `two_charge_slots_occupied` — checks whether the specified side has both Charge slots occupied.

**New trigger:** `take_damage` — fires on a creature when it takes non-lethal damage.

**New ChargeState helpers:** `canGainWithoutReplace`, `bothSlotsOccupied`, `destroySlot`, `drainCharge`.

**New Ops helpers:** `destroyChargeSlot`, `drainCharge`, `addChargeCostMod`, `clearChargeCostMod`, `effectiveChargeCost`.

**CardCost (RS):** `canPay`, `getCostParts`, `failureReason` now apply `chargeCostMods` from `side.chargeCostMods` so both NPC and client badge show the effective (hand-taxed) cost.

**BattleRegistry:** `viewFor` now includes `chargeCostMods` in the player side payload.

**BattleUIController / CardVisuals:** `popChargeSocket` has distinct tweens for `board_end_turn` (gentle pulse), `drain` (sharp shrink+recover), and `destroy_slot` (scale-to-zero). `ChargeCostBadge.Value.TextColor3` accepts `chargeCostColor` (STAT_DEBUFF = red when hand-taxed). Hand render loop computes effective charge cost via `clientEffectiveChargeCost` and passes it through `buildCard`. Board cards show a compact red `X` marker when `shatterDisabled=true`.

**NpcAI:** contextual scoring for `destroy_charge_slot` (+6 if the action owner has ≥2 slots, −5 otherwise), `drain_charge` (+4 if enemy has charge, −3 otherwise), `disable_shatter` (+5 if enemy board has a shatter creature, −6 otherwise), `add_additional_charge_cost_to_player_hand` (+3 baseline). Creature scoring adds +2 if creature type stacks an existing slot, +1 otherwise.

**Pack counts:** 132 pack cards total (ruby_bear 40, emerald_cat 40, sapphire_frog 40, stonebark 12). 29 pure-Charge cards (ruby_bear 10, emerald_cat 9, sapphire_frog 10). 3 starters at 30 cards each, no Crystal Vent in starters.

Headless sim: 45 games (15 per matchup, 0 errors). Win rates: mighty vs swift swift wins 15–0 (avg 8 turns); mighty vs vital mighty wins 11–4 (avg 21 turns); swift vs vital swift wins 8–7 (avg 12 turns).

---

## Charge costs and CORRUPTED trait (PLAN_BATTLE_CHARGE_USAGE.md, 2026-06-23)

Three cost models live: **Energy-only** (unchanged), **Hybrid** (`cost=N` +
`chargeCost={battleType,amount}`), and **Pure-Charge** (`cost=0` +
`chargeCost={battleType,amount}`). Payment is atomic — both resources validated
before either is spent. Charge cost is paid before effect resolution; there is no normal played-card Charge grant in the current V2 rules.

- New `ReplicatedStorage/Modules/CardTraits` — `has(card, trait)` scans effects[] for
  a `passive` trigger entry by action name (e.g. `"corrupted"`).
- New `ReplicatedStorage/Modules/CardCost` — shared server+client helper:
  `getEnergyCost`, `getChargeCost`, `canPay`, `getCostParts`, `failureReason`.
- `CardSchema` extended: `passive` trigger, `corrupted` action, CORRUPTED-needs-passive guard.
- `BattleLogic.playCard` upgraded: `payChargeCost` helper uses reason `"card_cost"`.
  The former `grantNormalCharge` path was removed by PLAN_BATTLE_CHARGE_V2.
- `CardVisuals` extended: `ChargeCostBadge` alongside `CostBadge` (pure-Charge repositions
  to Energy slot, hides `CostBadge`); CORRUPTED name prefix `☠ `; `buildCardFrame` stores
  `EMBLEM_X`/`ENERGY_SIZE`/`ENERGY_Y` as frame attributes for runtime repositioning.
- `BattleUIController` and `InventoryController`: pass `chargeCost` and `corrupted` to
  `updateCardFrame`; hand, hover, mobile, and board previews preserve printed
  Charge costs and CORRUPTED markers; `InventoryController` deck editor shows
  per-type gen/spender/PC counts.
- `CardText`: renders passive `corrupted` as rules text instead of exposing the raw action name.
- `GraveLogPanel`: passes `chargeCost` and `corrupted` in card opts; removed stray
  `CostBadge.Visible` override that was fighting pure-Charge logic.
- `NpcAI`: affordability check upgraded to `CardCost.canPay` — NPC now correctly handles
  hybrid and pure-Charge cards.
- The early fixture cards from this phase were superseded by the PLAN_BATTLE_CHARGE_V2
  pack reconstruction. Current packs contain 29 pure-Charge cards and no current
  content depends on Corrupted.

Verified headless (Phase 1: 34/34, Phase 2+3+4: 21/23 correct assertions + 3/3 fix,
Phase 6 NPC: 4/4, Phase 7 content: 14/14).

---

## Battle Charge migration (2026-06-23)

The **Crystal Core active skill is fully removed and replaced by the two-slot
Battle Charge system** (`PLAN_BATTLE_CHARGE.md`). Summary of what changed:

- New shared `ReplicatedStorage/Modules/ChargeConfig` (producing types + Battle Type
  palette) and server `ServerScriptService/Modules/ChargeState` (authoritative
  two-slot state machine: gain/spend/normalize/replace + per-change events).
- `BattleLogic.playCard` originally granted **+1 normal Charge** after a
  MIGHTY/SWIFT/VITAL card resolved. PLAN_BATTLE_CHARGE_V2 removed that grant;
  Charge now comes from board end-turn generation and explicit `gain_charge`
  effects. `countCoreCard` and `useCore` remain removed.
- Removed: `coreId`/`coreUsedThisTurn`/`coreCounters`, `BattleLogic.useCore`, the
  `UseCore` server handler (remote left orphaned), NPC `aiUseCore`, and the entire
  client Core surface (preview/drag/targeting/panel). `CrystalCores.lua` is orphaned.
- Snapshots carry `chargeSlots`/`currentChargeSlot`/`chargeSeq`/`chargeEvents`
  (perspective-remapped); hero cards render two Charge sockets with emblem art.
- SaveService schema **v5.1**: v5.0 performed the intentional major reset for
  canonical card IDs; v5.1 non-destructively adds Developer Product receipt history.
  Profiles below major version 5 are wiped to fresh onboarding data on load,
  preventing retired IDs from surviving in collections or decks.

Verified headless (state machine 39/39, card-play integration, replication 16/16,
SaveService 8/8, 9-game AI sim 0 errors) and in live Studio Play (charge accrues and
renders, deck builder Core-free).

---

## Module Status

| Module | Location | Status |
|---|---|---|
| Cards (definitions) | `ReplicatedStorage/Definitions/Cards.lua` | ✅ Complete — 132 pack cards across 4 packs + `the_coin` engine card (NEUTRAL spell, cost 0, `gain_energy` 1; not collectible / never in a deck), id-keyed map, effects[] schema |
| Decks (definitions) | `ReplicatedStorage/Definitions/Decks.lua` | ✅ Complete — 3 starter decks normalized to 30 cards each, expanded from deck_starter.json |
| CrystalCores (definitions) | `ReplicatedStorage/Definitions/CrystalCores.lua` | ⚪ Orphaned — Crystal Core active skills removed (Battle Charge migration). Module still exists but nothing requires it; kept as a migration artifact. |
| ChargeConfig (definitions) | `ReplicatedStorage/Modules/ChargeConfig.lua` | ✅ Complete — shared single source of truth: Charge-producing types (`MIGHTY`/`SWIFT`/`VITAL`; NEUTRAL excluded), `isProducing()`, `MAX_SLOTS=2`, `ChargeEmblems`-adjacent `Colors` palette (also consumed by `CardVisuals.TC_type`) |
| ChargeState (engine) | `ServerScriptService/Modules/ChargeState.lua` | ✅ Complete — authoritative two-slot Charge state machine: `init`, `normalizeSlots`, `gainCharge`, `canSpendCharge`, `spendCharge`, `gainChargesOrdered`, `drainEvents`, `canGainWithoutReplace`, `bothSlotsOccupied`, `destroySlot`, `drainCharge`. Charge source is now board end-turn only; board generation uses `canGainWithoutReplace` to never displace an occupied off-type slot. |
| CardSchema | `ReplicatedStorage/Modules/CardSchema.lua` | ✅ Complete — validates required fields, trigger/action/target/condition/playTarget vocabs (incl. `passive` trigger + `corrupted` action + CORRUPTED-needs-passive guard + `take_damage` trigger + 4 new actions: `destroy_charge_slot`, `drain_charge`, `disable_shatter`, `add_additional_charge_cost_to_player_hand`), spell playTarget/effect compatibility, condition `two_charge_slots_occupied`, chargeCost fields, deck id resolution |
| CardTraits | `ReplicatedStorage/Modules/CardTraits.lua` | ✅ Complete — `has(card, trait)` scans effects[] for a `{trigger="passive", action=trait}` entry; nil-safe |
| CardCost | `ReplicatedStorage/Modules/CardCost.lua` | ✅ Complete — shared server+client cost helper: `getEnergyCost` (respects cost mods), `getChargeCost`, `canPay` (atomic: energy + effective charge), `getCostParts`, `failureReason`; handles all 3 cost models; applies `side.chargeCostMods` via local `effectiveChargeCost` helper so hand-taxed charge costs are reflected in affordability, badge display, and NPC decisions |
| CardText | `ReplicatedStorage/Modules/CardText.lua` | ✅ Complete — `getAbilityDisplay(cardId)` renders effects[] as (label, body), spell-level conditions shown as an *If …,* / *Chain:* prefix; passive `corrupted` renders as its Battle Charge rule text; `playTarget(card)` returns explicit spell playTarget or `"empty_slot"` for creatures |
| CardData (shim) | `ReplicatedStorage/Modules/CardData.lua` | ✅ Complete — thin shim the client requires; re-exposes `Cards` plus CardText's `getAbilityDisplay`/`playTarget` under the legacy `CardData` name |
| Effects/Util | `ServerScriptService/Modules/Effects/Util.lua` | ✅ Complete — BOARD_SIZE=3, `opp`, `getCreature`, `creatureTargets`, `attackOf`, `valueOf` (value/valueFrom) |
| Effects/Conditions | `ServerScriptService/Modules/Effects/Conditions.lua` | ✅ Complete — 7 condition types: `damaged`, `target_undamaged`, `attack_gte`, `attack_lte`, `friendly_damaged_exists`, `chain`, `two_charge_slots_occupied` |
| Effects/Targeting | `ServerScriptService/Modules/Effects/Targeting.lua` | ✅ Complete — resolves all target/area combos; chosen targets are descriptor-validated before use and illegal picks fall back only to legal server targets |
| Effects/Actions | `ServerScriptService/Modules/Effects/Actions.lua` | ✅ Complete — 16+ handlers: damage (single/all/split/lifesteal/valueFrom), heal, gain_armor, buff, draw_card (+filter), destroy, grant_keyword, summon, bounce, return_from_graveyard, reduce_cost, set_cost, gain_energy, gain_charge; plus 4 new: `destroy_charge_slot`, `drain_charge`, `disable_shatter`, `add_additional_charge_cost_to_player_hand` |
| Effects/Triggers | `ServerScriptService/Modules/Effects/Triggers.lua` | ✅ Complete — `fireEvent(state, event, base)`; `chain` fires on emerge/cast when `cardsPlayedThisTurn >= 2`; `base.dynamic` shared across entries of one card; `playBlock(base, card)` pre-play check rejects a spell when no effect would resolve (unmet condition / no valid target / action-specific invalid target such as `disable_shatter` on a non-Shatter creature) |
| Effects/Ops | `ServerScriptService/Modules/Effects/Ops.lua` | ✅ Complete — game-op mutation layer (healHero, healCreature, gainArmor, damageHero, damageCreature+`take_damage` event, killCreature+rebirth+`shatterDisabled` guard, buffCreature, drawCard+filter, bounce+`shatterDisabled` clear, summon, returnFromGraveyard, keyword helpers, cost system, gainEnergy, newInstance, destroyChargeSlot, drainCharge, addChargeCostMod with remaining-copy counts, clearChargeCostMod, effectiveChargeCost) |
| BattleLogic | `ServerScriptService/Modules/BattleLogic.lua` | ✅ Complete (effects[] engine + Board-Generated Charge V2) — `newSide`/`newBattle` initializes two-slot Charge state + `chargeCostMods={}`; `playCard` atomically validates/pays Energy + effective charge (`Ops.effectiveChargeCost`), clears `chargeCostMods` entry on play, threads `chosenZone` through emerge/playBlock/cast contexts, resolves emerge/cast — no normal +1 grant; `endTurn` iterates owner board and calls `ChargeState.gainCharge` for each non-NEUTRAL creature where `canGainWithoutReplace` is true (reason `"board_end_turn"`); `attack` fires `deal_damage` event. |
| NpcAI | `ServerScriptService/Modules/NpcAI.lua` | ✅ Complete (effects[] scoring, V2 action scoring, board-presence Charge bonus) — `takeTurn(state, Logic, who)`; `scoreCard` by action verb including contextual scoring for `destroy_charge_slot`, `drain_charge`, `disable_shatter`, `add_additional_charge_cost_to_player_hand`; creature scoring includes +1/+2 bonus for non-NEUTRAL types (board end-turn Charge generation); affordability uses `CardCost.canPay` with effective charge cost; `aiAttack` prefers lethal/clean kills and handles Taunt. |
| BattleController | `ServerScriptService/BattleController.lua` | ✅ Complete (v5 + PLAN_MATCHMAKING) — thin remote-wiring; battle records in `BattleRegistry`, turn loop in `DuelSession`, tables/seating in `TableManager`. `startPvE`/`startPvP` read active deck cards from `SaveService.getActiveBattleDeck`; Noob TalkPrompt wired; battle remotes derive seat/battle server-side, rate-limit lightly, validate `PlayCard`/`DeclareAttack`, validate chosen targets and `opts.zone` against `playTarget`, reject targeted enemy Stealth, leave `UseCore` orphaned/unwired, cancel session timers on battle end, delegate rewards to `RewardService`; every mode persists via `SaveService.applyBattleRewards` (PLAN_ECONOMY_REVAMP — PvP now earns rewards too, not just PvE), gates the early-forfeit cooldown ladder via `registerEarlyForfeit`, and includes `exp` progress in the `BattleOver` payload; `battle.matchmaking` flag (set only by `attemptSeatPendingMatches`) distinguishes matchmaking-originated battles from local ReadyUp PvP. `onMatchStart` (fired from `DuelSession.start` at mulligan-begin) calls `Save.beginMatch` for `mode=="pvp"` or any matchmaking battle. `attemptReconnect` (injected into `SaveService.init`) resumes a still-live same-server battle or attempts a different-server `TeleportAsync`. `PlayerRemoving` pauses (does not forfeit) a matchmaking battle still in progress — the existing turn-timeout/streak machinery becomes the only forfeit trigger; local PvP/normal PvE keep instant-forfeit-on-disconnect unchanged. `JoinMatchmaking`/`CancelMatchmaking` handlers + two poll loops (fast: queue pop/teleport processing; slow: expensive destination-side seating scan) wire `Matchmaker`/`ServerRegistry`. |
| BattleRegistry | `ServerScriptService/Modules/BattleRegistry.lua` | ✅ Complete — `Battles[battleId]`, `PlayerBattle[userId]` reverse index, `spectators` set; `viewFor`/`viewForSpectator` perspective relabel (own seat→`player`), `remapOpts`; clients never send battleId; state views include Battle Charge fields (`chargeSlots`, `currentChargeSlot`, `chargeSeq`, `chargeEvents`, `chargeCostMods`) and server timer metadata. PLAN_MATCHMAKING adds `canonicalSeatByUserId` (matches by UserId, not Player-instance identity — needed since a paused battle's seat holds a stale/disconnected Player reference) and `reconnectSeat` (repoints a seat's Player reference on rejoin). |
| DuelSession | `ServerScriptService/Modules/DuelSession.lua` | ✅ Complete — per-battle turn loop: `start` (deals hands, opens the `"mulligan"` pre-battle stage before the turn loop; PLAN_MATCHMAKING adds an optional `onMatchStart(battle)` callback fired right after `battle.status="mulligan"`), `confirmMulligan`, `afterHumanAction`, `humanEndTurn`, internal `runNpcTurn`/`startSeatTurn`; token-guarded human turn timers with `TURN_TIMEOUT_SECONDS` and `MAX_TIMEOUTS_BEFORE_FORFEIT` (this existing mechanism is now also the sole matchmaking-battle forfeit trigger, unmodified); mulligan timeout tokens are tracked per seat so simultaneous PvP mulligans force-resolve reliably; `checkAndEnd` runs after both `startTurn` (Fatigue) and `endTurn`. |
| RewardService | `ServerScriptService/Modules/RewardService.lua` | ✅ Complete (PLAN_ECONOMY_REVAMP) — pure classifier, no profile access; `buildBattleRewards(ctx)` with `reason="win"\|"forfeit"` returns `{mode, category, outcome, forfeited, earlyForfeit, valid, baseCardFragments, archetype}` per DESIGN_REWARD.md's Matchmaking/Local/NPC tables and the turn-4-or-2-actions validity gate. Fixed card drops removed. |
| TableManager | `ServerScriptService/Modules/TableManager.lua` | ✅ Complete — FREE/RESERVED/OCCUPIED tables; one table `ProximityPrompt` ("Sit"/disabled, no Stand Up); **chained `awaitSeated` seating, no HRP anchoring** (SeatWeld positions, jump-state+controls block eject); `spawnNpcAt` clones Noob to chair 2 for PvE; `handleTalkToNpc`/`handleReadyUp`/`handleStandUp`. **Seating reliability (2026-06-22):** `seatPlayerAt` now clears stale seat/lock state before re-seating, **respects `awaitSeated`** (3s window + one retry), and on failure releases the reservation and returns false — a battle can never start with the player unseated ("in place"). `handleTalkToNpc` no longer returns silently: when no table is free or seating fails it fires `BattleUnseated` (clears the optimistic "Finding Table" overlay) and `Notify` with a reason. BattleUI records the active Seat CFrame and, after the SeatWeld releases, performs the final client-owned 3.5-stud side placement on `BattleUnseated`/`BattleOver`. PLAN_MATCHMAKING adds `countFree()` (free-table count for `ServerRegistry`'s heartbeat). |
| ProfileStore | `ServerScriptService/Packages/ProfileStore.lua` | ✅ Vendored (loleris/MAD STUDIO, pinned commit `45c9847`) — session-locked DataStore lib; provenance/raw copy in repo `vendor/`. `DataStoreState="Access"` confirmed in this published place |
| SaveService | `ServerScriptService/Modules/SaveService.lua` | ✅ Complete — ProfileStore wrapper. Schema **v5.3** (PLAN_ECONOMY_REVAMP) adds `cardFragments`, `dailyRewards` (day-bucketed caps/forfeit counter), `matchmakingCooldownUntil`, `pveFirstClear`; removes `crystalDust`. New `applyBattleRewards` (caps + first-clear + EXP scaling, the sole place a `RewardService` plan becomes a real mutation), `registerEarlyForfeit`, `getExpProgress`, `getMatchmakingCooldownRemaining`, `dayBucket`. The old `applyRewards` (Shards/card-drop grant) is removed. PLAN_MATCHMAKING's v5.2 `jobId`/`mode` on `activeMatch` and reconnect-before-abandonment logic (mode-aware, live-confirmed) are unchanged. PLAN_CARD_VENDOR adds `applyCardCraft`/`applyCardBuy`/`applyCardDestroy` (delegate to `VendorTransaction`, share a new `commitVendorResult` helper for the mark-Dirty/currency-refresh/immediate-Save tail) — no schema version bump, only mutates fields already in v5.3. |
| Matchmaker | `ServerScriptService/Modules/Matchmaker.lua` | ✅ Complete (PLAN_MATCHMAKING) — `MemoryStoreQueue`-backed global FIFO queue (`enqueue`/`dequeue`/`tryMatch`/`consume`); destination selection (`selectDestination`/`selectDestinationForSingle`, authoritative self-check via `TableManager.countFree()` before falling back to the `ServerRegistry` hint); match creation (`createMatch`/`createNpcFallbackMatch`, writes `MM_PendingMatches`/`MM_PendingTeleports`, uses `TeleportService:ReserveServer` for the no-server-has-room case); per-server processing (`processPendingTeleportsForPlayers`, `getMatchesForThisServer`, `clearMatch`). |
| ServerRegistry | `ServerScriptService/Modules/ServerRegistry.lua` | ✅ Complete (PLAN_MATCHMAKING) — per-server heartbeat to a `MemoryStoreSortedMap` (`publish`, 10s cadence, sort key = free-table count), `getCandidates()` (hint only, per the "never trust the registry" rule), `init(getFreeTableCount)`. Guards against `game.JobId==""` in unpublished Studio Play (confirmed real, not just Edit-mode) with a one-time warning instead of a repeating MemoryStore error. |
| GachaConfig | `ReplicatedStorage/Modules/GachaConfig.lua` | ✅ Complete (PLAN_ECONOMY_REVAMP; PLAN_CARD_VENDOR fixed the price) — `COST_CARD_FRAGMENTS=200` (Standard Pack price, matches Core Packs), three rarity weights unchanged, `DUPE_DUST` removed. ⚠️ Still a single unified 132-card pool — the full named 4-pack DESIGN_ECONOMY catalog (Core Mighty/Swift/Vital + Standard) is a separate, still-pending migration. |
| GachaTransaction | `ServerScriptService/Modules/GachaTransaction.lua` | ✅ Complete (PLAN_ECONOMY_REVAMP) — deducts `cardFragments`; a duplicate roll is added to the collection uncapped with `isDupe=true` and no currency award (DESIGN_ECONOMY §12.4) instead of converting to Dust. Manual destroy-for-Shards now exists as of PLAN_CARD_VENDOR (see `VendorTransaction`/`VendorService` below) — this module itself is unchanged, dupes still aren't auto-converted on roll. |
| GachaService | `ServerScriptService/Modules/GachaService.lua` | ✅ Currency migrated (PLAN_ECONOMY_REVAMP) — `roll()` charges `Config.COST_CARD_FRAGMENTS`. ⚠️ Still a unified 132-card, three-rarity pool; the source-document pack pools and four alpha rarities remain a separate pending migration. |
| GachaController | `ServerScriptService/GachaController.lua` | ✅ Complete — authoritative proximity/rate-limit structure; currency now flows through as Card Fragments via `GachaService`/`SaveService.applyCardPackPurchase`/`GachaTransaction`. |
| VendorConfig | `ReplicatedStorage/Modules/VendorConfig.lua` | ✅ Complete (PLAN_CARD_VENDOR) — centralizes Craft/Buy/Destroy rates and rotation constants per DESIGN_ECONOMY §9/§10.4; `MAX_USEFUL_COPIES=2` (Craft/Buy eligibility) is deliberately distinct from `DESTROY_PROTECTED_COPIES.legendary=1` (destroy eligibility). |
| VendorTransaction | `ServerScriptService/Modules/VendorTransaction.lua` | ✅ Complete (PLAN_CARD_VENDOR) — pure `craft`/`buy` (shared `directPurchase` helper, differs only by currency field) and `destroy` (validates every request before mutating any, mirrors `GachaTransaction.apply`'s atomicity). No profile access, no game-state access. |
| VendorService | `ServerScriptService/Modules/VendorService.lua` | ✅ Complete (PLAN_CARD_VENDOR) — epoch-aligned deterministic rotation (`getRotationBucket`/`getStockCardIds`, zero persisted state, exact 00:00/08:00/16:00 boundaries), `buildStockView` for client display, `craftCard`/`buyCard` re-validate against the *current* stock before delegating to `SaveService`. |
| VendorController | `ServerScriptService/VendorController.lua` | ✅ Complete (PLAN_CARD_VENDOR) — mirrors `GachaController.lua`; `GetVendorStock`/`CraftCard`/`BuyCard` require Vendor-NPC proximity, `DestroyCards` deliberately does not (reachable from `InventoryController` anywhere). |
| VendorUI / VendorUIController | `StarterGui/VendorUI`, `StarterPlayer/StarterPlayerScripts/VendorUIController.lua` | ✅ Complete (PLAN_CARD_VENDOR) — `VendorUI` cloned from `ItemMallUI`'s shell (editor-first); `VendorUIController.lua` combines the Card Vendor NPC's `DialogueController`-based talk trigger with a Stock→Detail page-stack shop UI (Craft/Buy buttons, maxed/error states); re-fetches stock before re-rendering Detail post-purchase (a real staleness bug, fixed and live-verified). |
| InventoryController (Destroy) | `StarterGui/InventoryUI/InventoryController.lua` | ✅ Complete (PLAN_CARD_VENDOR) — "My Cards" card-select handler gains a "Destroy 1 Copy (+N Shards)" button, only spawned when owned copies exceed `VendorConfig.DESTROY_PROTECTED_COPIES` for that rarity; fires `DestroyCards`, reuses the existing `errorLabel` for feedback. One copy per click (disclosed simplification, not a quantity stepper). Live-verified via the underlying remote and the negative case (no button below the protection floor); the positive in-UI click wasn't exercised this pass (see Known Issues). |
| ShopConfig / ShopTransaction | `ReplicatedStorage/Modules/ShopConfig.lua`, `ServerScriptService/Modules/ShopTransaction.lua` | ⚠️ Legacy product configuration — receipt dedupe/grant structure is reusable; bundle sizes and prices must be replaced from `DESIGN_ECONOMY.md`. |
| RobuxShopController | `ServerScriptService/RobuxShopController.lua` | ✅ Code complete — one `ProcessReceipt` handler, persisted acknowledgement, policy cache/remote, unknown-product deferral, and authoritative currency refresh. Published real-purchase test pending. |
| VendingMachineController | `StarterPlayer/StarterPlayerScripts/VendingMachineController.lua` | ✅ Complete — Pack Select → Detail → live Contents page stack, per-draw disclosure, authoritative purchase, existing reveal lifecycle. Balance display is Fragments-only now (PLAN_ECONOMY_REVAMP — Shards aren't relevant to pack purchases); duplicate-protection copy no longer mentions Dust. `PackRevealController`'s summary screen reports duplicate counts instead of a Dust total. |
| CurrencyBar / ItemMall | `StarterGui/Hud`, `StarterGui/ItemMallUI`, `StarterPlayerScripts/ItemMallController` | ✅ Complete — `CurrencyBarController` shows Shards + Card Fragments (`FragmentsBadge`, renamed in-place from `DustBadge`, new `Theme.Colors.Fragment` warm-gold accent). ItemMall (Robux Shard shop) unaffected/unchanged — still deterministic Shard bundles. |
| GachaOddsSpec / ShopTransactionSpec | `TestService` | ✅ Passing, unaffected by the economy revamp — neither touches `crystalDust`/`cardFragments`. |
| GachaAcquisitionSpec | `TestService/GachaAcquisitionSpec.lua` | ✅ Complete (PLAN_ECONOMY_REVAMP) — assertions rewritten for `cardFragments` cost/balance and the uncapped-dupe-add-with-`isDupe`-flag transaction shape. |
| CardVisuals | `StarterGui/BattleUI/Modules/CardVisuals` | ✅ Complete — emblems LEFT edge; `ChargeCostBadge` alongside `CostBadge`; `updateCardFrame` accepts `chargeCost`, `chargeCostColor` (STAT_DEBUFF when hand-taxed), `corrupted`, and board status opts (`taunt`, `stealth`, `sick`, `shatterDisabled`); pure-Charge hides `CostBadge` and repositions `ChargeCostBadge` to Energy slot; Taunt uses a shield icon, Stealth uses a cloud/fog icon, disabled Shatter renders as a compact red `X` badge, and only sleeping/exhausted cards use the dark overlay; CORRUPTED prefix `☠ ` in NameBar |
| BattleUIController | `StarterGui/BattleUI/BattleUIController` | ✅ Complete — `buildCard` accepts `effChargeCost`; board/hand/mobile rendering handles Battle Charge costs and targeting; `popChargeSocket` has distinct Charge tweens; event-log translation now stages draw/play/cast/effect/attack work and queues phases from the full `animEvents` list in server order, including later attacks/casts in batched NPC-turn broadcasts; draw cards are hidden until the draw phase starts, including the first active hand reveal after mulligan. PLAN_ECONOMY_REVAMP: `PostBattle`'s `BattleOver` handler renders the new reward-plan shape (Fragments/first-clear/EXP line list) and the EXP progress bar; `ContinueBtn`/new `CloseButton` share a `dismissPostBattle` handler. PLAN_MATCHMAKING adds a `BattleReconnected` handler — the only client entry point that primes camera/lock state and renders directly from a full state snapshot without the normal `BattleSeated`→mulligan→first-`UpdateBattleState` sequence, since a reconnecting player's fresh client session has no such history to build on. |
| MatchmakingUI + MatchmakingController | `StarterGui/MatchmakingUI` (+ `StarterPlayerScripts/MatchmakingController`) | ✅ Complete (PLAN_MATCHMAKING) — HUD icon (`TopRightAnchor.MatchmakingButton`, cloned from `ItemMallButton`'s structure) + panel (Level display + Find Opponent/Cancel Matchmaking, `ItemMallUI`/`ItemMallController` shell pattern) + ticking elapsed-time icon label (`MulliganController`'s countdown pattern, counting up). Server-confirmed state transitions only (`JoinMatchmaking`/`CancelMatchmaking`/`MatchmakingUpdate`), never purely optimistic. Live-verified: icon/label at rest, and server-fired synthetic `MatchmakingUpdate` events correctly start/stop the real ticking timer and open/close the panel. Panel body click-to-`FireServer` wiring itself not exercised via a real simulated click this pass (same known UI-click-simulation limitation as `MulliganUI` Phase 8). |
| TargetingSystem | `StarterGui/BattleUI/Modules/TargetingSystem` | ✅ Complete — `computeDropZones` driven by `CardData.playTarget(card)` across single targets and zone drops; `endDrag` sends `{slot=idx}`, `{target={side,slot}}`, or `{zone="..."}`; targeted enemy creatures with Stealth are excluded client-side; Stealth no longer uses full-card dark dimming. |
| GraveLogPanel | `StarterGui/BattleUI/Modules/GraveLogPanel` | ✅ Complete — uses `creature`/`spell` types; passes `race`, `chargeCost`, and `corrupted` to card opts; stray `CostBadge.Visible=true` override removed (was fighting pure-Charge badge logic) |
| CardPreviewController | `StarterGui/BattleUI/Modules/CardPreviewController` | ✅ Complete — preview layer at ZIndex 50; `show(frame, opts, side)` supports above/left (auto-flips right near screen edge) |
| UXMode | `StarterGui/BattleUI/Modules/UXMode` | ✅ Complete — Desktop/Mobile toggle driven by viewport width (<800px=Mobile) and LastInputType |
| BattleDirector | `StarterGui/BattleUI/Modules/BattleDirector` | ✅ Complete — FIFO phase queue; single `isLocked()` input gate; per-phase `maxDuration` timeout safety net; `skip()` now clears queued work, marks the active phase cancelled, and cancels tracked tweens/connections before unlocking input. |
| PhaseRegistry | `StarterGui/BattleUI/Modules/PhaseRegistry` | ✅ Complete — handler-per-phase-type registry (`draw`, `play`, `attack`, `turn_banner`, `cast_reveal`, `effect`), mirrors the server's `Effects/Actions` pattern. `cast_reveal` now restores parent/anchor/position/rotation/size/z-index and uses cancellation-aware delayed callbacks/tween tracking. |
| EffectVisuals | `StarterGui/BattleUI/Modules/EffectVisuals` | ✅ Complete (mechanism only) — `resolveVisualArchetype(entry, card)`: default archetype from action/target/area, optional `card.vfx` override (unused by any current card); only the `projectile` archetype has a real handler so far |
| MulliganUI + MulliganController | `StarterGui/MulliganUI` (+ `StarterPlayerScripts/MulliganController`) | ✅ Complete — "First Draw" dialog; dealt-hand tiles each with their own "Re-draw" button (parented to the card); picking one calls `RedrawMulliganCard` for a real, immediate in-place swap (final, at most one), then "Battle" (`ConfirmMulligan`, no payload) finalizes; closes on the battle's first `UpdateBattleState`. Verified via genuine simulated clicks (`user_mouse_input` + `instance_path` targeting), not code inspection |
| InventoryService | `ServerScriptService/InventoryService` | ✅ Complete (Phase 5) — `GetInventory` RemoteFunction handler; returns the player's `collection` (cardId multiset) from `SaveService`; empty for no/inactive profile |
| DeckService | `ServerScriptService/DeckService` | ✅ Complete — RemoteFunction wrapper for `GetDecks`, `CreateDeck`, `SaveDeckCards`, `RenameDeck`, `DeleteDeck`, and `SetActiveDeck`; responses use `{ok=true,data=...}` or `{ok=false,error=...}` |
| Hud + HudController | `StarterGui/Hud` (+ `HudController`) | ✅ Complete — `TopRightAnchor` frame (horizontal UIListLayout) hosting world icons; `InventoryButton` now opens **Card Library**. `HudController` shows the anchor in free-roam, hides the whole group on `BattleLoading`/`BattleSeated`/`UpdateBattleState`, restores on `BattleOver`/`BattleUnseated`/respawn |
| InventoryUI + InventoryController | `StarterGui/InventoryUI` (+ `InventoryController`) | ✅ Complete — Card Library page stack. Card grid passes `chargeCost` and `corrupted` to `updateCardFrame`. Deck editor shows non-blocking `>2 Charge Types` warning plus per-type generator/spender (`MIG:+N/-N`) and pure-Charge count (`PC:N`) summary beneath the type indicator. |
| AssetIds | `ReplicatedStorage/Modules/AssetIds` | ✅ Complete — image SSOT with a small `startupList()`, exact-five `revealList(cards)`, and full-library `criticalList()` retained for audits. CardVisuals consumes the same IDs. |
| AssetPreloader | `ReplicatedStorage/Modules/AssetPreloader` | ✅ Complete — requires dense arrays, passes literal arrays to `PreloadAsync`, uses the documented callback plus successful `GetAssetFetchStatus`, and retries/times out each ID independently with bounded concurrency and failure reporting. |
| LoadingScreen | `ReplicatedFirst/LoadingScreen` | ✅ Complete — zero-remote-asset functional UI; gates only immediately needed shared images. The decorative background is non-blocking, Workspace/Lighting is not bulk preloaded, and exact rolled card art is gated by PackRevealController before the 3D stage. |
| NpcSit | `ServerScriptService/NpcSit` | ⚪ Retired (Disabled) — superseded by TableManager |
| ChairInteraction | `StarterPlayer/StarterPlayerScripts/ChairInteraction` | ⚪ Retired (removed/missing in current place) — superseded by TableManager |

**The game is playable for manual testing.** All modules implement the current ruleset (universal Energy, 3-slot board, direct face attacks, effects[] abilities, quickstrike/lifesteal/rebirth keywords, two-slot Battle Charge). Player starts with an active `Mighty Starter` deck; PvE Noob randomizes among the three starter decks.

---

## Card Definitions — Detail

- **132 unique pack cards** across 4 packs: ruby_bear (40 MIGHTY, 24 creatures / 16 spells, 10 pure-Charge), emerald_cat (40 SWIFT, 24 creatures / 16 spells, 9 pure-Charge), sapphire_frog (40 VITAL, 24 creatures / 16 spells, 10 pure-Charge), stonebark (12 NEUTRAL — 5 Treants, 5 Golems, Crystal Vent, Crystal Growth); plus `the_coin` engine card (not collectible). 29 pure-Charge cards total.
- Notable new cards using the four new actions:
  - `crystal_vent` (NEUTRAL spell, cost=2 Energy) — `destroy_charge_slot` (self, lowest) gated on `two_charge_slots_occupied`
  - `spirit_crush` (VITAL spell) — `drain_charge` (enemy current, 1)
  - `glassfang_seal` (SWIFT spell) — `disable_shatter` (enemy creature)
  - `shadow_smoke` (SWIFT spell) — `add_additional_charge_cost_to_player_hand` (enemy, all, +1)
  - Cards with `take_damage` trigger: `rumbleclaw`, `shardwake_stalwart` (MIGHTY), `amber_golem` (NEUTRAL)
- **3 starter decks** from deck_starter.json: mighty (30), swift (30), vital (30)
- **CrystalCores module remains orphaned**: 3 pure and 3 dual-type legacy Cores still exist in `ReplicatedStorage/Definitions/CrystalCores.lua` as a migration artifact, but no live code requires them.
- No Invoker; no old 32-card CardData
- All cards have `image_prompt` fields for AI art generation
- the_coin engine card: cost 0, `{trigger="cast", action="gain_energy", value=1}` — dealt to the second player in `DuelSession.start`; expires end of turn 2 if unused (`BattleLogic.endTurn`)

---

## BattleLogic — Detail

Effects[] engine implementing:
- Universal Energy ramp 0→10, Coin, Fatigue. Hero damage, including fatigue overkill, clamps HP at 0 so the UI never displays negative Core HP
- `playCard` — uses `Ops.effectiveChargeCost` + `Ops.effectiveCost` for cost mods; creature summons (slot required); spell casts; fires `emerge`/`cast` via Triggers bus; tallies `cardsPlayedThisTurn`; decrements affected `chargeCostMods` remaining-copy counts when a taxed card is played. Spells are gated by `Triggers.playBlock` first. No normal +1 Charge grant.
- `attack` — Hearthstone-style simultaneous combat; Taunt/Stealth gating; `quickstrike`; `lifesteal`; fires `deal_damage` event after resolution
- `startTurn` / `endTurn` — energy ramp, `clearTurnCostMods`, reset `attackedThisTurn`/`summonedThisTurn`; turn_end event fires; board end-turn Charge generation loop after turn_end effects; Coin expires on turn 2
- **Keywords:** `taunt`, `charge`, `stealth`, `quickstrike` (first-strike), `lifesteal` (heal source hero for damage dealt), `rebirth` (resummon full stats once; Shatter fires on the triggering death before rebirth)
- **Cost system:** `addCostMod`/`effectiveCost`/`clearTurnCostMods` over `hand`/`drawn_cards`/`returned_card` pools with `this_turn` duration
- No Invoker, no discounts, no combo_extra_attack

---

## NpcAI — Detail

- **`takeTurn(state, Logic, who)`** — `who` defaults to "npc"
- **Phase 1 — card play:** scores all affordable plays via `scoreCard(state, who, opp, card)` by action verb; `noisyPick` with jitter; loops until nothing scores above threshold. New action scoring: `destroy_charge_slot` (+6 if the action's charge owner has ≥2 slots, −5 otherwise), `drain_charge` (+4 if enemy has charge, −3), `disable_shatter` (+5 if enemy board has shatter creature, −6), `add_additional_charge_cost_to_player_hand` (+3 baseline). Creature scoring: non-NEUTRAL type bonus +2 if stacks existing slot, +1 otherwise (board end-turn Charge generation value).
- **Phase 2 — attack:** `aiAttack` prefers clean kills → lethal → even trade → safe poke → face; handles Taunt gating
- No Invoker scoring; does not deliberately sequence for Chain

---

## RemoteEvents

| Event | Direction | Payload |
|---|---|---|
| `StartDuel` | Client → Server | — (orphaned; no handler in BattleController v5) |
| `PlayCard` | Client → Server | `cardId, opts` where `opts = {slot=N}` (creature), `opts = {target={side,slot}}` (single-target spell; `slot=0` = hero), or `opts = {zone="own_board"|"enemy_board"|"battle_board"|"own_side"|"enemy_side"}` (zone-drop spell) |
| `DeclareAttack` | Client → Server | `attackerSlot, targetSlot` |
| `EndTurn` | Client → Server | — |
| `Forfeit` | Client → Server | — |
| `StandUp` | Client → Server | — (stand from a seat; also auto-stand on disconnect) |
| `ReadyUp` | Client → Server | — (PVP ready handshake) |
| `UseCore` | Client → Server | **Orphaned** (Battle Charge migration) — no server handler; firing it does nothing. Kept as a migration artifact like `StartDuel`/`UseSkill` |
| `OfferMulligan` | Server → Client | dealt 5-card hand, sent once per human seat when `DuelSession.start` opens the mulligan window |
| `RedrawMulliganCard` | Client → Server (RemoteFunction) | invoke with a 1-based hand index → `true, newCardId` on success (swaps that slot in place immediately) or `false, reason`; at most one success per seat per mulligan |
| `ConfirmMulligan` | Client → Server | no payload — finalizes the seat's mulligan (any redraw already happened via `RedrawMulliganCard`) |
| `UpdateBattleState` | Server → Client | sanitized, perspective-relabelled state snapshot (densified board arrays); player snapshot carries `costMods` (client effective-cost coloring); `animEvents` = ordered animatable event log (perspective-relabelled, cleared after each broadcast) driving `BattleDirector`; timer metadata = `serverNow`, `turnStartedAt`, `turnEndsAt`, `turnDuration`, `timeoutStreaks`; `warnings` = transient rejection reasons (energy/taunt/prerequisite/timeout), cleared after each broadcast |
| `BattleOver` | Server → Client | `{ winner, rewards }`. Current legacy PvE rewards = EXP/Crystal Shards/card drop; current PvP rewards use placeholder messages. Target payloads must implement `DESIGN_REWARD.md`. |
| `BattleSeated` | Server → Client | `tableId, chairIdx` — PVP pre-battle seat; shows SeatedOverlay |
| `BattleUnseated` | Server → Client | — hides SeatedOverlay/loading, unlocks controls, restores local table prompts after stand-up or aborted seating |
| `JoinMatchmaking` | Client → Server | no payload — enqueues the player into the cross-server matchmaking queue (PLAN_MATCHMAKING) |
| `CancelMatchmaking` | Client → Server | no payload — dequeues the player |
| `MatchmakingUpdate` | Server → Client | `"queued"\|"cancelled"\|"matched"` — server-confirmed matchmaking state transitions |
| `BattleReconnected` | Server → Client | full state snapshot (`Registry.viewFor` shape) — fired instead of the normal `BattleSeated`→mulligan→`UpdateBattleState` sequence when a reconnecting player resumes an already-active matchmaking battle |
| `BattleLoading` | Server → Client | — shows input-blocking PvE "Finding Table..." overlay; clears on battle state, unseat, battle over, timeout, or respawn |
| `Notify` | Server → Client | `message` — free-roam toast (own `NotifyOverlay` ScreenGui, shows even when BattleUI is disabled). Used by `handleTalkToNpc` for "all tables busy" / "couldn't seat you" |
| `GetInventory` | Client → Server (RemoteFunction) | invoke → returns the player's `collection` (cardId multiset) from `SaveService`; empty list if no active profile |
| `GetDecks` / `CreateDeck` / `SaveDeckCards` / `RenameDeck` / `DeleteDeck` / `SetActiveDeck` | Client → Server (RemoteFunction) | invoke → server-validated deck management responses |

---

## Persistence

**ProfileStore-backed persistence is live (PLAN_BACKEND Phase 4).** `SaveService`
(`SSS/Modules/SaveService`) wraps the vendored ProfileStore (`SSS/Packages/ProfileStore`,
pinned commit `45c9847`).

- **Store:** `"PlayerProfiles"`, key `Player_<UserId>`. Current legacy schema **v5.1** (canonical card-ID reset + receipt history):
  `{_version={major,minor}, archetype, collection, decks, activeDeckId,
  crystalShards, crystalDust, purchaseHistory, exp, level, pvp, activeMatch, quests}`. `crystalDust` must be removed and `cardFragments` added in the economy migration. Profiles below major version 5 run
  `major_reset` and receive fresh onboarding data using canonical card IDs.
- **Economy safety:** the former `crystalShards = 125` login override is removed;
  loaded and purchased balances are no longer overwritten on rejoin.
- **Lifecycle:** PlayerAdded → `StartSessionAsync` (session lock, `Cancel` on leave) →
  `migrate` (before `Reconcile`) → `Reconcile`. PlayerRemoving → `EndSession`.
  `OnSessionEnd` kicks on remote session steal. Connect-first + `Loading` guard.
- **New-player grant:** the v5 template starts empty and quest-gated; choosing an
  archetype grants its 30-card starter collection and active starter deck.
- **Autosave:** dirty-flag 60s pooled `Profile:Save()`; ProfileStore `AUTO_SAVE_PERIOD`
  (~300s) backstop; card drops and successful pack purchases schedule an immediate save.
- **Pack purchase (legacy):** `GachaTransaction` currently validates the entire
  roll, then updates Shards/cards/Dust atomically. It must migrate to Card Fragment
  deduction, no automatic duplicate conversion, and the duplicate-protection rules
  in `DESIGN_ECONOMY.md`.
- **Migration:** `migrate(data)` — minor (`MINOR_MIGRATIONS` table) / major (guarded
  hard reset to starter, `ALLOW_MAJOR_RESET`) / ahead (served as-is).
- **PvE rewards (legacy):** `BattleController.endBattle` →
  `SaveService.applyRewards` currently grants EXP/Crystal Shards/card drops to
  present human winners. Replace with the NPC reward schema in `DESIGN_REWARD.md`.
- **PvP W/L + anti rage-quit (v1.1):** `startPvP` → `SaveService.beginPvpMatch` flags both
  players `activeMatch` and **force-saves** it. `endBattle` → `recordPvpResult(player, won)`
  records `pvp.wins/losses` + clears the flag for present players (returns the running
  record, shown as `BattleOver` message "Victory!/Defeat. Record: XW/YL"). A player who
  disconnects mid-match keeps the flag (saved at start); on their **next login**
  `onPlayerAdded` sees it and records a loss + clears it. Exactly one loss either path
  (present→recorded now/flag cleared; absent→flag resolves on load). Survives rage-quit,
  crash, server crash.
- **Verified 2026-06-21:** live load + starter grant, real-DataStore reward persistence
  across a rejoin, hard-reset, and (headless) migration branches + session double-load guard.

> Verifying a running server's module state from MCP `execute_luau` does **not** work:
> it runs in an isolated plugin VM (separate `require` cache and `_G`). Use in-script
> `print` + `get_console_output` for live checks; `execute_luau` is for self-contained
> headless tests only.

---

## Known Issues

| Issue | Priority | Notes |
|---|---|---|
| Card art missing for most cards | 🔴 High | All cards have `image_prompt` fields; art not yet generated/wired. Placeholder `rbxassetid://115543591799677` used for creatures; `rbxassetid://127780045941863` for spell circles |
| Balance: VITAL too weak, MIGHTY too strong | 🔴 High | Headless sim (n=40/matchup, symmetric NpcAI): MIGHTY 71%, SWIFT 55%, VITAL 24%. MIGHTY vs VITAL 35–5. Naive AI doesn't pilot sustain/Lifesteal. Needs card tuning + smarter AI |
| Full PVP Local Server smoke still needed | 🟡 Medium | Phase 3 implementation has single-client Play smoke and isolated timer simulation coverage. Still run Studio Local Server with 2 players: sit/ready/start, independent views, timer resync across mobile/desktop switches, invalid remote probes, forfeit/disconnect cleanup. |
| Cross-server matchmaking/reconnect needs a published-place test | 🟡 Medium | PLAN_MATCHMAKING.md is fully implemented and verified single-server (real MemoryStore ops, real NPC-fallback seating, real disconnect-pauses-not-forfeits proof, real mode-aware abandonment firing). What's genuinely unverified: a real `TeleportAsync` landing a player on a different running server instance, a destination server receiving a real player via `PlayerAdded`/`GetJoinData().TeleportData`, and the different-server reconnect branch — Studio (published or not) cannot exercise cross-instance teleport by design. Needs a published, multi-server-capable place as a dedicated follow-up. |
| Archived/unauthorized SOUND assets | 🟡 Medium | Studio play console spams `Failed to load sound rbxassetid://1914538756: Requested asset is archived` and `asset id 150463355 … User is not authorized` (also `150463355`). These are **sound** assets (out of scope of the image preloader); likely from the environment template / a UI sound. Find the referencing instances and replace with owned, non-archived sounds. |
| World/decor textures are not explicitly pre-warmed | 🟢 Low | Roblox streams Workspace/Lighting assets normally. Bulk preloading them previously competed with the essential image gate; startup and exact-five reveal images are the explicit preload scope. |
| Legacy remotes intentionally orphaned | 🟢 Low | `StartDuel`, `UseSkill`, and `UsePlayerSkill` still exist in Remotes with no live server handler in BattleController v5. Kept as migration artifacts for now; deletion deferred to a later cleanup. |
| Stray empty image (`rbxassetid://0`) | 🟢 Low | One `ImageLabel`/`Decal` has `Image=""`/`rbxassetid://0` (surfaced during the asset audit). Harmless; clean up the leftover. |
| Avatar thumbnails in info widgets | 🟢 Low | Main hero portrait uses `GetUserThumbnailAsync`; check remaining placeholder widgets before closing this. |
| NPC foot orientation | 🟢 Low | Z-axis rotation fix pending |
| Economy revamp: no full live battle-playthrough verification | 🟡 Medium | PLAN_ECONOMY_REVAMP.md's reward math is verified headless (`RewardService.buildBattleRewards`, 14/14 assertions) and the currency/snapshot plumbing is verified live via real `GetQuestSnapshot`/`OpenCardPack` remote round-trips against the real connected test player's profile — but no full multi-turn battle was played to a real win/loss through simulated clicks end-to-end through `endBattle`/`applyBattleRewards`. Also discovered: `execute_luau` with `datamodel_type="Server"` during real Studio Play is itself an isolated VM (separate `require` cache from the actual running server threads) — `SaveService.getProfile(player)` returns `nil` there even for a real connected player, extending the previously-known Edit-mode isolation limitation. |
| Card Fragment icon is a reused placeholder | 🟢 Low | `AssetIds.Icons.CARD_FRAGMENT` reuses the former Crystal Dust icon asset (`rbxassetid://118745543637085`); no dedicated Fragment art exists yet, same class of gap as missing card art. |
| Card Vendor: Destroy button's positive in-UI click unverified | 🟢 Low | The `DestroyCards` remote it calls was independently live-verified multiple times (success, protected-copy rejection, proximity-independence); only the literal "click the button inside `InventoryUI`'s My Cards page" step wasn't exercised, since the test profile ran out of 3+-copy cards and had too few Card Fragments (7) to roll a fresh duplicate this session. Retest once a 3+-copy card is available. |
| Vendor icon is a reused placeholder | 🟢 Low | `VendorUI`'s header icon reuses `AssetIds.VendingIcon`; no dedicated Card Vendor icon exists yet, same class of gap as the Card Fragment icon. |
