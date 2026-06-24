# DESIGN_ENGINE — Battle Engine Architecture & Rework Plan

> The runtime battle engine: how cards execute, and how it stays scalable for future
> mechanics. Pairs with [DESIGN_DATABASE.md](DESIGN_DATABASE.md) (card data schema)
> and [DESIGN_CORE.md](DESIGN_CORE.md) (rules). Status: **implemented** (2026-06-20).

---

## Locked decisions (alpha)

- **No hero power: Battle Charge replaces Crystal Core (which had replaced Invoker).**
  There is no active hero skill. Each side instead builds **Battle Charge** — a
  two-slot hero resource. Playing a MIGHTY/SWIFT/VITAL card grants +1 Charge of its
  type *after* it resolves; NEUTRAL never produces Charge. Cards may cost Charge
  (`chargeCost`) or grant extra Charge (`gain_charge`, which stacks with the normal
  +1). State is server-authoritative. See [DESIGN_CORE.md](DESIGN_CORE.md) Battle Charge.
- **`lifesteal` is the canonical term.** "Siphon" is retired everywhere. Lifesteal
  = your hero heals for the damage this deals — applies to **combat** (the keyword
  on a creature) and **effects** (`lifesteal = true` on a `damage` entry).
- **`quickstrike` = first-strike.** When this creature *attacks another creature*,
  it deals its damage first; if the defender dies, it deals **no** retaliation.
  (Only relevant on the attack; no effect when defending or hitting a hero.)
- **`rebirth` = resummon once at full stats.** The first time the creature dies it
  returns to its slot immediately at full HP/Attack, loses Rebirth, then resolves
  normally on later deaths. (Its Shatter, if any, still fires on the death that
  triggers Rebirth — see Trigger ordering.)
- **Combat unchanged:** Hearthstone-style simultaneous damage, Taunt/Stealth
  gating, full retaliation (except vs. quickstrike lethal). 30 HP, energy 0→10,
  hand cap 10, fatigue, Coin all unchanged.
- **The four packs fully replace the old 32 cards.** Playtest decks come from
  [deck_starter.json](deck_starter.json) (one per archetype).

---

## Why the current engine blocks the new cards

1. **One `effect` per instance.** Every trigger is `if m.effect.trigger == "X"`.
   The new `effects[]` array breaks this at every site.
2. **Triggers are hardcoded and scattered.** Each game event manually loops the
   board for one specific trigger string. No central dispatch → a new trigger
   means new loops at new call sites.
3. **Two parallel if/elseif chains** (`applyMonsterTriggerEffect` +
   `applyActionEffect`, ~40 types, ~22 dead) with duplicated damage/heal logic.

The rework replaces these three with data-driven subsystems.

---

## Target architecture

```
ReplicatedStorage/
  Definitions/
    Cards.lua        ← all pack cards as one id-keyed map (canonical)
    Decks.lua        ← starter decks (from deck_starter.json)
    (CrystalCores.lua remains in the tree but is unused — Crystal Core is removed)
  Modules/
    CardSchema       ← validates Cards.lua on load (fields, known triggers/actions/targets)
    CardText         ← renders ability text from effects[] (replaces in-data EFFECT_TEXT)
    ChargeConfig     ← shared Battle Type palette + Charge-producing rules (server + client)
    CardTraits       ← `has(card, trait)` — scans effects[] for a passive trait by action name (e.g. "corrupted")
    CardCost         ← shared cost helper (server + client): getEnergyCost, getChargeCost, canPay, getCostParts, failureReason

ServerScriptService/Modules/
  Effects/
    Triggers         ← fireEvent(state, event, ctx): scans effects[] and runs matches
    Actions          ← Actions[action] = fn(ctx); one handler per action verb
    Targeting        ← resolveTargets(ctx, target, area, condition) → concrete targets
    Conditions       ← Conditions[type](ctx) → bool
    Keywords         ← static keyword checks + hooks (lifesteal, quickstrike, rebirth)
    Costs            ← reduce_cost / set_cost over hand|drawn_cards|returned_card
  ChargeState        ← authoritative two-slot Battle Charge state machine (gain/spend/normalize/events)
  BattleLogic        ← state, turn flow, combat; delegates all effect work to Effects/

(unchanged role) ServerScriptService/BattleController ← orchestration, RemoteEvents, DataStore, rewards
(client) StarterGui/BattleUI/* ← render from effects[], target picking, keyword visuals
```

