# DESIGN_UI — Elemental TCG: UI & Presentation

## Overview

Hybrid 3D/2D presentation. The 3D world shows the card shop and table setup. A 2D ScreenGui overlay handles all battle information during a duel.

---

## Pre-Battle: Table Interaction

The player approaches a DuelTable. A ProximityPrompt appears on the tabletop:

```
[E] Sit Down
```

Once seated, two buttons appear:

```
[Challenge]    [Leave]
```

- **Challenge** — locks the player in the chair, starts the duel, opens Battle UI
- **Leave** — player stands up, no duel

Player cannot move while seated.

---

## Battle UI Layout

Full ScreenGui overlay active during a duel. Two anchored sections split the screen.

### Top — Enemy State

```
┌─────────────────────────────────────────────┐
│  [Enemy Core: 30 HP]          Energy: 4/4   │
│  Invoker: ████░░░░░ (5)                     │
│                                             │
│  [Slot 1]   [Slot 2]   [Slot 3]             │
└─────────────────────────────────────────────┘
```

Enemy hand shown as card backs (count visible, contents hidden).

### Middle — Battle Log

```
┌─────────────────────────────────────────────┐
│  "Bonk Bear attacked for 3 damage."         │
│  "Enemy played Extra Fluffy — +5 Armor."    │
│                                             │
│                  [End Turn]                 │
└─────────────────────────────────────────────┘
```

### Bottom — Player State

```
┌─────────────────────────────────────────────┐
│  [Slot 1]   [Slot 2]   [Slot 3]             │
│                                             │
│  [My Core: 30 HP]             Energy: 3/4   │
│  Invoker: ██░░░░░░░ (2)                     │
│                                             │
│  Hand: [Card] [Card] [Card] [Card] [Card]   │
└─────────────────────────────────────────────┘
```

---

## Monster Card Display (On Board)

Each board slot shows:

```
┌──────────┐
│  [ART]   │
│  Name    │
│  3 / 4   │  ← ATK / HP
│ [Taunt]  │  ← keyword badge if applicable
└──────────┘
```

- Click a monster to see full card text (effect, keywords)
- Armor value shown as a separate badge when active: `[A: 5]`
- Stealth shown as a visual overlay (dimmed/translucent)
- Taunt shown as a shield border around the card

---

## Hand Card Display

Cards displayed as a horizontal row at the bottom. Each shows:
- Card artwork (large — art is the centerpiece)
- Card name
- Cost (Energy)
- Card type badge (Monster / Action)

Hovering or clicking a card expands it to show full effect text.

Cards that cannot be played (insufficient Energy, no valid target) are grayed out.

---

## Playing a Card

Cards are played by dragging them out of the hand. Valid drop zones
highlight green while dragging, with a hint banner naming the target:

- **Monster** / **buff-friendly-minion Action:** drag onto a highlighted
  board slot (open slots for monsters, your own minions for buffs)
- **Enemy-targeted Action** (damage, destroy, bounce-to-enemy, take
  control, etc.): drag onto the highlighted enemy area
- **Other Action** (self-buff, heal, draw, etc.): drag onto your hero
  portrait

Releasing outside a valid zone, or pressing ESC/right-click, cancels and
returns the card to the hand.

---

## Attacking

Drag one of your monsters that can still attack toward an enemy target:

1. Press and drag a monster that hasn't attacked this turn, isn't
   summoning-sick, and has ATK > 0
2. Valid enemy targets highlight red as you drag — enemy minions (unless
   Stealthed) and the enemy hero portrait
3. If the enemy controls a non-Stealthed Taunt minion, only that minion is
   a valid target
4. Release over a highlighted target — attack resolves immediately, both
   sides deal damage simultaneously, including full retaliation damage
   even if it kills the attacker

If a monster has already attacked this turn or is summoning-sick (and
lacks Charge), dragging it does nothing.

---

## Energy Display

Single Energy bar per side showing **current / max**. No types.

Example: `Energy: 3 / 5` — 3 remaining, 5 max this turn.

Coin card is shown in hand before turn 1 for the second player.

---

## Invoker Display

A tally bar per player showing progress toward the next threshold (3 / 6 / 9). Active threshold bonuses shown as a small icon or tooltip.

---

## Post-Battle Screen

```
┌────────────────────────────────┐
│         YOU WON!               │
│                                │
│  +50 EXP                       │
│  +25 Gold                      │
│                                │
│  Card Drop:                    │
│  [Bonk Bear]                   │
│                                │
│       [Continue]               │
└────────────────────────────────┘
```

Or on loss:

```
┌────────────────────────────────┐
│         YOU LOST.              │
│                                │
│       [Continue]               │
└────────────────────────────────┘
```

Continue closes the Battle UI and returns the player to the world.

---

## Visual Style

- Card artwork is large and prominent — the art is what sells the card
- Card text hidden by default, shown on hover/click
- Board state must be readable at a glance: ATK, HP, keywords visible without interaction
- Avoid clutter — status badges (Armor, Taunt, Stealth) use iconography, not text spam

---

## Spectator View (Planned)

Players not in a duel can observe from outside the table area. Visible from the 3D world without UI:
- Board monsters (cards displayed on the table surface)
- Core HP bars above each player's seat
- Full card text visible on click
