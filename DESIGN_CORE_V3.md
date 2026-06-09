# DESIGN_CORE_V3 — Elemental TCG: v0.3 Redesign Specification

> **Status: IN DESIGN — supersedes the typed-energy system described in
> `DESIGN_CORE.md`, `DESIGN_BATTLE.md`, and `DESIGN_CARDS.md` (the v0.2 system).**
>
> This document captures the v0.3 mechanical pivot decided on 2026-06-07,
> following live playtesting that surfaced two structural problems no balance
> patch could fix (see "Why This Redesign Happened" below; full design-review
> reasoning is in `DEV_LOG.md` → Session 9).
>
> **This is a complete mechanical rewrite, not a balance pass.** `BattleLogic`,
> `NpcAI`, `BattleUI`, and all 30 card definitions in `CardData` will be rebuilt
> around the systems described here — including a full content-scope reduction
> from 4 decks to 3. Per the team's own proven methodology (`DESIGN_BALANCE.md`),
> **prototype and simulate the core loop before writing the new card set.** Don't
> repeat the v0.2 mistake of designing content on paper against unvalidated rules.

---

## Why This Redesign Happened

Live playtesting of the v0.2 system (typed energy, 5-slot board) surfaced two
problems that go deeper than tuning:

1. **"Only one monster matters."** Despite 5 open board slots — the literal
   embodiment of the "Board Presence" pillar — the typed-energy economy
   bottlenecks players to roughly **one** effective skill-use per turn. The
   other slots sit there generating energy, never acting. The board never
   delivers the tactical depth its own design promises.

2. **Comebacks are structurally impossible — a "guaranteed-loss" trap.**
   Falling behind on board creates a forced loop: summon one monster (free,
   capped at 1/turn), watch it die to a fuller enemy board with **zero chance
   to trade**, repeat. That's not "behind and fighting" — it's "behind and
   waiting to lose." This is a sharper, more concrete framing of the
   first-player snowball already measured in `DESIGN_BALANCE.md` (83-93%
   first-player win rate in MIGHTY mirrors): the problem isn't just that one
   side starts ahead — it's that **the system gives the trailing side no
   avenue to ever contest the board once behind.**

---

## What's Being Replaced

| v0.2 System | v0.3 Replacement |
|---|---|
| 4 typed energy pools (MIGHTY/SWIFT/TOUGH/VITAL), persistent, board-generated | **1 universal Energy pool**, Hearthstone-style: cap rises +1/turn, refills each turn, **unused energy is wasted — no banking** |
| Free, unconditional summoning (1/turn from hand) | **Summoning costs Energy.** No hard 1/turn cap — limited only by what you can afford |
| Equipment / Trainers free to play | **Equipment and Trainers cost Energy** — they compete for the same pool as summons and skills |
| Skills usable "any number of times per turn while energy allows" | **Each monster may use its skill/attack only ONCE per turn**, regardless of Energy remaining |
| 5 open board slots | **3 open board slots** |
| 4 battle types | **3 battle types** — TOUGH merges into VITAL (keeping the VITAL name) |
| Hybrid Cards & Deck Archetypes ("locked decision," Session 8) | **Retired — moot.** No typed costs remain for a "hybrid" card to bridge. |
| No deck-out rule | **Fatigue system** (Hearthstone-style escalating direct damage on empty-deck draw) |

> **On Hybrid Cards specifically:** the "Locked design decision — 2026-06-07"
> section in `DESIGN_CORE.md` (the entire Session 8 deliverable) is retired by
> this redesign. Its core premise — a monster bridging a Main+Sub *typed* cost
> — cannot exist once every cost is paid from one universal pool. That section
> has been marked superseded in place; do not build against it.

---

## Core Resource: Universal Energy

- Single pool. No types.
- Starting value TBD (likely 1, mirroring a Hearthstone-style curve), **+1
  maximum per turn**
- Refills to current maximum at the start of each turn
- **Unused Energy does not carry over — it is wasted at end of turn**

