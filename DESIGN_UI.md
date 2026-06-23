# DESIGN_UI — Elemental TCG: UI & Presentation

## Overview

Hybrid 3D/2D presentation. The 3D world shows the card shop and table setup. A 2D ScreenGui overlay handles all battle information during a duel.

---

## Pre-Battle: Table Interaction

Two entry flows (server-owned tables — see `PLAN_BACKEND.md` A3):

**PvE (talk to the Noob NPC).** A `[E] Talk` ProximityPrompt sits on the Noob.
Triggering it requests the server-owned table flow: seat the player at a free
Battle Table, seat a cloned NPC opponent on the opposite chair, and **auto-start**
the duel — no Challenge button. `BattleLoading` shows an input-blocking
"Finding Table..." overlay while seating/bench setup is in progress, then clears
on battle state, unseat/abort, battle over, timeout, or respawn. The client also
shows this overlay optimistically when the local Noob `TalkPrompt` triggers, while
the server remote remains the authoritative entry signal and cleanup path.

**PVP (sit at a table).** Each Battle Table has one `[E] Sit` ProximityPrompt (server
picks the empty chair). On sitting, a bottom **SeatedOverlay** appears:

```
   Seated (chair N) — waiting for opponent…
   [ Ready ]            [ Leave Seat ]
```

- **Ready** — marks this player ready; the duel starts once both players are ready.
- **Leave Seat** — stands the player up, no duel.

There is **no "Stand Up" prompt** — the seated player uses Leave Seat. The player
is **not anchored**: the chair's SeatWeld holds position (anchoring fights client
physics ownership). The server locks WalkSpeed/Jump while seated, and the client
ControlModule is disabled during loading, seated, and battle states. The seated
player's client locally suppresses table prompts so the same table does not still
look interactable to them. Controls and prompts are restored after unseating,
post-battle Continue, timeout, or respawn. The battle camera teardown is guarded
so it can't re-arm after the duel ends.

---

## Battle UI Layout

Full ScreenGui overlay active during a duel. Two anchored sections split the screen.

**ScreenGui configuration:** `IgnoreGuiInset = true`, `ScreenInsets = DeviceSafeInsets` (UI lives within the device safe area; per-element margins handle notches), and `ZIndexBehavior = Sibling`. `ClipToDeviceSafeArea` is left **off**: Roblox does not clip rotated GuiObjects, so an enabled safe-area clip would crop only the un-rotated center card of an odd fan (centerOff = 0) while sparing its tilted neighbors. The reported `AbsoluteSize` can be ~1px short of the physical screen due to Windows display-scaling being folded into Roblox's logical units; this is engine behavior, not a layout bug.

### Top — Enemy State

```
┌─────────────────────────────────────────────┐
│  [Enemy Core: 30 HP]          Energy: 4/4   │
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
│             Turn 02: 0:42 [End Turn]        │
└─────────────────────────────────────────────┘
```

### Turn Timer

Phase 3 adds a server-authoritative turn timer. The server sends timer metadata in
`UpdateBattleState`; the client renders a display-only countdown and resyncs whenever
a fresh state arrives.

- Desktop: compact timer text/bar sits beside the current-turn indicator / End Turn
  control in the middle HUD.
- Mobile: timer lives in the bottom-right HUD cluster above or beside End Turn, using
  the same compact styling as Energy/Deck counters.
- Normal state above the warning threshold; warning color under the final seconds;
  optional pulse under the final 5 seconds.
- Timeout enforcement is server-only. The client countdown is never trusted for rules.
- Layout changes may re-render the last battle state; if `turnEndsAt` has not changed,
  the client preserves the live countdown instead of recomputing from stale metadata.

### Bottom — Player State

