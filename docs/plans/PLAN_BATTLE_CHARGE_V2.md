# PLAN_BATTLE_CHARGE_V2 - Board-Generated Charge and New Card Effects

## Summary

Implement the new card-pack rules around **board-generated Battle Charge**:

- Remove normal Charge gained from playing MIGHTY/SWIFT/VITAL cards.
- At end turn, non-NEUTRAL creatures on board generate Charge.
- Keep 2 Charge Slots; automatic board generation never replaces occupied off-type slots.
- Implement the four new card actions now present in the pack JSON.
- Bring the runtime card/deck definitions in line with the redesigned pack JSON and starter decks.
- Update schema, card text, UI, AI, and tests in phases with validation gates between each phase.

Assumptions locked:

- All non-NEUTRAL creatures currently on board at end turn generate, including creatures played that turn.
- `disable_shatter` lasts until the target creature leaves board.
- `add_additional_charge_cost_to_player_hand` supports `selector = "all" | "random"`; current `Shadow Smoke` should use `"all"` unless card data is later changed.

## Implementation Validation Notes

Status as of 2026-06-25:

- Runtime Studio implementation and source JSON reflect the reconstructed packs/starters.
- Post-review fixes applied after Phase 8:
  - `disable_shatter` is rejected on creatures without a Shatter effect.
  - Disabled Shatter is visible on board cards and board-card previews as a compact red `X` marker.
  - `add_additional_charge_cost_to_player_hand` tracks affected current-hand copies with a remaining-copy count, so duplicate copies are not over-taxed and future same-id draws do not extend the modifier.
  - `destroy_charge_slot` NPC scoring checks the action owner (`self` for Crystal Vent), not always the opponent.
  - `Shadow Smoke` JSON explicitly includes `selector = "all"`.
- Current validation is focused headless coverage for schema, core board-generated Charge, Crystal Vent, Glassfang Seal, hand-tax duplicates/persistence, and relevant card/deck counts. Larger balance sims are still a tuning task, not a correctness gate.

## Current Content Baseline

This plan assumes the repo JSON content has already been redesigned and must be treated as the new source for the implementation pass:

- `pack_ruby_bear.json`: 40 MIGHTY cards, 24 creatures / 16 spells, 10 pure-Charge cards.
- `pack_emerald_cat.json`: 40 SWIFT cards, 24 creatures / 16 spells, 9 pure-Charge cards.
- `pack_sapphire_frog.json`: 40 VITAL cards, 24 creatures / 16 spells, 10 pure-Charge cards.
- `pack_stonebark.json`: 12 NEUTRAL cards only:
  - 5 Treants
  - 5 Golems
  - `Crystal Vent`
  - `Crystal Growth`
- `deck_starter.json`: 3 starters at 30 cards each.
  - Each starter uses 24 main-type cards and 6 Neutral cards.
  - Each starter has 20 creatures / 10 spells.
  - Starters intentionally do **not** include `Crystal Vent`.

Important content-design changes:

- Neutral was intentionally reduced from a broad utility pack into a mostly-creature support package.
- Most spell identity now lives inside MIGHTY/SWIFT/VITAL, where Charge costs can protect archetype identity.
- Neutral Charge interaction is intentionally minimal for alpha: only `Crystal Vent` manipulates own Charge slots.
- Pure-Charge cards are now common enough that Charge economy, hand affordability, UI, and NPC logic must all treat them as real content, not fixtures.

## Key Interfaces

Add and validate these effect shapes:

```lua
{ trigger = "cast", action = "destroy_charge_slot", chargeOwner = "self", selector = "lowest",
  condition = { type = "two_charge_slots_occupied", chargeOwner = "self" } }

{ trigger = "cast", action = "drain_charge", chargeOwner = "enemy", selector = "current", value = 1 }

{ trigger = "cast", action = "disable_shatter", target = "enemy_creature" }

{ trigger = "cast", action = "add_additional_charge_cost_to_player_hand",
  targetPlayer = "enemy", selector = "all", filter = { hasChargeCost = true }, value = 1 }
```

Add and validate:

- Condition: `two_charge_slots_occupied`
- Charge slot selectors: `current`, `lowest`
- Hand tax selector: `all`, `random`
- Board status: `shatterDisabled = true`

## Phase 1 - Data, Schema, and Text Gate

- Sync the redesigned pack/deck JSON into runtime card definitions.
  - Runtime `Cards.lua` should reflect all current pack JSON cards and names.
  - Runtime `Decks.lua` should reflect the current `deck_starter.json`.
  - Remove runtime cards that no longer exist in the pack JSON unless they are engine-only cards such as `the_coin`.
  - Preserve the existing engine-only `the_coin` card and keep it non-collectible / non-deck.
- Update card schema to accept the four new actions and the new condition.
- Update card text rendering for:
  - "Destroy your lowest Charge slot. Requires two Charge slots."
  - "Enemy loses 1 Charge from their current slot."
  - "Disable Shatter on an enemy creature."
  - "Enemy Charge-cost cards in hand cost +1 more Charge."
- Keep `CORRUPTED` schema support for compatibility, but no new behavior depends on it.

Tests:

- Runtime card count matches JSON source: 132 pack cards plus engine-only cards.
- All 3 starter decks validate at 30 cards.
- Runtime starter deck contents match `deck_starter.json`.
- New action params reject malformed owners/selectors/values.
- Card text does not expose raw action names.

