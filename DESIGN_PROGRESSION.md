# DESIGN_PROGRESSION — Elemental TCG: Progression & Rewards

## Overview

Progression is built around monster mastery and incremental collection. No stat inflation — stronger play comes from better deckbuilding and mastery unlocks, not upgraded numbers.

---

## Battle Rewards

Awarded to the **winning player** after a completed duel.

| Reward | Amount |
|---|---|
| EXP | 50 |
| Gold | 25 |
| Card Drop | 1 card, randomly drawn from the NPC's deck pool |

Losing player receives nothing in v0.1. Consolation rewards planned for a later version.

---

## NPC Drop Pools

Each NPC is associated with one archetype. Their drop pool is all unique identity cards from their deck (equal weight, unweighted).

Drop pool expands as more NPCs and archetypes are added.

---

## Monster Mastery System

Monsters gain mastery through use in battles.

### What Mastery Does NOT Do
- Does not increase HP or base stats
- Does not change Energy costs

### What Mastery Unlocks
- **Mastery 1:** Skill 2 slot unlocked — the primary mastery reward (planned feature, not yet implemented)
- **Higher mastery (future):** Additional skills added to the card's pool, cosmetic upgrades (card border, art variants, animations)

### Mastery Tracking
- Mastery is tied to the individual card instance in the player's collection
- Each time the monster is played onto the board in a duel counts toward mastery
- Specific mastery thresholds are TBD pending playtesting

---

## Player EXP and Leveling

Player level is separate from monster mastery and tracks overall account progression. Level thresholds and unlocks are TBD.

---

## Gold Uses (Planned)

- Buy card packs from the in-game store
- Cosmetic purchases
- Trade facilitation

---

## Card Collection

Players collect cards through:
- NPC battle drops (v0.1)
- Card packs (planned)
- Player trading (planned)
- Tournament rewards (planned)

---

## Planned Progression Features (Post-v0.1)

- Player levels with cosmetic unlocks
- Seasonal ranked ladders
- Tournament entry and prize pools
- Pack opening with rarity tiers
- Card trading between players