```
┌─────────────────────────────────────────────┐
│  [Slot 1]   [Slot 2]   [Slot 3]             │
│                                             │
│  [My Core: 30 HP]             Energy: 3/4   │
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
  card's upper-left edge, each overlapping the left edge slightly so the
  group reads as one unit (see Stat Cluster below).
- **Type badge**: pill-shaped, **bottom-center** with a slight overflow past
  the bottom edge, archetype-colored — **full mode only** (omitted on board
  cards). White border, Fredoka One label showing the card's **race** for
  creatures (BEAR / CAT / FROG / TREANT / GOLEM …) or **SPELL** for spells.
- **Spell circle**: spell cards render their art inside a **circular frame**
  (ringed in the archetype color) in the upper-center, with the card's default
  archetype background behind it; the name, description, and stat emblems sit
  in front of the circle. Creatures keep body-filling art and have no circle —
  this gives an at-a-glance creature-vs-spell read (reinforcing that spells
  carry no Attack/Health emblems). Full mode only.
- **Description panel**: light panel below the name bar showing the card's
  ability name and text — **full mode only**.
- **Card border**: 4px outline colored by the card's archetype (see Type
  Colors below). Renders inward only (`Contextual` stroke mode), so the
  card's footprint/size is unchanged regardless of border thickness.

### Stat Cluster

Three circular emblems — Energy (cost), Attack, Health — stacked vertically
along the card's upper-left edge, anchored to the same left-edge offset so
they read as one grouped component. Each emblem is an icon with its value
overlaid on top (centered, Fredoka One, scaled text). Attack and Health
values are white with a dark outline; the Energy value is gold/yellow
(`RGB(255,224,70)`) with a dark outline, matching the HUD energy badge. On
**hand** cards the Energy value recolors to flag cost mods — green when the
effective cost is below the card's base cost, red when above, gold otherwise —
mirroring the Attack/Health buff/debuff coloring (driven by the `costMods` sent
in the state broadcast).

- **Full mode** (hand, deck, graveyard): all three emblems shown,
  Energy → Attack → Health from top to bottom. Each emblem is 0.15 of the
  card's width/height, anchored at `x = -0.05` (overlapping the left edge).
- **Compact mode** (board slots): only Attack and Health are shown (the
  Energy/cost emblem is hidden — irrelevant once a card is on the board).
  Each emblem is 0.2 of the card's width/height, anchored at `x = 0.03`.
- Both modes use a 0.03 top inset and a 0.03 gap between stacked emblems
  (fractions of card height).

Icon assets: Energy `rbxassetid://114305689596215`, Attack
`rbxassetid://139799158026059`, Health `rbxassetid://113514992851320`.

### Type Colors

Each card's archetype (`battleType`: MIGHTY / SWIFT / VITAL / NEUTRAL) maps
to a single main color, used for the card border, the type badge's gradient
fill, board minion borders, and combat-target highlight strokes — one palette,
used everywhere.

| Archetype | Main Color |
|---|---|
| MIGHTY | `#A50E0E` |
| SWIFT | `#0D652D` |
| VITAL | `#174EA6` |
| NEUTRAL | `#9AA0A6` |

The type badge's fill is a subtle vertical gradient: the main color lightened
~15% toward white (top) to darkened ~15% toward black (bottom).

### Two modes, one silhouette

- **Full mode** (hand, deck, graveyard): artwork fills the top **62%** of the
  card (`artPct`); the description panel sits directly below, covering the
  remaining ~34% (with a small bottom margin).
- **Compact mode** (board slots): artwork fills the **entire card** (no
  description panel, name bar, or type badge), giving board cards an
  art-dominant look while keeping the same cost/stat emblem layout.

### Sizes

