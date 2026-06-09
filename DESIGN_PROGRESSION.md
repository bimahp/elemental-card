# DESIGN_PROGRESSION — Elemental TCG: Progression & Rewards

## Overview

Progression is designed around monster mastery and incremental collection. No stat inflation — stronger monsters come from better deckbuilding, not from upgrading numbers.

---

## Battle Rewards (v0.1)

Awarded to the **winning player** after a completed duel.

| Reward      | Amount (v0.1 baseline) |
|-------------|------------------------|
| EXP         | 50 (TBD — adjust by playtesting) |
| Gold        | 25 (TBD) |
| Card Drop   | 1 card, randomly drawn from NPC's drop pool |

Losing player receives nothing in v0.1. (Consolation rewards TBD in later versions.)

---

## NPC Drop Pools (v0.1)

Each NPC is associated with one element. Their drop pool consists of all non-duplicate cards from their deck.

### Fire NPC Drop Pool

All unique cards from the Fire Deck:

**Monsters**
- Fire Imp
- Fire Priest
- Flame Hound
- Fire Berserker
- Baby Dragon

**Skills**
- Fireball
- Dragon Breath
- Burning Frenzy
- Inferno

**Supports**
- Fire Claw
- Molten Armor
- Kindle
- Flame Banner
- Sacrificial Flame

Drop is 1 card selected at random from this pool (equal weight, unweighted — adjust later if needed).

---

## Player EXP and Leveling

Player level is separate from monster mastery. Player EXP tracks overall account progression.

**v0.1 scope:** Track EXP and Gold only. Level thresholds and unlocks are TBD.

---

## Monster Mastery System

Monsters gain mastery through use during battles.

### What Mastery Does NOT Do
- It does NOT increase HP (HP is fixed at card design time)
- It does NOT change base stats numerically

### What Mastery Unlocks
- **Skill 2 slot** — the primary mastery reward. Each monster's Skill 2 is locked until Mastery 1 is reached.
- Additional skills added to the card's skill pool at higher mastery levels (future)
- Cosmetic upgrades: card border, art variants, animations (future)

Mastery unlocks feed into the **deck settings** screen where players configure which 2 skill slots are active. A player with Mastery 1 on Baby Dragon can now choose between Fire Breath and Inferno for their skill slots.

### Mastery Example

```
Baby Dragon — Mastery Track

Mastery 0 (base):     Skill pool: [Fire Breath]
                      Skill 1 slot: Fire Breath (only option)
                      Skill 2 slot: locked

Mastery 1:            Skill pool: [Fire Breath, Inferno]
                      Skill 1 slot: Fire Breath or Inferno (player chooses in deck settings)
                      Skill 2 slot: Fire Breath or Inferno (the other)

Mastery 2+ (future):  Additional skills added to pool
                      Cosmetic unlocks
```

### Mastery Tracking
- Mastery is tied to the individual card in the player's collection
- Each use of the monster in a duel (playing it onto the board) counts toward mastery
- Specific mastery thresholds are TBD

---

## Gold Uses (Planned, Not v0.1)

- Buy card packs from the in-game store
- Trade facilitation
- Cosmetic purchases

---

## Card Collection

- Players collect cards through:
  - NPC battle drops
  - Card packs (future)
  - Trading with other players (future)
  - Tournament rewards (future)

- Duplicate cards can be held but deck construction limits use to 2 copies

---

## Future Progression (Post-v0.1)

- Player levels with unlockable cosmetics
- Seasonal ranked ladders
- Tournament entry and rewards
- Pack opening with rarity tiers
- Card trading economy
