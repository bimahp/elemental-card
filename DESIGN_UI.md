# DESIGN_UI — Elemental TCG: UI & Presentation

## Overview

The game uses a hybrid 3D/2D presentation. The 3D world shows the social store environment and table setup. The 2D ScreenGui overlay shows battle information and the player's hand during a duel.

---

## Pre-Battle: Table Interaction

### Setup
- A table is placed in the world with two chairs (one per player/NPC)
- The NPC (Noob humanoid) is already seated on their chair
- The player approaches the table

### Proximity Prompt
When the player is close enough to the player-side chair, a prompt appears:

```
[E] Sit Down
```

Once seated, two buttons appear:

```
[Challenge]    [Leave]
```

- **Challenge** — starts the duel, locks the player in the chair, opens the Battle UI
- **Leave** — player stands up and walks away, no duel started

The player cannot move while seated (character is locked to seat).

---

## Battle UI Layout (Screen Space)

The Battle UI is a full ScreenGui overlay that appears when a duel begins.

### Top Section — Enemy State

```
┌─────────────────────────────────────────────┐
│  [Enemy Core: 20 HP]                        │
│  Energy: 3   Fire: 2                        │
│                                             │
│  [Bench 1] [Bench 2] [Bench 3]              │
│       [Active Monster]                      │
└─────────────────────────────────────────────┘
```

Enemy hand is hidden (card backs shown or hidden entirely — TBD).

### Middle Section — Battle Log / Action Area

```
┌─────────────────────────────────────────────┐
│                                             │
│  "Fire Imp attacked for 1 damage."          │
│  "You played Fireball — dealt 2 damage."    │
│                                             │
│            [End Turn]                       │
└─────────────────────────────────────────────┘
```

### Bottom Section — Player State

```
┌─────────────────────────────────────────────┐
│       [Active Monster]                      │
│  [Bench 1] [Bench 2] [Bench 3]              │
│                                             │
│  Energy: 2   Fire: 3                        │
│  [My Core: 20 HP]                           │
│                                             │
│  Hand: [Card] [Card] [Card] [Card] [Card]   │
└─────────────────────────────────────────────┘
```

---

## Monster Card Display (On Board)

Each monster slot on the board shows:

```
┌──────────┐
│  [ART]   │
│  Name    │
│  HP: 5   │
│  ATK: 2  │
│  🔥 +1   │
└──────────┘
```

- Click a monster to see full card text (passive, skill, cost)
- Equipment attached to a monster shows as an icon overlay

---

## Hand Card Display

Cards in the player's hand are displayed at the bottom of the screen as a fan or horizontal row.

Each card shows:
- Card artwork (large, intentionally prominent)
- Card name
- Cost (Energy + Element)
- Card type icon (Monster / Skill / Support / Equipment)

Hovering a card expands it to show full text.

### Playing a Card
- **Monster:** Click card → choose board slot (Active or Bench) → confirm
- **Skill/Support:** Click card → choose target (if required) → confirm
- **Equipment:** Click card → choose monster to equip → confirm

Cards with no valid target are grayed out.

---

## Attack Interaction

During the Attack Phase:

1. Player clicks their Active Monster
2. Active Monster highlights
3. Enemy Active Monster is highlighted as the target
4. A prompt appears: `[Attack] [Cancel]`
5. Confirming deals damage to both Active Monsters

If there is no enemy Active Monster, Core is highlighted as the target.

---

## Post-Battle Screen

After the duel ends:

```
┌────────────────────────────────┐
│        YOU WON!                │
│                                │
│  +50 EXP                       │
│  +25 Gold                      │
│                                │
│  Card Drop:                    │
│  [Baby Dragon]                 │
│                                │
│     [Continue]                 │
└────────────────────────────────┘
```

Or:

```
┌────────────────────────────────┐
│        YOU LOST.               │
│                                │
│     [Continue]                 │
└────────────────────────────────┘
```

Clicking Continue closes the Battle UI and returns the player to the world. The player stands up from the chair automatically.

---

## Spectator View (Planned, Not v0.1)

Players not in a duel can walk up to a table and observe.

Visible from the 3D world (no UI required):
- Active Monster on each side (card displayed on table surface)
- Bench Monsters (smaller display)
- Core HP bars above each player's seat

Detailed card text requires the spectator to click the card.

---

## Visual Style Notes

- Card artwork is intentionally large — the art is the centerpiece
- Card text is hidden until the card is clicked or hovered
- Readable board state from a distance is a priority
- Avoid clutter: show only HP, ATK, and element generation at a glance