**Scalability contract:** a new card mechanic should require only (a) a new
`Actions[...]` entry and/or (b) a new `Conditions[...]`/`Triggers` event — never
edits to combat, turn flow, or a mega-switch. If a new card forces a change to
`BattleLogic` core, the abstraction has leaked and needs revisiting.

---

## Card instance

On summon, deep-copy the definition's `effects` (and `keywords`) into the
instance so buffs/granted keywords never mutate the shared definition.

```lua
{
  cardId, name, atk, hp, maxHp, tempAtk,
  battleType, race,
  keywords = { ... },        -- mutable copy
  effects  = { ... },        -- mutable copy of the definition array
  attackedThisTurn, summonedThisTurn,
  rebornUsed = false,        -- rebirth bookkeeping
}
```

Removed from state: `invoker`, `discounts` (→ Costs), `usedComboExtraAttackThisTurn`,
and the Crystal Core fields (`coreId`, `coreUsedThisTurn`, `coreCounters`) — Core is
gone. Added for **Battle Charge** on each side (initialized by `ChargeState.init`):
`chargeSlots` (two `{battleType, amount}` slots), `currentChargeSlot`, `chargeSeq`,
and `pendingChargeEvents`. Kept: `deadAllies` (graveyard recursion), fatigue, etc.

---

## Trigger model

`fireEvent(state, event, ctx)` is the single dispatch. On each event it finds the
relevant cards, iterates their `effects[]`, and for every entry whose `trigger`
matches (and whose `condition` passes) calls `Actions[entry.action](ctx')`.

| Event | Fired when | Whose effects fire |
|---|---|---|
| `emerge` | a creature is summoned from hand | that creature |
| `cast` | a spell resolves | that spell |
| `shatter` | a creature dies | the dying creature |
| `deal_damage` | a creature deals damage | the dealer |
| `take_damage` | a creature is damaged | the damaged |
| `attacked` | a creature is declared as attack target | the defender |
| `turn_end` | owner's turn ends | all that owner's creatures |
| `ally_death` | a friendly creature dies | surviving allies |
| `resonance` | continuous (checked on read) | aura sources |

`chain` is **not** its own event — it's the `emerge`/`cast` moment gated by
"you've already played another card this turn" (`cardsPlayedThisTurn >= 2` at
resolution). A `trigger:"chain"` entry is sugar for "fire on summon/cast **if**
chain is active." Treated as `condition:{type:"chain"}` internally.

**Trigger ordering** (locked): resolve damage → fire `take_damage`/`deal_damage`
→ if HP ≤ 0, fire `shatter`, then apply `rebirth` (resummon) if present, then fire
`ally_death` on survivors. Document edge cases as they arise in implementation.

---

## Action contract

```lua
Actions[action] = function(ctx) ... end
-- ctx = { state, sourceWho, source (card/instance), entry, targets, event }
```

`BattleLogic`/`Triggers` build `ctx`, resolve `entry.condition` (skip if false)
and `entry.target`/`area` into `ctx.targets`, then call the handler. Handlers are
small and parameter-driven; cross-cutting modifiers are applied uniformly:

- **`value` vs `valueFrom`** — fixed number, or dynamic (`"drawn_card_cost"`)
  resolved at call time.
- **`area`** — `single` (chosen/one), `all` (each matching target), `split`
  (distribute `value` as 1-damage hits).
- **`lifesteal=true`** on `damage` — heal `sourceWho` hero for total dealt.

Alpha action set (each one handler): `damage`, `heal`, `buff`, `draw_card`
(+`filter`), `destroy`, `grant_keyword`, `summon`, `bounce`,
`return_from_graveyard`, `reduce_cost`, `set_cost`, `gain_energy`, `gain_charge`.
(Full param spec in DESIGN_DATABASE.)

---

## Targeting

`target` is **player-chosen** for the explicit single targets (`enemy_creature`,
`friendly_creature`, `any_creature`, `enemy_target`), matching the schema's intent
and Hearthstone convention. `self`, `own_hero`, `all_*`, `random_*`, and `area:all`
need no pick and resolve server-side.

- Client sends the chosen target through the existing drag-to-target flow:
  `PlayCard(cardId, {target={side="npc", slot=N}})` from the client's perspective;
  `slot=0` means hero for `enemy_target` burn.
