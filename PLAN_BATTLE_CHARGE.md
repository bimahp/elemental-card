# PLAN_BATTLE_CHARGE.md - Two-Slot Hero Charge System

## Summary
Replace the current Crystal Core active-skill/counter system with a server-authoritative two-slot Battle Type Charge system. Each hero stores up to two Charge Types at once. MIGHTY, SWIFT, and VITAL cards generate normal +1 Charge after successful resolution; NEUTRAL never generates or occupies Charge. Explicit extra Charge effects stack with normal generation, so a card texted as "gain +2 extra Charge" produces +3 total when played. Decks no longer choose or store a Core, and deck construction allows any owned cards while warning when more than two Charge-producing types are represented.

## Locked Decisions
- Remove Crystal Core active skills entirely.
- Remove deck-bound `coreId`; do not keep Cores as cosmetic deck identity.
- NEUTRAL is non-Charge-producing.
- First implementation is system/engine/UI/deck-builder foundation; do not broadly migrate card content to Charge costs yet.
- Energy, Armor, HP, combat, turn timer, PvP lifecycle, rewards, collection, and seating stay unchanged unless directly affected by Core removal.

## Implementation Status (2026-06-23)

**All phases implemented and verified** (Claude, in tandem with Codex). Built directly
in the Studio place via MCP; save the place to persist.

- [x] **Phase 0** — Baseline audit + safety harness. Clean reference captured (schema valid, headless battle 0 errors, Studio Play boots clean).
- [x] **Phase 1** — `ReplicatedStorage/Modules/ChargeConfig` + `ServerScriptService/Modules/ChargeState` (two-slot machine, all invariants). **39/39 unit assertions.** `CardVisuals.TC_type` now sources `ChargeConfig.Colors` (dedup).
- [x] **Phase 2** — `BattleLogic.playCard` grants +1 normal Charge post-resolution; `chargeCost` pay + `gain_charge` action (stacks); `Ops.gainCharge/spendCharge`; `CardSchema` vocab. `countCoreCard` removed. Integration tests pass (creature/spell +1, stacking +3, NEUTRAL none, energy/playBlock reject, self-cost guard, cross-card spend, self-killing creature).
- [x] **Phase 3** — Crystal Core active system fully removed (engine + AI + controller + client UI). Zero residual `useCore`/`coreCounters`/`coreUsedThisTurn`; 6-game sim 0 errors; Studio Play clean. `UseCore` remote + `CrystalCores.lua` left orphaned.
- [x] **Phase 4** — Snapshots carry `chargeSlots`/`currentChargeSlot`/`chargeSeq`/`chargeEvents`, perspective-remapped, drained per broadcast. **16/16 replication assertions.**
- [x] **Phase 5** — `mkHeroSlot` two-socket Charge container + `paintChargeSlots` (emblem art from `AssetIds.ChargeEmblems`, current-slot glow) + socket pop animation on `chargeEvents`. Desktop + mobile verified in live battle; emblems preloaded (14/14). *(Note: gain/spend feedback is an on-socket pop, not a fly-from-source; spell-origin anchor deferred as optional polish.)*
- [x] **Phase 6** — SaveService **v1.3** (Core-free validation; `1.2->1.3` migration tolerates leftover `coreId`); `createDeck(player,name)`; deck builder removed Core Select, allows any owned cards, adds the `>2 Charge Types` warning. **8/8** headless + live remote/UI smoke.
- [x] **Phase 7** — NPC Core logic already removed (Phase 3); 9-game symmetric AI sim 0 errors, NPC accrues Charge.
- [x] **Phase 8** — Docs reconciled (`DESIGN_CORE`/`ENGINE`/`DATABASE`/`UI`, `DEV_STATUS`, `README`, this file).

**Remaining manual gates:** full 2-player Local Server PVP smoke; a real-device first-join
check of the new emblem assets; the optional fly-from-source Charge animation + spell anchor;
and the deferred Charge **content** pass (deciding which cards use `chargeCost`/`gain_charge`)
and post-Core-removal balance re-tuning.

---

## Phase 0 - Baseline Audit and Safety Harness
**Goal:** Establish a clean reference point before replacing a central battle resource.

**Implementation steps**
- Record current live Studio paths and symbols touched by Core counters and Core active skills:
  - `ServerScriptService.Modules.BattleLogic`
  - `ServerScriptService.Modules.BattleRegistry`
  - `ServerScriptService.Modules.NpcAI`
  - `ServerScriptService.BattleController`
  - `ServerScriptService.Modules.SaveService`
  - `ReplicatedStorage.Definitions.CrystalCores`
  - `StarterGui.BattleUI.BattleUIController`
  - `StarterGui.BattleUI.Modules.TargetingSystem`
  - `StarterGui.InventoryUI.InventoryController`