> **Open question, flagged during design review — resolve via simulation, not
> assumption:** "wasted if unused" Energy is *symmetric* — leader and trailing
> player get the same cap on the same turn, so by itself it does **not**
> preferentially help comebacks. Its real, testable value is probably
> different: combined with paid/uncapped summoning (below), it likely
> **eliminates the v0.2 "guaranteed-loss" trap** — a trailing player can mass
> several bodies in one turn and at least force trades, instead of being fed
> into the enemy board one helpless sacrifice at a time. **Test this directly:**
> does the new ruleset ever produce a turn where a player faces a mathematically
> certain loss with zero chance to trade? If that state disappears, the
> redesign has succeeded at the thing that actually matters — independent of
> where the raw win-rate numbers land.

---

## What Costs Energy Now: Everything

This is the headline change, and it's a **direct, surgical fix to the root
cause `DESIGN_BALANCE.md` already diagnosed** for the first-player snowball —
Finding #1 names "summoning is free and unconditional" as the mechanism.
Pricing it removes that mechanism at the source, instead of patching around it
the way "Opening Turn Rules" did (and per `DEV_STATUS.md`, that patch is
currently even wired backwards).

- **Summoning a monster** — costs Energy; no hard per-turn cap
- **Playing a Trainer card** — costs Energy
- **Attaching Equipment** — costs Energy
- **Using a monster's skill/attack** — costs Energy, **and each monster may
  only do this once per turn**

Every turn becomes a genuine **develop vs. act** allocation puzzle — the exact
tension that makes Hearthstone's mana curve work. Expect the card-cost balance
surface to be considerably larger than v0.2's: every card type now competes
for the same budget as every other card type, where previously summons/
Trainers/Equipment were free and only skills had costs.

---

## Once-Per-Turn Attack Limit — the load-bearing rule

**Each monster may use its skill/attack only once per turn**, no matter how
much Energy remains. This is the rule that actually makes a multi-slot board
matter. Without it, a player would simply pour their whole pool into one
attacker — recreating "only one monster matters" with a different currency.