- Server remaps that descriptor from client perspective to canonical battle seats,
  then **always re-validates** it against the card's target class and descriptor
  shape before battle logic runs. Malformed or illegal targets reject without throwing.
- `Effects.Targeting` also guards chosen descriptors before use. `random_*`,
  `area`, and legal fallback targets are resolved entirely server-side.

This replaces the current auto-pick (`lowest_hp`, random) for player-facing
targeted effects.

### Pre-play prerequisite gate

A spell is **rejected before it is consumed** if none of its effects would do
anything — every entry's `condition` fails or its required target is missing.
`Triggers.playBlock(base, card)` dry-runs the effects (resolve targets + check
conditions, no execution) and returns a player-facing reason (e.g.
*No Wounded Ally*, *Target not damaged*, *No valid target*); `BattleLogic.playCard`
refuses the play with that reason, so the card stays in hand and the Energy is
kept — the same shape as the Energy and Taunt pre-checks. Creatures are **never**
blocked this way: the body is the point, so a fizzled Emerge is allowed. The
reason is delivered to the client via a transient `warnings` array on the state
broadcast (cleared after each broadcast) and shown as a toast.

---

## Keywords

Centralized in `Keywords`. Static set carried on the instance:

| Keyword | Hook |
|---|---|
| `taunt` | combat targeting (must be attacked first) — existing |
| `charge` | exempt from summoning sickness — existing |
| `stealth` | untargetable until it attacks — existing |
| `quickstrike` | **attacker** deals damage first; lethal → no retaliation |
| `lifesteal` | on dealing damage (combat or effect), heal source hero by that much |
| `rebirth` | on death, if `rebornUsed` false → resummon full stats, set flag, consume |

`lifesteal` unifies the keyword and the `damage` `lifesteal=true` flag through one
code path in `dealDamage*`.

---

## Costs

`Costs` replaces the one-shot `discounts` list. Tracks cost modifiers with a
`target` pool and `duration`:

- targets: `hand` (cards held now), `drawn_cards` (drawn earlier this resolution),
  `returned_card` (pulled by `return_from_graveyard` this resolution).
- `reduce_cost` (−value) and `set_cost` (=value); `duration` omitted = persists
  while the card stays in hand; `this_turn` clears at turn end.
- Effective cost is computed at play time: `max(0, base − reductions)` or the set
  value, clamped ≥ 0.

---

## Cut list

- **Invoker**: `invokerBonus`, `tallyInvoker`, `comboScaledValue` (Invoker part),
  `siphonAmount`, `mightyDamageBonus`, `applyDestroyInvokerBonus`, armor/destroy
  Invoker bonuses, and the Invoker UI panel.
- **Crystal Core** (the former Invoker replacement, now also cut): `BattleLogic.useCore`
  + target validators, `coreId`/`coreUsedThisTurn`/`coreCounters`, the `UseCore`
  server handler, NPC `aiUseCore`, and the Core preview/drag/targeting UI. Replaced
  by Battle Charge (`ChargeState`/`ChargeConfig`). `CrystalCores.lua` and the
  `UseCore` remote are left orphaned as migration artifacts.
- **22 dead effect renderers** + unused effect branches.
- **Old `CardData` (32 cards)** and its in-module `EFFECT_TEXT`.
- **Equipment remnants** (already removed) and `combo_extra_attack` passive.

---

## Open items

- **Balance**: card values are alpha numbers (previous sims showed MIGHTY over- and VITAL under-performing). The Core active power is now removed — an expected balance shift — and the first Charge-cost fixtures are live (`ruby_mauler`, `rubyhide_bear`); rerun balance sims before broader card-pool migration.
- **Manual PVP smoke**: run a full 2-player Local Server pass with active decks.
- **Charge content**: `PLAN_BATTLE_CHARGE_USAGE.md` implemented 2026-06-23 — three cost models (Energy-only, Hybrid, Pure-Charge), CORRUPTED trait, CardTraits/CardCost shared modules, ChargeCostBadge UI, NpcAI CardCost.canPay upgrade, deck builder gen/spender feedback, and first fixture cards (`ruby_mauler` hybrid 1E+1M, `rubyhide_bear` Corrupted pure 3M). Broader card-pool migration deferred until balance sims run on fixture data.
- **Rebirth + board full**: creature died into a freed slot, so the slot is always available. Edge case already handled by design.
