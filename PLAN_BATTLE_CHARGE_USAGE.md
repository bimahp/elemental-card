# PLAN_BATTLE_CHARGE_USAGE.md - Charge Costs and Corrupted Trait

## Summary

Extend the existing two-slot Battle Charge system so selected cards can require
Battle Charge as part or all of their printed play cost.

The game keeps the four existing Battle Types:

- `MIGHTY`
- `SWIFT`
- `VITAL`
- `NEUTRAL`

`CORRUPTED` is **not** a fifth Battle Type. It is a permanent card trait that
prevents a card from gaining its normal played-card Charge after resolving.

Supported cost models:

- **Energy-only:** `cost = 3`
- **Hybrid Energy + Charge:** `cost = 2`, `chargeCost = { battleType = "MIGHTY", amount = 2 }`
- **Pure Charge:** `cost = 0`, `chargeCost = { battleType = "MIGHTY", amount = 2 }`

Use the live schema names already present in Studio:

- Energy cost remains `cost`, including `cost = 0`
- Charge cost remains `chargeCost = { battleType = "...", amount = N }`
- Card type remains lowercase `cardType = "creature" | "spell"`
- Race remains `race`
- Add CORRUPTED as a passive effects entry:
  `effects = { { trigger = "passive", action = "corrupted" } }`

Normal played-card Charge remains:

> Every successfully played non-NEUTRAL typed card gains +1 matching Charge after
> resolution, unless it has the `CORRUPTED` trait.

There is no confirmation prompt for Charge spending. Printed Charge costs are
mandatory and paid automatically when the player commits a valid play.

---

## Locked Decisions

- Keep only `MIGHTY`, `SWIFT`, `VITAL`, and `NEUTRAL` as Battle Types.
- Do not add `CORRUPTED` as a Battle Type.
- Add `CORRUPTED` as a permanent printed card trait.
- Corrupted cards retain their original Battle Type, race, rarity, ownership, and synergies.
- Printed Charge costs are mandatory, not optional empowerment.
- No confirmation dialog for Charge payment.
- No partial Charge payment.
- Cards must have the full printed cost before play.
- A card cannot use its future normal +1 Charge to pay its own cost.
- Non-Corrupted hybrid and pure-Charge typed cards still generate normal +1 Charge after successful resolution.
- Corrupted blocks only normal played-card Charge, not explicit effects such as `gain_charge`.
- Existing two-slot Charge replacement and current-slot rules remain unchanged.
- Initial implementation should add only controlled fixture/example cards, not broadly migrate the current card pool.

---

## Current Implementation Notes

The live Studio implementation now has the foundation and first fixtures:

- `ReplicatedStorage/Modules/CardSchema` validates `chargeCost.battleType`,
  `chargeCost.amount`, and passive `corrupted` entries.
- `ReplicatedStorage/Modules/CardTraits` checks permanent traits encoded in
  `effects[]` as `{ trigger = "passive", action = traitName }`.
- `ReplicatedStorage/Modules/CardCost` provides shared affordability and
  UI-ready cost parts for Energy-only, hybrid, and pure-Charge cards.
- `ServerScriptService/Modules/BattleLogic.playCard` validates both resources
  before payment, spends printed Charge with event reason `card_cost`, and skips
  normal +1 Charge for passive `corrupted`.
- `ServerScriptService/Modules/ChargeState` supports `gainCharge`,
  `spendCharge`, `canSpendCharge`, slot normalization, event recording, and
  spend-to-zero behavior.
- `StarterGui/BattleUI/Modules/CardVisuals` renders `ChargeCostBadge` alongside
  `CostBadge`; pure-Charge cards hide the Energy badge.
- `NpcAI` uses `CardCost.canPay`, so it considers both Energy and Charge.
- Fixture cards are live in `Cards.lua` and `pack_ruby_bear.json`:
  `vangorn` is hybrid (`cost = 1`, `1 MIGHTY` Charge) and
  `rubyhide` is Corrupted pure-Charge (`cost = 0`, `3 MIGHTY` Charge).

Important live-schema mapping from the TRD:

| TRD term | Live schema |
|---|---|
| `energyCost` | `cost` |
| `chargeCost.type` | `chargeCost.battleType` |
| `raceType` | `race` |
| `cardType = "CREATURE"` | `cardType = "creature"` |
| `attack`, `health` | `atk`, `hp` |

---