> **Card-design consequence to track during the rewrite:** once spam is off
> the table, players will near-always pick the *most impactful available*
> option on a monster. A cheap, repeatable "Skill 1" (the old "1 cost → 1
> damage" pattern, e.g. Battle Imp's Quick Jab) loses its reason to exist the
> instant a pricier option is affordable. **Skill 1 and Skill 2 must be
> differentiated by *function*, not just *cost/power*** — different target
> rules, different effect category (utility / control / damage), situational
> conditions — or roughly half of every monster's card text goes dead in
> practice.

---

## Board: 3 Open Slots (down from 5)

Not simplification for its own sake — a fit decision for the new economy. On a
shared, paid-everything pool, a 5-slot board turns every turn into an
overwhelming allocation spreadsheet. 3 keeps "what do I do with my Energy this
turn" legible and trackable — including for the new Player Skill system below.

> **Trade-off to be deliberate about:** on a 3-slot board, every KO represents
> a much larger fraction of total board state (~33% vs. ~20% on the old
> 5-slot board) — and since KO damage = max HP still hits the Core directly,
> swings get proportionally larger and more punishing. This may be the
> *intended* texture (high-stakes, chess-like — every piece matters
> enormously), or it may *amplify* the very swinginess this redesign exists to
> reduce. **Decide on purpose which one it is**, and check whether the
> Sustain/Control identity (below) can still function as a grind-it-out
> playstyle when individual losses are this costly.

---

## Battle Types: 4 → 3 (TOUGH merges into VITAL)

**MIGHTY, SWIFT, and a merged "VITAL"** absorbing TOUGH's role. TOUGH retires
as a standalone type.

### Why this merge is the right call, not just a headcount cut

- **The split was already blurry in the existing card pool.** Stone Turtle
  (TOUGH) and Frost Guardian (VITAL) already carry an *identical* passive —
  "incoming skill damage reduced by 1, minimum 1." The team's own card
  designs independently arrived at overlapping identities before this
  conversation ever happened.
- **It halves the hardest part of this whole redesign.** The new Player Skill
  system (below) needs one option per possible board composition. At 4 types
  on a 3-slot board that's C(3+4−1,3) = **20** compositions to design, balance,
  and teach. At 3 types it's C(3+3−1,3) = **10** — half the surface area of the
  single most balance-intensive system in the rewrite.
- **3 types × 3 slots is a closed system.** Every possible board state maps to
  exactly one of those 10 compositions, with no asymmetric "gaps" (boards that
  structurally can't represent every color). That numerical fit doesn't exist
  at 4-types-on-3-slots.
- **It produces a strategic upgrade, not just a smaller list.** MIGHTY (Aggro)
  / SWIFT (Tempo) / merged-VITAL (Control) is one of the most battle-tested
  strategic trichotomies in competitive card-game design. Crucially, this
  asymmetry is *strategic* — decks pressure each other through actual play,
  and a skilled player can answer pressure — not *chart-based* (a
  pre-determined type-advantage table). This stays fully consistent with the
  "no type beats another type" pillar this project has held since v1 of
  `DESIGN_CORE.md`.

### What the merged type must get right

1. **One unifying verb — not two verbs sharing a label.** TOUGH's
   "heal/reduce damage to self" and VITAL's "drain/disrupt the opponent" are
   mechanically different actions. Don't just alternate between the two parent
   themes inside one color; find a fusion point where both verbs *are the same
   action*. **Suggested direction: vampiric/leech design** — "drain the
   opponent's Energy and heal yourself with what you took" satisfies both
   halves in a single card concept, in a single beat.
2. **One unified visual identity — decided before new art prompts are
   written.** TOUGH is green/nature/plant-and-stone (Sproutling, Ancient
   Treant, Stone Turtle). VITAL is blue/water-ice (Water Sprite, Frost
   Guardian, Sea Leviathan). These are different aesthetic languages. A
   "vampiric/leech" framing could plausibly resolve into something like
   deep-water/abyssal/parasitic-predator imagery — carrying both "ancient,
   patient, hard to kill" *and* "draining, controlling" without reading as two
   decks stapled together.

### Proposed archetype economic identities (for the card rewrite)

Tie each type to a **distinct economic relationship** with universal Energy —
not just a different combat flavor. This gives every color a coherent "why
pick this" answer that emerges naturally from "everything costs Energy now":

| Type | Economic identity |
|---|---|
| MIGHTY | Efficiency through raw output — most damage per Energy spent |
| SWIFT | Efficiency through tempo/cards — more actions or card advantage per Energy spent |
| VITAL (merged) | Efficiency through **reduced overhead** (sustain → fewer redeploys → more value extracted per Energy spent on a summon) **and** through **denial** (degrade the opponent's Energy-to-output ratio — a relative, not absolute, advantage) |

---

## Type Counter → Player Skill ("Invoker" system)

The most novel piece of this redesign — and a genuine candidate for a
signature mechanic.

**Concept:** instead of a passive buff keyed to board composition, the Type
Counter becomes a **player-cast ability, usable once per turn**, where the
*menu of available effects* is determined by the current type-composition of
the player's board.

- With 3 types on a 3-slot board there are exactly **10** distinct
  compositions (multisets) — see the combinatorics above. A complete, closed
  design space: every board state maps to exactly one of the 10.
- This directly resolves a dead-end flagged in design review: a system where
  "3 different types = nothing" would have been a soft mono-color lock dressed
  up as a reward. **Every composition must yield *some* castable option** —
  including mixed boards. Diversity becomes "a different toolkit," not "the
  punished choice."

### Open design questions — resolve before/during prototyping

1. **Enumerate all 10, or categorize?** At 10 (vs. 20 at four types), full
   enumeration is plausible — but weigh it against grouping into **Pure**
   (3-of-one-type — 3 variants), **Dominant+Support** (2+1 split, collapsible
   to "which type leads" — 3 variants), and **Balanced** (all-different — 1
   variant). Categorizing trades granularity for learnability; decide based on
   how well playtesters can actually track "what can I do this turn" at full
   resolution.
2. **Smooth or threshold-gated?** Don't recreate the mono-color gravity well —
   effects should reward *whatever* composition exists, never make "pure"
   strictly dominant over "mixed."
3. **UI surfacing is mandatory.** Players must see, at a glance, "here is your
   current Player Skill option, and here is the composition that produced it."
   Without this, the system is a hidden-knowledge trap.
4. **Name the variance trade-off honestly.** This system reintroduces a "did I
   draw/build the right pieces" element — the same shape as the "energy
   screw" frustration this team specifically critiqued in Pokémon, just moved
   from "energy type in hand" to "board composition achieved." That's not
   automatically bad — forward-planning ("I'm holding this card to trigger
   Balanced next turn") is a *richer* tension than a coin flip — but design
   both the system and its UI to reward planning, not feel like luck.

---

## Win Condition — Kept On Purpose

**Core HP remains attackable only when the opponent's board is completely
empty.** This was weighed directly against Hearthstone's "always-attackable
hero" model and **deliberately rejected** — adopting it would invite "ignore
the board, race to the face" as a dominant strategy, gutting the project's #1
pillar (Board Presence). This rule is one of the more distinctive, coherent
pieces of this game's identity. It survives the redesign unchanged.

No overkill carry-through (excess damage simply vanishes) — matches both the
Hearthstone baseline and this project's "readable at a glance" pillar. Don't
add overkill math; it would force every combat exchange to be tracked with an
extra subtraction step, for little payoff.

---

## Fatigue System (New)

Adopted from Hearthstone: when a player must draw from an empty deck, they
take escalating direct Core damage instead (1, then 2, then 3...). Resolves
the long-standing "Deck-out behavior" TBD, open since v0.1 (see
`DESIGN_ROADMAP.md` / `DEV_STATUS.md`). Low-complexity, well-proven, no real
downside — adopt as designed in Hearthstone, no modification needed.

---

## Recommended Build Order

Follow the **exact methodology that caught the 83% first-player problem**
in `DESIGN_BALANCE.md` — simulate the mechanism, don't reason about it on paper:

1. Build a minimal/headless prototype of the **core loop only**: universal
   Energy, paid/uncapped summoning, once-per-turn attacks, 3-slot board, and a
   *stubbed* Player Skill system (placeholder effects, real composition logic).
2. Run it through the team's existing `runBatch` simulation harness (proven in
   Session 7). Specifically verify: does the "guaranteed-loss trap" actually
   disappear? What does pacing/swinginess feel like with only 3 slots?
3. **Only once the skeleton feels right**, write the full redesigned card set
   — 3 decks instead of 4 (a smaller content scope than v0.2's catalog) — and
   the 10-composition Player Skill set.
4. Re-run simulations after the card set lands. Apply the same incremental
   layering discipline `DESIGN_CORE.md` already recommended for Hybrid Cards:
   build one piece, observe it in isolation, then layer the next.

---

## Open Items Carried Into the Rewrite

| Item | Status |
|---|---|
| Does "wasted-if-unused" Energy create a comeback *advantage*, or "just" eliminate the guaranteed-loss trap? | Needs simulation — see "Core Resource" section above |
| Full enumeration vs. categorical grouping for the 10 Player Skill compositions | Open — decide during prototyping based on learnability testing |
| Unifying theme + visual identity for merged VITAL | Proposed direction: vampiric/leech; needs final art-prompt decision |
| Is the 3-slot board's larger per-KO swing the intended texture or an unwanted amplifier? | Open — test via simulation, decide on purpose |
| Turn order (who goes first) | Still an inherited TBD from v0.2 — see `DESIGN_BATTLE.md` TBDs and `DEV_STATUS.md` Known Issues. Must be resolved as part of this rewrite, not deferred again. |
