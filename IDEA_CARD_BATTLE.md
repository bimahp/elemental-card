# Roblox TCG Battle UX & Animation Specification (Locked V1)

## Design Principles

### Gameplay vs Visualization

The battle system consists of two layers:

#### Layer 1: Battle UI (ScreenGui)

Visible only to the two battling players.

Responsible for:

* Hand
* Board
* Hero HP
* Mana/Energy
* Card selection
* Target selection
* Animations
* Effects

This is the authoritative gameplay presentation.

---

#### Layer 2: Table Visualization (World)

Visible to spectators.

Implemented using:

* Part
* SurfaceGui

Responsibilities:

* Current board state
* Current HP
* Current turn
* Active creatures

This layer mirrors battle state but does not contain gameplay interactions.

---

## Battlefield Layout

Player perspective:

```text
┌──────────────────────────────┐
│ Opponent Hero                │
│                              │
│ Opponent Board               │
│                              │
│──────────────────────────────│
│                              │
│ Your Board                   │
│                              │
│                    Graveyard │
│                    Deck      │
│                              │
│ Your Hand                    │
└──────────────────────────────┘
```

### Deck

Located at bottom-right.

Displays:

* Deck icon
* Remaining card count

Example:

```text
Deck
23
```

---

### Graveyard

Located above deck.

Displays:

* Graveyard icon
* Card count

Example:

```text
Graveyard
11
```

Clicking opens graveyard browser.

---

## Card Movement Rules

All card transitions should be visible.

### Draw

```text
Deck
 ↓
Hand
```

Animation:

* Deck glow
* Card emerges
* Card flies into hand

---

### Play

```text
Hand
 ↓
Board
```

Animation:

* Card lifts
* Card travels
* Card lands in board slot

---

### Destroy

```text
Board
 ↓
Graveyard
```

Animation:

* Brief shake
* Fade
* Fly to graveyard

---

### Discard

```text
Hand
 ↓
Graveyard
```

Visible movement required.

---

### Mill

```text
Deck
 ↓
Graveyard
```

Visible movement required.

---

## Hand System

### Maximum Hand Size

Locked value:

```text
8 cards
```

If hand is full:

```text
Drawn card burns
```

The drawn card never enters hand.

---

## Hand Layout

Cards are positioned along an invisible arc.

Behavior:

```text
Small hand
↓
Nearly straight

Large hand
↓
Increasing fan shape
```

Cards maintain individual rotation based on arc position.

---

## Hand Card Hover

Trigger:

```text
Mouse enters card
```

Effects:

* Scale up
* Lift upward slightly
* Open spacing with neighboring cards

Card rotation remains unchanged.

Mouse leaves: card and neighbors return to their base position, scale, and
spacing.

---

## Drag-and-Drop Targeting

There is no "Selected" state and no `[Play]` / `[Attack]` / `[Info]`
buttons. Both playing a hand card and attacking with a board monster use
press-and-drag:

```text
Idle
↓ (press + drag past threshold)
Dragging — arrow follows cursor, valid zones highlighted, hint banner shown
↓ release over highlighted zone   ↓ release elsewhere / ESC / right-click
Resolved — remote fires            Cancelled — returns to Idle
```

While dragging, invalid targets are dimmed, valid targets are highlighted,
and a hint banner at the top of the screen names the current drop target
(e.g. "Drop on an empty slot", "Drop on the enemy to attack",
"No valid targets").

---

### Playing a Hand Card

Drag a card out of the hand. Valid drop zones depend on the card:

* **Monster** / **buff-friendly-minion Action** → open board slots (or your
  own minions for buffs) highlight green
* **Enemy-targeted Action** (damage, destroy, bounce-to-enemy, take
  control, etc.) → the enemy board area highlights green
* Any other Action (self-buff, heal, draw, etc.) → your hero portrait
  highlights green

Releasing over a highlighted zone fires `PlayCard` (with a target slot for
board-slot zones, `nil` otherwise). Releasing elsewhere, or pressing ESC /
right-click, cancels — the card returns to the hand and all
highlights/arrow/banner clear.

---

### Attacking with a Monster

Drag one of your monsters that can still attack (not summoning-sick, hasn't
attacked this turn, ATK > 0):

* Enemy minions highlight red as valid targets, unless Stealthed
* If any non-Stealthed enemy minion has Taunt, it is the *only* valid
  minion target
* The enemy hero portrait highlights red unless a Taunt minion is present

Releasing over a highlighted target fires `DeclareAttack` (target slot, or
`nil` for the enemy hero portrait). Combat resolves immediately — both
sides deal damage simultaneously, including full retaliation damage even if
it kills the attacker. Monsters that can't attack do not start a drag.

---

# Combat Animation Specification

## Attack Style

Locked style:

```text
Card Lunge
```

Cards themselves perform attack motion.

No creature models required.

---

## Creature vs Creature Timeline

### Total Duration

```text
0.45 seconds
```

### Breakdown

```text
Windup      0.05s
Lunge       0.15s
Impact      0.10s
Return      0.15s
```

---

### Sequence

```text
0.00 Start

0.05 Begin Lunge

0.20 Impact

0.30 Damage Feedback

0.45 Return Complete
```

---

## Face Attack Timeline

### Total Duration

```text
0.37 seconds
```

### Breakdown

```text
Windup      0.05s
Lunge       0.12s
Impact      0.08s
Return      0.12s
```

---

## Lunge Distance

Cards do NOT travel to target.

Travel:

```text
25% - 35%
```

of target distance.

Impact effects complete the illusion.

---

## Easing

### Lunge

```lua
Enum.EasingStyle.Quad
Enum.EasingDirection.Out
```

---

### Return

```lua
Enum.EasingStyle.Quad
Enum.EasingDirection.In
```

---

## Impact Effects

At impact:

Target receives:

* Brief shake
* Small scale punch

Suggested:

```text
Scale:
1.00 → 1.05 → 1.00

Shake:
0.08s
```

---

## Damage Numbers

Damage numbers appear immediately after impact.

Do not wait for attacker return.

Example:

```text
Impact
↓
-3
```

---

## Death Timing

Death begins immediately after damage resolution.

Sequence:

```text
Impact
↓
Damage
↓
Death starts
↓
Attacker returns
```

Death and return animations occur simultaneously.

If the attacker also dies (full retaliation damage), its shrink-to-nothing
animation plays during its return tween, and its slot becomes "Empty" once
the return completes.

---

## Networking Rule

Server resolves combat immediately.

Example:

```lua
ResolveAttack()
```

Server sends final outcome.

Clients animate result.

Server never waits for animation completion.

Animation is presentation only.

Gameplay state is already resolved.
