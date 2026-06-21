# DEV_STATUS — Elemental TCG: Implementation State

> Last updated: 2026-06-21

---

## Module Status

| Module | Location | Status |
|---|---|---|
| Cards (definitions) | `ReplicatedStorage/Definitions/Cards.lua` | ✅ Complete — 90 pack cards across 4 packs + `the_coin` engine card (NEUTRAL spell, cost 0, `gain_energy` 1; not collectible / never in a deck), id-keyed map, effects[] schema |
| Decks (definitions) | `ReplicatedStorage/Definitions/Decks.lua` | ✅ Complete — 3 starter decks normalized to 30 cards each, expanded from deck_starter.json |
| CrystalCores (definitions) | `ReplicatedStorage/Definitions/CrystalCores.lua` | ✅ Complete — six alpha Cores (`core_vanguard`, `core_assassin`, `core_renewal`, `core_warrior`, `core_guardian`, `core_sage`), supported Battle Types, 2-Energy cost, 5/10/15 scaling helpers, and description text |
| CardSchema | `ReplicatedStorage/Modules/CardSchema.lua` | ✅ Complete — validates required fields, trigger/action/target/condition vocabs, deck id resolution |
| CardText | `ReplicatedStorage/Modules/CardText.lua` | ✅ Complete — `getAbilityDisplay(cardId)` renders effects[] as (label, body), spell-level conditions shown as an *If …,* / *Chain:* prefix; `targetClass(card)` → slot/friendly/enemy/hero; `canHitFace(card)` → bool |
| CardData (shim) | `ReplicatedStorage/Modules/CardData.lua` | ✅ Complete — thin shim the client requires; re-exposes `Cards` plus CardText's `getAbilityDisplay`/`targetClass`/`canHitFace` under the legacy `CardData` name |
| Effects/Util | `ServerScriptService/Modules/Effects/Util.lua` | ✅ Complete — BOARD_SIZE=3, `opp`, `getCreature`, `creatureTargets`, `attackOf`, `valueOf` (value/valueFrom) |
| Effects/Conditions | `ServerScriptService/Modules/Effects/Conditions.lua` | ✅ Complete — all 6 condition types: `damaged`, `target_undamaged`, `attack_gte`, `attack_lte`, `friendly_damaged_exists`, `chain` |
| Effects/Targeting | `ServerScriptService/Modules/Effects/Targeting.lua` | ✅ Complete — resolves all target/area combos; chosen targets are descriptor-validated before use and illegal picks fall back only to legal server targets |
| Effects/Actions | `ServerScriptService/Modules/Effects/Actions.lua` | ✅ Complete — 12+ handlers: damage (single/all/split/lifesteal/valueFrom), heal, gain_armor, buff, draw_card (+filter), destroy, grant_keyword, summon, bounce, return_from_graveyard, reduce_cost, set_cost, gain_energy |
| Effects/Triggers | `ServerScriptService/Modules/Effects/Triggers.lua` | ✅ Complete — `fireEvent(state, event, base)`; `chain` fires on emerge/cast when `cardsPlayedThisTurn >= 2`; `base.dynamic` shared across entries of one card; `playBlock(base, card)` pre-play check rejects a spell when no effect would resolve (unmet condition / no valid target) |
| Effects/Ops | `ServerScriptService/Modules/Effects/Ops.lua` | ✅ Complete — game-op mutation layer (healHero, healCreature, gainArmor, damageHero, damageCreature, killCreature+rebirth, buffCreature, drawCard+filter, bounce, summon, returnFromGraveyard, keyword helpers, cost system, gainEnergy, newInstance) |
| BattleLogic | `ServerScriptService/Modules/BattleLogic.lua` | ✅ Complete (effects[] engine + Crystal Core) — `newSide`/`newBattle`, `startTurn` (energy ramp, clearTurnCostMods, reset attacks/summons, reset Core use), `endTurn` (turn_end event, Coin expiry), `playCard` (effectiveCost, emerge/cast, Core counters for collectible MIGHTY/SWIFT/VITAL cards), `attack`, and `useCore` (cost, once-per-turn, target validation, armor/heal/damage/draw/Assassin kill bonus). No Invoker. |
| NpcAI | `ServerScriptService/Modules/NpcAI.lua` | ✅ Complete (effects[] scoring + simple Core AI) — `takeTurn(state, Logic, who)`; `scoreCard` by action verb; `aiUseCore` prefers Assassin lethal creature shots, Renewal healing, and Vanguard armor when spare Energy exists; `aiAttack` prefers lethal/clean kills and handles Taunt. |
| BattleController | `ServerScriptService/BattleController.lua` | ✅ Complete (v5) — thin remote-wiring; battle records in `BattleRegistry`, turn loop in `DuelSession`, tables/seating in `TableManager`. `startPvE`/`startPvP` read battle cards/Core from `SaveService.getActiveBattleDeck`; Noob TalkPrompt wired; battle remotes derive seat/battle server-side, rate-limit lightly, validate `PlayCard`/`DeclareAttack`/`UseCore`, cancel session timers on battle end, delegate rewards to `RewardService`; PvE persists via `SaveService.applyRewards` (present winners), PvP flags `beginPvpMatch` at start + records `recordPvpResult` at end (W/L, anti rage-quit); calls `SaveService.init()` at boot |
| BattleRegistry | `ServerScriptService/Modules/BattleRegistry.lua` | ✅ Complete — `Battles[battleId]`, `PlayerBattle[userId]` reverse index, `spectators` set; `viewFor`/`viewForSpectator` perspective relabel (own seat→`player`), `remapOpts`; clients never send battleId; state views include Core fields (`coreId`, `coreUsedThisTurn`, `coreCounters`) and server timer metadata (`serverNow`, `turnStartedAt`, `turnEndsAt`, `turnDuration`, perspective-remapped `timeoutStreaks`) |
| DuelSession | `ServerScriptService/Modules/DuelSession.lua` | ✅ Complete — per-battle turn loop: `start`, `afterHumanAction`, `humanEndTurn`, internal `runNpcTurn`; token-guarded human turn timers with `TURN_TIMEOUT_SECONDS` and `MAX_TIMEOUTS_BEFORE_FORFEIT`; timeout auto-end and repeated-timeout auto-forfeit |
| RewardService | `ServerScriptService/Modules/RewardService.lua` | ✅ Complete (policy only) — builds mode-aware reward payloads without persistence: PvE winner EXP/gold/NPC-deck card drop; PvE loser/npc no payload; PVP winner/loser placeholder messages for Phase 4 persistence |
| TableManager | `ServerScriptService/Modules/TableManager.lua` | ✅ Complete — FREE/RESERVED/OCCUPIED tables; one table `ProximityPrompt` ("Sit"/disabled, no Stand Up); **chained `awaitSeated` seating, no HRP anchoring** (SeatWeld positions, jump-state+controls block eject); `spawnNpcAt` clones Noob to chair 2 for PvE; `handleTalkToNpc`/`handleReadyUp`/`handleStandUp` |
| ProfileStore | `ServerScriptService/Packages/ProfileStore.lua` | ✅ Vendored (loleris/MAD STUDIO, pinned commit `45c9847`) — session-locked DataStore lib; provenance/raw copy in repo `vendor/`. `DataStoreState="Access"` confirmed in this published place |
| SaveService | `ServerScriptService/Modules/SaveService.lua` | ✅ Complete (Phase 4 + Crystal Core deck schema) — ProfileStore wrapper. Schema **v1.2** `{_version, archetype(legacy), collection(multiset), decks, activeDeckId, gold, exp, pvp={wins,losses}, activeMatch}`; new/migrated profiles receive one active valid `Mighty Starter` using `core_vanguard`; draft decks persist but only valid 30-card decks can be active. Validates ownership, Core-supported Battle Types + NEUTRAL, max 2 copies, exact 30 for active decks, 12-deck cap, immutable Core, and "must always have one active valid deck." API includes `getActiveBattleDeck`, `getDecks`, `createDeck`, `saveDeckCards`, `renameDeck`, `deleteDeck`, `setActiveDeck`, plus existing reward/PVP/profile APIs. |
| CardVisuals | `StarterGui/BattleUI/Modules/CardVisuals` | ✅ Complete — emblems LEFT edge (`EMBLEM_X=-0.05` full / `0.03` compact, AnchorPoint.X=0); type badge BOTTOM-CENTER (race label for creatures, "SPELL" for spells); spell circle frame (circular art + UICorner on art ImageLabel for true clip + archetype-colored ring); `wrapAbility(text,20)` deterministic word-wrap at fixed `TextSize=10*cardScale`; emblem value labels nudged to `(0.44, 0.5)` for optical centering in icons |
| BattleUIController | `StarterGui/BattleUI/BattleUIController` | ✅ Complete for current battle entry — CardText shim replaces old CardData; `cardType=="creature"`/`"spell"` throughout; `race` field passed to buildCard/preview opts; mobile drag zones use `CardData.targetClass` (desktop parity); rejection `warnings` shown as a transient toast on `TargetingOverlay`; `setCardHidden` saves `_wasVisible` before hiding, restores exact value on unhide. `BattleLoadingOverlay`, `SeatedOverlay`, client ControlModule lock, jump disable, local table-prompt suppression, desktop/mobile turn timer labels, and PVP reward messages now cover loading, seated, battle, unseat, battle-over, timeout, and respawn paths. Regression guards: `battleEnded` prevents post-battle `render(lastState)` from re-arming the battle camera, timer re-renders preserve the live countdown when `turnEndsAt` is unchanged, and Noob `TalkPrompt` also shows loading optimistically while the server-owned entry flow proceeds. |
| TargetingSystem | `StarterGui/BattleUI/Modules/TargetingSystem` | ✅ Complete — `computeDropZones` driven by `CardData.targetClass(card)` → slot/friendly/enemyCreature/enemyHero zones; `endDrag` sends `{slot=idx}` or `{target={side,slot}}` or `{target={side="npc",slot=0}}` for hero; stealth check inlined |
| GraveLogPanel | `StarterGui/BattleUI/Modules/GraveLogPanel` | ✅ Complete — uses `creature`/`spell` types; passes `race` to card opts |
| CardPreviewController | `StarterGui/BattleUI/Modules/CardPreviewController` | ✅ Complete — preview layer at ZIndex 50; `show(frame, opts, side)` supports above/left (auto-flips right near screen edge) |
| UXMode | `StarterGui/BattleUI/Modules/UXMode` | ✅ Complete — Desktop/Mobile toggle driven by viewport width (<800px=Mobile) and LastInputType |
| InventoryService | `ServerScriptService/InventoryService` | ✅ Complete (Phase 5) — `GetInventory` RemoteFunction handler; returns the player's `collection` (cardId multiset) from `SaveService`; empty for no/inactive profile |
| DeckService | `ServerScriptService/DeckService` | ✅ Complete — RemoteFunction wrapper for `GetDecks`, `CreateDeck`, `SaveDeckCards`, `RenameDeck`, `DeleteDeck`, and `SetActiveDeck`; responses use `{ok=true,data=...}` or `{ok=false,error=...}` |
| Hud + HudController | `StarterGui/Hud` (+ `HudController`) | ✅ Complete — `TopRightAnchor` frame (horizontal UIListLayout) hosting world icons; `InventoryButton` now opens **Card Library**. `HudController` shows the anchor in free-roam, hides the whole group on `BattleLoading`/`BattleSeated`/`UpdateBattleState`, restores on `BattleOver`/`BattleUnseated`/respawn |
| InventoryUI + InventoryController | `StarterGui/InventoryUI` (+ `InventoryController`) | ✅ Complete — Card Library page stack in one reusable panel: Home, My Cards, Deck List, Core Select, Deck Editor. My Cards preserves the owned-card grid/filter/preview behavior. Deck Builder uses deck remotes for create/save/rename/delete/set-active, shows Core identity/validity/card counts/active marker, saves incomplete drafts, filters legal owned cards by Core-supported types plus NEUTRAL, and uses a shared header Back button. |
| NpcSit | `ServerScriptService/NpcSit` | ⚪ Retired (Disabled) — superseded by TableManager |
| ChairInteraction | `StarterPlayer/StarterPlayerScripts/ChairInteraction` | ⚪ Retired (removed/missing in current place) — superseded by TableManager |

