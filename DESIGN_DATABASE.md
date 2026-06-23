# DESIGN_DATABASE — Card Schema & Data Architecture

> Status: **implemented** (2026-06-20). Engine fully migrated to this schema.

---

## Source of Truth

- **Runtime canonical:** a hand-authored Lua map at
  `ReplicatedStorage/Definitions/Cards.lua`, keyed by card string `id`.
  No Rojo, no runtime JSON. Roblox loads the Lua module directly.
- **Human-readable literal catalog:** the `pack_*.json` files in the repo root.
  These are the intended card-list editing/reference surface for designers, but
  they are not loaded by the game at runtime.
- **Schema authority:** this document defines field meanings and allowed
  vocabulary. It should not duplicate literal card lists.

If a pack JSON and `Cards.lua` disagree, verify and reconcile them before
shipping runtime work. Runtime behavior follows `Cards.lua`; catalog review
should use the pack JSON files.

---

## Card Schema

```lua
Cards.emberclaw_bear = {
    id         = "emberclaw_bear",   -- unique key (matches table key)
    name       = "Emberclaw Bear",
    pack       = "ruby_bear_pack",   -- release/set grouping
    battleType = "MIGHTY",           -- MIGHTY | SWIFT | VITAL | NEUTRAL
    cardType   = "creature",         -- creature | spell
    race       = "BEAR",             -- creatures only; BEAR | TREANT | GOLEM | ...
    rarity     = "rare",             -- common | rare | epic   (legendary TBD)
    cost       = 4,
    atk        = 4, hp = 5,          -- creatures only
    keywords   = { "taunt" },        -- static, always-on states (see Keywords)
    effects    = {                   -- triggered abilities (see Effects)
        { trigger = "emerge", action = "damage", target = "enemy_creature", value = 2 },
    },
}
```

