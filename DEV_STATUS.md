# DEV_STATUS — Elemental TCG: Implementation State

> Last updated: 2026-07-01 (monetization configured; published receipt test pending)

## Monetization and Vending Machine revamp — configured, receipt test pending

`PLAN_MONETIZATION.md` is the implementation record and source of truth. The live
place now has the persistent Shards/Dust HUD, leveled Vending Machine, live
server-computed **per-card-draw** odds, same-rarity duplicate protection using one
pre-pack ownership snapshot, policy-gated Item Mall, dynamic regional price lookup,
schema v5.1 receipt history, and a single idempotent `ProcessReceipt` handler that
waits for confirmed persistence before returning `PurchaseGranted`. The temporary
`crystalShards = 125` login override is removed.

All four Developer Product IDs and both dedicated currency icons are configured.
The remaining external step is the published-place receipt test with real Robux.
Existing acquisition, new odds, and Shop transaction specs pass, and Studio Play
starts without monetization script errors. Live Marketplace metadata resolves all
four products at the intended default prices, and the loading gate reports 14/14
essential assets preloaded with the new icons included.

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
| BattleController | `ServerScriptService/BattleController.lua` | ✅ Complete (v5) — thin remote-wiring; battle records in `BattleRegistry`, turn loop in `DuelSession`, tables/seating in `TableManager`. `startPvE`/`startPvP` read active deck cards from `SaveService.getActiveBattleDeck`; Noob TalkPrompt wired; battle remotes derive seat/battle server-side, rate-limit lightly, validate `PlayCard`/`DeclareAttack`, validate chosen targets and `opts.zone` against `playTarget`, reject targeted enemy Stealth, leave `UseCore` orphaned/unwired, cancel session timers on battle end, delegate rewards to `RewardService`; PvE persists via `SaveService.applyRewards` (present winners), PvP flags `beginPvpMatch` at start + records `recordPvpResult` at end (W/L, anti rage-quit); calls `SaveService.init()` at boot |
| BattleRegistry | `ServerScriptService/Modules/BattleRegistry.lua` | ✅ Complete — `Battles[battleId]`, `PlayerBattle[userId]` reverse index, `spectators` set; `viewFor`/`viewForSpectator` perspective relabel (own seat→`player`), `remapOpts`; clients never send battleId; state views include Battle Charge fields (`chargeSlots`, `currentChargeSlot`, `chargeSeq`, `chargeEvents`, `chargeCostMods`) and server timer metadata |
| DuelSession | `ServerScriptService/Modules/DuelSession.lua` | ✅ Complete — per-battle turn loop: `start`, `afterHumanAction`, `humanEndTurn`, internal `runNpcTurn`; token-guarded human turn timers with `TURN_TIMEOUT_SECONDS` and `MAX_TIMEOUTS_BEFORE_FORFEIT`; timeout auto-end and repeated-timeout auto-forfeit |
| RewardService | `ServerScriptService/Modules/RewardService.lua` | ✅ Complete (policy only) — builds mode-aware reward payloads without persistence: PvE winner EXP/gold/NPC-deck card drop; PvE loser/npc no payload; PVP winner/loser placeholder messages for Phase 4 persistence |
| TableManager | `ServerScriptService/Modules/TableManager.lua` | ✅ Complete — FREE/RESERVED/OCCUPIED tables; one table `ProximityPrompt` ("Sit"/disabled, no Stand Up); **chained `awaitSeated` seating, no HRP anchoring** (SeatWeld positions, jump-state+controls block eject); `spawnNpcAt` clones Noob to chair 2 for PvE; `handleTalkToNpc`/`handleReadyUp`/`handleStandUp`. **Seating reliability (2026-06-22):** `seatPlayerAt` now clears stale seat/lock state before re-seating, **respects `awaitSeated`** (3s window + one retry), and on failure releases the reservation and returns false — a battle can never start with the player unseated ("in place"). `handleTalkToNpc` no longer returns silently: when no table is free or seating fails it fires `BattleUnseated` (clears the optimistic "Finding Table" overlay) and `Notify` with a reason. BattleUI records the active Seat CFrame and, after the SeatWeld releases, performs the final client-owned 3.5-stud side placement on `BattleUnseated`/`BattleOver`. |
| ProfileStore | `ServerScriptService/Packages/ProfileStore.lua` | ✅ Vendored (loleris/MAD STUDIO, pinned commit `45c9847`) — session-locked DataStore lib; provenance/raw copy in repo `vendor/`. `DataStoreState="Access"` confirmed in this published place |
| SaveService | `ServerScriptService/Modules/SaveService.lua` | ✅ Complete — ProfileStore wrapper. Schema **v5.1** adds `purchaseHistory` non-destructively; the temporary login Shard override is removed. Card packs remain atomic, and Developer Product receipts are granted once and acknowledged only after `OnAfterSave`/`LastSavedData` confirms that PurchaseId persisted. |
| GachaConfig | `ReplicatedStorage/Modules/GachaConfig.lua` | ✅ Complete — shared 50-Shard cost, five-card count, 70/25/5 weights, 5/20/80 duplicate Dust, 8-stud prompt range, server tolerance, and cooldown. |
| GachaTransaction | `ServerScriptService/Modules/GachaTransaction.lua` | ✅ Complete — pure validate-first transaction; enforces the two-copy cap across existing and pending same-pack copies, converts later copies to Dust, and commits shards/cards/Dust together. |
| GachaService | `ServerScriptService/Modules/GachaService.lua` | ✅ Complete — unified 132-card pool, weighted five-card rolls, pre-pack snapshot duplicate protection, all-capped rarity fallback, and live per-draw odds from the same candidate logic. |
| GachaController | `ServerScriptService/GachaController.lua` | ✅ Complete — owns proximity/rate-limited `OpenCardPack` and `GetPackOdds`; serializes purchases and uses guarded cleanup. |
| ShopConfig / ShopTransaction | `ReplicatedStorage/Modules/ShopConfig.lua`, `ServerScriptService/Modules/ShopTransaction.lua` | ✅ Configured — four Developer Product IDs; pure atomic PurchaseId dedupe + Shard grant. |
| RobuxShopController | `ServerScriptService/RobuxShopController.lua` | ✅ Code complete — one `ProcessReceipt` handler, persisted acknowledgement, policy cache/remote, unknown-product deferral, and authoritative currency refresh. Published real-purchase test pending. |
| VendingMachineController | `StarterPlayer/StarterPlayerScripts/VendingMachineController.lua` | ✅ Complete — Pack Select → Detail → live Contents page stack, per-draw disclosure, authoritative purchase, and existing reveal lifecycle. |
| CurrencyBar / ItemMall | `StarterGui/Hud`, `StarterGui/ItemMallUI`, `StarterPlayerScripts/ItemMallController` | ✅ Configured — dedicated Shard/Dust icons, live balances, fail-closed policy gate, regional product prices, and battle-close behavior. |
| GachaOddsSpec / ShopTransactionSpec | `TestService` | ✅ Passing — odds totals/tier weights, capped exclusion/fallback, protected generation, receipt dedupe/atomicity, and v5.0→v5.1 preservation. |
| GachaAcquisitionSpec | `TestService/GachaAcquisitionSpec.lua` | ✅ Passing — verifies pool=132, five-card generation, same-pack cap/Dust behavior, insufficient-funds atomicity, and invalid-roll atomicity. |
| CardVisuals | `StarterGui/BattleUI/Modules/CardVisuals` | ✅ Complete — emblems LEFT edge; `ChargeCostBadge` alongside `CostBadge`; `updateCardFrame` accepts `chargeCost`, `chargeCostColor` (STAT_DEBUFF when hand-taxed), `corrupted`, and board `status.shatterDisabled` opts; pure-Charge hides `CostBadge` and repositions `ChargeCostBadge` to Energy slot; disabled Shatter renders as a compact red `X` badge; CORRUPTED prefix `☠ ` in NameBar |
| BattleUIController | `StarterGui/BattleUI/BattleUIController` | ✅ Complete — `buildCard` accepts `effChargeCost` and passes effective `chargeCost`/`chargeCostColor` to `updateCardFrame`; board render passes `shatterDisabled` status; hand render loop computes effective charge cost via `clientEffectiveChargeCost(state.player.chargeCostMods, ...)`; mobile hand dragging mirrors `CardData.playTarget(card)` zones and sends `opts.zone` for zone drops; `popChargeSocket` has distinct tweens for `board_end_turn` (gentle pulse), `drain` (sharp shrink), `destroy_slot` (scale-to-zero), `spend` (shrink), and other gains (pop). |
| TargetingSystem | `StarterGui/BattleUI/Modules/TargetingSystem` | ✅ Complete — `computeDropZones` driven by `CardData.playTarget(card)` across single targets and zone drops; `endDrag` sends `{slot=idx}`, `{target={side,slot}}`, or `{zone="..."}`; targeted enemy creatures with Stealth are excluded client-side |
| GraveLogPanel | `StarterGui/BattleUI/Modules/GraveLogPanel` | ✅ Complete — uses `creature`/`spell` types; passes `race`, `chargeCost`, and `corrupted` to card opts; stray `CostBadge.Visible=true` override removed (was fighting pure-Charge badge logic) |
| CardPreviewController | `StarterGui/BattleUI/Modules/CardPreviewController` | ✅ Complete — preview layer at ZIndex 50; `show(frame, opts, side)` supports above/left (auto-flips right near screen edge) |
| UXMode | `StarterGui/BattleUI/Modules/UXMode` | ✅ Complete — Desktop/Mobile toggle driven by viewport width (<800px=Mobile) and LastInputType |
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
  - Cards with `take_damage` trigger: `rumbleclaw`, `scarback` (MIGHTY), `amber_golem` (NEUTRAL)
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
| `UpdateBattleState` | Server → Client | sanitized, perspective-relabelled state snapshot (densified board arrays); player snapshot carries `costMods` (client effective-cost coloring); timer metadata = `serverNow`, `turnStartedAt`, `turnEndsAt`, `turnDuration`, `timeoutStreaks`; `warnings` = transient rejection reasons (energy/taunt/prerequisite/timeout), cleared after each broadcast |
| `BattleOver` | Server → Client | `{ winner, rewards }`. PvE rewards = EXP/gold/card-drop (persisted via SaveService). PvP rewards `.message` = "Victory!/Defeat. Record: XW/YL" (W/L persisted via SaveService) |
| `BattleSeated` | Server → Client | `tableId, chairIdx` — PVP pre-battle seat; shows SeatedOverlay |
| `BattleUnseated` | Server → Client | — hides SeatedOverlay/loading, unlocks controls, restores local table prompts after stand-up or aborted seating |
| `BattleLoading` | Server → Client | — shows input-blocking PvE "Finding Table..." overlay; clears on battle state, unseat, battle over, timeout, or respawn |
| `Notify` | Server → Client | `message` — free-roam toast (own `NotifyOverlay` ScreenGui, shows even when BattleUI is disabled). Used by `handleTalkToNpc` for "all tables busy" / "couldn't seat you" |
| `GetInventory` | Client → Server (RemoteFunction) | invoke → returns the player's `collection` (cardId multiset) from `SaveService`; empty list if no active profile |
| `GetDecks` / `CreateDeck` / `SaveDeckCards` / `RenameDeck` / `DeleteDeck` / `SetActiveDeck` | Client → Server (RemoteFunction) | invoke → server-validated deck management responses |

