# DESIGN_CORE — Elemental TCG

## Concept

A Roblox digital card battle game. Players build decks around one of three archetypes, summon monsters onto a 3-slot board, and spend Energy to play cards and attack. The setting is a 3D social TCG card shop — battles happen at visible tables, cards are collected through play.

---

## Design Pillars

- **Board presence** — what's on the field matters more than hand tricks
- **Earned resources** — Energy ramps naturally; nothing is free
- **Readable state** — board and energy readable at a glance at all times
- **Social atmosphere** — 3D card shop, visible duels, spectatable matches

---

## Core Resource: Universal Energy

- Single pool, no types
- Starts at 1 on turn 1; cap increases by +1 each turn
- Refills to current cap at the start of each turn
- Unused Energy is wasted — no carry-over

---

## Board

- Each player controls **3 open monster slots** — no Active/Bench distinction
- All slots are equal; all monsters can attack and be attacked freely
- A destroyed monster leaves its slot empty immediately

---

## Turn Structure

1. **Energy** — cap increases by 1, pool refills to cap
2. **Draw** — draw 1 card; if deck is empty, take Fatigue damage instead
3. **Main Phase** — play cards and attack in any order, any number of times while resources allow
4. **End Turn** — pass to opponent

---

## Fatigue

Drawing from an empty deck deals escalating direct Core damage: 1 the first time, 2 the second, 3 the third, and so on.

---

## Card Types

**Monster** — Summon to an empty board slot. Cannot attack the turn it is summoned (**Summoning Sickness**), unless it has **Charge**. Costs Energy.

**Action** — One-shot effect. Played from hand, resolves immediately, goes to discard. Costs Energy.

All cards cost Energy. Nothing is free.

---

## Combat

Monsters can attack the enemy hero directly or enemy minions, chosen freely each turn.

- **Taunt** blocks minion attacks — minion attacks must target a Taunt minion before any other target. Action card effects ignore Taunt entirely.
- Each monster attacks once per turn.
- When two monsters fight, each deals damage equal to its ATK to the other simultaneously.
- A monster at 0 HP is destroyed.

---

## Win Condition

Reduce the opponent's **Core HP** from **30** to 0.

---

## Coin

The second player starts with the **Coin** in hand before turn 1: "Gain 1 Energy this turn only." It is not part of the deck and does not count toward deck size.

---

## Keywords

| Keyword | Effect |
|---|---|
| **Taunt** | Minion attacks must target this minion first. Action effects bypass Taunt. |
| **Stealth** | Cannot be targeted by enemy minion attacks or targeted effects until it attacks. |
| **Armor** | Absorbs incoming damage before HP. No cap, no decay. |
| **Battlecry** | Effect triggers when this card is played from hand. |
| **Deathrattle** | Effect triggers when this monster is destroyed. |
| **Siphon** | Any heal-on-damage or direct-heal effect (VITAL mechanic). VITAL Invoker amplifies all Siphon. |
| **Charge** | Can attack immediately on the turn it is summoned. Ignores Summoning Sickness. |
| **Combo** | Bonus effect triggers if you played at least one other card earlier this turn (SWIFT mechanic). |

---

## Archetypes

### MIGHTY — Bears
**Fantasy:** Warrior. Cute, chunky, frontline combat creatures.

**Wins through:** Board combat, efficient removal, durable threats, stat buffs, Armor as defense.

**Design constraints:**
- Armor is defensive only — no converting Armor into damage output
- No Shield Slam-style mechanics

---

### SWIFT — Cats
**Fantasy:** Rogue. Sneaky, clever, agile cats.

**Wins through:** Tempo, Stealth, bounce, theft, temporary Energy.

**Design constraints:**
- SWIFT is the only archetype that regularly generates temporary Energy
- Never combine card draw and Energy cheating on the same card — this creates runaway combos

---

### VITAL — Frogs
**Fantasy:** Priest. Life magic, spirits, restoration.

**Core fantasy:** "My creatures may die, but they keep coming back."

**Wins through:** Healing (Siphon), protection, persistence, resurrection.

**Design constraints:**
- Avoid mind control, theft, and generic removal-heavy gameplay
- Removal should feel incidental, not the plan

---

## Invoker System

A persistent passive tally per archetype tracking how many cards of that type have been played this game. Crossing thresholds permanently upgrades the archetype's core mechanic for the rest of the game. Neutral cards do not tally toward any archetype.

| Tally | MIGHTY | SWIFT | VITAL |
|---|---|---|---|
| 3 | Effect damage +1 | Combo triggers on 1st card of turn | Siphon +1 |
| 6 | Effect damage +2 (total); kill → 2 face damage | Combo bonus ×1.5 | Siphon +2 (total); ally destroy → heal 2 |
| 9 | Effect damage +3 (total); kill → 3 face damage | Combo bonus ×2 | Siphon +3 (total); ally dies → heal 1 |

---

## Deck Construction

- Deck size: **30 cards**
- 2 copies of each selected identity card
- 2 copies of each selected neutral card
- One archetype per deck — no mixing
