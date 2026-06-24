# DEV_STATUS — Elemental TCG: Implementation State

> Last updated: 2026-06-23 (charge-cost + CORRUPTED pass)

---

## Charge costs and CORRUPTED trait (PLAN_BATTLE_CHARGE_USAGE.md, 2026-06-23)

Three cost models live: **Energy-only** (unchanged), **Hybrid** (`cost=N` +
`chargeCost={battleType,amount}`), and **Pure-Charge** (`cost=0` +
`chargeCost={battleType,amount}`). Payment is atomic — both resources validated
before either is spent. Charge cost paid before effect resolution and normal +1 grant.

- New `ReplicatedStorage/Modules/CardTraits` — `has(card, trait)` scans effects[] for
  a `passive` trigger entry by action name (e.g. `"corrupted"`).
- New `ReplicatedStorage/Modules/CardCost` — shared server+client helper:
  `getEnergyCost`, `getChargeCost`, `canPay`, `getCostParts`, `failureReason`.
- `CardSchema` extended: `passive` trigger, `corrupted` action, CORRUPTED-needs-passive guard.
- `BattleLogic.playCard` upgraded: `payChargeCost` helper uses reason `"card_cost"`;
  `grantNormalCharge` helper guards on `CardTraits.has(card, "corrupted")`.
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
- **Fixture cards**: `ruby_mauler` → hybrid cost=1+1M; `rubyhide_bear` → Corrupted pure-Charge cost=0+3M
  (passive corrupted + emerge gain_armor 3). `pack_ruby_bear.json` updated to match.

Verified headless (Phase 1: 34/34, Phase 2+3+4: 21/23 correct assertions + 3/3 fix,
Phase 6 NPC: 4/4, Phase 7 content: 14/14).

---

## Battle Charge migration (2026-06-23)

The **Crystal Core active skill is fully removed and replaced by the two-slot
Battle Charge system** (`PLAN_BATTLE_CHARGE.md`). Summary of what changed:

- New shared `ReplicatedStorage/Modules/ChargeConfig` (producing types + Battle Type
  palette) and server `ServerScriptService/Modules/ChargeState` (authoritative
  two-slot state machine: gain/spend/normalize/replace + per-change events).
- `BattleLogic.playCard` grants **+1 normal Charge** after a MIGHTY/SWIFT/VITAL card
  resolves (NEUTRAL/Coin none); supports `chargeCost` (paid before resolution) and a
  `gain_charge` effect action that **stacks** with the normal +1. `countCoreCard` and
  `useCore` removed.
- Removed: `coreId`/`coreUsedThisTurn`/`coreCounters`, `BattleLogic.useCore`, the
  `UseCore` server handler (remote left orphaned), NPC `aiUseCore`, and the entire
  client Core surface (preview/drag/targeting/panel). `CrystalCores.lua` is orphaned.
- Snapshots carry `chargeSlots`/`currentChargeSlot`/`chargeSeq`/`chargeEvents`
  (perspective-remapped); hero cards render two Charge sockets with emblem art.
- SaveService schema **v1.3**: decks are Core-free; migration tolerates leftover
  `coreId`; deck validation drops Core-type restrictions; the deck builder removed
  the Core Select page and added a `>2 Charge Types` warning.

Verified headless (state machine 39/39, card-play integration, replication 16/16,
SaveService 8/8, 9-game AI sim 0 errors) and in live Studio Play (charge accrues and
renders, deck builder Core-free).

---

## Module Status

