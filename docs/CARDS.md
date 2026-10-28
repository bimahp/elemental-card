# Elemental TCG — Cards

**Status:** card design of record. On 2026-10-29 every card in `data/` matched `Cards` in Studio field for field (stats, effects, Charge costs, image ids) and the starter decks matched `Decks`.

**Owns:** what a card is, the packs, the archetype and tribe guardrails, rarity, and the card data format.
**Does not own:** battle rules ([GAME_DESIGN.md](GAME_DESIGN.md) §3); pack prices, odds and duplicate protection ([MONETIZATION.md](MONETIZATION.md)); how the engine runs effects ([ARCHITECTURE.md](ARCHITECTURE.md) §4); card art ([docs/ART.md](ART.md)).

---

## 1. Where cards live

| Source | Role |
|---|---|
| `ReplicatedStorage/Definitions/Cards` (Studio) | **Runtime canonical.** A hand-authored Lua map keyed by card id. The game reads only this. |
| [data/pack_*.json](../data/) | The human-readable catalog and design surface, including each card's `image_prompt` and `image_asset`. Not loaded at runtime. |
| [data/deck_starter.json](../data/deck_starter.json) | The three starter decks; `Definitions/Decks` is generated from it. |

This document does not copy card lists. For a card's name, cost, stats, effects or art prompt, read the pack JSON, and check it against `Cards` before shipping. When the two disagree, the game follows `Cards`; reconcile them before the next change.

## 2. Packs and catalog

Cards ship in **packs**: themed, archetype-aligned sets designed and balanced as a whole.

| Pack file | Runtime pack | Battle Type | Cards | Creatures / spells | Rarity (C / R / E) |
|---|---|---|---|---|---|
| [pack_ruby_bear.json](../data/pack_ruby_bear.json) | `ruby_bear_pack` | MIGHTY | 40 | 24 Bears / 16 | 20 / 14 / 6 |
| [pack_emerald_cat.json](../data/pack_emerald_cat.json) | `emerald_cat_pack` | SWIFT | 40 | 24 Cats / 16 | 20 / 14 / 6 |
| [pack_sapphire_frog.json](../data/pack_sapphire_frog.json) | `sapphire_frog_pack` | VITAL | 40 | 24 Frogs / 16 | 21 / 15 / 4 |
| [pack_stonebark.json](../data/pack_stonebark.json) | `young_treant` (see §6) | NEUTRAL | 12 | 5 Treants + 5 Golems / 2 | 8 / 3 / 1 |

- **132 collectible cards**, plus the Coin (an engine card, `pack = "engine"`, `collectible = false`).
- **30 pure-Charge cards**: 10 MIGHTY, 9 SWIFT, 11 VITAL. **No card uses the hybrid cost** (Energy + Charge) yet, though the engine supports it.
- **No Legendary cards exist yet**; every Legendary rule is ready for when one ships.
- All 132 cards have an `image_asset` and an `image_prompt`.
- The NEUTRAL Stonebark pack is deliberately narrow for alpha: 5 Treants, 5 Golems, Crystal Vent and Crystal Growth.

A "pack" here is a card set. What players buy at the Vending Machine is a **pack product** that draws from one or more sets ([MONETIZATION.md](MONETIZATION.md) §5).

## 3. Affinities and tribes

Every card has a `battleType` (affinity). Creatures also have a `race` (tribe), the hook for tribal synergies such as "draw a BEAR". Affinity drives colour and deck identity; tribe drives silhouette.

### 3.1 The launch rule

At launch, recognition is kept extremely simple: **MIGHTY = Bears, SWIFT = Cats, VITAL = Frogs.** Later sets add tribes to each affinity without breaking this identity.

| Affinity | Launch tribe | Future tribes | Themes | Silhouette |
|---|---|---|---|---|
| MIGHTY (Ruby) | Bears | Boars, Rhinos, Bison | Strength, Armor, toughness, endurance | Large mass, broad, thick fur, heavy posture, ruby growths |
| SWIFT (Emerald) | Cats | Foxes, Falcons, Rabbits | Speed, combo, precision, trickery | Lean, dynamic poses, emerald accents, motion |
| VITAL (Sapphire) | Frogs | Deer, Owls, Turtles | Healing, restoration, protection, renewal | Rounded, soft, sapphire growths, water and bioluminescence |

### 3.2 NEUTRAL

NEUTRAL is not a faction; it is a set of independent creature groups outside the three affinities.

