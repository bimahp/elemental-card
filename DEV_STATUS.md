# DEV_STATUS — Elemental TCG: Implementation State

> Last updated: 2026-06-21

---

## Module Status

| Module | Location | Status |
|---|---|---|
| Cards (definitions) | `ReplicatedStorage/Definitions/Cards.lua` | ✅ Complete — 90 cards across 4 packs, id-keyed map, effects[] schema |
| Decks (definitions) | `ReplicatedStorage/Definitions/Decks.lua` | ✅ Complete — 3 starter decks normalized to 30 cards each, expanded from deck_starter.json |
| CardSchema | `ReplicatedStorage/Modules/CardSchema.lua` | ✅ Complete — validates required fields, trigger/action/target/condition vocabs, deck id resolution |
| CardText | `ReplicatedStorage/Modules/CardText.lua` | ✅ Complete — `getAbilityDisplay(cardId)` renders effects[] as (label, body), spell-level conditions shown as an *If …,* / *Chain:* prefix; `targetClass(card)` → slot/friendly/enemy/hero; `canHitFace(card)` → bool |
| CardData (shim) | `ReplicatedStorage/Modules/CardData.lua` | ✅ Complete — thin shim the client requires; re-exposes `Cards` plus CardText's `getAbilityDisplay`/`targetClass`/`canHitFace` under the legacy `CardData` name |
| Effects/Util | `ServerScriptService/Modules/Effects/Util.lua` | ✅ Complete — BOARD_SIZE=3, `opp`, `getCreature`, `creatureTargets`, `attackOf`, `valueOf` (value/valueFrom) |
| Effects/Conditions | `ServerScriptService/Modules/Effects/Conditions.lua` | ✅ Complete — all 6 condition types: `damaged`, `target_undamaged`, `attack_gte`, `attack_lte`, `friendly_damaged_exists`, `chain` |
| Effects/Targeting | `ServerScriptService/Modules/Effects/Targeting.lua` | ✅ Complete — resolves all target/area combos; player-chosen via `ctx.chosenTarget` with random fallback |
| Effects/Actions | `ServerScriptService/Modules/Effects/Actions.lua` | ✅ Complete — 12+ handlers: damage (single/all/split/lifesteal/valueFrom), heal, gain_armor, buff, draw_card (+filter), destroy, grant_keyword, summon, bounce, return_from_graveyard, reduce_cost, set_cost, gain_energy |
| Effects/Triggers | `ServerScriptService/Modules/Effects/Triggers.lua` | ✅ Complete — `fireEvent(state, event, base)`; `chain` fires on emerge/cast when `cardsPlayedThisTurn >= 2`; `base.dynamic` shared across entries of one card; `playBlock(base, card)` pre-play check rejects a spell when no effect would resolve (unmet condition / no valid target) |
| Effects/Ops | `ServerScriptService/Modules/Effects/Ops.lua` | ✅ Complete — game-op mutation layer (healHero, healCreature, gainArmor, damageHero, damageCreature, killCreature+rebirth, buffCreature, drawCard+filter, bounce, summon, returnFromGraveyard, keyword helpers, cost system, gainEnergy, newInstance) |
| BattleLogic | `ServerScriptService/Modules/BattleLogic.lua` | ✅ Complete (effects[] engine) — `newSide`/`newBattle`, `startTurn` (energy ramp, clearTurnCostMods, reset attack/summon flags), `endTurn` (turn_end event, Coin expiry), `playCard` (effectiveCost, emerge/cast), `attack` (quickstrike first-strike, lifesteal). No Invoker. |
| NpcAI | `ServerScriptService/Modules/NpcAI.lua` | ✅ Complete (effects[] scoring) — `takeTurn(state, Logic, who)`; `scoreCard` by action verb; `aiAttack` prefers lethal/clean kills, handles Taunt. No Invoker scoring. |
| BattleController | `ServerScriptService/BattleController.lua` | ✅ Complete (v5) — thin remote-wiring; battle records in `BattleRegistry`, turn loop in `DuelSession`, tables/seating in `TableManager`. `startPvE`/`startPvP`; Noob TalkPrompt wired; `PlayCard.OnServerEvent` accepts `opts={slot=N}` or `opts={target={side,slot}}` |
| BattleRegistry | `ServerScriptService/Modules/BattleRegistry.lua` | ✅ Complete — `Battles[battleId]`, `PlayerBattle[userId]` reverse index, `spectators` set; `viewFor`/`viewForSpectator` perspective relabel (own seat→`player`), `remapOpts`; clients never send battleId |
| DuelSession | `ServerScriptService/Modules/DuelSession.lua` | ✅ Complete — per-battle turn loop: `start`, `afterHumanAction`, `humanEndTurn`, internal `runNpcTurn`; `endBattle` is the sole `status="ending"` setter |
| TableManager | `ServerScriptService/Modules/TableManager.lua` | ✅ Complete — FREE/RESERVED/OCCUPIED tables; one table `ProximityPrompt` ("Sit"/disabled, no Stand Up); **chained `awaitSeated` seating, no HRP anchoring** (SeatWeld positions, jump-state+controls block eject); `spawnNpcAt` clones Noob to chair 2 for PvE; `handleTalkToNpc`/`handleReadyUp`/`handleStandUp` |
| CardVisuals | `StarterGui/BattleUI/Modules/CardVisuals` | ✅ Complete — emblems LEFT edge (`EMBLEM_X=-0.05` full / `0.03` compact, AnchorPoint.X=0); type badge BOTTOM-CENTER (race label for creatures, "SPELL" for spells); spell circle frame (circular art + UICorner on art ImageLabel for true clip + archetype-colored ring); `wrapAbility(text,20)` deterministic word-wrap at fixed `TextSize=10*cardScale`; emblem value labels nudged to `(0.44, 0.5)` for optical centering in icons |
| BattleUIController | `StarterGui/BattleUI/BattleUIController` | 🟡 Mostly complete — CardText shim replaces old CardData; `cardType=="creature"`/`"spell"` throughout; `race` field passed to buildCard/preview opts; mobile drag zones use `CardData.targetClass` (desktop parity); rejection `warnings` shown as a transient toast on `TargetingOverlay`; `setCardHidden` saves `_wasVisible` before hiding, restores exact value on unhide. **Battle-entry UI:** `SeatedOverlay` exists, but `BattleLoading` has no client listener yet, seated ControlModule lock is only active once battle state arrives, and local table-prompt suppression while seated still needs Phase 2.1 cleanup. |
| TargetingSystem | `StarterGui/BattleUI/Modules/TargetingSystem` | ✅ Complete — `computeDropZones` driven by `CardData.targetClass(card)` → slot/friendly/enemyCreature/enemyHero zones; `endDrag` sends `{slot=idx}` or `{target={side,slot}}` or `{target={side="npc",slot=0}}` for hero; stealth check inlined |
| GraveLogPanel | `StarterGui/BattleUI/Modules/GraveLogPanel` | ✅ Complete — uses `creature`/`spell` types; passes `race` to card opts |
| CardPreviewController | `StarterGui/BattleUI/Modules/CardPreviewController` | ✅ Complete — preview layer at ZIndex 50; `show(frame, opts, side)` supports above/left (auto-flips right near screen edge) |
| UXMode | `StarterGui/BattleUI/Modules/UXMode` | ✅ Complete — Desktop/Mobile toggle driven by viewport width (<800px=Mobile) and LastInputType |
| NpcSit | `ServerScriptService/NpcSit` | ⚪ Retired (Disabled) — superseded by TableManager |
| ChairInteraction | `StarterPlayer/StarterPlayerScripts/ChairInteraction` | ⚪ Retired (Disabled) — superseded by TableManager |