| | Desktop | Mobile |
|---|---|---|
| Hand | 132×178 | 112×152 |
| Board | 96×130 | dynamic — scales to 30% of viewport height |
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
- Hover (desktop) or tap-and-hold (mobile) a board minion to preview its full
  card — see [Board Card Preview](#board-card-preview).

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
highlight green while dragging, with a hint banner naming the target. Zones are
driven by `CardData.targetClass(card)` — the same logic on desktop and mobile:

- **Creature:** drag onto a highlighted open board slot
- **Friendly-target spell** (buff / heal / grant a friendly creature): drag
  onto one of your minions
- **Enemy-target spell** (damage / destroy / bounce an enemy creature; burn
  may also hit the enemy hero): drag onto a highlighted enemy minion, or the
  enemy hero where allowed
- **Untargeted spell** (self-buff, heal hero, draw, armor, board-wide buff):
  drag onto your hero portrait

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

On **mobile**, the attack is a tap-drag: press a friendly minion and drag past
a small threshold to begin (a brief *stationary* hold instead opens the card
preview — see Board Card Preview), then release over a highlighted target. The
targeting arrow and hint render in an always-visible overlay (`TargetingOverlay`)
so they appear in both desktop and mobile layouts, and the system targets the
active layout's board frames (`UXMode`-driven). Board-card preview is suppressed
while any card-play or attack drag is in progress.

---

## Rejected Actions — Warning Toast

When the server refuses an action — not enough Energy; an illegal attack
(Taunt / Stealth / summoning sickness); or a spell whose prerequisite isn't met
(no valid target, or an unmet condition such as *No Wounded Ally*) — the reason
appears as a brief red toast near screen-center, then fades. The card stays in
hand and its Energy is kept. The toast renders on the always-on-top
`TargetingOverlay`, so it shows in both desktop and mobile layouts.

---

## Board Card Preview

Inspecting a board minion shows an enlarged copy of its full card (1.7× scale)
placed just to the **left** of the slot, so a cursor or finger resting on the
card doesn't cover it. For the left-most slots, where a left-side preview would
run off the screen's left edge, it auto-flips to the card's right.

- **Desktop:** hover a board card for 0.5s; the preview hides instantly when the
  cursor leaves the card.
- **Mobile:** tap-and-hold a board card for 0.5s without dragging; the preview
  hides when the finger is released. Dragging a friendly minion instead starts
  an attack.
- The preview is suppressed while any card-play or attack drag is in progress.

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

## Hero Card + Battle Charge Slots

The Crystal Core active panel is removed (no hero power). Each side's fourth
board-row cell is the **hero card**: a square surface with the player's portrait,
HP (bottom-left), and Armor (bottom-right, hidden at 0).

On the right edge sit the **two Battle Charge Slots** (`paintChargeSlots`):

- Always exactly two sockets; empty sockets stay visible (faint dark). Sized to
  read at a glance but secondary to HP/portrait (it overlaps the portrait edge
  rather than widening the board row).
- An occupied socket shows its Battle Type emblem image (MIGHTY/SWIFT/VITAL, from
  `AssetIds.ChargeEmblems`) with the amount overlaid and a type-colored rim.
- The **current** slot carries a persistent bright (yellow) ring.
- Charge changes pop the affected socket (gain/replace scale up, spend dims) — a
  cosmetic cue driven by the snapshot's `chargeEvents`; the authoritative slot
  state is painted first, so a skipped/late pop never changes rules.
- Both desktop and mobile hero cards render the slots; the board row is unchanged.

State comes from the server snapshot (`chargeSlots`, `currentChargeSlot`,
`chargeEvents`), perspective-remapped per recipient. There is no Core remote or
client activation; the orphaned `UseCore` remote does nothing.

---

## Card Library

The top-right world HUD entry is **Card Library**. It opens one reusable
`InventoryUI` panel with a page stack instead of stacking multiple ScreenGuis:

`Home -> My Cards / Deck Builder -> Deck List -> Deck Editor`

- Home shows `My Cards` and `Deck Builder`.
- My Cards reuses the existing owned-card grid/filter/preview behavior backed by
  `GetInventory`.
- Deck Builder shows saved decks, validity, card count, active marker, and deck
  actions. There is no Core column (Core is removed).
- Create Deck makes a deck directly with a default name (no Core Select page);
  optional rename remains in the editor.
- Deck Editor saves drafts, shows **all** owned cards (no Core type filter),
  enforces max 2 copies per card in the UI, shows validation messages, and enables
  Set Active only for valid 30-card decks.
- Because a hero has only **two Charge Slots**, the editor shows a Charge-type
  indicator (`N Charge Type(s) in deck`) that turns into a non-blocking warning
  (`N Charge Types - Hero Slots: 2`, plus a one-time toast) when a deck crosses to
  more than two Charge-producing types. NEUTRAL does not count.
- One shared header/back button navigates to the previous page; Back from root
  closes the panel.
- The HUD anchor still hides during battle states.

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

## Mobile Battle Layout

Mobile mode activates when viewport width < 800px or input type is Touch. `main` (desktop Frame) is hidden; `mobileRoot` (a sibling Frame filling the ScreenGui) is shown.

### 4-Row Vertical Grid

| Row | Height | Contents |
|---|---|---|
| EnemyHandRow | 20% | Face-down card backs, fanned (mirrors the player hand's curve), ~46px of each visible |
| EnemyBoardRow | 30% | 3 slots + hero, card sizes scale to row height |
| PlayerBoardRow | 30% | Same structure as enemy |
| PlayerHandRow | 20% collapsed / 35% expanded | Player's playable hand |

Rows are straight percentages of the full screen height; the two board rows are
equal and centered so the board pair sits at vertical screen center. The
enemy-hand peek (46px) and the collapsed player-hand peek (46px) are matched so
the gap above each board row is symmetric.

`mobileRoot` also contains a scrim (`ZIndex=15`, full-screen, visible when hand expanded), a grave button (bottom-left, 44×44, with discard count badge), and a HUD cluster — Energy badge, Deck count, End Turn, Forfeit, stacked vertically — docked to the **bottom-right** corner.

### Mobile Player Hand

**Collapsed** (default): Row sits at the bottom, height=20%. Cards fan slightly (16°/(n-1) angle step), showing only the top 46px (`COLLAPSED_VISIBLE`) of each card above the row.

**Expanded**: Tapping any card when collapsed triggers a 0.18s tween to Y=65%, height=35%. Cards re-layout with a tighter 8°/(n-1) fan and full spacing.

**Drag to play**: Dragging a card ≥25px lifts it to `mobileRoot` at ZIndex=100, collapses the hand, and highlights valid zones with a green UIStroke. Releasing over a zone fires `PlayCard` to the server; releasing elsewhere returns the card.

**ZIndex**: cards are ordered `25 + i` (left-most = lowest, right-most = highest), matching deck-draw direction.

**`isDraggingMobileCard` flag**: set true at drag start, prevents hand InputBegan from triggering expand/collapse while a drag is in progress.

---

## Spectator View (Planned)

Players not in a duel can observe from outside the table area. Visible from the 3D world without UI:
- Board monsters (cards displayed on the table surface)
- Core HP bars above each player's seat
- Full card text visible on click
