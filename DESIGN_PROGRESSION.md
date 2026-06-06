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
- It does NOT increase HP or ATK
- It does NOT make the card stronger numerically

### What Mastery Unlocks
- Alternative active skills
- Alternative passive builds
- Cosmetic upgrades (card border, art variants, animations)
- New strategic options for deckbuilding

### Mastery Example

```
Baby Dragon — Mastery Track

Mastery 1: Unlocks Fire Breath (alternative active skill)
Mastery 2: Unlocks Magma Armor (alternative passive build)
Mastery 3: Unlocks Inferno (alternative active skill — high cost, high power)
Mastery 4+: Cosmetic upgrades (TBD)
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