| Module | Location | Status |
|---|---|---|
| Cards (definitions) | `ReplicatedStorage/Definitions/Cards.lua` | ✅ Complete — 90 pack cards across 4 packs + `the_coin` engine card (NEUTRAL spell, cost 0, `gain_energy` 1; not collectible / never in a deck), id-keyed map, effects[] schema |
| Decks (definitions) | `ReplicatedStorage/Definitions/Decks.lua` | ✅ Complete — 3 starter decks normalized to 30 cards each, expanded from deck_starter.json |
| CrystalCores (definitions) | `ReplicatedStorage/Definitions/CrystalCores.lua` | ⚪ Orphaned — Crystal Core active skills removed (Battle Charge migration). Module still exists but nothing requires it; kept as a migration artifact. |
| ChargeConfig (definitions) | `ReplicatedStorage/Modules/ChargeConfig.lua` | ✅ Complete — shared single source of truth: Charge-producing types (`MIGHTY`/`SWIFT`/`VITAL`; NEUTRAL excluded), `isProducing()`, `MAX_SLOTS=2`, `ChargeEmblems`-adjacent `Colors` palette (also consumed by `CardVisuals.TC_type`) |
| ChargeState (engine) | `ServerScriptService/Modules/ChargeState.lua` | ✅ Complete — authoritative two-slot Charge state machine: `init`, `normalizeSlots`, `gainCharge`, `canSpendCharge`, `spendCharge`, `gainChargesOrdered`, `drainEvents`. Gained Charge becomes current; 3rd distinct type replaces the inactive slot; spend moves current only on reaching zero. Unit-tested 39/39 |
| CardSchema | `ReplicatedStorage/Modules/CardSchema.lua` | ✅ Complete — validates required fields, trigger/action/target/condition vocabs (incl. `passive` trigger + `corrupted` action + CORRUPTED-needs-passive guard), chargeCost fields, deck id resolution |
| CardTraits | `ReplicatedStorage/Modules/CardTraits.lua` | ✅ Complete — `has(card, trait)` scans effects[] for a `{trigger="passive", action=trait}` entry; nil-safe |
| CardCost | `ReplicatedStorage/Modules/CardCost.lua` | ✅ Complete — shared server+client cost helper: `getEnergyCost` (respects cost mods), `getChargeCost`, `canPay` (atomic: energy + charge), `getCostParts`, `failureReason`; handles all 3 cost models |
| CardText | `ReplicatedStorage/Modules/CardText.lua` | ✅ Complete — `getAbilityDisplay(cardId)` renders effects[] as (label, body), spell-level conditions shown as an *If …,* / *Chain:* prefix; passive `corrupted` renders as its Battle Charge rule text; `targetClass(card)` → slot/friendly/enemy/hero; `canHitFace(card)` → bool |
| CardData (shim) | `ReplicatedStorage/Modules/CardData.lua` | ✅ Complete — thin shim the client requires; re-exposes `Cards` plus CardText's `getAbilityDisplay`/`targetClass`/`canHitFace` under the legacy `CardData` name |
| Effects/Util | `ServerScriptService/Modules/Effects/Util.lua` | ✅ Complete — BOARD_SIZE=3, `opp`, `getCreature`, `creatureTargets`, `attackOf`, `valueOf` (value/valueFrom) |
| Effects/Conditions | `ServerScriptService/Modules/Effects/Conditions.lua` | ✅ Complete — all 6 condition types: `damaged`, `target_undamaged`, `attack_gte`, `attack_lte`, `friendly_damaged_exists`, `chain` |
| Effects/Targeting | `ServerScriptService/Modules/Effects/Targeting.lua` | ✅ Complete — resolves all target/area combos; chosen targets are descriptor-validated before use and illegal picks fall back only to legal server targets |
| Effects/Actions | `ServerScriptService/Modules/Effects/Actions.lua` | ✅ Complete — 12+ handlers: damage (single/all/split/lifesteal/valueFrom), heal, gain_armor, buff, draw_card (+filter), destroy, grant_keyword, summon, bounce, return_from_graveyard, reduce_cost, set_cost, gain_energy |
| Effects/Triggers | `ServerScriptService/Modules/Effects/Triggers.lua` | ✅ Complete — `fireEvent(state, event, base)`; `chain` fires on emerge/cast when `cardsPlayedThisTurn >= 2`; `base.dynamic` shared across entries of one card; `playBlock(base, card)` pre-play check rejects a spell when no effect would resolve (unmet condition / no valid target) |
| Effects/Ops | `ServerScriptService/Modules/Effects/Ops.lua` | ✅ Complete — game-op mutation layer (healHero, healCreature, gainArmor, damageHero, damageCreature, killCreature+rebirth, buffCreature, drawCard+filter, bounce, summon, returnFromGraveyard, keyword helpers, cost system, gainEnergy, newInstance) |
| BattleLogic | `ServerScriptService/Modules/BattleLogic.lua` | ✅ Complete (effects[] engine + Battle Charge + charge costs) — `newSide`/`newBattle` initializes two-slot Charge state; `startTurn`/`endTurn`/`attack` unchanged; `playCard` atomically validates and pays both Energy and Charge (`payChargeCost` with reason `"card_cost"` before any effect), resolves emerge/cast, then calls `grantNormalCharge` (which guards on `CardTraits.has(card,"corrupted")` — CORRUPTED cards skip the +1). Event order: card_cost spend → explicit gain_charge effects → normal_play grant. |
| NpcAI | `ServerScriptService/Modules/NpcAI.lua` | ✅ Complete (effects[] scoring, no Core AI, CardCost.canPay affordability) — `takeTurn(state, Logic, who)`; `scoreCard` by action verb; affordability check uses `CardCost.canPay` (handles Energy-only, hybrid, and pure-Charge correctly — NPC can play cost=0 pure-Charge cards when it has enough Charge); `aiAttack` prefers lethal/clean kills and handles Taunt. |
| BattleController | `ServerScriptService/BattleController.lua` | ✅ Complete (v5) — thin remote-wiring; battle records in `BattleRegistry`, turn loop in `DuelSession`, tables/seating in `TableManager`. `startPvE`/`startPvP` read active deck cards from `SaveService.getActiveBattleDeck`; Noob TalkPrompt wired; battle remotes derive seat/battle server-side, rate-limit lightly, validate `PlayCard`/`DeclareAttack`, leave `UseCore` orphaned/unwired, cancel session timers on battle end, delegate rewards to `RewardService`; PvE persists via `SaveService.applyRewards` (present winners), PvP flags `beginPvpMatch` at start + records `recordPvpResult` at end (W/L, anti rage-quit); calls `SaveService.init()` at boot |
| BattleRegistry | `ServerScriptService/Modules/BattleRegistry.lua` | ✅ Complete — `Battles[battleId]`, `PlayerBattle[userId]` reverse index, `spectators` set; `viewFor`/`viewForSpectator` perspective relabel (own seat→`player`), `remapOpts`; clients never send battleId; state views include Battle Charge fields (`chargeSlots`, `currentChargeSlot`, `chargeSeq`, `chargeEvents`) and server timer metadata (`serverNow`, `turnStartedAt`, `turnEndsAt`, `turnDuration`, perspective-remapped `timeoutStreaks`) |
| DuelSession | `ServerScriptService/Modules/DuelSession.lua` | ✅ Complete — per-battle turn loop: `start`, `afterHumanAction`, `humanEndTurn`, internal `runNpcTurn`; token-guarded human turn timers with `TURN_TIMEOUT_SECONDS` and `MAX_TIMEOUTS_BEFORE_FORFEIT`; timeout auto-end and repeated-timeout auto-forfeit |
| RewardService | `ServerScriptService/Modules/RewardService.lua` | ✅ Complete (policy only) — builds mode-aware reward payloads without persistence: PvE winner EXP/gold/NPC-deck card drop; PvE loser/npc no payload; PVP winner/loser placeholder messages for Phase 4 persistence |
| TableManager | `ServerScriptService/Modules/TableManager.lua` | ✅ Complete — FREE/RESERVED/OCCUPIED tables; one table `ProximityPrompt` ("Sit"/disabled, no Stand Up); **chained `awaitSeated` seating, no HRP anchoring** (SeatWeld positions, jump-state+controls block eject); `spawnNpcAt` clones Noob to chair 2 for PvE; `handleTalkToNpc`/`handleReadyUp`/`handleStandUp`. **Seating reliability (2026-06-22):** `seatPlayerAt` now clears stale seat/lock state before re-seating, **respects `awaitSeated`** (3s window + one retry), and on failure releases the reservation and returns false — a battle can never start with the player unseated ("in place"). `handleTalkToNpc` no longer returns silently: when no table is free or seating fails it fires `BattleUnseated` (clears the optimistic "Finding Table" overlay) and `Notify` with a reason. |
| ProfileStore | `ServerScriptService/Packages/ProfileStore.lua` | ✅ Vendored (loleris/MAD STUDIO, pinned commit `45c9847`) — session-locked DataStore lib; provenance/raw copy in repo `vendor/`. `DataStoreState="Access"` confirmed in this published place |
| SaveService | `ServerScriptService/Modules/SaveService.lua` | ✅ Complete (Phase 4 + Charge deck schema) — ProfileStore wrapper. Schema **v1.3** `{_version, archetype(legacy), collection(multiset), decks, activeDeckId, gold, exp, pvp={wins,losses}, activeMatch}`; decks are **Core-free** (no `coreId`); `1.2->1.3` migration tolerates leftover `coreId` harmlessly. New/migrated profiles receive one active valid `Mighty Starter` deck; draft decks persist but only valid 30-card decks can be active. Validates known + owned cards, max 2 copies, exact 30 for active decks, 12-deck cap, and "must always have one active valid deck" — **no Core type restriction** (any owned card is legal). `createDeck(player, name)` is Core-free. API: `getActiveBattleDeck`, `getDecks`, `createDeck`, `saveDeckCards`, `renameDeck`, `deleteDeck`, `setActiveDeck`, plus reward/PVP/profile APIs. |
| CardVisuals | `StarterGui/BattleUI/Modules/CardVisuals` | ✅ Complete — emblems LEFT edge (`EMBLEM_X=-0.05` full / `0.03` compact, AnchorPoint.X=0); type badge BOTTOM-CENTER; spell circle frame; `wrapAbility`; `buildCardFrame` stores layout constants as frame attributes (`EMBLEM_X`, `ENERGY_SIZE`, `ENERGY_Y`) for runtime badge repositioning; `ChargeCostBadge` (battle-type emblem + amount) built alongside `CostBadge`; `updateCardFrame` accepts `chargeCost` and `corrupted` opts — pure-Charge hides `CostBadge` and repositions `ChargeCostBadge` to Energy slot; CORRUPTED prefix `☠ ` prepended to NameBar/NameBarShadow at same font/size/color |
| BattleUIController | `StarterGui/BattleUI/BattleUIController` | ✅ Complete — `buildCard` and board-preview opts pass `chargeCost = card.chargeCost` and `corrupted = CardTraits.has(card,"corrupted")` to `updateCardFrame`; all other existing behavior (CardText shim, race field, mobile drag zones, warning toasts, seating/loading/battle/timer paths) unchanged. |
| TargetingSystem | `StarterGui/BattleUI/Modules/TargetingSystem` | ✅ Complete — `computeDropZones` driven by `CardData.targetClass(card)` → slot/friendly/enemyCreature/enemyHero zones; `endDrag` sends `{slot=idx}` or `{target={side,slot}}` or `{target={side="npc",slot=0}}` for hero; stealth check inlined |
| GraveLogPanel | `StarterGui/BattleUI/Modules/GraveLogPanel` | ✅ Complete — uses `creature`/`spell` types; passes `race`, `chargeCost`, and `corrupted` to card opts; stray `CostBadge.Visible=true` override removed (was fighting pure-Charge badge logic) |
| CardPreviewController | `StarterGui/BattleUI/Modules/CardPreviewController` | ✅ Complete — preview layer at ZIndex 50; `show(frame, opts, side)` supports above/left (auto-flips right near screen edge) |
| UXMode | `StarterGui/BattleUI/Modules/UXMode` | ✅ Complete — Desktop/Mobile toggle driven by viewport width (<800px=Mobile) and LastInputType |
| InventoryService | `ServerScriptService/InventoryService` | ✅ Complete (Phase 5) — `GetInventory` RemoteFunction handler; returns the player's `collection` (cardId multiset) from `SaveService`; empty for no/inactive profile |
| DeckService | `ServerScriptService/DeckService` | ✅ Complete — RemoteFunction wrapper for `GetDecks`, `CreateDeck`, `SaveDeckCards`, `RenameDeck`, `DeleteDeck`, and `SetActiveDeck`; responses use `{ok=true,data=...}` or `{ok=false,error=...}` |
| Hud + HudController | `StarterGui/Hud` (+ `HudController`) | ✅ Complete — `TopRightAnchor` frame (horizontal UIListLayout) hosting world icons; `InventoryButton` now opens **Card Library**. `HudController` shows the anchor in free-roam, hides the whole group on `BattleLoading`/`BattleSeated`/`UpdateBattleState`, restores on `BattleOver`/`BattleUnseated`/respawn |
| InventoryUI + InventoryController | `StarterGui/InventoryUI` (+ `InventoryController`) | ✅ Complete — Card Library page stack. Card grid passes `chargeCost` and `corrupted` to `updateCardFrame`. Deck editor shows non-blocking `>2 Charge Types` warning plus per-type generator/spender (`MIG:+N/-N`) and pure-Charge count (`PC:N`) summary beneath the type indicator. |
| AssetIds | `ReplicatedStorage/Modules/AssetIds` | ✅ Complete — single source of truth for every gameplay image asset id (archetype BGs, per-card art, spell placeholder, ATK/HP/Energy icons, card-back, energy-alt/inventory icons, loading background). `criticalList()` returns the de-duped flat list the loading screen gates on. CardVisuals sources its ids from here (no hardcoded `rbxassetid` strings) |
| AssetPreloader | `ReplicatedStorage/Modules/AssetPreloader` | ✅ Complete — reliable preloading: builds a temp `ImageLabel` per id and `PreloadAsync`es **Instances** (not content strings, which fail at a high rate), then **re-preloads any failed asset up to N attempts** with linear backoff (the actual fix for the cold-fetch "blank on first join, works after rejoin" bug). `preload(ids, opts)` (progress callback + summary) and best-effort `preloadInstances(insts)` |
| LoadingScreen | `ReplicatedFirst/LoadingScreen` | ✅ Complete — branded loading screen built from **zero remote assets** (solid `BackgroundColor3`, default-font text, Frame progress bar) so it can never render blank; decorative bg image (`99142567993225`) faded in only on successful preload. Removes default loading GUI, gates release on the critical preload + `game.Loaded` with a ~12s hard timeout / continue-anyway, warms environment textures best-effort, then fades out. Verified in Studio play: `preloaded 11/11 critical assets`, no failures |
| NpcSit | `ServerScriptService/NpcSit` | ⚪ Retired (Disabled) — superseded by TableManager |
| ChairInteraction | `StarterPlayer/StarterPlayerScripts/ChairInteraction` | ⚪ Retired (removed/missing in current place) — superseded by TableManager |