- Snapshot current behavior for:
  - playing a creature
  - playing a spell
  - using a Core
  - starting PvE
  - creating/editing/saving/activating a deck
  - desktop and mobile battle UI render
- Decide implementation branch/file ownership before code changes.

**Tests and regression checks**
- Run current card schema validation.
- Run a simple headless battle start and one card play to confirm current baseline.
- Run Studio Play once and confirm no new console errors before implementation begins.
- Regression watch: existing uncommitted doc changes and Studio-only scripts must not be overwritten accidentally.

## Phase 1 - Charge Config and State Machine
**Goal:** Add the authoritative Charge model independently of card play and UI.

**Implementation steps**
- Create a shared Charge configuration module:
  - Charge-producing Battle Types: `MIGHTY`, `SWIFT`, `VITAL`
  - Non-producing Battle Types: `NEUTRAL`
  - Type colors should reuse existing card Battle Type colors.
- Add per-side battle state:
  ```lua
  chargeSlots = {
    { battleType = nil, amount = 0 },
    { battleType = nil, amount = 0 },
  }
  currentChargeSlot = nil
  chargeSeq = 0
  pendingChargeEvents = {}
  ```
- Implement one central server module for Charge transitions:
  - `normalizeSlots(side)`
  - `gainCharge(state, who, battleType, amount, sourceInfo)`
  - `canSpendCharge(side, battleType, amount)`
  - `spendCharge(state, who, battleType, amount, sourceInfo)`
  - `gainChargesOrdered(state, who, orderedGains, sourceInfo)`
- Enforce invariants:
  - max two occupied Charge Types
  - no duplicate occupied Battle Type
  - occupied slot has amount > 0
  - empty slot has `battleType=nil`, `amount=0`
  - if one slot is occupied, it is current
  - if both slots are occupied, exactly one is current
- Third type gain replaces the inactive occupied slot. No prompt, no client decision.
- Spending does not change current slot unless the spent slot reaches zero.

**Tests and regression checks**
- Unit-test the state machine:
  - first Charge fills slot 1 and becomes current
  - second distinct Charge fills empty slot and becomes current
  - matching current Charge increments and remains current
  - matching inactive Charge increments and becomes current
  - third type replaces inactive slot and preserves previously current slot as inactive
  - spending current does not move current unless amount reaches zero
  - spending inactive does not move current unless inactive reaches zero
  - spending exactly to zero empties the slot
  - one remaining occupied slot is normalized to current
  - invalid duplicate-type state is repaired deterministically
  - ordered multi-gain resolves one event at a time
- Regression watch:
  - Energy values must never be affected by Charge operations.
  - Armor/HP must not be stored inside Charge state.
  - NEUTRAL must never occupy a slot.

## Phase 2 - Card Play Integration and Charge Costs
**Goal:** Generate normal Charges after successful card resolution and prepare for future Charge costs/effects.

**Implementation steps**
- Remove the existing `countCoreCard()` timing from `BattleLogic.playCard`; it currently increments before effects resolve and must not survive.
- For creatures:
  - validate Energy, Charge costs, board slot, target, and play requirements
  - pay Energy and Charge costs
  - remove card from hand
  - place creature in board slot
  - resolve `emerge`
  - then register normal +1 Charge if the card's Battle Type is Charge-producing
- For spells:
  - validate Energy, Charge costs, target, and play requirements
  - pay Energy and Charge costs
  - remove card from hand
  - resolve `cast`
  - then register normal +1 Charge if Charge-producing
  - then move spell to discard
- Add card/effect schema support for future:
  ```lua
  chargeCost = { battleType = "MIGHTY", amount = 2 }
  { trigger = "cast", action = "gain_charge", battleType = "MIGHTY", value = 2 }
  ```
- Explicit `gain_charge` effects stack with normal played-card generation. If a MIGHTY spell has `gain_charge MIGHTY 2`, it gains +2 during effect resolution and then +1 normal after successful play.
- Keep current card pool unchanged unless a tiny test-only fixture is needed.

**Tests and regression checks**
- Creature play grants +1 after `emerge`.
- Spell play grants +1 after `cast` and before discard snapshot is finalized.
- A failed Energy check grants no Charge.
- A rejected spell from `Triggers.playBlock` grants no Charge.
- A creature whose Emerge effect kills itself still grants normal Charge if the play succeeded.
- Tokens, rebirth, summon-from-effect, return-from-graveyard, and board copies do not grant normal played-card Charge.
- A bounced card replayed from hand grants Charge again.
- A card cannot use the Charge it will generate to pay its own `chargeCost`.
- A later card in the same turn can spend Charge generated by an earlier resolved card.
- Regression watch:
  - Chain still counts card play correctly.
  - Cost modifiers still use Energy cost only.
  - Spell prerequisites still keep card and Energy when rejected.
  - Coin remains Energy-only and should not generate Charge.

