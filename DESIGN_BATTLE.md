# DESIGN_BATTLE — Elemental TCG: Battle Rules

## Board Layout

Each player controls:

```
[Bench 1] [Bench 2] [Bench 3]

      [Active Monster]

         [CORE: 20 HP]
```

- **Active Monster** — participates in combat and can be targeted by enemy skills
- **Bench Monsters** — generate elemental resources, provide passives, serve as future Active Monsters
- Maximum 1 Active + 3 Bench = 4 monsters on board at once

---

## Starting Conditions

| Property         | Value                       |
|------------------|-----------------------------|
| Core HP          | 20                          |
| Starting hand    | 5 cards                     |
| Starting Energy  | 0 (gain 1 on Turn 1)        |
| Starting Elements| 0                           |
| Deck size        | 24 cards                    |

Turn order is determined at game start (coin flip or first-player rule — TBD).

---

## Turn Structure

Every turn follows this order:

### 1. Draw Phase
Draw 1 card from your deck.

- If your deck is empty, you cannot draw (no deck-out loss rule defined yet — TBD).
- There is no maximum hand size defined yet (TBD).

### 2. Generate Phase
All your monsters (Active + all Bench) generate their elements.

Example:
```
Active: Fire Imp (+1 Fire)
Bench:  Fire Priest (+1 Fire), Flame Hound (+1 Fire), Baby Dragon (+2 Fire)
→ Total this turn: +5 Fire
```

Element resources accumulate and persist between turns.

### 3. Play Phase
Play any number of cards in any order, as long as you can pay the cost.

You may:
- **Summon monsters** — pay Energy + optional Element cost
  - Summoned monsters go to Active slot if empty, otherwise Bench
  - You choose which slot to place them in
- **Play Skill cards** — pay Energy + Element cost, apply effect, card goes to discard
- **Play Support cards** — pay Energy + Element cost, apply effect (Field Supports stay on board)
- **Equip Equipment** — pay Energy + Element cost, attach to a monster you control
- **Use monster active skills** — pay the skill's Element cost, monster must be on your board

You may do all of the above in any order and as many times as you can afford.

### 4. Attack Phase
Your Active Monster may declare one attack.

- Target: opponent's Active Monster
- Both monsters take damage equal to the attacker's ATK
- **You are not required to attack** — attacking is optional

Combat damage calculation:
```
Your Active ATK → deals that much damage to enemy Active Monster's HP
Enemy Active ATK → deals that much damage to your Active Monster's HP
```

Both take damage simultaneously.

If a monster's HP reaches 0:
- It is destroyed and sent to the discard pile (along with any attached Equipment)
- The owner must promote a Bench Monster to Active at the start of their next turn
- If no Bench Monster exists, the player is exposed: attacks go directly to their Core

### 5. End Phase
Turn ends. Opponent begins their turn.

---

## Combat Rules

### Attacking
- Only the Active Monster attacks
- One attack per turn (during the Attack Phase)
- You choose whether to attack or skip

### Taking Damage
- Active Monsters absorb all incoming combat damage
- Bench Monsters cannot be targeted by combat (only by skills that specifically target bench)
- Core HP is only targeted if no Active Monster is present

### Monster Death
- When HP reaches 0, the monster is destroyed
- Equipment attached to the destroyed monster is also destroyed (not returned to hand)
- Owner promotes a Bench Monster to Active at the start of their next turn

### Promoting from Bench
- Player chooses which Bench Monster becomes Active
- Promotion happens at the start of the owner's next turn, before the Draw Phase
- A monster promoted from Bench begins with full HP (it was not in combat)

---

## Equipment Rules

- Equipment attaches to one specific monster
- Equipment effects apply only to the attached monster
- If the attached monster dies, the Equipment is destroyed with it
- A monster can have multiple Equipment attached (no defined limit yet — TBD)

---

## Field Support Rules

- Field Supports stay on the board after being played
- Effects apply each turn as described on the card
- Field Supports can be destroyed by card effects that specifically destroy them
- No defined limit on Field Supports in play (TBD)

---

## Skill Cards

- Played from hand during the Play Phase
- Paid with Energy + Element
- Immediate effect applied, then discarded
- No targeting restrictions unless specified on the card

---

## Monster Active Skills

- Each monster card has a built-in active skill (e.g., Fire Imp's Spark)
- These are NOT separate cards in the deck — they are part of the monster card
- Cost: Element only (no Energy cost unless specified)
- Can be used during the Play Phase while the monster is on board
- No limit on how many times you can use a monster's skill per turn, unless the card says otherwise

---

## Passive Effects

- Always active while the monster is on board
- Do not need to be activated
- Apply to Active and Bench monsters equally unless the card specifies otherwise

---

## Element Drain Rules

Some Water cards remove opponent elements. The opponent's element count cannot go below 0.

---

## Win Condition

Reduce opponent Core HP to 0.

Core HP can only be targeted when the opponent has no Active Monster.