**The game is playable for manual testing.** All modules implement the current ruleset (universal Energy, 3-slot board, direct face attacks, effects[] abilities, quickstrike/lifesteal/rebirth keywords, two-slot Battle Charge). Player starts with an active `Mighty Starter` deck; PvE Noob randomizes among the three starter decks.

---

## Card Definitions — Detail

- **90 unique pack cards** across 4 packs: ruby_bear (24 MIGHTY), emerald_cat (24 SWIFT), sapphire_frog (24 VITAL), stonebark (18 NEUTRAL); plus the `the_coin` engine card (second player's turn-1 Coin). Of these, **2 cards now carry `chargeCost`** (first charge-cost fixtures):
  - `ruby_mauler` — Hybrid: cost=1 Energy + 1 MIGHTY Charge (ATK 3 / HP 2)
  - `rubyhide_bear` — Corrupted Pure-Charge: cost=0 Energy + 3 MIGHTY Charge (ATK 2 / HP 5, passive corrupted, emerge gain_armor 3)
- **3 starter decks** from deck_starter.json: mighty (30), swift (30), vital (30)
- **CrystalCores module remains orphaned**: 3 pure and 3 dual-type legacy Cores still exist in `ReplicatedStorage/Definitions/CrystalCores.lua` as a migration artifact, but no live code requires them.
- No Invoker; no old 32-card CardData
- All cards have `image_prompt` fields for AI art generation
- the_coin engine card: cost 0, `{trigger="cast", action="gain_energy", value=1}` — dealt to the second player in `DuelSession.start`; expires end of turn 2 if unused (`BattleLogic.endTurn`)

---

## BattleLogic — Detail

Effects[] engine implementing:
- Universal Energy ramp 0→10, Coin, Fatigue. Hero damage, including fatigue overkill, clamps HP at 0 so the UI never displays negative Core HP
- `playCard` — uses `Ops.effectiveCost` for cost mods; creature summons (slot required); spell casts; fires `emerge`/`cast` via Triggers bus; tallies `cardsPlayedThisTurn`. Spells are gated by `Triggers.playBlock` first: if no effect would resolve, the play is refused with a player-facing reason and the card/Energy are kept
- `attack` — Hearthstone-style simultaneous combat; Taunt/Stealth gating; `quickstrike`: attacker deals first, no retaliation if defender dies from it; `lifesteal` via Ops on damage dealt
- `startTurn` / `endTurn` — energy ramp, `clearTurnCostMods`, reset `attackedThisTurn`/`summonedThisTurn`; turn_end event fires on endTurn; Coin expires on turn 2
- **Keywords:** `taunt`, `charge`, `stealth`, `quickstrike` (first-strike), `lifesteal` (heal source hero for damage dealt), `rebirth` (resummon full stats once; Shatter fires on the triggering death before rebirth)
- **Cost system:** `addCostMod`/`effectiveCost`/`clearTurnCostMods` over `hand`/`drawn_cards`/`returned_card` pools with `this_turn` duration
- No Invoker, no discounts, no combo_extra_attack

---

## NpcAI — Detail

- **`takeTurn(state, Logic, who)`** — `who` defaults to "npc"
- **Phase 1 — card play:** scores all affordable plays via `scoreCard(state, who, opp, card)` by action verb; `noisyPick` with jitter; loops until nothing scores above threshold
- **Phase 2 — attack:** `aiAttack` prefers clean kills → lethal → even trade → safe poke → face; handles Taunt gating
- No Invoker scoring; does not deliberately sequence for Chain

---

## RemoteEvents

| Event | Direction | Payload |
|---|---|---|
| `StartDuel` | Client → Server | — (orphaned; no handler in BattleController v5) |
| `PlayCard` | Client → Server | `cardId, opts` where `opts = {slot=N}` (creature) or `opts = {target={side,slot}}` (spell), `slot=0` = hero |
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

- **Store:** `"PlayerProfiles"`, key `Player_<UserId>`. Schema **v1.3** (Core-free decks):
  `{_version={major,minor}, archetype(legacy), collection (multiset of cardIds),
  decks={...}, activeDeckId, gold, exp, pvp={wins,losses},
  activeMatch=false|{battleId,startedAt}}`. `1.2->1.3` migration tolerates leftover
  `coreId` on old decks (harmless).
- **Lifecycle:** PlayerAdded → `StartSessionAsync` (session lock, `Cancel` on leave) →
  `migrate` (before `Reconcile`) → `Reconcile`. PlayerRemoving → `EndSession`.
  `OnSessionEnd` kicks on remote session steal. Connect-first + `Loading` guard.
- **New-player grant:** the template grants the 30-card MIGHTY starter collection plus
  one active valid `Mighty Starter` deck (no Core).
- **Autosave:** dirty-flag 60s pooled `Profile:Save()`; ProfileStore `AUTO_SAVE_PERIOD`
  (~300s) backstop; **card drops force an immediate save**.
- **Migration:** `migrate(data)` — minor (`MINOR_MIGRATIONS` table) / major (guarded
  hard reset to starter, `ALLOW_MAJOR_RESET`) / ahead (served as-is).
- **PvE rewards:** `BattleController.endBattle` → `SaveService.applyRewards` for present
  human winners (EXP/gold/card drop).
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
| Non-critical workspace SpecialMesh textures are not pre-warmed | 🟢 Low | `LoadingScreen` best-effort environment warm currently scans `ImageLabel`, `ImageButton`, `Decal`, `Texture`, and `MeshPart` under Workspace/Lighting, but not `SpecialMesh.TextureId`. The critical gameplay/UI image path is covered; this only affects cafe/world prop textures. |
| Legacy remotes intentionally orphaned | 🟢 Low | `StartDuel`, `UseSkill`, and `UsePlayerSkill` still exist in Remotes with no live server handler in BattleController v5. Kept as migration artifacts for now; deletion deferred to a later cleanup. |
| Stray empty image (`rbxassetid://0`) | 🟢 Low | One `ImageLabel`/`Decal` has `Image=""`/`rbxassetid://0` (surfaced during the asset audit). Harmless; clean up the leftover. |
| Avatar thumbnails in info widgets | 🟢 Low | Main hero portrait uses `GetUserThumbnailAsync`; check remaining placeholder widgets before closing this. |
| NPC foot orientation | 🟢 Low | Z-axis rotation fix pending |