## Phase 3 - Remove Crystal Core Active System
**Goal:** Fully remove the old Core active power and hidden per-type counter model.

**Implementation steps**
- Remove or retire:
  - `coreId`
  - `coreUsedThisTurn`
  - `coreCounters`
  - `BattleLogic.useCore`
  - `UseCore` remote handler
  - Core activation targeting in `TargetingSystem`
  - Core active preview/input binding in `BattleUIController`
  - NPC `aiUseCore`
  - Core scaling display via `CrystalCores.describe`
- Keep the hero/Core visual as the hero card surface only: HP, Armor, portrait, and Charge Slots.
- Remove Core active state from snapshots and spectator views.
- Keep obsolete `UseCore` remote only if needed as a migration artifact, but leave it unwired and documented like other orphaned remotes.

**Tests and regression checks**
- Studio grep confirms no live code path calls `Logic.useCore`.
- `UseCore` spam from a client does nothing and causes no server error.
- NPC turns still play cards and attack.
- PvE and PvP battle start still work.
- Hero HP/Armor rendering still updates.
- Regression watch:
  - Removing Core input must not break dragging cards or attacks.
  - Removing Core AI must not break `NpcAI.takeTurn`.
  - Removing `coreCounters` must not break `BattleRegistry.viewFor`.

## Phase 4 - Replication and Charge Event Payloads
**Goal:** Ensure clients, opponents, and spectators receive full authoritative Charge state and enough event data for animation.

**Implementation steps**
- Extend battle snapshots with:
  ```lua
  chargeSlots
  currentChargeSlot
  chargeSeq
  chargeEvents
  ```
- Add `ChargeChanged` event records to `pendingChargeEvents` during Charge mutations.
- Include event fields:
  - affected side
  - source card/effect id
  - source board slot or visual hint
  - reason: `normal_play`, `effect_gain`, `spend`, `replace`, `steal`, `destroy`, `convert`
  - Battle Type
  - amount gained or spent
  - changed slot index
  - previous slot state
  - final slot state
  - replacement flag
  - replaced Battle Type and amount
  - updated current slot
  - sequence number
- Include `chargeEvents` in `viewFor` and `viewForSpectator`.
- Clear `pendingChargeEvents` after broadcast, similar to transient warnings.
- State must be authoritative immediately; animation completion must not affect rules.

**Tests and regression checks**
- Local player view shows own Charge Slots.
- Opponent view shows public enemy Charge Slots.
- Spectator view includes both sides' Charge Slots.
- Multiple Charge gains in one card produce ordered event sequence numbers.
- A reconnect/snapshot without historical events still renders correct final Charge state.
- Regression watch:
  - Warnings still clear after broadcast.
  - Timer metadata still reaches clients.
  - Perspective remap must not invert Charge ownership incorrectly.

## Phase 5 - Battle UI and Animation
**Goal:** Render two compact Charge Slots on each hero card across desktop and mobile.

**Implementation steps**
- Update `mkHeroSlot` in `BattleUIController` to add a right-edge Charge container:
  - always exactly two slots
  - subtle dark wrapper
  - empty sockets visible even with zero Charges
  - occupied slots show type emblem/rim and numeric amount
  - current slot has persistent bright outline
- Do not widen the 3-creature board row.
- Keep HP, Armor, portrait, name, and Energy display readable.
- For mobile, fit within the existing 4-cell row sizing; if needed, use slight overlap on hero card's right edge instead of increasing row width.
- Add render helper:
  - `paintChargeSlots(heroFrame, sideState)`
  - reusable for player, enemy, mobile player, mobile enemy
- Add animation helpers:
  - gain: source card/effect to Charge slot
  - spend: Charge slot to played card/effect source
  - replace: inactive slot fades/cracks before new slot fills
  - skipped/late animation: snap to final snapshot
- Optional polish deferred after v1: add a temporary spell resolution anchor so a future fly-from-source Charge animation can originate from the spell card, not its target or graveyard. The implemented v1 feedback is the authoritative on-socket pop.

**Tests and regression checks**
- Desktop battle UI shows two slots on both heroes.
- Mobile battle UI shows two slots without layout overlap.
- Empty, occupied, current, gained, spent, and replaced states are visually distinct.
- Two-digit Charge values remain legible.
- Rapid same-turn card plays do not block card selection.
- Late animation does not revert slot state after a newer snapshot.
- Regression watch:
  - Hand drag, attack drag, targeting highlights, board previews, and warning toasts still work.
  - Core removal must not leave invisible hitboxes over hero cards.
  - Hero damage lunge/pop animations still target hero frames correctly.

## Phase 6 - Deck Persistence and Builder Rules
**Goal:** Remove deck Core dependency and implement nonblocking multi-type warnings.

