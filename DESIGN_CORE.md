# DESIGN_CORE — Elemental TCG

> The ruleset — single source of truth for how the game plays. Card data schema
> lives in [DESIGN_DATABASE.md](DESIGN_DATABASE.md); the engine architecture in
> [DESIGN_ENGINE.md](DESIGN_ENGINE.md).

## Concept

A Roblox digital card battle game. Players build decks, summon creatures onto a 3-slot board, and spend Energy to play cards and attack. Creatures on board build **Battle Charge** at the end of their owner's turn, creating a second hero resource for Charge-cost cards. The setting is a 3D social TCG card shop — battles happen at visible tables, cards are collected through play.

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
4. **End Turn** — resolve end-turn abilities, generate Battle Charge from non-NEUTRAL creatures on board, then pass to opponent

---

## Fatigue

Drawing from an empty deck deals escalating direct Core damage: 1 the first time, 2 the second, 3 the third, and so on.

---

## Card Types

**Creature** — Summon to an empty board slot. Cannot attack the turn it is summoned (**Summoning Sickness**), unless it has **Charge**. Costs Energy, Battle Charge, or both.

**Spell** — A one-shot effect. Played from hand, resolves immediately, goes to discard. Costs Energy, Battle Charge, or both.

A card's abilities are an ordered `effects[]` list (trigger + action); a card
with none is a vanilla body. See [DESIGN_DATABASE.md](DESIGN_DATABASE.md).
Cards may cost Energy, Battle Charge, or both; pure-Charge cards use `cost = 0`
plus a printed `chargeCost`.

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

## Battle Charge

Battle Charge is a second hero resource, separate from Energy. It **replaces the
removed Crystal Core active skill** — there is no hero power, and decks no longer
choose or store a Core.

- Each hero holds up to **two Charge Types** at once, shown as two Charge Slots on
  the hero card. Exactly one occupied slot is the **current** slot.
- **MIGHTY, SWIFT, and VITAL are Charge-producing.** At the end of a player's turn,
  each non-NEUTRAL creature that player controls generates **+1 Charge** of its
  Battle Type. Generation checks the board left-to-right after `turn_end` effects.
  **NEUTRAL never produces or occupies Charge** (and neither does the Coin).
- Automatic board generation follows the two-slot limit: matching type stacks,
  an empty slot is filled, and a third off-type creature generates nothing while
  both slots are occupied. Board generation never replaces an occupied slot.
- Direct effect gains such as `gain_charge` still use the core Charge gain rule:
  a matching gain stacks, an empty slot is filled, and a third distinct direct gain
  replaces the inactive occupied slot.
- **Spending** Charge does not move the current slot unless the spent slot reaches
  zero; an emptied slot hands "current" to the remaining occupied slot.
- Cards may **cost** Charge (`chargeCost = { battleType, amount }`) and effects may
  **grant** explicit Charge (`gain_charge`). A card can never use Charge it will
  generate later to pay its own `chargeCost` — cost validation and payment happen
  before card resolution.
- Energy, Armor, and HP are unaffected by Charge — it is its own pool.
- The old `corrupted` trait is retained only as a legacy schema action. Current
  alpha packs do not rely on Corrupted because board-generated Charge removed the
  need for a "played card does not grant Charge" exception.

> Charge is fully server-authoritative. Slots, the current slot, and per-change
> events replicate to clients/spectators for animation; animation completion never
> affects rules, and a skipped/late animation snaps to the authoritative state.

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
- A deck may include **any owned cards of any Battle Type** — there is no Core type
  restriction. Maximum **2 copies per card**.
- A hero holds only **two Charge Slots**, so the deck builder shows an informational
  warning when a deck runs **more than two** Charge-producing types
  (`3 Charge Types - Hero Slots: 2`). The warning is non-blocking: the add/save is
  still allowed. NEUTRAL does not count toward the type total.
- Draft decks may be saved incomplete or invalid, but only valid 30-card decks can be set active or used in battle.
- Each profile must always have one active valid deck. Existing and new profiles migrate to a valid `Mighty Starter` deck.
- Alpha starter decks are generated from `deck_starter.json`; PvE Noob randomizes among the pure starter decks.
