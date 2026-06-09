# DESIGN_BATTLE — Elemental TCG: Battle Rules

> **⚠️ SUPERSEDED BY v0.3 — 2026-06-07.** The 5-slot board, typed-energy turn
> economy, and skill-spam rules described here are being replaced. See
> **`DESIGN_CORE_V3.md`** for the new battle structure (3-slot board, universal
> Energy, once-per-turn attacks) and `DEV_LOG.md` → Session 9 for why. Kept for
> historical reference — **do not build new work against it.**

## Board Layout

Each player controls 5 open monster slots. All slots are equivalent — no Active/Bench distinction.

```
Player A: [Slot 1] [Slot 2] [Slot 3] [Slot 4] [Slot 5]
──────────────────────────────────────────────────────
Player B: [Slot 1] [Slot 2] [Slot 3] [Slot 4] [Slot 5]
```

All monsters:
- Generate typed energy at the start of the owner's turn
- Can be targeted by any enemy skill (unless a card effect restricts it)
- Can use their active skills during the owner's Play Phase

---

## Starting Conditions

| Property          | Value                        |
|-------------------|------------------------------|
| Core HP           | 30                           |
| Starting hand     | 5 cards                      |
| Starting Energy   | 0 (no monsters on board yet) |
| Starting Monsters | 0                            |
| Deck size         | 20 cards                     |

Turn order determined by coin flip *(currently hardcoded to player-first in
`BattleController` — see the "Turn order" row in TBDs below; this needs
revisiting)*. Neither player can use skills on Turn 1 regardless — energy starts
at 0 and monsters don't generate until the turn after they're summoned.

The player who goes first is also subject to the **Opening Turn Rules** below —
a balance fix added 2026-06-07 after simulation testing showed an extreme
first-player advantage in mirror matches (full investigation in
`DESIGN_BALANCE.md`).

---

## Opening Turn Rules

Added 2026-06-07 after simulation testing showed MIGHTY-mirror matches were won
by the first player **~83-93% of the time** — free, unconditional summoning lets
whoever moves first establish a board lead the opponent can never close. Two
rules now offset this (server-enforced in `BattleLogic`, applies identically to
the human player and the NPC):

**Turn 1 — Summon only.** The first player's opening turn allows *only*
summoning a monster. Skills, Trainer cards, and Equipment are all blocked. In
practice this costs the first player almost nothing — they have no energy for a
skill and no established monster to equip yet regardless — but it removes one
sliver of their head start.

**Turn 2 — "Second Wind."** The second player's *first* hand-summoned monster
begins generating its energy **immediately**, instead of waiting until their
following turn like every other summon. (E.g. summoning a Battle Imp — which
generates +1 MIGHTY — grants that +1 MIGHTY the instant it lands on the board.)
This is the stronger of the two rules: it scales with whatever's actually
summoned and is never wasted (unlike a flat energy bonus, which sits unused —
see `DESIGN_BALANCE.md` for why that was tried and rejected).

**Net effect (per simulation):** first-player win rate in MIGHTY mirrors drops
from ~83-93% to ~62-64%. A real, meaningful improvement — but it does not reach
50/50 parity, and the AI-mirror simulation likely *overstates* the real-world
gap besides. See `DESIGN_BALANCE.md` for the full investigation, methodology,
results across every variant tested, and why chasing exact parity may not even
be the right goal.

---

## Turn Structure

### 1. Generate Phase
All monsters currently on your board add their listed energy to your pool.

- Monsters summoned during a **previous** turn's Play Phase generate here
- Monsters summoned during **this** turn's Play Phase do NOT generate until next turn

### 2. Draw Phase
Draw 1 card from your deck.

- If the deck is empty, no draw — play with remaining hand
- No deck-out loss condition
- No maximum hand size (TBD)

### 3. Play Phase
Perform any of the following in any order, as many times as affordable:

**Summon a monster** *(once per turn from hand)*
- Play from hand to any empty board slot
- Free, no energy cost
- 1 per turn limit (applies to hand summons only — Trainer placements are separate)
- Summoned monster generates starting next turn