| Group | What | Examples |
|---|---|---|
| **Ancients** | Primordial beings older than the Crystal Clans | Treant, Mammoth, Colossus Beetle, Elder Beast |
| **Constructs** | Stone, crystal and relic creations of lost civilisations | Golem, Crystal Sentinel, Quartz Guardian, Relic Automaton |
| **Mystics** | Floating, semi-transparent manifestations of crystal magic | Crystal Wisp, Wandering Echo, Frostbound Spirit |
| **Dragons** | Legendary pinnacle creatures | Skyreach Wyrm, Cloudscale Drake, Stormwing Dragon |

Tortoises are not used anywhere (they would overlap the future VITAL Turtles).

### 3.3 Forbidden

- No humans, elves, dwarves, orcs, goblins or halflings, as races or as main creature identities.
- No species built on a human profession (cleric, priest, paladin, knight, assassin, warlock). A role word in a card name is fine only when the animal clearly dominates ([docs/ART.md](ART.md) §3).

## 4. Design guardrails

### 4.1 Archetypes

| Archetype | Wins through | Never |
|---|---|---|
| **MIGHTY** | Board combat, durable threats, efficient removal, stat pressure, Armor as defense | Armor converted into damage; Shield Slam-style effects |
| **SWIFT** | Tempo, Stealth, Quickstrike pressure, cost reduction, card draw, Chain sequencing | Draw plus Energy/cost cheating strong enough to loop |
| **VITAL** | Healing, Lifesteal, protection, persistence, resurrection | Mind control, theft, removal-heavy play; removal is incidental |

### 4.2 Rarity

`common`, `rare`, `epic`, `legendary`. Rarity signals collectibility, pack weight and build-around complexity; it does not mean "strictly stronger".

### 4.3 Charge in card design

- Three cost models are live: Energy-only, hybrid (Energy + Charge) and pure-Charge.
- Charge comes from creatures that survive your turn, so Charge payoffs reward board presence.
- The `corrupted` trait (a played card that grants no Charge) is a legacy schema action. Current packs do not use it; board-generated Charge removed the need.

### 4.4 Design notes

- **Balance is not settled.** The last simulations predate board-generated Charge; rerun before trusting any matchup numbers.
- **MIGHTY identity:** the Ruby Bear pack has leaned towards defensive control (heavy Armor and draw) rather than frontline combat. Check it in the next balance pass.
- **Neutral Taunt** is back (`sentinel_oryn` has it; `barkskin_blessing` grants it), reversing an earlier ban on neutral Taunt as tempo-warping. Confirm it is intended.
- **Tribes are light.** Only a few cards (`clan_rally`, `hunting_instinct`, `pack_tactics`) care about race.

## 5. Card data format

### 5.1 Card

```lua
Cards.embermaw = {
    id         = "embermaw",          -- lowercase snake_case of the name, equal to the key
    name       = "Embermaw",
    pack       = "ruby_bear_pack",
    battleType = "MIGHTY",            -- MIGHTY | SWIFT | VITAL | NEUTRAL
    cardType   = "creature",          -- creature | spell
    race       = "BEAR",              -- creatures only
    rarity     = "rare",              -- common | rare | epic | legendary
    cost       = 4,                   -- Energy
    chargeCost = { battleType = "MIGHTY", amount = 2 },  -- optional
    atk = 4, hp = 5,                  -- creatures only
    keywords   = { "taunt" },         -- optional static properties
    effects    = {                    -- optional; empty = vanilla
        { trigger = "emerge", action = "damage", target = "enemy_creature", value = 2 },
    },
}
```

| Field | Rule |
|---|---|
| `playTarget` | **Required on spells, forbidden on creatures.** Where the spell is dropped (§5.5). Effect `target`s still decide what the rules hit. |
| `chargeCost` | `{ battleType, amount > 0 }`, never NEUTRAL. Pure-Charge cards use `cost = 0`. |
| `keywords` | `taunt`, `charge`, `stealth`, `quickstrike`, `lifesteal`, `rebirth` ([GAME_DESIGN.md](GAME_DESIGN.md) §3.9). Kept out of `effects`: a keyword is a property, not a triggered action. `rebirth` is only ever granted (`grant_keyword`), never printed. A granted `charge` lifts summoning sickness like a printed one (`Ops.addKeyword`). |
| `collectible` | `false` keeps a card out of packs, the Vendor and collection counts (the Coin). Absent means collectible. |
| `vfx` | Optional per-card override of the effect's visual archetype. Unused so far. |
| `image_prompt`, `image_asset` | Pack JSON only. |

### 5.2 Effects

`effects` is an array so a card can carry any number of abilities. Each entry is `{ trigger, action, condition?, …params }`. A "bonus" or "combo" side effect is just another entry with a `condition` or a follow-up action. **Order matters:** entries resolve top to bottom, and a later entry can refer to the cards an earlier one drew (`drawn_cards`) or returned (`returned_card`).

### 5.3 Triggers