**The game is playable for manual testing.** All modules implement the current ruleset (universal Energy, 3-slot board, direct face attacks, effects[] abilities, quickstrike/lifesteal/rebirth keywords). Player starts with the MIGHTY starter deck; PvE Noob randomizes among the three starter decks.

---

## Card Definitions — Detail

- **90 unique cards** across 4 packs: ruby_bear (24 MIGHTY), emerald_cat (24 SWIFT), sapphire_frog (24 VITAL), stonebark (18 NEUTRAL)
- **3 starter decks** from deck_starter.json: mighty (30), swift (30), vital (30)
- No Invoker; no old 32-card CardData
- All cards have `image_prompt` fields for AI art generation
- the_coin engine card: cost 0, `{trigger="cast", action="gain_energy", value=1}`

---

## BattleLogic — Detail

Effects[] engine implementing:
- Universal Energy ramp 0→10, Coin, Fatigue
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
| `UpdateBattleState` | Server → Client | sanitized, perspective-relabelled state snapshot (densified board arrays); player snapshot carries `costMods` (client effective-cost coloring); `warnings` = transient rejection reasons (energy/taunt/prerequisite), cleared after each broadcast |
| `BattleOver` | Server → Client | `{ winner, rewards }` |
| `BattleSeated` | Server → Client | `tableId, chairIdx` — PVP pre-battle seat; shows SeatedOverlay |
| `BattleUnseated` | Server → Client | — hides SeatedOverlay (stand up / PVP battle start) |
| `BattleLoading` | Server → Client | — PvE loading hook exists; client listener/overlay is pending Phase 2.1 |

---

## Persistence

No production persistence is currently wired. Raw `GetAsync`/`SetAsync` reward
writes were removed during the BattleController refactor. `SaveService` with
ProfileStore is planned for PLAN_BACKEND Phase 4.

---

## Known Issues

| Issue | Priority | Notes |
|---|---|---|
| Card art missing for most cards | 🔴 High | All cards have `image_prompt` fields; art not yet generated/wired. Placeholder `rbxassetid://115543591799677` used for creatures; `rbxassetid://127780045941863` for spell circles |
| Balance: VITAL too weak, MIGHTY too strong | 🔴 High | Headless sim (n=40/matchup, symmetric NpcAI): MIGHTY 71%, SWIFT 55%, VITAL 24%. MIGHTY vs VITAL 35–5. Naive AI doesn't pilot sustain/Lifesteal. Needs card tuning + smarter AI |
| Phase 2.1 hardening pending | 🟡 Medium | BattleLoading client handling, seated prompt suppression/control lock, stale seat artifacts, and remote target validation need cleanup before Phase 3. |
| Legacy remotes may be orphaned | 🟢 Low | `StartDuel`, `UseSkill`, and `UsePlayerSkill` exist in Remotes but have no live server handler in BattleController v5. Confirm before deleting. |
| Avatar thumbnails in info widgets | 🟢 Low | Main hero portrait uses `GetUserThumbnailAsync`; check remaining placeholder widgets before closing this. |
| NPC foot orientation | 🟢 Low | Z-axis rotation fix pending |