## Phase 1 - Schema, Traits, and Shared Cost Helper

**Goal:** Make Charge costs and Corrupted trait canonical and reusable.

### Implementation

- Add `ReplicatedStorage/Modules/CardTraits`.
- Expose:
  ```lua
  CardTraits.has(card, "corrupted")
  ```
- Extend `CardSchema`:
  - `passive` is a valid trigger for permanent printed traits.
  - `corrupted` is a valid action only when `trigger = "passive"`.
  - `cost` may be `0`.
  - `chargeCost` must use `battleType`, not `type`.
  - `chargeCost.battleType` must be `MIGHTY`, `SWIFT`, or `VITAL`.
  - `chargeCost.battleType = "NEUTRAL"` is invalid.
  - `chargeCost.amount` must be a positive number.
- Add a shared cost helper module usable by server and client.
- The helper should compute:
  - effective Energy cost using existing cost-mod semantics,
  - optional Charge requirement,
  - matching Charge availability,
  - complete affordability,
  - UI-ready cost parts.

Recommended interface:

```lua
CardCost.getEnergyCost(side, cardId, card)
CardCost.getChargeCost(card)
CardCost.canPay(side, cardId, card)
CardCost.getCostParts(side, cardId, card)
CardCost.failureReason(side, cardId, card)
```

The server remains authoritative. Client usage is for display and hints only.

### Tests

- Schema accepts Energy-only cards.
- Schema accepts hybrid Energy + Charge cards.
- Schema accepts pure-Charge cards with `cost = 0`.
- Schema accepts `{ trigger = "passive", action = "corrupted" }`.
- Schema rejects `corrupted` on non-`passive` triggers.
- Schema rejects `battleType = "CORRUPTED"`.
- Schema rejects `chargeCost.battleType = "NEUTRAL"`.
- Schema rejects `chargeCost.type` without `chargeCost.battleType`.
- Schema rejects missing, zero, negative, or non-number `chargeCost.amount`.
- Cost helper returns no Energy cost part for pure-Charge cards.
- Cost helper includes both Energy and Charge parts for hybrid cards.

---

## Phase 2 - Atomic Authoritative Payment

**Goal:** Ensure Energy and Charge costs are validated and paid as one atomic play cost.

### Implementation

- Refactor `BattleLogic.playCard` so complete validation occurs before spending any resource.
- Validation must include:
  - card exists,
  - card is in hand,
  - enough effective Energy,
  - enough matching Charge,
  - valid creature slot,
  - valid spell target,
  - spell `Triggers.playBlock` passes,
  - current battle state accepts the action.
- After validation succeeds:
  - spend Energy,
  - spend printed Charge with `ChargeState.spendCharge`,
  - remove the card from hand,
  - resolve summon/cast.
- Use Charge spend event reason `card_cost`.
- Keep `BattleController.validatePlayCard` focused on remote shape, slot, and target safety.
- Do not duplicate resource-payment logic between controller and battle logic.

### Tests

- Energy-only card with enough Energy succeeds.
- Energy-only card with insufficient Energy fails.
- Hybrid card with both resources succeeds.
- Hybrid card with insufficient Energy fails without spending Charge.
- Hybrid card with insufficient Charge fails without spending Energy.
- Pure-Charge card succeeds with enough matching Charge and zero Energy.
- Pure-Charge card fails with insufficient Charge.
- Charge of the wrong type cannot satisfy the cost.
- Invalid target spends no Energy or Charge.
- Full board spends no Energy or Charge.
- Spell blocked by `Triggers.playBlock` spends no Energy or Charge.
- Failed play emits no successful payment event.
- Future post-resolution Charge cannot satisfy the current card's cost.

---

## Phase 3 - Normal Charge Generation and Corrupted

**Goal:** Centralize normal played-card Charge generation and apply the Corrupted exception.

### Implementation

- Replace inline normal Charge generation in `BattleLogic.playCard` with a helper.
- The helper grants normal played-card Charge only when all are true:
  - card was played from hand,
  - play resolved successfully,
  - `card.battleType ~= "NEUTRAL"`,
  - `not CardTraits.has(card, "corrupted")`.
- Creature timing:
  - pay costs,
  - place creature,
  - resolve `emerge`,
  - grant normal Charge if eligible.
- Spell timing:
  - pay costs,
  - resolve `cast`,
  - grant normal Charge if eligible,
  - move spell to discard.