**Implementation steps**
- Bump SaveService schema to v1.3.
- Migration:
  - preserve existing decks and cards
  - ignore/remove `coreId` from deck validation and future writes
  - keep old `coreId` fields harmless if already present during migration
  - active deck remains active if it has 30 owned legal cards by ownership/copy rules
- Replace deck creation flow:
  - no Core select page
  - create a deck directly with a default name
  - optional rename remains
- Remove `Cores.supports` deck legality checks from server and client.
- Deck validation becomes:
  - known card
  - owned card
  - max 2 copies
  - draft cannot exceed 30
  - active deck must have exactly 30
- Deck Builder warning:
  - calculate distinct Charge-producing types using shared config
  - MIGHTY/SWIFT/VITAL count
  - NEUTRAL does not count
  - show modal/toast only when edit crosses from <=2 to >2 distinct Charge Types
  - do not repeat for additional cards while deck remains above 2
  - show persistent indicator while above 2:
    `3 Charge Types - Hero Slots: 2`
- Warning is informational only; card add/save remains allowed.

**Tests and regression checks**
- Existing player profile with `coreId` decks migrates without data loss.
- New deck can be created without selecting Core.
- Active deck can include MIGHTY + SWIFT + VITAL if owned and exactly 30 cards.
- NEUTRAL cards do not trigger warning.
- First third Charge-producing type triggers warning once.
- Adding more cards of already represented third type does not repeat warning.
- Removing back to two types clears indicator.
- Adding a third type again may warn again.
- Regression watch:
  - "must always have one active valid deck" remains true.
  - max 2 copies and ownership enforcement remain server-authoritative.
  - PvE/PvP start still uses active deck cards correctly.

## Phase 7 - AI and Gameplay Validation
**Goal:** Keep NPC and simulations functional after Core removal.

**Implementation steps**
- Remove NPC Core-use logic.
- Update NPC card scoring to optionally value Charge costs once future cards use them.
- For now, NPC can ignore Charge strategy because no content migration is planned.
- Ensure Noob still randomizes among starter decks and starts battles correctly.

**Tests and regression checks**
- Headless NPC turn simulation completes without Core references.
- PvE Noob battle starts and progresses.
- NPC does not attempt removed remote/actions.
- Regression watch:
  - Balance sims will change because Core active power is removed; record as expected, not a bug.
  - Existing "MIGHTY too strong / VITAL too weak" issue remains separate from this technical migration.

## Phase 8 - Documentation and Final Verification
**Goal:** Reconcile repo docs with the implemented design and close migration risks.

**Implementation steps**
- Update:
  - `DESIGN_CORE.md`
  - `DESIGN_ENGINE.md`
  - `DESIGN_DATABASE.md`
  - `DESIGN_UI.md`
  - `DEV_STATUS.md`
  - `README.md`
- Document:
  - Energy vs Charge distinction
  - NEUTRAL non-Charge behavior
  - removed Core active system
  - deck builder warning behavior
  - Charge state invariants
  - post-resolution timing
  - explicit extra Charge stacking rule
- Add `PLAN_BATTLE_CHARGE.md` checklist status as implementation progresses.

**Final acceptance tests**
- Automated:
  - card schema validates
  - deck schema/migration tests pass
  - Charge state machine tests pass
  - battle play integration tests pass
  - snapshot serialization tests pass
- Studio Play:
  - PvE battle starts
  - playing MIGHTY/SWIFT/VITAL cards updates Charge Slots
  - playing NEUTRAL updates no Charge
  - third type replaces inactive slot
  - Charge socket pop animation plays for gain/spend/replace events
  - no Core active UI remains
  - no Core remote errors
- Manual responsive:
  - desktop hero slots readable
  - mobile hero slots readable
  - tablet layout does not widen board row
- Regression:
  - Energy spending/refill unchanged
  - creature play unchanged except Charge gain
  - spell targeting/rejection unchanged except Charge gain
  - attack/combat unchanged
  - turn timer unchanged
  - PvP start/end and anti-rage-quit unchanged
  - rewards and collection unchanged
  - asset preloading unaffected

## Rollback Strategy
- Keep Charge service isolated so battle state can temporarily ignore Charge rendering if UI work has issues.
- Remove Core active in a dedicated phase after Charge state and snapshots pass tests.
- For persistence, migration should tolerate old `coreId` fields rather than destructively deleting data immediately.
- If deck builder UI breaks, server validation should still allow correct deck saves through remotes once fixed.

## Open Follow-Up After v1
- Decide which cards gain explicit extra Charge effects or Charge costs.
- Rebalance starter decks after Core active removal.
- Decide whether future Battle Types produce Charges by default or require config.
- Consider reduced-motion settings for Charge animations.
