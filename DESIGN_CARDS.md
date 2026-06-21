# DESIGN_CARDS - Card Philosophy & Pack Catalog Pointers

> Card design philosophy lives here. Literal card lists do not.
> The runtime source is `ReplicatedStorage/Definitions/Cards.lua`; the
> human-readable pack source files are the `pack_*.json` files in this repo.
> For schema details, see [DESIGN_DATABASE.md](DESIGN_DATABASE.md). For rules,
> see [DESIGN_CORE.md](DESIGN_CORE.md).

---

## Source Of Truth

- **Runtime canonical:** `ReplicatedStorage/Definitions/Cards.lua` inside Roblox
  Studio.
- **Starter decks:** `ReplicatedStorage/Definitions/Decks.lua`, generated from
  [deck_starter.json](deck_starter.json). Current alpha starters are 30 cards
  each.
- **Literal pack catalog:** the pack JSON files in the repo root:
  - [pack_ruby_bear.json](pack_ruby_bear.json) - MIGHTY / Ruby Bear
  - [pack_emerald_cat.json](pack_emerald_cat.json) - SWIFT / Emerald Cat
  - [pack_sapphire_frog.json](pack_sapphire_frog.json) - VITAL / Sapphire Frog
  - [pack_stonebark.json](pack_stonebark.json) - NEUTRAL / Stonebark

This document intentionally does not duplicate card tables. If a literal card
name, cost, stat line, keyword, effect, rarity, or image prompt is needed, use
the pack JSON files and verify against `Cards.lua` before shipping runtime work.

---

## Philosophy

### Cards Ship In Packs

The catalog is organized into packs: themed, archetype-aligned sets released
over time. A pack has an `id`, a `battleType`, a theme, and a list of cards.
Packs are the unit of release and the unit of balance: design and tune a whole
pack together.

Deck construction is still a later system. The current alpha uses fixed starter
decks, not custom decklists.

### Affinities And Races

Every card belongs to a `battleType`: `MIGHTY`, `SWIFT`, `VITAL`, or `NEUTRAL`.
Creatures also carry a `race` such as `BEAR`, `CAT`, `FROG`, `TREANT`, or
`GOLEM`.

Affinity drives color identity and deck identity. Race is the hook for tribal
synergies such as "draw a BEAR." See [DESIGN_BEAST.md](DESIGN_BEAST.md) for
affinities, races, and creature-group language.

### Two Card Types

- **creature** - a body with `atk`/`hp` that holds the board.
- **spell** - a one-shot effect that resolves and is discarded.

The engine uses `creature` and `spell` throughout.

### Abilities Are Data

Every ability is an entry in a card's `effects[]` array: a `trigger`, an
`action`, optional `condition`, and action-specific params. No abilities means a
vanilla body.

Signature trigger names use the crystal-world vocabulary:

- **Emerge** - on summon
- **Shatter** - on death
- **Chain** - payoff when another card has already been played this turn
- **Resonance** - reserved aura/continuous language

Full trigger/action/target/condition vocabulary lives in
[DESIGN_DATABASE.md](DESIGN_DATABASE.md).

### Rarity

`common`, `rare`, and `epic` are the current rarities. Rarity signals
collectibility, drop weight, and build-around complexity; it does not mean
"strictly stronger."

---

## Archetype Guardrails

### MIGHTY - Ruby / Bears

MIGHTY wins through board combat, durable threats, Armor as defense, efficient
removal, and stat pressure.

Armor is defensive only: no Armor-to-damage conversion and no Shield Slam-style
mechanics.

### SWIFT - Emerald / Cats

SWIFT wins through tempo, Stealth, Quickstrike pressure, cost reduction, card
draw, and Chain sequencing.

Avoid combining card draw and Energy/cost cheating strongly enough to create
runaway loops.

### VITAL - Sapphire / Frogs

VITAL wins through healing, Lifesteal, protection, persistence, and resurrection.

Removal should feel incidental, not the plan. Avoid mind control, theft, and
generic removal-heavy gameplay.

---

## Current Catalog Status

The alpha set is authored across four packs:

| Pack JSON | BattleType | Runtime pack |
|---|---|---|
| [pack_ruby_bear.json](pack_ruby_bear.json) | MIGHTY | `ruby_bear_pack` |
| [pack_emerald_cat.json](pack_emerald_cat.json) | SWIFT | `emerald_cat_pack` |
| [pack_sapphire_frog.json](pack_sapphire_frog.json) | VITAL | `sapphire_frog_pack` |
| [pack_stonebark.json](pack_stonebark.json) | NEUTRAL | `stonebark_pack` |

Current runtime validation, as of 2026-06-21:

- 90 unique cards across the four packs.
- 3 starter decks at 30 cards each: `mighty`, `swift`, `vital`.
- Card and deck schema validation pass with zero errors.

---

## Known Design Notes

- Most cards still use placeholder art in runtime. Use the `image_prompt`
  fields in the pack JSON files as the art-generation brief.
- MIGHTY, SWIFT, and VITAL balance should be re-evaluated only after Phase 2.1
  cleanup and Phase 3 PVP hardening; old balance results were tied to earlier
  rules and are no longer canonical.
- Tribe support exists in data, but tribal payoff density is still light. Treat
  `race` as a real schema field whose mechanical importance can grow later.