---

## Persistence

**ProfileStore-backed persistence is live (PLAN_BACKEND Phase 4).** `SaveService`
(`SSS/Modules/SaveService`) wraps the vendored ProfileStore (`SSS/Packages/ProfileStore`,
pinned commit `45c9847`).

- **Store:** `"PlayerProfiles"`, key `Player_<UserId>`. Schema **v5.1** (canonical card-ID reset + receipt history):
  `{_version={major,minor}, archetype, collection, decks, activeDeckId,
  crystalShards, crystalDust, purchaseHistory, exp, level, pvp, activeMatch, quests}`. Profiles below major version 5 run
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
- **Pack purchase:** `GachaTransaction` validates the entire roll before mutation,
  updates Shards/cards/Dust atomically, and returns authoritative balances. Same-pack
  repeats participate in the two-copy cap.
- **Migration:** `migrate(data)` — minor (`MINOR_MIGRATIONS` table) / major (guarded
  hard reset to starter, `ALLOW_MAJOR_RESET`) / ahead (served as-is).
- **PvE rewards:** `BattleController.endBattle` → `SaveService.applyRewards` for present
  human winners (EXP/Crystal Shards/card drop).
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
| Archived/unauthorized SOUND assets | 🟡 Medium | Studio play console spams `Failed to load sound rbxassetid://1914538756: Requested asset is archived` and `asset id 150463355 … User is not authorized` (also `150463355`). These are **sound** assets (out of scope of the image preloader); likely from the environment template / a UI sound. Find the referencing instances and replace with owned, non-archived sounds. |
| World/decor textures are not explicitly pre-warmed | 🟢 Low | Roblox streams Workspace/Lighting assets normally. Bulk preloading them previously competed with the essential image gate; startup and exact-five reveal images are the explicit preload scope. |
| Legacy remotes intentionally orphaned | 🟢 Low | `StartDuel`, `UseSkill`, and `UsePlayerSkill` still exist in Remotes with no live server handler in BattleController v5. Kept as migration artifacts for now; deletion deferred to a later cleanup. |
| Stray empty image (`rbxassetid://0`) | 🟢 Low | One `ImageLabel`/`Decal` has `Image=""`/`rbxassetid://0` (surfaced during the asset audit). Harmless; clean up the leftover. |
| Avatar thumbnails in info widgets | 🟢 Low | Main hero portrait uses `GetUserThumbnailAsync`; check remaining placeholder widgets before closing this. |
| NPC foot orientation | 🟢 Low | Z-axis rotation fix pending |