- Corrupted blocks only normal played-card Charge.
- Explicit `gain_charge` effects still resolve normally if present.

### Tests

- Energy-only MIGHTY card grants +1 Mighty after resolution.
- Hybrid MIGHTY card pays Charge and later grants +1 Mighty if not Corrupted.
- Pure-Charge non-Corrupted MIGHTY card pays Charge and later grants +1 Mighty.
- Corrupted MIGHTY card pays Charge and grants no normal Charge.
- NEUTRAL card grants no Charge.
- Corrupted NEUTRAL card grants no Charge.
- Corrupted card with explicit `gain_charge` still resolves that explicit effect.
- Bounced and replayed non-Corrupted card grants Charge again.
- Token summon grants no normal played-card Charge.
- Rebirth grants no normal played-card Charge.
- Graveyard-to-board return grants no normal played-card Charge.
- Board copy grants no normal played-card Charge.

---

## Phase 4 - Slot Normalization and Event Ordering

**Goal:** Preserve existing two-slot behavior while supporting printed Charge payments.

### Implementation

- Keep current `ChargeState` slot rules unchanged:
  - matching Charge adds to matching occupied slot,
  - new type fills empty slot,
  - third distinct type replaces inactive occupied slot,
  - current slot is protected from third-type replacement,
  - spending does not change current unless the spent slot reaches zero,
  - if one occupied slot remains, it becomes current.
- Payment events must be recorded before explicit effect gains and before normal played-card gains.
- Event reason naming should be consistent:
  - `card_cost` for printed Charge payment,
  - `effect_gain` or current equivalent for explicit `gain_charge`,
  - `normal_play` for normal post-resolution Charge.
- Do not predict permanent Charge state on the client.
- Snapshot state remains authoritative.

### Tests

- Spending inactive slot above zero does not change current.
- Spending inactive slot to zero leaves current unchanged if another occupied slot remains.
- Spending current slot above zero keeps it current.
- Spending current slot to zero makes the remaining occupied slot current.
- Non-Corrupted post-resolution generation can refill an emptied slot.
- Refilling an emptied slot does not restore the previous current slot automatically.
- Corrupted card leaves a spent-to-zero slot empty.
- Third-type replacement still replaces inactive occupied slot.
- Charge events are ordered: payment, explicit effects, normal gain.
- Corrupted card emits payment event but no normal gain event.

---

## Phase 5 - Battle UI, Card UI, and Corrupted Visuals

**Goal:** Make Energy-only, hybrid, pure-Charge, and Corrupted cards readable in battle and collection views.

### Implementation

- Extend `CardVisuals` beyond the current single `CostBadge`.
- Render cost models:
  - Energy-only: Energy icon + value.
  - Hybrid: Energy icon + value and Charge emblem + value.
  - Pure-Charge: Charge emblem + value only.
- Do not show a zero-Energy badge on pure-Charge cards.
- Reuse `AssetIds.ChargeEmblems` for Charge cost icons.
- Ensure cost rendering works in:
  - battle hand,
  - hover preview,
  - mobile hand,
  - board preview,
  - grave log preview,
  - inventory grid,
  - deck builder grid.
- Add Corrupted visual identity:
  - keep Battle Type border and badge color,
  - use a dark purple/black nameplate treatment,
  - keep card name text white,
  - add a small Corrupted trait icon or compact marker near the name,
  - do not replace Battle Type badge with black.
- Add consistent tooltip/rules text:
  > Corrupted: This card does not generate Battle Charge when played.
- Client may gray out cards missing Energy or Charge, but server remains authoritative.
- No confirmation dialog should appear for Charge spending.

### Tests

- Energy-only costs remain readable on desktop and mobile.
- Hybrid costs fit without covering name, art, or stats.
- Pure-Charge cards show no `0` Energy badge.
- MIGHTY/SWIFT/VITAL Charge cost icons are visually distinct.
- Corrupted MIGHTY still clearly appears MIGHTY.
- Corrupted nameplate remains readable at hand and preview sizes.
- Corrupted marker remains visible on mobile hand cards.
- Missing Charge is communicated distinctly from missing Energy if client hints are implemented.
- No confirmation appears when playing a Charge-cost card.
- Spend and gain socket animations occur in server event order.

---

## Phase 6 - Deck Builder and AI

**Goal:** Make deck editing and NPC turns understand Charge-cost cards without adding deck restrictions.

### Implementation

