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

## Unified Card Display

Hand, board, deck, and graveyard all share a single artwork-forward card
silhouette (~14:19 ratio). Artwork fills the frame edge-to-edge; name and
stats are overlaid on top of it rather than boxed in separate strips.

```
┌──────────────┐
│           (E)│ ← stat cluster, upper-right edge
│   [ART]   (A)│   (Energy / Attack / Health emblems, stacked)
│           (H)│
│ type badge   │ ← top-left (full mode only)
│──Name Bar────│ ← straddles the art/description boundary
│ Description  │ ← ability name + text (full mode only)
└──────────────┘
```

- **Name bar**: bold white text on a dark outline, centered horizontally,
  positioned so it overlaps the bottom of the artwork and the top of the
  description panel (50/50).
- **Stat cluster**: Energy / Attack / Health emblems stacked along the
  card's upper-right edge, each overlapping the right edge slightly so the
  group reads as one unit (see Stat Cluster below).
- **Type badge**: pill-shaped, top-left corner, archetype-colored —
  **full mode only** (omitted on board cards as secondary decoration). White
  border, Fredoka One label showing the archetype name (MIGHTY / SWIFT /
  VITAL / NEUTRAL — no separate "Action" label).
- **Description panel**: light panel below the name bar showing the card's
  ability name and text — **full mode only**.
- **Card border**: 4px outline colored by the card's archetype (see Type
  Colors below). Renders inward only (`Contextual` stroke mode), so the
  card's footprint/size is unchanged regardless of border thickness.

### Stat Cluster

Three circular emblems — Energy (cost), Attack, Health — stacked vertically
along the card's upper-right edge, anchored to the same right-edge offset so
they read as one grouped component. Each emblem is an icon with its value
overlaid on top (centered, Fredoka One, scaled text). Attack and Health
values are white with a dark outline; the Energy value is gold/yellow
(`RGB(255,224,70)`) with a dark outline, matching the HUD energy badge.

- **Full mode** (hand, deck, graveyard): all three emblems shown,
  Energy → Attack → Health from top to bottom. Each emblem is 0.15 of the
  card's width/height, anchored at `x = 1.05` (overlapping the right edge).
- **Compact mode** (board slots): only Attack and Health are shown (the
  Energy/cost emblem is hidden — irrelevant once a card is on the board).
  Each emblem is 0.2 of the card's width/height, anchored at `x = 0.97`.
- Both modes use a 0.03 top inset and a 0.03 gap between stacked emblems
  (fractions of card height).

Icon assets: Energy `rbxassetid://114305689596215`, Attack
`rbxassetid://139799158026059`, Health `rbxassetid://113514992851320`.

### Type Colors

Each card's archetype (`battleType`: MIGHTY / SWIFT / VITAL / NEUTRAL) maps
to a single main color, used for the card border, the type badge's gradient
fill, board minion borders, combat-target highlight strokes, and the Invoker
panel swatches/labels — one palette, used everywhere.

| Archetype | Main Color |
|---|---|
| MIGHTY | `#A50E0E` |
| SWIFT | `#0D652D` |
| VITAL | `#174EA6` |
| NEUTRAL | `#9AA0A6` |

The type badge's fill is a subtle vertical gradient: the main color lightened
~15% toward white (top) to darkened ~15% toward black (bottom).

### Two modes, one silhouette

- **Full mode** (hand, deck, graveyard): artwork fills the top **68%** of the
  card; the description panel occupies the bottom area.
- **Compact mode** (board slots): artwork fills the top **85%** of the card
  (no description panel or element badge), giving board cards a taller,
  art-dominant look while keeping the same name/cost/stat layout.

### Sizes

| | Desktop | Mobile |
|---|---|---|
| Hand | 132×178 | 112×152 |
| Board | 96×130 | 80×108 |
| Deck / Graveyard | 86×116 | 70×95 |

### Card Back

Used for the enemy hand (face hidden, Hand size) and the deck pile (Deck
size):

- Background: rounded rect, fill `RGB(92,62,38)`, 1.5px outer stroke
  `RGB(58,38,22)`.
- Artwork: `rbxassetid://139116126302379`, cropped full-bleed — a dark brown
  crystal-sunburst motif with an energy-gem centerpiece, matching the front
  card's Energy icon.
- Inner border: an inset panel (84% size, centered) with a 2.5px solid black
  `UIStroke`.
- Gloss: a full-card white overlay with a 115° diagonal gradient, producing
  a soft sheen streak across the card.

### Status Overlays (board cards)

- **Taunt** — large semi-transparent shield icon centered over the artwork.
- **Stealth** — the whole card is dimmed/translucent.
- **Summoning Sickness** — floating "Z" particles drift up from the
  top-right of the card and fade out, looping. A minion with **Charge**
  never shows this (it's never summoning-sick).
- **Attacked this turn** — the whole card is dimmed (lighter than Stealth's
  dim).
- Click a monster to see full card text (effect, keywords).

---

## Hand Card Display

Cards displayed as a horizontal row at the bottom, using the unified card
display in **full mode** at hand size (132×178 / 112×152). Cost, name,
artwork, and ability text are all visible without interaction.

Hovering a hand card scales it up (1× → 1.22×) so it overlaps neighboring
cards; the description text scales in lockstep with the card so its size
stays visually consistent with the rest of the card.

Cards that cannot be played (insufficient Energy, no valid target) are grayed out.

### Hand Fan Layout

Both hands are arranged as a horizontal fan, anchored to the bottom (player) or top (enemy) edge of the screen, with independently configurable spacing, edge margin, and arc curvature.

- **Fan strength** (shared by both hands): cards beyond a threshold of 3 start fanning, ramping to full strength over 3 additional cards. Each card's rotation step is capped at 4° per card, with a 28° maximum total spread regardless of hand size.
- **Card spacing**: spacing between cards is the smaller of (card width × spacing factor) or the space needed to fit all cards within the row width. The player hand uses a spacing factor of 0.8; the enemy hand uses 0.5 (enemy cards sit closer together).
- **Edge margins**: the player hand sits 20px below the bottom screen edge; the enemy hand sits 30px above the top screen edge — both hands overflow off-screen by these amounts.
- **Arc curvature**: the fan's vertical arc height scales with the card spacing, so tighter fans curve more smoothly and wider fans curve more dramatically.

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

The player's Energy (current/cap) is shown via the HUD energy badge, sitting
directly above the Grave pile in the bottom-right of the battle UI. There's
no background or border — the Energy icon (`rbxassetid://114305689596215`)
itself is the badge, sized to match the combined height of the End Turn +
Forfeit buttons (1.15× the badge's height, square). The "current/cap" value
is overlaid centered on the icon, Fredoka One, a fixed text size (so "1/1"
and "10/10" render at the same size), gold/yellow with a dark outline.

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