## Phase 2 - Remove Played-Card Charge

- Remove the normal post-resolution `+1 Charge` from card play.
- Keep printed `chargeCost` payment unchanged.
- Keep explicit `gain_charge` action support for future compatibility, but it no longer stacks with any normal played-card gain.
- Remove or retire UI/event assumptions around `normal_play`.

Tests:

- Playing MIGHTY/SWIFT/VITAL Energy-only cards gives no Charge.
- Playing pure-Charge cards spends Charge but does not refund Charge by being played.
- Failed plays still spend no Energy/Charge.
- Existing charge-cost affordability tests still pass.

## Phase 3 - End-Turn Board Charge

- Add end-turn board generation after existing `turn_end` creature effects resolve.
- Iterate owner board slots left to right.
- For each non-NEUTRAL creature:
  - Matching occupied slot: add +1.
  - Empty slot: create that Battle Type with +1.
  - Two occupied non-matching slots: generate nothing.
- Automatic board generation never replaces a slot.
- Record Charge events with reason `board_end_turn`.

Tests:

- Empty slots + MIGHTY/SWIFT/VITAL board produces MIGHTY + SWIFT only.
- Existing matching slots gain Charge.
- Third off-type creature does not replace either slot.
- NEUTRAL creatures never generate.
- Creatures played this turn generate at end turn.
- End-turn effects resolve before Charge generation.

## Phase 4 - Charge Slot Effects

- Add ChargeState helpers for:
  - Destroy slot by selector.
  - Drain N Charge from selector.
  - Normalize current slot after destruction/drain.
- `destroy_charge_slot`:
  - For `Crystal Vent`, only works on self.
  - Requires two occupied self slots.
  - Destroys the lowest amount slot; tie-break inactive slot, then left slot.
- `drain_charge`:
  - Removes `value` from target slot.
  - If amount reaches 0, empties the slot and normalizes current slot.
  - Public no-target cases are rejected with a warning.

Tests:

- Crystal Vent cannot be played with 0 or 1 Charge slot.
- Crystal Vent destroys the lowest of 2 own slots.
- Drain current enemy slot by 1.
- Drain-to-zero empties the slot.
- Events replicate correct spend/destroy/drain reasons.

## Phase 5 - Shatter Disable

- Add board-instance status `shatterDisabled`.
- `disable_shatter` targets an enemy creature that has at least one `shatter` effect.
- While marked, that creature's `shatter` effects do not fire.
- Marker disappears when the creature leaves board, is bounced, dies, or is transformed/recreated.
- Add a compact board status icon and preview text.

Tests:

- Target without Shatter is rejected.
- Target with Shatter gets marker.
- Disabled Shatter does not fire on death.
- Rebirth, normal death cleanup, and ally-death triggers still behave correctly.
- Marker is visible in battle UI and board preview.

## Phase 6 - Charge-Cost Hand Tax

- Extend cost modifiers so hand cards can receive temporary `chargeCost` increases.
- `add_additional_charge_cost_to_player_hand`:
  - Applies to current hand only.
  - Filters to cards with `chargeCost`.
  - `selector = "all"` applies to all matching cards.
  - `selector = "random"` applies to one hidden random matching card.
  - Modifier persists while the affected card remains in hand.
- Hidden-hand effects are always playable and resolve quietly even if no matching enemy hand card exists, so they do not reveal private hand contents.
- CardCost, UI cost badges, and NpcAI affordability must include modified Charge cost.

Tests:

- Enemy Charge-cost cards in hand cost +1 Charge.
- Non-Charge-cost cards are unaffected.
- Modifier is lost when the card leaves hand.
- UI shows increased Charge cost distinctly.
- NPC respects modified Charge cost.
- If enemy has no matching cards, the spell resolves without revealing that fact.

## Phase 7 - UI, AI, and Simulation Pass

- Update Charge slot animations for board end-turn generation, drain, and slot destruction.
- Update hand/deck/inventory previews for new text and modified Charge costs.
- Update NpcAI scoring:
  - Values end-turn board presence as Charge generation.
  - Scores Charge-cost payoffs only when realistically payable soon.
  - Scores `drain_charge`, `destroy_charge_slot`, and `disable_shatter` contextually.
- Run smarter headless sims for MIGHTY/SWIFT/VITAL starter matchups.

Tests:

- Desktop/mobile Charge slots remain readable during multi-creature end-turn gains.
- New warning toasts render for invalid Crystal Vent, drain, and disable-shatter attempts.
- 100+ headless games per starter matchup complete without errors.
- Record Charge generated/spent per archetype and win rates for tuning.

## Phase 8 - Docs and Final Regression

- Update rules docs to make board-generation Charge the single source of truth.
- Update database/action docs with new action schemas.
- Update UI docs for disabled-Shatter icon and Charge-cost modifiers.
- Update dev status with new pack counts matching the current JSON.

Final acceptance:

- Card/deck schema validation passes.
- ChargeState tests pass.
- BattleLogic play/end-turn tests pass.
- New action integration tests pass.
- UI smoke passes on desktop and mobile.
- PvE battle starts and progresses with new starters.
- No played-card normal Charge events remain.