- Deck builder remains permissive:
  - no new legality restriction,
  - all owned cards remain legal,
  - existing `>2 Charge Types - Hero Slots: 2` warning remains.
- Corrupted typed cards count as their Battle Type for deck type analysis.
- Optional first-pass deck feedback:
  - generator counts by type,
  - spender counts by type,
  - pure-Charge card count.
- Update `NpcAI`:
  - affordability must use the shared cost helper,
  - NPC must consider Energy and Charge,
  - pure-Charge cards can be playable at zero Energy,
  - NPC should keep its existing loop that re-evaluates after every successful play.
- Do not precompute an entire NPC turn before Charge changes resolve.

### Tests

- Deck builder allows Energy-only, hybrid, pure-Charge, and Corrupted cards.
- Corrupted MIGHTY counts as MIGHTY for deck type warning.
- NEUTRAL still does not count as a Charge-producing type.
- NPC skips unaffordable hybrid cards.
- NPC skips pure-Charge cards without enough Charge.
- NPC can play a pure-Charge card with zero Energy when it has enough Charge.
- NPC can play a generator first, then re-evaluate and play a newly affordable Charge-cost card.
- NPC simulation completes without Charge-cost errors.

---

## Phase 7 - Minimal Content Fixtures

**Goal:** Prove the system with controlled content before migrating the wider card pool.

### Implementation

- Add a tiny test/example set only.
- Implemented fixtures:
  - `vangorn`: hybrid non-Corrupted MIGHTY creature, `cost = 1`,
    `chargeCost = { battleType = "MIGHTY", amount = 1 }`, ATK 3 / HP 2.
  - `rubyhide`: pure-Charge Corrupted MIGHTY creature, `cost = 0`,
    `chargeCost = { battleType = "MIGHTY", amount = 3 }`, ATK 2 / HP 5,
    passive `corrupted`, Emerge: gain 3 Armor.
- Avoid broad pack migration until balance testing is complete.
- Initial content rule:
  - Corrupted cards should not contain explicit same-type `gain_charge` effects.
  - Pure-Charge spells should be added cautiously after creature tests pass.

### Tests

- `vangorn` requires 1 Energy and 1 MIGHTY Charge.
- `vangorn` pays Energy and Charge, resolves, then generates +1 MIGHTY
  because it is not Corrupted.
- `rubyhide` requires 3 MIGHTY Charge and zero Energy.
- `rubyhide` spends 3 MIGHTY Charge, enters the board, gains 3 Armor on
  Emerge, and does not generate normal +1 MIGHTY because it is Corrupted.
- Starter decks still validate.
- Existing pack cards remain unchanged unless intentionally edited.

---

## Phase 8 - Documentation and Final Validation

**Goal:** Reconcile docs with the implemented Charge-cost and Corrupted design.

### Documentation Updates

Update:

- `DESIGN_CORE.md`
- `DESIGN_DATABASE.md`
- `DESIGN_ENGINE.md`
- `DESIGN_UI.md`
- `DEV_STATUS.md`
- `PLAN_BATTLE_CHARGE.md`
- `README.md` if project structure changes

Document:

- three cost models,
- mandatory Charge payment,
- Corrupted trait behavior,
- schema field names,
- no fifth Battle Type,
- no confirmation dialogs,
- pure-Charge UI rules,
- Energy and Charge remain separate resources.

### Final Tests

- Card schema validates.
- Starter decks validate.
- ChargeState unit tests pass.
- BattleLogic cost integration tests pass.
- Failure atomicity tests pass.
- NPC simulation passes with Charge-cost fixtures.
- Snapshot/charge-event tests pass.
- Desktop battle UI manual smoke passes.
- Mobile battle UI manual smoke passes.
- Inventory/deck builder manual smoke passes.
- PvE battle still starts and completes.
- No Core active UI or `UseCore` behavior regresses.

---

## Rollout Notes

- Implement engine and UI support first with test fixtures.
- Do not broadly rebalance or migrate existing packs in the same pass.
- After fixture validation, run balance sims before adding more pure-Charge cards.
- Hybrid cards should generally cost 1-3 Charge.
- Pure-Charge cards should generally cost at least 2 Charge.
- Start with pure-Charge creatures before pure-Charge spells because board slots naturally limit creature spam.
- Avoid cheap pure-Charge cards that draw multiple cards, return themselves, copy themselves, deal efficient direct hero damage, or generate extra Charge.