**The game is playable for manual testing.** All modules implement the current ruleset (universal Energy, 3-slot board, direct face attacks, effects[] abilities, quickstrike/lifesteal/rebirth keywords, Crystal Core active skills). Player starts with an active Core of Vanguard `Mighty Starter` deck; PvE Noob randomizes among the three starter decks and receives the matching pure Core.

---

## Card Definitions — Detail

- **90 unique pack cards** across 4 packs: ruby_bear (24 MIGHTY), emerald_cat (24 SWIFT), sapphire_frog (24 VITAL), stonebark (18 NEUTRAL); plus the `the_coin` engine card (second player's turn-1 Coin)
- **3 starter decks** from deck_starter.json: mighty (30), swift (30), vital (30)
- **6 Crystal Cores**: 3 pure and 3 dual-type Cores, alpha-tuned
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
| `UseCore` | Client → Server | `targetDescriptor` only; server derives battle/seat, remaps perspective, validates turn/energy/target/once-per-turn, then resolves the active Core |
| `UpdateBattleState` | Server → Client | sanitized, perspective-relabelled state snapshot (densified board arrays); player snapshot carries `costMods` (client effective-cost coloring); timer metadata = `serverNow`, `turnStartedAt`, `turnEndsAt`, `turnDuration`, `timeoutStreaks`; `warnings` = transient rejection reasons (energy/taunt/prerequisite/timeout), cleared after each broadcast |
| `BattleOver` | Server → Client | `{ winner, rewards }`. PvE rewards = EXP/gold/card-drop (persisted via SaveService). PvP rewards `.message` = "Victory!/Defeat. Record: XW/YL" (W/L persisted via SaveService) |
| `BattleSeated` | Server → Client | `tableId, chairIdx` — PVP pre-battle seat; shows SeatedOverlay |
| `BattleUnseated` | Server → Client | — hides SeatedOverlay/loading, unlocks controls, restores local table prompts after stand-up or aborted seating |
| `BattleLoading` | Server → Client | — shows input-blocking PvE "Finding Table..." overlay; clears on battle state, unseat, battle over, timeout, or respawn |
| `GetInventory` | Client → Server (RemoteFunction) | invoke → returns the player's `collection` (cardId multiset) from `SaveService`; empty list if no active profile |
| `GetDecks` / `CreateDeck` / `SaveDeckCards` / `RenameDeck` / `DeleteDeck` / `SetActiveDeck` | Client → Server (RemoteFunction) | invoke → server-validated deck management responses |

---

## Persistence

**ProfileStore-backed persistence is live (PLAN_BACKEND Phase 4).** `SaveService`
(`SSS/Modules/SaveService`) wraps the vendored ProfileStore (`SSS/Packages/ProfileStore`,
pinned commit `45c9847`).

- **Store:** `"PlayerProfiles"`, key `Player_<UserId>`. Schema **v1.2**:
  `{_version={major,minor}, archetype(legacy), collection (multiset of cardIds),
  decks={...}, activeDeckId, gold, exp, pvp={wins,losses},
  activeMatch=false|{battleId,startedAt}}`.
- **Lifecycle:** PlayerAdded → `StartSessionAsync` (session lock, `Cancel` on leave) →
  `migrate` (before `Reconcile`) → `Reconcile`. PlayerRemoving → `EndSession`.
  `OnSessionEnd` kicks on remote session steal. Connect-first + `Loading` guard.
- **New-player grant:** the template grants the 30-card MIGHTY starter collection plus
  one active valid `Mighty Starter` deck using `core_vanguard`.
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
| Legacy remotes intentionally orphaned | 🟢 Low | `StartDuel`, `UseSkill`, and `UsePlayerSkill` still exist in Remotes with no live server handler in BattleController v5. Kept as migration artifacts for now; deletion deferred to a later cleanup. |
| Avatar thumbnails in info widgets | 🟢 Low | Main hero portrait uses `GetUserThumbnailAsync`; check remaining placeholder widgets before closing this. |
| NPC foot orientation | 🟢 Low | Z-axis rotation fix pending |
