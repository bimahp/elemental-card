# DEV_LOG — Elemental TCG: Session Build History

Chronological record of what was built each session. Most recent sessions at the top.

---

## Session 11 — NpcAI Bias Audit + Balance Re-sim
**Date:** 2026-06-09

### Problem identified
After the initial v0.4 balance sim (Session 10) showed MIGHTY at 51.7% and VITAL at 45%, a critical flaw in NpcAI was identified: the AI was biased toward MIGHTY because greedy curve play (always try a monster before an action) exactly matches MIGHTY's own game plan. The two bugs that invalidated the results:

1. **`restore_health` scored 18 (baseline) at full health** — the AI would cast soothing_balm/mass_mending on a full-health hero rather than hold it. `score = 18 + math.min(missing, value) * 2` never subtracted for waste, so even when `missing = 0`, score stayed at 18.
2. **`buff_friendly_minion` had no handler** — Iron Warmaul and Titan's Warplate fell through to the default `else` case, always scoring 18 flat regardless of board state. The AI played equip cards into an empty board with no penalty.
3. **Structural ordering bias** — the play loop always tried `bestAffordableMonsterInHand` first, only falling through to actions if no monster could be played. VITAL's timing-sensitive heals and SWIFT's draw/combo actions were structurally deprioritized on every turn.

### Fixes applied to NpcAI

**Fix 1 — `restore_health` scoring:**
Added check: if `effectiveMissing <= 0` (accounting for hero OR minion damage for `hero_or_minion`/`all_friendly` targets), apply `-35` penalty instead of a positive bonus. Heals now only score positively when something is actually injured.

**Fix 2 — `buff_friendly_minion` handler:**
Added explicit scoring: `(e.atk or 0) * 3 + (e.hp or 0) * 2` (value of the buff), minus 20 penalty if `boardCount(side) == 0`. Equip cards no longer fizzle into empty boards.

**Fix 3 — unified candidate pool (structural):**
Replaced the two-branch `monster-first → action-fallback` loop with a single candidate pool per iteration. Added `scoreMonster(card)` returning a value on the same scale as `scoreAction` (`10 + atk*2 + hp*1.5 + hp/cost*3` ≈ 18–35 range). Each iteration now picks the highest-scoring affordable play — monster or action — and the archetype's natural strategy emerges from the scoring rather than from hard-coded loop order.

### Results — 90-game sim with fixed AI (n=15 per matchup per seat)

| Archetype | Win rate | vs MIGHTY | vs SWIFT |
|---|---|---|---|
| VITAL | **61.7%** | 53% even seat | 70% even seat |
| MIGHTY | 46.7% | — | 53% even seat |
| SWIFT | 41.7% | 47% | 30% |

First-mover advantage remains extreme in mirrors: MIGHTY 12–3, SWIFT 12–3 (80%), VITAL 8–7 (53% — healthier).

### Findings

- **VITAL is the dominant archetype**, not MIGHTY. The previous result was entirely an AI bias artifact. With fair play, VITAL's healing + conditional removal (Husk Reclaimer, Domination Rite) is very effective.
- **SWIFT is the weakest** at 41.7%. Specific problems identified: zero identity minions (board presence = neutral pool only), all damage targets minions rather than hero, combo payoffs (Calculated Strike 4dmg, Coordinated Strike 6dmg) too small to close games, Smoke Bomb nearly wasted in most situations.
- **MIGHTY is average**, roughly correct after the stat nerfs from Session 10.
- First-mover advantage in non-VITAL mirrors is a remaining structural issue.

### Documents updated
- `DEV_LOG.md` — this entry
- `DEV_STATUS.md` — NpcAI section updated
- `DESIGN_BALANCE.md` — new investigation section added

---

## Session 10 — v0.4 Implementation: Hearthstone-Pattern Redesign
**Date:** 2026-06-09

### Design context (v0.3 → v0.4)
Session 9 specified the v0.3 mechanical pivot. v0.4 is the full implementation of that pivot in the live modules (`CardData`, `BattleLogic`, `NpcAI`).

### Architecture changes

**Rule system overhaul (v0.3 → v0.4):**
- Universal Energy (Hearthstone-style: +1 cap/turn, full refill, no banking) replaces typed pools
- Two card types: **monster** (summon to board, attacks each turn) and **action** (one-shot effect). Trainer/Equipment distinction removed — equip effects now live on action cards (`buff_friendly_minion` effect type)
- **Direct face damage** — monsters attack the enemy hero directly (Hearthstone-style), gated only by Taunt. "Core only attackable when board is empty" rule retired
- Board: 5 slots → 3 slots
- Types: MIGHTY / SWIFT / VITAL (TOUGH merged into VITAL, Session 9)
- **Invoker system** — persistent passive tally per archetype (cards of that type played, capped at 9). Crossing 3/6/9 permanently amplifies the archetype's core mechanic:
  - MIGHTY: +1/+2/+3 to effect damage; destroying a minion deals 2/3 face damage (tier 6/9)
  - SWIFT: combo triggers on 1st card (tier 3); combo bonus ×1.5/×2 (tier 6/9)
  - VITAL: Siphon +1/+2/+3; destroying a minion heals 2 (tier 6); on-ally-death heal 1 (tier 9)
- **Coin** — second player gets +1 temporary energy on their first turn (replaces "Second Wind")
- **Fatigue** — escalating damage for drawing from empty deck (carried from v0.3 spec)