**Use a monster skill**
- Select one of your monsters
- Select one of its active skill slots
- Choose a target (see Targeting Rules below)
- Pay the energy cost
- Effect resolves

**Play a Trainer card**
- Play from hand, no energy cost
- Resolve immediately, move to discard

**Attach Equipment**
- Play from hand to any of your monsters
- Free, no energy cost
- Takes effect immediately

### 4. End Phase
Temporary effects that expire this turn resolve. Opponent begins their turn.

---

## Targeting Rules

| Situation | Valid Targets |
|---|---|
| Enemy has monsters on board | Any enemy monster (your choice of which) |
| Enemy has **no monsters** on board | Enemy Core HP directly |
| Ally target required | Any of your own monsters |
| Any target | Any occupied slot on either side |

**You cannot target the enemy Core while any enemy monster is alive.** Clear the board first.

If no valid target exists for a required-target skill, the skill cannot be used.

---

## Skill Resolution

1. Player selects a monster they control
2. Player selects one of that monster's active skills
3. Player selects a target (if required)
4. Server validates energy is available
5. Energy is deducted
6. Skill effect applies
7. If any monster's HP reaches 0, KO resolution triggers immediately (see below)

---

## KO Resolution

When a monster's HP reaches 0:

1. Monster is destroyed, removed from board
2. The player who dealt the killing blow deals **Core damage to the opponent** equal to the dead monster's **max HP**
3. The slot becomes empty
4. Owner may summon a replacement on a future turn

If a Trainer or skill kills multiple monsters simultaneously, each KO resolves separately and deals its own Core damage.

---

## Direct Core Attacks

When the enemy has no monsters:
- Skills that would target an enemy monster instead target the enemy Core
- The skill deals its listed damage value directly to Core HP
- This is in addition to any KO damage that may have already been dealt this turn

Example:
```
Enemy's last monster (HP 6) is killed by Drake Whelp's Power Fang (4 damage).
→ Enemy Core takes 6 damage (KO damage from the dead monster's max HP)
Enemy now has no monsters.
Drake Whelp still has energy — player uses Power Fang again.
→ Enemy Core takes 4 damage directly (direct skill damage, no monsters to absorb it)
Total this sequence: 10 Core damage
```

---

## Passive Effects

Always active while the monster is on board. Not optional.

**Trigger types:**
- **Constant** — always applies while on board
- **On Summon** — fires once when entering the board from hand (not from Trainer placement)
- **On Damaged** — fires when this monster takes damage from a skill
- **On Skill Use** — fires when this monster uses any skill
- **End of Turn** — fires during the owner's End Phase

---

## Equipment Rules

- Equipment attaches to one specific monster
- A monster can have multiple Equipment attached (no defined limit — TBD)
- Equipment effects apply only to the attached monster
- If the attached monster is destroyed, all Equipment attached to it is also destroyed
- Equipment is NOT returned to hand on monster death

---

## Win Condition

Reduce the opponent's Core HP to 0.

Core HP is reduced by:
1. **KO damage** — killed monster's max HP dealt to its owner's Core
2. **Direct skill damage** — skill hits Core when opponent has no monsters

Forfeit is available at any time during the Play Phase.

---

## TBDs

| Item              | Priority | Notes                                   |
|-------------------|----------|-----------------------------------------|
| Max hand size     | Low      | No cap currently                        |
| Deck-out behavior | Low      | No loss — just play remaining hand      |
| Equipment limit   | Low      | No cap per monster currently            |
| On-Summon passive | Medium   | Trainer placements: do On Summon passives trigger? Recommend: NO — On Summon is hand-play only |
| Turn order (who goes first) | **High** | Hardcoded to player-first in `BattleController` (`Logic.startTurn(state,"player")`), not actually a coin flip. The new Opening Turn Rules above assume a *randomized* first/second seat — under the current hardcoded order they apply **backwards**: the human player always eats the Turn-1 restriction, and the NPC always gets "Second Wind". Must resolve before the fix helps anyone, and definitely before PvP. See `DESIGN_BALANCE.md` Follow-ups. |