| Trigger | Fires when |
|---|---|
| `emerge` | the creature is summoned from hand |
| `shatter` | the creature is destroyed |
| `chain` | on summon or cast, if another card was already played this turn |
| `cast` | the spell resolves |
| `turn_end` | at the end of the owner's turn |
| `attacked` | the creature is declared as an attack target |
| `deal_damage` | the creature deals damage |
| `take_damage` | the creature takes non-lethal damage |
| `ally_death` | a friendly creature dies |
| `resonance` | reserved for continuous auras; unused |
| `passive` | never fires; marks a printed trait such as `corrupted` |

### 5.4 Actions

Targeting is always a parameter, never part of the action name (`damage` + `target = "enemy_creature"` + `area = "all"`, not `damage_all_enemy_creatures`).

| Action | Params | Effect |
|---|---|---|
| `damage` | `target`, `area?`, `value` or `valueFrom`, `lifesteal?` | Deal damage |
| `heal` | `target`, `value` | Restore HP |
| `gain_armor` | `value` | Your hero gains Armor |
| `buff` | `target`, `area?`, `atk?`, `hp?`, `duration?` | +ATK/+HP, permanent unless `duration` |
| `draw_card` | `value`, `filter?` | Draw; `filter = { race = "BEAR" }` narrows the pool |
| `destroy` | `target`, `condition?` | Destroy a creature |
| `grant_keyword` | `target`, `area?`, `keyword`, `duration?` | Grant a keyword |
| `summon` | `cardId`, `count` | Summon copies to your board |
| `bounce` | `target` | Return a creature to its owner's hand |
| `return_from_graveyard` | `target` | Return a card from your graveyard to hand |
| `reduce_cost` / `set_cost` | `target` (`hand`, `drawn_cards`, `returned_card`), `value`, `duration?` | Change costs; no `duration` = while in hand; `this_turn` clears at turn end |
| `gain_energy` | `value` | Energy this turn (the Coin) |
| `gain_charge` | `battleType`, `value` | Gain Charge directly; no-op for NEUTRAL |
| `destroy_charge_slot` | `chargeOwner`, `selector`, `condition?` | Destroy a Charge slot (Crystal Vent: self, lowest) |
| `drain_charge` | `chargeOwner`, `selector`, `value` | Remove Charge from a slot |
| `disable_shatter` | `target` | An enemy creature's Shatter does not fire while it stays on board; only valid on a creature that has Shatter |
| `add_additional_charge_cost_to_player_hand` | `targetPlayer`, `selector` (`all`/`random`), `filter`, `value` | Raise Charge costs in a hand (Shadow Smoke) |
| `corrupted` | — | Legacy printed trait; `trigger = "passive"` only |

`valueFrom` resolves a dynamic amount at cast time (for example `"drawn_card_cost"`).

### 5.5 Targets, areas and conditions

| `target` | Meaning |
|---|---|
| `enemy_creature`, `friendly_creature`, `any_creature` | one chosen creature |
| `enemy_target` | one enemy character: a creature or the enemy hero |
| `self` | this creature |
| `own_hero` | your hero |
| `random_friendly`, `random_enemy` | a random creature on that side |
| `all_friendly` | your hero and all your creatures |

`area`: `single` (default), `all` (every match) or `split` (`value` as 1-damage hits spread randomly). `count` defaults to 1.

| `playTarget` | Drop surface |
|---|---|
| `friendly_creature`, `enemy_creature`, `any_creature` | one creature |
| `friendly_character`, `enemy_character` | one creature or that side's hero |
| `own_hero`, `enemy_hero` | a hero |
| `own_board`, `enemy_board`, `battle_board` | board slots of one side or both |
| `own_side`, `enemy_side` | that side's slots plus its hero |

| `condition` | Passes when |
|---|---|
| `{ type = "damaged" }` / `"target_undamaged"` | the target has lost HP / is at full HP |
| `{ type = "attack_gte", value }` / `"attack_lte"` | the target's ATK ≥ / ≤ value |
| `{ type = "friendly_damaged_exists" }` | you control a damaged creature |
| `{ type = "chain" }` | another card was played this turn |
| `{ type = "two_charge_slots_occupied", chargeOwner }` | that side has both Charge slots occupied |

`CardSchema` validates every field, vocabulary and `playTarget`/effect compatibility when the game loads.

## 6. Known data issues

- **Stonebark names are swapped, in Studio and in the JSON.** The set's id and name are `young_treant` / "Young Treant", and a vanilla 2/3 Treant card has id `stonebark_pack` and the name **"Stonebark Pack"**. Players see that card name; the SWIFT starter deck runs two. The set should be `stonebark_pack` / "Stonebark" and the card `young_treant` / "Young Treant". Renaming the card id changes ids stored in saved collections and decks, so it needs a save migration.