| Field | Required | Notes |
|---|---|---|
| `id` | ✅ | Unique; equals the table key. |
| `name` | ✅ | Display name. |
| `pack` | ✅ | Set id, e.g. `ruby_bear_pack`. |
| `battleType` | ✅ | Archetype / affinity. Drives color identity and deck identity. |
| `cardType` | ✅ | `creature` or `spell`. (Renamed from the engine's old `monster`/`action`.) |
| `race` | creatures | Tribe. Omitted on spells. |
| `rarity` | ✅ | `common` / `rare` / `epic`. |
| `cost` | ✅ | Energy cost. |
| `chargeCost` | optional | Battle Charge cost: `{ battleType = "MIGHTY"\|"SWIFT"\|"VITAL", amount = N>0 }`. Paid (and validated) before the card resolves, so a card can't use the Charge it will generate. See [DESIGN_CORE.md](DESIGN_CORE.md) Battle Charge. |
| `atk`, `hp` | creatures | — |
| `keywords` | optional | Static states (Keywords table). Absent = none. |
| `effects` | optional | Triggered abilities. **Absent / empty = vanilla.** |

---

## Effects

`effects` is an **array** of ability entries. We use an array (not separate
`effect`/`bonus`/`modifier` fields) so a card can carry any number of abilities —
including a creature with both an Emerge *and* a Shatter — without ambiguity
about "which field does this go in."

### Entry shape

```lua
{ trigger = <trigger>, action = <action>, condition = {…}, <params…> }
```

- **`trigger`** — *when* it fires. Required.
- **`action`** — *what* it does. Required.
- **`condition`** *(optional)* — a gate; the entry only resolves if it passes.
  Always an object `{ type = …, … }`.
- **params** — `value`, `target`, `area`, `count`, `atk`, `hp`, `keyword`,
  `cardId`, `filter`, `duration`, etc. — depend on the action.

A card with a `bonus`/`combo`/`modifier` side-effect just becomes **multiple
entries**: the second entry carries a `condition` (e.g. `chain` for a Combo
payoff) or is a follow-up action (e.g. `draw_card` after `damage`). There is one
mechanism — the array — for everything.

**Entry order matters.** Effects resolve top-to-bottom. An entry whose `target`
is `drawn_cards` (cost manipulation) refers to the cards drawn by an earlier
entry of the *same* card during this resolution.

### Triggers

Signature triggers use crystal-world names (no Hearthstone vocabulary);
generic timing triggers stay descriptive.

| Trigger | Fires when | Replaces |
|---|---|---|
| `emerge` | creature is summoned | Battlecry |
| `shatter` | creature is destroyed | Deathrattle |
| `chain` | you've already played another card this turn | Combo (SWIFT) |
| `resonance` | continuous while in play | passive / aura |
| `cast` | a spell resolves | (spell on-play) |
| `turn_end` | at the end of your turn | — |
| `attacked` | this creature is attacked | — |
| `deal_damage` | this creature deals damage | Lifesteal/reactive damage hook |
| `ally_death` | a friendly creature dies | — |

> `turn_end`, `attacked`, `deal_damage`, `ally_death` are descriptive
> timing/reactive triggers, not signature keywords — rename later if you want
> crystal flavor. `chain`/`resonance` aren't used by the two current packs but
> are reserved for SWIFT/aura cards.

### Actions (standardized)

| Action | Params | Effect |
|---|---|---|
| `damage` | `target`, `area?`, `value` | Deal `value` damage. |
| `gain_armor` | `value` | Your hero gains Armor (no target). |
| `buff` | `target`, `area?`, `atk?`, `hp?`, `duration?` | +atk/+hp. Absorbs old `grant_attack`/`grant_hp`/`buff_friendly_creature`/`buff_allies`. Permanent unless `duration` set. |
| `draw_card` | `value`, `filter?` | Draw cards. `filter` (e.g. `{race="BEAR"}`) narrows the pool. |
| `destroy` | `target`, `condition?` | Destroy a creature. |
| `heal` | `target`, `value` | Restore `value` Health. |
| `grant_keyword` | `target`, `area?`, `keyword`, `duration?` | Grant a keyword. |
| `summon` | `cardId`, `count` | Summon token/creature copies to your board. |
| `bounce` | `target` | Return a creature to its owner's hand. |
| `return_from_graveyard` | `target` | Return a card from your graveyard to hand (`target:"random"`). |
| `reduce_cost` | `target`, `value`, `duration?` | Lower the cost of cards in `target` by `value`. |
| `set_cost` | `target`, `value`, `duration?` | Set the cost of cards in `target` to `value`. |
| `gain_charge` | `battleType`, `value` | Gain `value` Battle Charge of `battleType` (no board target). Stacks with the card's normal +1 played Charge. No-op for NEUTRAL. See [DESIGN_CORE.md](DESIGN_CORE.md). |
| `gain_energy` | `value` | Gain `value` Energy this turn (the Coin). |

A `damage` entry may carry **`lifesteal = true`** — your hero heals for the
damage dealt. **`value`** is normally a fixed number; for dynamic amounts use
**`valueFrom`** instead (e.g. `valueFrom = "drawn_card_cost"`), resolved at
cast time.

Cost actions take a card-pool `target` rather than a board target: `hand` (cards
currently held) or `drawn_cards` (cards drawn earlier this resolution — see Entry
order above). `duration` omitted = persists while the card stays in hand.

**Targeting is fully parameterized** — never bake the target into the action
name. `damage` + `target:"enemy_creature"` + `area:"all"`, *not*
`damage_all_enemy_creatures`. One handler per action, parameterized by target.

### Target vocabulary

| `target` | Meaning |
|---|---|
| `enemy_creature` | one enemy creature (chosen) |
| `friendly_creature` | one friendly creature (chosen) |
| `any_creature` | one creature, either side |
| `enemy_target` | one enemy character — creature **or** enemy hero (burn) |
| `self` | this creature (creature triggers) |
| `own_hero` | your own hero |
| `random_friendly` | a random friendly creature |
| `random_enemy` | a random enemy creature |
| `all_friendly` | your hero **and** all your creatures (heal target) |

`area`: `single` (default), `all` (every target matching `target`), or
`split` (distribute `value` as 1-damage hits randomly among matching targets).
`count`: for multi-hit / multi-summon, default 1.

Cost actions (`reduce_cost`/`set_cost`) use a card-pool target instead:
`hand`, `drawn_cards`, or `returned_card` (the card pulled by an earlier
`return_from_graveyard` entry this resolution).

### Condition vocabulary (object form)

| `condition` | Passes when |
|---|---|
| `{ type = "damaged" }` | the target has lost HP |
| `{ type = "target_undamaged" }` | the target is at full HP |
| `{ type = "attack_gte", value = N }` | the target's Attack ≥ N |
| `{ type = "attack_lte", value = N }` | the target's Attack ≤ N |
| `{ type = "friendly_damaged_exists" }` | you control a damaged creature |
| `{ type = "chain" }` | you've already played another card this turn (Combo) |

> Cost manipulation (`reduce_cost`/`set_cost`) is an **action**, not a separate
> "modifier" block — there is no standalone modifier field. This keeps one
> consistent mechanism whether a card discounts your hand or the cards it just drew.

---

## Keywords (separate from effects)

Static, always-on states the engine checks on hot paths (combat targeting,
summoning sickness). Kept out of `effects` deliberately — a keyword is a
*property*, not a *triggered action*.

`taunt`, `charge`, `stealth`, `quickstrike`, `lifesteal`, `rebirth` (+ existing
engine keywords). Stored as a flat `keywords = { … }` list.

> **Keyword rules (locked):**
> - `quickstrike` — **first-strike**: when it *attacks a creature*, it deals its
>   damage first; if the defender dies it takes no retaliation. Attacker-only.
> - `lifesteal` — your hero heals for the damage this deals (combat keyword **and**
>   `damage` entries with `lifesteal=true`). This is the canonical term; the old
>   "Siphon" wording is retired. (Invoker is cut, so there is no amplification.)
> - `rebirth` — the first time it dies it resummons in place at full stats once.

See [DESIGN_ENGINE.md](DESIGN_ENGINE.md) for how these hook into the engine.

---

## Module Layout

```
ReplicatedStorage/
  Definitions/
    Cards.lua        ← the card map (runtime canonical, hand-authored)
  Modules/
    CardText         ← display text: derives ability text from effects[] +
                       trigger labels. (Moved OUT of CardData; the 22 dead
                       renderers in the old module are dropped.)
    CardSchema       ← validator: required fields, known triggers/actions/
                       targets, deck legality. Run in tests / on load.

ServerScriptService/
  Modules/
    Actions/         ← effect-handler registry: Actions[<action>] = fn(state, who, entry, ctx)
    BattleLogic      ← loops a card's effects, checks condition, dispatches via
                       Actions[entry.action]. Replaces the ~300-line if/elseif chain.
```

The **Actions registry keyed by `action`** is the core scalability win: a new
card's behavior = register one function, no edits to a mega-dispatch.

---

## Open / Unresolved

- **Deck model — TBD.** Starter decks are a playtest stopgap (fixed precon per archetype). Current alpha starter decks are normalized to 30 cards each; final construction rules are not yet designed.
- **MIGHTY identity concern (Ruby Bear pack).** 8 creatures vs 16 spells, heavy Armor + heavy card draw — plays like defensive control, not the aggressive Ruby fantasy. Flagged for balance tuning.
- **Neutral Taunt reinstated.** `crystal_sentinel` has Taunt and `barkskin_blessing` grants it. The prior design banned neutral Taunt as tempo-warping — confirm reversal is intentional.
- **`race` underdeveloped.** Only `rally_the_clan` and `hunting_instinct`/`pack_tactics` care about tribe. Flavor-only until more tribal payoffs exist.