### New modules written
All in-Studio via `execute_luau` / `multi_edit` — no .lua files on disk.

**`CardData` (RS.Modules.CardData):**
- 32 total cards: 9 neutral + 8 MIGHTY + 7 SWIFT + 8 VITAL unique cards
- 3 starter decks: MIGHTY (30), SWIFT (30), VITAL (30)
- `InvokerThresholds` table for all 3 types at tiers 3/6/9
- `EFFECT_TEXT` and `getCardText` helpers

**`BattleLogic` (SSS.Modules.BattleLogic):**
- Full rules engine: `newBattle`, `playCard`, `attack`, `startTurn`, `endTurn`, `drawCard`, `checkWin`
- Effect dispatchers: `applyMonsterTriggerEffect` (battlecry/deathrattle/on_X), `applyActionEffect` (all action effect types)
- Key new helpers: `mightyDamageBonus` (applies MIGHTY Invoker damage bonus to effect damage), `applyDestroyInvokerBonus` (VITAL heal + MIGHTY face damage on kill), `pickAnyOccupiedSlot`, `pickEnemyTarget`
- `tallyInvoker` nil-guard added (neutral cards have no `battleType`, guarded against table-index-nil error)

**`NpcAI` (SSS.Modules.NpcAI):**
- Rebuilt for v0.4: unified Energy budget, monster + action cards, attack phase
- `scoreAction` scores every action effect type contextually
- `chooseAttackTarget` evaluates lethal/clean-kill/trade/poke/face heuristics
- DEFAULT_NOISE = 0.35 (noisy-argmax to produce per-game variance)

### Card changes applied during this session (8 total)
| Card | Change |
|---|---|
| Riverbank Croc | Taunt removed |
| Cragheart Behemoth | Taunt removed |
| Beheading Strike | Replaced: renamed **Titan's Warplate**, cost 6→5, effect changed to `buff_friendly_minion` +5 atk/+2 hp |
| Bastion Defender | hp 6→4, armor granted 3→2 |
| Reckless Brute | atk 4→3 |
| Warpath Roar | Renamed **Iron Warmaul**, effect changed to `buff_friendly_minion` +3 atk/+2 hp (cost stays 3) |
| Shield Wall | Cost 1→3, armor 3→5 |
| *All above tested via 90-game sim* | |

### Critical infrastructure incident: CardData destruction
During module freshening (clone → destroy → reparent pattern), a bug in the freshen helper accessed `original.Parent` AFTER calling `original:Destroy()` — `.Parent` returns nil on destroyed instances in Roblox. This silently reparented the clone to nil (inaccessible). Both `CardData` and `BattleLogic` were destroyed.

**Recovery:** No `.lua` source files exist on disk (git repo tracks only markdown docs). `CardData` was reconstructed from session memory via `execute_luau` `Instance.new("ModuleScript")`. `BattleLogic` reconstructed from a tool-result file that captured the pre-session source.

**Root cause / correct freshen pattern:**
```lua
-- WRONG (parent read after Destroy returns nil):
local clone = original:Clone(); original:Destroy()
clone.Name = original.Name; clone.Parent = original.Parent  -- nil!

-- CORRECT (capture before Destroy):
local parent = original.Parent; local name = original.Name
local clone = original:Clone(); original:Destroy()
clone.Name = name; clone.Parent = parent
```

### Simulation harness: shuffle bug fixed
The sim harness (`runGame`) was not calling `Logic.shuffle()` on decks before dealing, meaning every game played an identical card sequence. `BattleController` calls `Logic.shuffle` at lines 125–126 after `newBattle`. Added matching calls to the harness — this was responsible for the suspicious 10–0 sweep results seen in earlier runs.

### Initial balance results (broken AI, pre-fix)
- MIGHTY: 51.7% | SWIFT: 53.3% | VITAL: 45.0%
- These are not valid — see Session 11 for corrected results.

### Documents updated
- `DESIGN_CARDS.md` — v0.4 card catalog section added
- `DEV_STATUS.md` — full rewrite to v0.4
- `DEV_LOG.md` — this entry
- `DESIGN_BALANCE.md` — v0.4 investigation section

---

## Session 9 — v0.3 Pivot: Structural Redesign After Playtesting
**Date:** 2026-06-07

### The question
Live playtesting of the v0.2 system (typed energy, 5-slot board,
MIGHTY/SWIFT/TOUGH/VITAL) surfaced two problems that no balance patch could
fix:

1. **"Only one monster matters."** Despite 5 open board slots — the literal
   embodiment of the "Board Presence" pillar — the typed-energy economy
   bottlenecks players to roughly **one** effective skill-use per turn. The
   rest of the board sits there generating energy, never acting.
2. **Comebacks are structurally impossible — a "guaranteed-loss" trap.**
   Falling behind creates a forced loop: summon one free monster (capped at
   1/turn), watch it die to a fuller enemy board with **zero chance to
   trade**, repeat. This sharpens the first-player snowball already measured
   in `DESIGN_BALANCE.md` (83-93% first-player win rate): the issue isn't just
   that one side starts ahead — the system gives the trailing side **no avenue
   to ever contest the board once behind.**

### Models surveyed, and what was actually taken from each
A wide design-review pass weighed this game's resource model against four
references — the goal was never to "copy" any of them, but to identify which
*specific mechanisms* solve *this game's specific, measured problems*:

- **Hearthstone** — universal mana (ramping, refills, no banking) and
  class-based identity via Hero Powers + exclusive pools. **Took:** the
  ramping-universal-Energy shape. **Explicitly rejected:** its
  always-attackable-hero rule — adopting it would gut Board Presence and
  invite "race to face" decks as a dominant strategy.
- **Marvel Snap** — zero factions, identity via count-based synergy text,
  with lanes and simultaneous hidden-reveal as its actual depth engines.
  **Conclusion:** its core tension (bluffing, lane positioning) is
  structurally incompatible with this game's sequential, server-authoritative
  architecture. Not pursued — correctly identified as a trap before any time
  was spent chasing it.
- **Pokémon TCG Pocket** — review confirmed several things this project
  already does *better*: predictable board-based generation (vs. Pocket's
  random energy attachment / "energy screw"), fully deterministic combat (vs.
  Pocket's heavy reliance on coin flips), and "every board slot matters" (vs.
  Pocket's single-Active-Pokémon bottleneck, where benched Pokémon are
  effectively inert). One idea — evolution as an in-match investment arc — was
  flagged as worth considering *separately*, in the future, as a complement to
  (not replacement for) the existing cross-session Mastery system. Out of
  scope for this redesign.
- **MTG-style "color tags as board-state conditions"** (cost discounts/
  requirements based on what's on board, not pooled currency) — explored as a
  way to keep type identity without a hard resource lock. Superseded by the
  simpler "universal Energy + composition-gated Player Skill" direction below,
  which solves the same problem with less rules overhead.

### What got decided — the v0.3 pivot
Captured in full in the new **`DESIGN_CORE_V3.md`**. Summary:

- **Universal Energy** (Hearthstone-style ramp, +1 cap/turn, no banking)
  replaces all four typed pools.
- **Everything costs Energy** — summons, Trainers, Equipment, and skills all
  draw from the same pool. This directly prices the exact mechanism
  `DESIGN_BALANCE.md` already named as the root cause of the first-player
  snowball ("summoning is free and unconditional") — a structural fix at the
  source, not another patch stacked on "Opening Turn Rules."
- **Each monster acts once per turn**, regardless of Energy available — the
  rule that actually makes a multi-slot board matter (without it, players
  would just pour everything into one attacker again, recreating "only one
  monster matters" with a different currency).
- **Board: 5 → 3 slots** — sized to fit the new shared-pool economy and keep
  per-turn decisions legible.
- **Battle types: 4 → 3** — TOUGH merges into VITAL. Justified by real
  evidence already in the card pool (Stone Turtle and Frost Guardian already
  share an identical damage-reduction passive — the split was never clean),
  by combinatorics (halves the new Player Skill system's design surface from
  20 to 10 board compositions), and by a strategic upgrade (produces a
  battle-tested Aggro/Tempo/Control triad — asymmetry through *play*, not a
  type chart, fully consistent with the "no type beats another type" pillar).
- **Type Counter reimagined as a Player Skill ("Invoker" system)** — a
  once-per-turn, composition-gated player ability where every one of the 10
  possible board compositions yields a usable, distinct option. Resolves a
  dead-end flagged mid-review: a system where "3 different types = nothing"
  would have been a soft mono-color lock wearing a reward system's clothes.
- **Hybrid Cards & Deck Archetypes (Session 8's "locked decision") is
  retired** — its premise (a monster bridging a Main+Sub *typed* cost) cannot
  survive the move to one universal pool. Marked superseded in place in
  `DESIGN_CORE.md`.
- **Fatigue system adopted** from Hearthstone, finally resolving the
  long-open "deck-out" TBD (open since v0.1).
- **Win condition kept on purpose** — "Core only attackable when the board is
  empty" was weighed directly against Hearthstone's model and deliberately
  retained, because removing it would gut the Board Presence pillar. One of
  the more distinctive, coherent pieces of this game's identity; it survives
  the pivot unchanged.

### Open items carried into the rewrite
- Whether "wasted-if-unused" Energy produces a comeback *advantage* (it's
  symmetric — it likely doesn't) vs. its more precise, testable contribution:
  eliminating the guaranteed-loss degenerate state outright. Resolve via
  simulation, the same way the 83% number was originally measured — not by
  reasoning about it on paper.
- Full enumeration vs. categorical grouping for the 10 Player Skill
  compositions.
- A unifying theme (proposed: vampiric/leech) and a single unified visual
  identity for the merged VITAL type (currently straddling green-nature and
  blue-water aesthetics).
- Whether the 3-slot board's larger per-KO swings (~33% of board per death,
  up from ~20%) are the intended high-stakes texture or an unwanted amplifier
  of the very swinginess this redesign exists to reduce.

### Recommended next step
Per the team's own proven methodology — the exact one that caught the 83%
first-player problem before it shipped — **prototype and simulate the core
loop (universal Energy, paid/uncapped summons, once-per-turn attacks, 3-slot
board, stubbed Player Skill) before writing a single one of the redesigned
cards.** Full build order documented in `DESIGN_CORE_V3.md`.

### Documents updated
- **New:** `DESIGN_CORE_V3.md` — full v0.3 mechanical specification
- `DESIGN_CORE.md` — superseded banner added; Hybrid Cards section marked retired
- `DESIGN_BATTLE.md` — superseded banner added (5-slot board / typed-energy turn structure)
- `DESIGN_CARDS.md` — superseded banner added (full catalog rewrite pending)
- `README.md` — doc index updated to include `DESIGN_CORE_V3.md` and reflect pivot status

---

## Session 8 — Energy Economy Design Lock: Hybrid Cards & Deck Archetypes
**Date:** 2026-06-07

### The question
Mid-design-review, the typed-energy economy itself got re-opened: does "build a
deck around one type" cap deckbuilding too narrowly for the long run, and how
*should* future cross-type synergy (e.g., "TOUGH tankiness comboed with VITAL
healing") actually work mechanically — given that, unlike Pokémon's per-card
attached energy, our pools are global?

### Paths explored and rejected
- **Universal "Any" / colorless costs** (Pokémon Colorless-style, including the
  softer "1 Any + 1 [Type]" Bulbasaur pattern) — would have meant retrofitting
  baseline costs (e.g., Battle Imp's Quick Jab: "1 MIGHTY" → "1 Any"), which
  hollows out the **Energy Engine** pillar: the cheapest, most-played skills
  stop caring about type, leaving typed pools to matter only for rare expensive
  finishers. Also exposes a structural gap Pokémon doesn't have — Pokémon
  resolves "which energy pays a Colorless slot" for free via manual per-card
  attachment; our globally-pooled model has no clean equivalent without
  inventing a whole new cast-time pool-selection UX.
- **True multi-type "splash" play** (Magic-style multicolor) — rejected as a
  general model. Unlike Magic (lands/spells decoupled), our creatures *are* our
  mana base *and* occupy our 5 precious board slots, so multicolor would tax
  **Board Presence** (pillar #1) directly — and would multiply an
  already-behind balance workload combinatorially (only 1 of 4 Pure decks has
  simulation data so far, see `DESIGN_BALANCE.md`).
- **Replacing typed energy with a universal generic resource entirely**
  (Hearthstone-style mana curve, "+1 max per turn") — explored as a full
  alternative foundation. Would have solved the "creatures-as-mana-base"
  problem outright and freed "type" to become a pure board-composition identity
  (e.g., count-based tribal payoffs like "+1 HP per VITAL ally" — well
  precedented via MTG Devotion / Hearthstone "for each X you control," and
  arguably a more natural fit for a small, fully-visible 5-slot board than an
  invisible internal-pool economy ever was). Ultimately the user chose to keep
  the existing, partially-validated typed-energy system rather than replace it
  — but the count-based synergy framing is worth carrying forward as a model
  for how "type identity" should express itself on the board, independent of
  how energy works.

### What got locked in
**Typed energy stays hard-typed. No "Any" cost will ever exist on any card.**
Cross-type play is instead enabled by a new card archetype — the **Hybrid
Card**: a monster whose type differs from its deck's declared Main type, which
generates its *own* Sub-type energy and carries a skill costing a Main+Sub mix
(e.g., a VITAL-typed Hybrid Card inside a MIGHTY-main deck, with a skill
costing "1 MIGHTY + 1 VITAL"). It is "self-sufficient" — it brings its own
fuel, so nothing else in the deck ever needs to generate the Sub type, and
nothing is left stranded if the card dies. This sidesteps the mana-base trap
that sank both of the rejected paths above.

Three mandatory checks were defined for every future Hybrid Card design:
**bootstrap lag** (it can't use its own hybrid skill the turn it lands — decide
if that's deliberate texture), **self-sufficiency ratio** (its own
generate-rate vs. its own spend-rate is a new tuning axis, separate from
HP/role/cost balance), and **splash tax** (swapping in a Hybrid Card naturally
slows the Main engine — an organic trade-off worth protecting, not designing
away).

Target scope: **4 Pure decks + up to 12 Hybrid (Main×Sub) decks = 16 total
deck identities**, to be built incrementally — finish validating all 4 Pure
decks first (SWIFT/TOUGH/VITAL currently have zero simulation data), then add
Hybrid Cards one at a time, re-simulating after each.

### Documents Updated
- `DESIGN_CORE.md` — new **"Hybrid Cards & Deck Archetypes"** section: locks
  the "no Any energy, ever" decision with full rationale for both rejected
  alternatives, defines the Pure vs. Hybrid deck philosophy, documents the
  self-sufficient Hybrid Card mechanism with a worked example, lists the three
  mandatory design checks, and sets the 16-archetype target scope with a
  recommended incremental build order.

---

## Session 7 — Balance Investigation: First-Player Advantage + Opening Turn Rules
**Date:** 2026-06-07

### The question
Concern raised during design review: because summoning is free and unconditional,
does whoever acts first in a match simply snowball an unbeatable lead? Investigated
via headless simulation against the **actual game modules** (`BattleLogic` /
`CardData` / `NpcAI`) — two identical MIGHTY decks, symmetric greedy AI, run many
times — rather than reasoning about it on paper.

### What we found
- **First-player win rate in MIGHTY-mirror matches: ~83-93%** (n=100 and n=50,
  reproduced across independent runs). A real, large structural problem.
- Hit and diagnosed a methodology trap along the way: Roblox's sandboxed
  `math.random` doesn't reseed across separate `execute_luau` executions, so
  comparing variants run in different script calls silently compares the *same*
  random sequence. Fix: run every variant to be compared sequentially inside one
  execution via a shared `runBatch` helper.
- Tested 7+ compensation mechanics and combinations at n=50 each (extra card draw,
  flat energy bonus, "instant energy on first summon" / **Second Wind**, turn-1
  action restrictions, and combos). Flat energy bonuses turned out to be inert —
  the second player has no monster on board yet to spend the bonus on the turn
  they'd receive it. Second Wind (granting the *summoned monster's own* generation
  amount immediately) avoids that trap and was the strongest lever found.
- Established an empirical noise floor: two runs of an *identical* ruleset landed
  ~10 percentage points apart at n=50 — meaning most fine-grained comparisons in
  this investigation aren't individually trustworthy; only the large gaps
  (baseline vs. any real fix) are reliable.
- Full results table, reasoning, and methodology reference written up in the new
  **`DESIGN_BALANCE.md`**.

### What we shipped
Implemented **"Turn 1 = summon only" + "Second Wind"** directly in `BattleLogic`
(server-enforced — applies identically to the player and the NPC, no client
bypass possible):
- `useSkill` / `playTrainer` / `attachEquipment` reject all calls when
  `state.turnNumber == 1`
- `summonMonster` grants the second player's first hand-summon its listed energy
  generation **immediately**, instead of making it wait a turn like every other
  summon

**Result: first-player win rate drops from ~83-93% to ~62-64%.** A real
improvement — though not full 50/50 parity (see caveat below for why that may
not even be the right target).

### A late realization that reframes the whole investigation
The simulation pits two copies of the *same deterministic, mistake-free* greedy
AI against each other — a setup with **zero comeback potential by construction**,
since neither side ever misplays or lets a lead slip. That's exactly the mechanism
that lets a real player behind on board state claw back into a game. So the
83-93% / 62-64% figures almost certainly **overstate** the real-world first-player
advantage — they're a structural ceiling, not a prediction of the live experience.
Confirmed against the user's own playtest report ("I lost, easily — I think
AI-vs-AI lacks the possibility of error that caused the disadvantage, and the
2nd-turn boost wasn't great either").

### Open follow-up
**Turn order is still hardcoded to "player always first"** in `BattleController`
(`Logic.startTurn(state,"player")`) — not an actual coin flip, despite
`DESIGN_BATTLE.md` previously claiming otherwise (now corrected). This means the
new rules currently run *backwards* in live play: the human player always eats
the Turn-1 restriction, and the NPC always gets Second Wind. Needs to be resolved
— likely by finally implementing the long-standing "turn order" TBD — before the
fix benefits anyone, and certainly before PvP. See `DESIGN_BALANCE.md` Follow-ups.

### Documents Updated
- `DESIGN_BATTLE.md` — corrected the stale "coin flip" turn-order claim; added a
  new "Opening Turn Rules" section documenting Summon-Only-Turn-1 and Second Wind;
  added a high-priority "Turn order" row to the TBDs table
- `DEV_STATUS.md` — documented the `BattleLogic` rule changes under Battle Logic
  Module; upgraded the "Turn order" Known Issue to high priority with full context
  on why the hardcoded order now matters more
- `DESIGN_BALANCE.md` — **new file**, created to hold this investigation: full
  methodology (including the `math.random` reseed gotcha and the noise-floor
  finding), the complete results table across every variant tested, the AI-mirror
  overstatement caveat, and a reusable headless-simulation reference for future
  balance work

---

## Session 6 — v0.2 Full Implementation + Battle UI Card-Size Tuning
**Date:** 2026-06-07

### Trainer Card Redesign (continuation of Session 5 design work, before implementation)
- Removed all 4 "Formation" trainer cards entirely (one per deck) — replaced with a new shared
  card, **Retreat**: "Return one of your monsters from the board to your hand. It returns at
  full HP." (now shared across all 4 decks alongside Potion and Quick Draw)
- Replaced the old shared "Energy Crystal (gain 2 any energy)" with **4 deck-unique Energy
  Crystal variants** — Energy Crystal (Mighty/Swift/Tough/Vital), each "Gain 1 [Type] energy"
- **Nerf pass (3 cards)**, per balance feedback against the 30-HP Core / single-digit monster
  HP scale:
  - Iron Shield: +3 max HP → **+2 max HP**
  - Energy Crystal: gain 2 energy → **gain 1 energy** (2 was judged too strong — "imagine
    bringing 3 of that card")
  - Potion: now heals the **Core** (the player/"trainer" in TCG terms) instead of a monster —
    "Heal 3 HP to your Core"
- `DESIGN_CARDS.md` updated to reflect the final trainer set for all 4 decks

### Full v0.2 Code Implementation (the big one — full rewrite of 5 modules)
Replaced the entire v0.1 ruleset (ATK-based combat, Active/Bench board, Fire/Nature/
Lightning/Water elements) with the new MIGHTY/SWIFT/TOUGH/VITAL system designed in Sessions
4–5:

- **`CardData`** rewritten (12,169 chars) — `CardData.Decks` (4×20-card decks),
  `CardData.Cards` (30 unique definitions: Monster/Equipment/Trainer shapes), `getCardText`
- **`BattleLogic`** rewritten (19,510 chars) — 5-slot open board, typed energy pools,
  skill-based damage resolution (`useSkill` handles 6 effect-type variants), KO damage =
  killed monster's maxHP to Core, direct Core attacks when board empty, Retreat mechanic,
  energy drain (auto-targets most-abundant type), all passive trigger types, all 7 equipment
  effect types
- **`NpcAI`** rewritten (3,093 chars) — new 4-step priority loop (summon → use skills
  greedily → play trainers contextually → equip)
- **`BattleController`** rewritten (7,956 chars) — new `UseSkill` RemoteEvent + handler,
  `PlayCard` now routes by `cardType`, DataStore renamed `ElementalTCG_v1` → `ElementalTCG_v2`,
  removed `DeclareAttack`/`playSkill`/`playSupport` handlers (now orphaned remote)
- **`BattleUIController`** rewritten (19,966 chars) — 5-slot board rendering (repurposing the
  old Bench row frames, hiding the old Active row frames), skill-selection click→highlight→
  "Use Skill" interaction flow, new board/energy state rendering

**Testing performed (all passing):**
- Headless: card/deck integrity (30 cards, 4×20), free summon + 1/turn limit, typed energy
  gen/spend, all skill effect variants, KO resolution (maxHP→Core confirmed exact), direct
  Core attacks, Retreat (full-HP return confirmed), energy drain (most-abundant targeting
  confirmed), all passive triggers, all equipment effects, full 6-turn NPC-vs-player sim
  (NPC won 30→-5 via KO chain + direct attacks)
- In-game: Play mode + `StartDuel`/`PlayCard`/`UseSkill`/`EndTurn` fired via `execute_luau`,
  screenshots confirmed correct rendering, NPC behavior, and passive triggering

### Battle UI Card-Size Tuning (3 iterative passes, all per direct user feedback)
With the board simplified to one open row of 5 slots (no more Active/Bench split), the user
wanted the board/active cards to read as the focal point of the layout:
1. **Flip the size relationship** — board slots were smaller than hand cards (BW/BH=78/106 vs
   HW/HH=93/128); swapped so board slots became the larger element (→ 104/142 vs 76/106)
2. **"Hand cards too small, raise board a bit too, add margin between rows"** — enlarged both
   (board → 112/150, hand → 92/124), grew `BenchRow`/`HandRow`/section frame heights to fit,
   shrank the now-hidden legacy `ActiveRow` frames to reclaim layout space, and added
   `Padding = UDim.new(0,12)` to each section's `UIListLayout` for a clean visual gap between
   the board row and hand row
3. **"Raise both bigger again"** — final sizes: board BW/BH = 128/172 (desktop), hand HW/HH =
   108/146 (desktop); grew section/row frames again (sections 400→440px, BenchRow→188px,
   HandRow→162px) to fit without clipping

All proportional text-size ratios in `mkSlot`/`fillSlot`/`buildCard`/`mkBack` (e.g. `BW*0.088`,
`HH*0.16`) scale automatically with these constants — no manual tuning needed; `math.max(8,
...)` floors keep text legible at all viewport sizes. Verified visually via Play-mode
screenshots after each pass.

### Documents Updated
- `DESIGN_CARDS.md` — final trainer card set (Retreat added, Formations removed, Energy
  Crystal split per-deck, 3-card nerf pass applied)
- `DEV_STATUS.md` — full rewrite to reflect the v0.2 implementation: module statuses, new
  `UseSkill` remote, `ElementalTCG_v2` DataStore key, orphaned `DeclareAttack` note, new
  Battle UI board structure + card-size constants, updated Out of Scope list
- `DEV_LOG.md` — this entry

---

## Session 5 — Battle Type Rename + Starter Deck Full Design
**Date:** 2026-06-07

### Design Decisions Made

| Decision | Old | New |
|---|---|---|
| Element names | Fire / Nature / Lightning / Water | MIGHTY / SWIFT / TOUGH / VITAL |
| Element advantage | Assumed by players due to naming | No advantage — types have strategic identities only |
| Starter deck composition | 12M + 4T + 0E | 12M + 4T + 4E = 20 cards |
| Equipment design | Not defined | 3 shared (Iron Shield, Combat Crest, Energy Coil) + 1 deck-unique |
| Trainer design | Not defined | 3 shared (Potion, Quick Draw, Energy Crystal) + 1 deck-unique "Formation" |
| Formation trainer | Not defined | "Spawn 2 of its type" from deck to board — bypasses 1/turn hand rule |
| On Summon from Formation | Undefined | Does NOT trigger On Summon passives (hand-play only) |
| Core HP determination | Deck-dependent or fixed | Fixed at 30 (Option A) |
| Forced HP total constraint | All decks sum to exactly 30 HP | Removed — balance comes from mechanics, not HP sum |
| Energy drain targeting | Player choice | Auto-targets most abundant energy type (simplicity for Roblox) |

### Deck Designs Finalized (all 4 starters)

**MIGHTY (Red):** Battle Imp (S/4), Charged Hound (F/6), Iron Berserker (F/7), Drake Whelp (A/10) — Battle Axe (unique equip), Mighty Formation (unique trainer)

**SWIFT (Yellow):** Spark Rat (S/4), Storm Runner (F/6), Thunder Hawk (F/7), Storm Drake (A/10) — Speed Boots (unique equip), Swift Formation (unique trainer)

**TOUGH (Green):** Sproutling (S/5), Vine Brute (F/6), Stone Turtle (F/7), Ancient Treant (A/10) — Thorn Bark (unique equip), Tough Formation (unique trainer)

**VITAL (Blue):** Water Sprite (S/4), Tide Hunter (F/6), Frost Guardian (F/7), Sea Leviathan (A/10) — Frost Lens (unique equip), Vital Formation (unique trainer)

**Shared (all 4):** Iron Shield (+3 HP), Combat Crest (+1 skill dmg), Energy Coil (+1 gen), Potion (heal 3), Quick Draw (draw 2), Energy Crystal (gain 2 any energy)

### Documents Updated
- `DESIGN_CARDS.md` — complete rewrite: all old Fire/Nature/Lightning/Water removed, all 4 new starter decks with full card text, image prompts, and summary tables
- `DESIGN_CORE.md` — finalized at MIGHTY/SWIFT/TOUGH/VITAL naming (no code changes needed)
- `DESIGN_BATTLE.md` — finalized targeting rules and direct Core attack rules (no code changes needed)
- `DEV_LOG.md` — this entry

### Not Yet Done
- CardData.lua rewrite (remove ATK, rename types, new card structures with 2 skill slots, equipment)
- BattleLogic.lua rewrite (5-slot board, skill-only damage, KO=maxHP Core damage, direct Core when no monsters)
- BattleUI rewrite (5-slot board layout, remove Active/Bench distinction)
- NpcAI.lua rewrite for new ruleset

---

## Session 4 — Core Mechanic Redesign
**Date:** 2026-06-07

### Design Decisions Made

| Decision | Old | New |
|---|---|---|
| Summon cost | 1 Energy | Free, 1 per turn |
| Resource system | Energy + Element (dual) | Element only (shared pool from board) |
| Board layout | Active + 3 Bench | 5 open slots, no distinction |
| Damage model | ATK stat, mutual combat | Skills only, no ATK stat |
| Win condition | Core HP after board clear | KO → Core damage = killed monster's max HP |
| Core HP | 20 | 30 |
| Deck size | 24 cards | 20 cards |
| Monster level | Level 1/2/3 (summon cost gating) | Removed — roles are Scout/Fighter/Anchor (design guidance only) |
| Skill slots | 1 built-in skill per monster | 2 configurable slots from skill pool (Skill 2 locked until Mastery 1) |
| Skill setting | Fixed at card design | Configured in deck settings screen |
| Attack phase | Separate phase, 1 attack | Part of Play Phase, unlimited while energy allows |
| Turn order | Always player first | Coin flip at battle start |

### Documents Updated
- `DESIGN_CORE.md` — full rewrite for new system
- `DESIGN_BATTLE.md` — full rewrite for new turn structure and KO rules
- `DESIGN_CARDS.md` — all 20 monsters rebalanced with new stat framework; old Skill/Support/Equipment sections deprecated
- `DESIGN_PROGRESSION.md` — mastery system updated to reflect Skill 2 unlock mechanic
- `DEV_STATUS.md` — flagged as design revision phase

### Monster Stat Changes (from v0.1)
- Fire Imp: HP 3 → 4
- Fire Berserker: HP 4 → 5
- Ancient Turtle: HP 8 → 7 (still tank, reduced slightly for balance)
- All ATK stats removed
- All Level designations removed
- Every monster now has exactly 2 skill entries (Skill 1 base, Skill 2 mastery-locked)

### Not Yet Done
- Trainer card redesign (replaces old Skill/Support/Equipment cards)
- CardData.lua rewrite for new system
- BattleLogic.lua rewrite for new system
- BattleUI rewrite for 5-slot board

---

## Session 3 — UI Polish + NPC Pose Fix
**Date:** 2026-06-06

### UI Layout Overhaul
- Restructured BoardContainer into two independently anchored sections:
  - `EnemySection` — AnchorPoint top-center, sticks to top of screen
  - `PlayerSection` — AnchorPoint bottom-center, sticks to bottom of screen
  - Thin divider line at screen center between them
- Enemy hand and player hand now **same card size** (HW=93, HH=128) for visual consistency
- All 8 board slots **unified size** (BW=86, BH=108) — active slot no longer larger than bench
- `getRow()` in BattleUIController updated to `bc:FindFirstChild(n, true)` for recursive search through new section hierarchy
- BattleLog height increased to 240px

### Previous Session's 7 Fixes (completed)
1. **Enemy card order** — Fixed UIListLayout SortOrder to LayoutOrder; enemy rows now mirror player
2. **Card back size** — Enemy backs made same dimensions as player hand cards
3. **Helmet/character visible** — `hideChar()` sets LocalTransparencyModifier=1 on all parts except arms on camera lock
4. **Forfeit position** — Moved under End Turn in ActionButtons frame
5. **Battle log** — Added ScrollingFrame on left side, above PlayerInfoWidget
6. **Passive descriptions** — All monster cards now show `[P] ...` passive line
7. **Movement after win** — Server no longer restores WalkSpeed; client only unlocks in Continue handler

### NPC Foot Pose
- Identified backward foot issue in R6 sitting pose
- Read C1 values: Right Hip C1 pos(0.5,1,0) rot(0,π/2,0), Left Hip C1 pos(-0.5,1,0) rot(0,-π/2,0)
- **Attempt 1 — swap Y rotations:** RH Y: +π/2→-π/2, LH Y: -π/2→+π/2. Result: legs went outward/upward — wrong. Reverted.
- **Attempt 2 — add Z=π:** RH/LH Z: 0→π (roll leg 180° around own axis). Result: pending test.

### Documentation
- Created this file (DEV_LOG.md)
- Created DEV_STATUS.md with full implementation state
- Rewrote README.md as proper entry point

---

## Session 2 — Battle UI Implementation
**Date:** 2026-06-06 (earlier)

### UI Built from Scratch
- ScreenGui BattleUI with IgnoreGuiInset=true
- BoardContainer with UIListLayout (7 rows: enemy hand, enemy bench, enemy active, divider, player active, player bench, player hand)
- EnemyInfoWidget (top-right, dark red)
- PlayerInfoWidget (bottom-left, dark green)
- ActionButtons (bottom-right): Attack, End Turn, Forfeit
- BattleLog (left side)
- PostBattle overlay (centered, ZIndex=30)

### BattleUIController LocalScript
- `hideChar()` / `showChar()` — LocalTransparencyModifier character visibility
- `startCam()` / `stopCam()` — Scriptable camera locked to player head facing NPC
- `fillSlot()` — board slot rendering with active/bench distinction
- `buildCard()` — hand card builder (name strip, element art block, stats/skill/passive text, type badge)
- `mkBack()` — enemy hand card back design
- `updateLog()` — battle log renderer, auto-scrolls to bottom
- `render(state)` — full state → UI update
- Hand card click handling → fires PlayCard RemoteEvent with appropriate slot logic
- BattleOver → PostBattle overlay shown, movement NOT restored
- ContinueBtn → restores WalkSpeed=16, JumpPower=50, Sit=false

### Camera Fix
- Camera positioned at `head.Position + (0, 0.3, 0)` looking at NPC seat position
- RenderStepped connection locks camera every frame during battle

---

## Session 1 — Core Systems + World Setup
**Date:** 2026-06-06 (earlier)

### World Objects Placed
- `Workspace.DuelTable` — table with ProximityPrompt on highest-Y part
- `Workspace.NPCChair` (IsNPCSeat=true) with NPCSeat (Seat)
- `Workspace.PlayerChair` (IsPlayerSeat=true) with PlayerSeat (Seat)
- `Workspace.Noob` — R6 humanoid NPC

### Card Data Module
- `ReplicatedStorage.Modules.CardData` — all 14 Fire Deck unique cards
- Fire Deck list (24 cards with duplicates)
- `getCardText()` helper

### Battle Logic Module
- Full rules engine in `ServerScriptService.Modules.BattleLogic`
- All core functions: newBattle, shuffle, draw, generate, summon, attack, skill, support, endTurn, checkWin, killActive, dealDamage

### NPC AI Module
- `ServerScriptService.Modules.NpcAI` — priority-based action selection
- 6-priority rule list (summon → skill → support → monster skill → attack → end turn)

### Battle Controller (Server)
- `ServerScriptService.BattleController`
- DataStore integration
- RemoteEvent handling for all player actions
- NPC turn execution via task.spawn (0.7s delay)
- Reward calculation and broadcast

### NPC Sit Behavior
- `ServerScriptService.NpcSit`
- Direct CFrame teleport to seat (no walk)
- R6 joint angle pose applied via Motor6D C0
- Heartbeat maintenance every 6 frames to prevent drift

### Chair Interaction (Client)
- `StarterPlayer.StarterPlayerScripts.ChairInteraction`
- DuelTablePrompt ProximityPrompt on tabletop
- Challenge/Leave GUI
- Player teleport + movement lock on trigger

### Fixes Applied During Session 1
- **NPC walk animation:** Replaced `humanoid:MoveTo()` with direct `hrp.CFrame` set
- **Standing pose after sit:** Added Heartbeat-maintained Motor6D pose
- **ProximityPrompt invisible:** Moved from PlayerSeat to DuelTable tabletop Part
- **ProximityPrompt client arg:** Removed `triggeringPlayer` check on client-side handler
- **UIListLayout SortOrder:** Set to LayoutOrder (was Name/alphabetical → wrong row order)

---

## Design Decisions Log

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Turn order | Draw → Generate → Play → Attack → End | Standard TCG flow; generate before play lets players plan spending |
| Starting hand | 5 cards | Enough options without overwhelming |
| Draw per turn | 1 card | Consistent hand replenishment |
| Attack | One optional attack per turn | Reduces complexity; strategic choice |
| Monster skills | Built into monster card | No extra deck needed; simpler for v0.1 |
| Equipment on death | Destroyed with monster | Keeps the punishment meaningful |
| v0.1 NPC deck | Fire | Most aggressive; good for testing damage/attack loop |
| Card art style | Anime/stylized (DALL-E prompts in DESIGN_CARDS.md) | Matches Roblox aesthetic + TCG genre |
| Server authority | All state server-side | Prevents cheating; clean client/server separation |
| Camera | Scriptable locked to head | Immersive first-person duel feel |
| Reward on win | +50 EXP, +25 Gold, 1 random Fire card | Low enough to feel earned, high enough to feel rewarding |

---

## TBDs Carrying Forward

| Item | Priority | Notes |
|------|----------|-------|
| Who goes first | Medium | Coin flip? Always player? Design call needed |
| Deck-out rule | Low | No loss currently; add after playtesting |
| Max hand size | Low | No cap currently; add if hand hoarding becomes issue |
| Max Equipment per monster | Low | No cap; add if needed |
| Max Field Supports | Low | No cap; add if needed |
| NPC foot pose | Active | Currently testing Z=π rotation |
| Avatar thumbnails in info widgets | Low | Placeholder box; can add `Players:GetUserThumbnailAsync` later |
