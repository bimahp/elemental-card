# DESIGN_CORE — Elemental TCG

> The ruleset — single source of truth for how the game plays. Card data schema
> lives in [DESIGN_DATABASE.md](DESIGN_DATABASE.md); the engine architecture in
> [DESIGN_ENGINE.md](DESIGN_ENGINE.md).

## Concept

A Roblox digital card battle game. Players build decks around an immutable deck-bound **Crystal Core**, summon creatures onto a 3-slot board, and spend Energy to play cards, attack, and activate the Core once each turn. The setting is a 3D social TCG card shop — battles happen at visible tables, cards are collected through play.

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

- Each player controls **3 open creature slots** — no Active/Bench distinction
- All slots are equal; all creatures can attack and be attacked freely
- A destroyed creature leaves its slot empty immediately

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

**Creature** — Summon to an empty board slot. Cannot attack the turn it is summoned (**Summoning Sickness**), unless it has **Charge**. Costs Energy.

**Spell** — A one-shot effect. Played from hand, resolves immediately, goes to discard. Costs Energy.

A card's abilities are an ordered `effects[]` list (trigger + action); a card with none is a vanilla body. See [DESIGN_DATABASE.md](DESIGN_DATABASE.md). All cards cost Energy. Nothing is free.

---

## Combat

Creatures can attack the enemy hero directly or enemy creatures, chosen freely each turn.

- **Taunt** blocks attacks — attacks must target a Taunt creature before any other target. Spell effects ignore Taunt entirely.
- Each creature attacks once per turn.
- When two creatures fight, each deals damage equal to its ATK to the other simultaneously. Exception: a **Quickstrike** attacker deals its damage first and takes no retaliation if the defender dies.
- **Lifesteal** damage heals the dealing side's hero for the amount dealt.
- A creature at 0 HP is destroyed.

---

## Win Condition

Reduce the opponent's **Core HP** from **30** to 0.

---

## Coin

The second player starts with the **Coin** in hand before turn 1: "Gain 1 Energy this turn only." It is not part of the deck and does not count toward deck size.

---

## Crystal Core

Crystal Core is the official replacement for the removed Invoker mechanic.

- Each deck has exactly one Core chosen when the deck is created.
- A deck's Core is immutable. To change Core identity, create a new deck or delete/recreate the old deck.
- In battle, the Core behaves like a Hearthstone-style Hero Power: it costs **2 Energy**, can be activated once on your own turn, and resets at the start of your next turn.
- Core scaling is based on cards played by that side during the battle, tracked separately for MIGHTY, SWIFT, and VITAL. NEUTRAL cards, Coin, fatigue, attacks, and Core activations do not advance counters.
- Threshold tiers are `0-4`, `5-9`, `10-14`, and `15+`.

Alpha Cores:

| Core | Supported Types | Effect |
|---|---|---|
| Core of Vanguard | MIGHTY | Gain Armor: 1 / 2 / 4 / 6 from MIGHTY counter |
| Core of Assassin | SWIFT | Deal damage to a creature: 1 / 2 / 2 / 3 from SWIFT counter. If it kills the target, draw 1 and reduce that drawn card's cost by 1 |
| Core of Renewal | VITAL | Heal a friendly hero/Core or creature: 1 / 2 / 4 / 6 from VITAL counter |
| Core of Warrior | MIGHTY + SWIFT | Gain Armor 1 / 2 / 3 / 4 from MIGHTY counter, and draw 0 / 1 / 1 / 2 from SWIFT counter |
| Core of Guardian | MIGHTY + VITAL | Gain Armor 1 / 2 / 3 / 4 from MIGHTY counter, and heal 0 / 1 / 2 / 3 from VITAL counter |
| Core of Sage | SWIFT + VITAL | Draw 0 / 1 / 1 / 2 from SWIFT counter, and heal 1 / 2 / 3 / 4 from VITAL counter |

Pure Cores are specialists and should stay stronger than dual Cores in their specialty.

---

## Keywords

Static, always-on creature states:

| Keyword | Effect |
|---|---|
| **Taunt** | Attacks must target this creature first. Spell effects bypass Taunt. |
| **Stealth** | Cannot be targeted by enemy attacks or targeted effects until it attacks. |
| **Charge** | Can attack immediately on the turn it is summoned. Ignores Summoning Sickness. |
| **Quickstrike** | When attacking a creature, deals its damage first; takes no retaliation if the defender dies. (Attacker only.) |
| **Lifesteal** | Damage this deals heals your hero for that amount. |
| **Rebirth** | The first time it dies, it resummons in place at full stats once. |
| **Armor** | Absorbs incoming damage before HP. No cap, no decay. (Hero resource, MIGHTY.) |

Ability **triggers** (when an `effects[]` entry fires) — **Emerge** (on summon), **Shatter** (on death), **Chain** (you've already played another card this turn), plus `cast` / `turn_end` / `attacked`. Full vocabulary in [DESIGN_DATABASE.md](DESIGN_DATABASE.md).

---

## Archetypes

### MIGHTY — Bears (Ruby)
**Fantasy:** Warrior. Cute, chunky, frontline combat creatures.

**Wins through:** Board combat, efficient removal, durable threats, stat buffs, Armor as defense.

**Design constraints:**
- Armor is defensive only — no converting Armor into damage output
- No Shield Slam-style mechanics

---

### SWIFT — Cats (Emerald)
**Fantasy:** Rogue. Sneaky, clever, agile cats.

**Wins through:** Tempo, Chain combos, Quickstrike pressure, cost reduction, card draw.

**Design constraints:**
- Never combine card draw and Energy/cost cheating to a degree that creates runaway combos

---

### VITAL — Frogs (Sapphire)
**Fantasy:** Priest. Life magic, spirits, restoration.

**Core fantasy:** "My creatures may die, but they keep coming back."

**Wins through:** Healing and Lifesteal, protection, persistence, resurrection.

**Design constraints:**
- Avoid mind control, theft, and generic removal-heavy gameplay
- Removal should feel incidental, not the plan

---

## Deck Construction

- Decks are exactly **30 cards** when active or battle-usable.
- A deck may include cards whose Battle Type is supported by its Crystal Core, plus NEUTRAL cards.
- Maximum **2 copies per card**.
- Draft decks may be saved incomplete or invalid, but only valid 30-card decks can be set active or used in battle.
- Each profile must always have one active valid deck. Existing and new profiles migrate to a valid `Mighty Starter` deck using `Core of Vanguard`.
- Alpha starter decks are generated from `deck_starter.json`; PvE Noob still randomizes among pure starter decks and receives the matching pure Core.
