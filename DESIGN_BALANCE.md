# DESIGN_BALANCE — Elemental TCG: Balance Investigation Log

> This doc tracks balance questions that were investigated via headless simulation
> (not just designed on paper) — methodology, findings, and the design decisions
> they led to. Treat it as a reference for *how* a balance conclusion was reached,
> not just *what* was concluded, so future investigations don't repeat the same
> methodology mistakes.

---

## Investigation: First-Player Advantage in Mirror Matches (2026-06-07)

### The question
During design review of the v0.2 core rules, a concern was raised: because
summoning is free and unconditional (no cost, no requirement), does whoever acts
first in a match simply snowball an unbeatable lead? Tested via headless
simulation — two identical MIGHTY decks, controlled by symmetric greedy AI, run
many times against the **actual game modules** (`BattleLogic`/`CardData`/`NpcAI`),
not a paper mockup.

### Finding #1 — the advantage is real and large
Across two independently-run baselines (n=100 and n=50), **the first player won
83-93% of MIGHTY-mirror matches**. This reproduced consistently across separate
runs with different random samples — not noise, a real structural problem.

### Finding #2 — methodology trap: Roblox's `math.random` doesn't reseed across script executions
Early comparison tests produced suspiciously identical results across different
"fixes" (three different compensation mechanics all landing on exactly 8/2).
Diagnosis: Roblox's sandboxed `math.random` resets to the same internal state at
the start of every fresh `execute_luau` call, regardless of `math.randomseed()`.

**Fix: never compare results from separate script executions.** Run every variant
you want to compare *sequentially within ONE execution*, via a shared
`runBatch(n, opts)` helper, so they draw from a single continuously-advancing
random sequence. All results below follow this rule.

### Finding #3 — compensation mechanics tested (n=50 each, single execution)

| Mechanic | 2nd-player win rate | Verdict |
|---|---|---|
| Baseline (no fix) | ~7-17% | confirms Finding #1 |
| Extra card draw on 2nd player's 1st turn | 26% | helps, but the weakest of the real levers |
| Flat +1 energy on 2nd player's 1st turn | 26% (functionally inert — see below) | **don't use** |
| Instant energy from 2nd player's 1st summon ("Second Wind") | 32% | strongest single lever |
| "Cannot attack / play Trainer on Turn 1" restriction alone | 18% | barely better than baseline |
| "Summon only on Turn 1" restriction alone | 18% (identical, run-for-run, to the row above) | functionally the same rule — see note |
| Restriction + extra card | 22% | extra card consistently the weak link |
| **Restriction + Second Wind (the combo we shipped)** | **36-38%** | best combo found; ~62-64% 1st-player win rate remains |

**Why flat "+1 energy" does nothing:** both sides start every match at 0 energy
(monsters only generate starting the turn *after* they're summoned). The instant
the 2nd player would receive a flat energy bonus — their first turn — is also the
turn they're forced to make their first, mandatory summon: they have no monster on
board yet to spend energy on. By the time they *do* have a skill-capable monster,
their own board has already generated equivalent energy naturally, and the +1 sits
unused. **"Second Wind" (granting the *summoned monster's own* generation amount
immediately) avoids this trap** — it scales with whatever's actually summoned and
is never wasted.

**Note on the "18% / 18%" exact match:** "cannot attack/play Trainer" and "summon
only" produced *literally identical* results because the AI never exercises the
marginal extra permission ("cannot attack" technically still allows equipping —
but the AI never has equipment in an opening hand in practice). They're the same
rule in effect; pick whichever phrasing reads clearer to players.

**The more important lesson came from a second coincidence:** two
*functionally-identical* rulesets (run in separate executions) landed 28% vs 38%
apart — a 10-point spread from sampling noise alone. **At n=50, expect up to
~±10 percentage points of noise.** Don't trust any comparison narrower than that
without a much larger sample (n≈150-200+ per variant).

### Decision: implemented combo
**"Turn 1 = summon only" + "Second Wind"** (instant energy from the 2nd player's
first summoned monster) — see `DESIGN_BATTLE.md` → "Opening Turn Rules".
Implemented server-side directly in `BattleLogic` (`summonMonster` /
`useSkill` / `playTrainer` / `attachEquipment`), so it applies uniformly to the
human player and the NPC with no client bypass possible.

**Result: first-player win rate drops from ~83-93% to ~62-64%.**

This does **not** reach 50/50 parity — that's a known, accepted gap (see caveats
below for why closing it further may not even be the right goal).

### Important caveat: AI-mirror simulation likely *overstates* the real-world gap
The simulation pits two copies of the *same deterministic, mistake-free* greedy
AI against each other. Neither side ever misplays, miscounts a board state, or
lets an advantage slip — which is exactly the mechanism that lets a human player
behind on board state claw back into a game. A flawless mirror match has **zero
comeback potential by construction**: whoever acts first simply executes their
fixed routine one cycle ahead, forever, because the trailing side can never
capitalize on a mistake the leading side never makes.

Real human-vs-human (or human-vs-NPC) play includes the variance that *creates*
comebacks, so it should show a meaningfully **smaller** gap than 83-93% / 62-64%.
**Treat these numbers as a structural ceiling — a worst case — not a prediction
of the live experience.**

### Follow-ups / open items
- [ ] **Turn order is currently hardcoded to "player always first"**
      (`BattleController.lua` seats the player as turn 1 unconditionally). The new
      Opening Turn Rules assume a *randomized* first/second assignment (as
      tested) — under the current hardcoded order, the rules run **backwards**:
      the human player always gets the Turn-1 restriction, and the NPC always
      gets Second Wind. This needs to be resolved (the long-standing "turn order"
      TBD in `DESIGN_BATTLE.md`) before the fix actually benefits anyone, and
      certainly before PvP.
- [ ] Re-test once the card pool grows toward ~120 cards — these numbers are
      based on the current ~30-card MIGHTY-only mirror and may shift with a
      larger, better-tuned pool.
- [ ] Don't chase a finer ranking between "Restriction + Second Wind" (36-38%)
      and any future tweak via n=50 sims — you'll be measuring noise. n≈150-200
      per variant is the minimum for that kind of comparison.
- [ ] Worth asking: is ~62% first-player win rate actually a problem? Several
      established TCGs (Magic, Hearthstone) ship with comparable first-move
      advantages and treat it as a tolerable asymmetry — not something to
      eliminate outright. Combined with the AI-mirror-overstatement caveat above,
      the *live* gap may already be acceptable.

---

## Methodology Reference: Headless Battle Simulation

For future balance investigations, the pattern that worked:

1. Require the **actual game modules** — `CardData`, `BattleLogic`, `NpcAI` — via
   `execute_luau` with `datamodel_type="Server"` (only available in Play mode;
   restart Play mode with `start_stop_play({is_start=true})` whenever you hit
   "Server datamodel is not available in Edit mode" — it stops unpredictably
   between tool calls).
2. Build a **symmetric AI driver** that mirrors `NpcAI`'s greedy heuristics for
   both sides — needed for fair mirror-match testing, since `NpcAI` itself is
   hardcoded to only ever play the `"npc"` side.
3. **Run every variant you want to compare inside ONE script execution**, in
   sequence, via a shared `runBatch(n, opts)` helper. Never compare numbers
   pulled from separate `execute_luau` calls (see Finding #2).
4. At n=50 per variant, expect noise of roughly ±10 percentage points — don't
   draw conclusions from gaps smaller than that; bump to n≈150-200 if you need
   to distinguish close variants.
5. When something looks "too clean" (e.g. identical results across different
   fixes), don't trust it — diagnose it. That instinct caught the
   `math.random` reseed bug in this investigation before it produced a wrong
   conclusion.

---

## Investigation: v0.4 Cross-Archetype Balance + AI Bias Audit (2026-06-09)

### Context
v0.4 is a full rules rewrite (universal Energy, 3-slot board, direct face damage, monster/action card dichotomy, Invoker passive tallies). Three archetypes: MIGHTY (armor/removal), SWIFT (draw/combo), VITAL (healing/siphon). First 90-game sim run produced suspicious results. This investigation documents both a methodology failure and the corrected findings.

### Harness bug: shuffle not called
The sim harness (`runGame`) was not calling `Logic.shuffle()` before dealing initial hands, meaning every game played an identical card sequence. `BattleController` calls `Logic.shuffle(state.player.deck)` and `Logic.shuffle(state.npc.deck)` at lines 125–126 post-`newBattle`. **Rule: always mirror `BattleController`'s setup steps exactly in any sim harness.** Added shuffle calls; results below are all post-fix.

### AI bias: NpcAI systematically favored MIGHTY

Three bugs caused the AI to play MIGHTY well and VITAL/SWIFT poorly:

**Bug 1 — heal scoring at full health.** `scoreAction` for `restore_health` used `score = 18 + math.min(missing, value) * 2`. When `missing = 0`, score remained at 18 (non-zero baseline). The AI would cast healing cards on a full-health hero rather than hold them. VITAL's kit is entirely based on timing heals correctly — wasted heals = VITAL performing as a weaker MIGHTY.

**Bug 2 — `buff_friendly_minion` unscored.** Iron Warmaul (`+3/+2 to a friendly minion`) and Titan's Warplate (`+5/+2`) had no `scoreAction` handler, falling through to the default `else` branch. Score stayed at 18 regardless of board state. The AI played equip cards into an empty board, wasting them completely.

**Bug 3 — structural ordering bias.** The play loop always tried `bestAffordableMonsterInHand` first, only considering actions if no monster could be summoned. MIGHTY's optimal play is exactly "develop the board, use removal/burn when nothing to summon" — the AI accidentally matched MIGHTY's strategy perfectly. VITAL's timing-sensitive heals and SWIFT's combo sequencing were always deprioritized.

### Fixes applied

- `restore_health`: if `effectiveMissing <= 0` (checking both hero and most-damaged minion for multi-target variants), score `-35` instead of a positive bonus.
- `buff_friendly_minion`: explicit handler scoring `(atk*3 + hp*2)` plus -20 penalty for empty board.
- Unified candidate pool: replaced the two-branch loop with a single scored pool per iteration. Added `scoreMonster(card)` on the same numeric scale as `scoreAction`. Each turn the AI now plays whatever scores highest — archetype strategy emerges from scoring, not hard-coded ordering.

### Results (n=15 per matchup per seat, 90 games total)

#### Pre-fix (broken AI):
| Archetype | Win rate |
|---|---|
| SWIFT | 53.3% |
| MIGHTY | 51.7% |
| VITAL | 45.0% |

#### Post-fix (corrected AI):
| Archetype | Win rate |
|---|---|
| **VITAL** | **61.7%** (37W/23L) |
| MIGHTY | 46.7% (28W/32L) |
| SWIFT | 41.7% (25W/35L) |

#### Cross-matchup detail (post-fix, player seat = first named, n=15):

| Matchup | First-seat win% | Notes |
|---|---|---|
| MIGHTY vs SWIFT | 73.3% | |
| MIGHTY vs VITAL | 60% | |
| SWIFT vs MIGHTY | 80% | Extreme first-mover flip |
| SWIFT vs VITAL | 46.7% | SWIFT can't push through healing |
| VITAL vs MIGHTY | 66.7% | |
| VITAL vs SWIFT | 86.7% | VITAL dominates SWIFT |

#### Mirrors:
| Archetype | First wins | Second wins | Notes |
|---|---|---|---|
| MIGHTY | 12 | 3 | 80% first-mover — broken |
| SWIFT | 12 | 3 | 80% first-mover — broken |
| VITAL | 8 | 7 | 53% — healthy |

### Adjusted for random seating
Taking each matchup as played equally from both seats:
- **VITAL vs SWIFT: ~70% VITAL edge** — the most egregious imbalance
- **VITAL vs MIGHTY: ~53% VITAL edge** — moderate
- **MIGHTY vs SWIFT: ~47% MIGHTY edge** — SWIFT is actually slightly worse than MIGHTY

### Findings

**VITAL is dominant.** The broken-AI results showing MIGHTY on top were entirely an artifact. With fair play, VITAL's healing + conditional removal (Husk Reclaimer destroys damaged, Domination Rite takes control of damaged) is very hard to run through. VITAL's win rate from first seat vs SWIFT (86.7%) is the single worst number in the table.

**SWIFT is the weakest archetype.** Root causes:
1. No identity minions — SWIFT's 7 action cards produce zero board presence. Its board is 100% the neutral pool, which every other deck also runs.
2. All SWIFT damage targets minions or splits randomly — no reliable face pressure to race VITAL's healing.
3. Combo payoffs (Calculated Strike: 4 damage, Coordinated Strike: 6 split) are too small to close games against 30-HP heroes.
4. Smoke Bomb (grant stealth to friendly) is nearly useless — protecting a minion from targeting effects doesn't matter when VITAL's removal conditionally targets *damaged* minions and MIGHTY's Execute conditionally targets *damaged* minions. Stealth doesn't prevent combat damage.

**MIGHTY is roughly correct** after the Session 10 nerfs (Reckless Brute atk 4→3, Bastion Defender hp/armor, Shield Wall cost/value rebalance). Its ~46.7% overall is acceptable given the first-mover issue inflates SWIFT's numbers slightly against it.

**First-mover advantage in mirrors is structurally broken for MIGHTY and SWIFT.** The Coin mechanic (+1 energy turn 1 for the second player) is not sufficient to offset snowball. VITAL's mirror is healthy (8–7) because healing from behind is a real comeback mechanism. MIGHTY and SWIFT have no equivalent.

### Open design questions
- [ ] SWIFT redesign: add identity minions (likely 1–2 low-cost SWIFT monsters with combo payoffs). SWIFT currently has a full deck of spells played into neutral bodies — it reads more like a control deck without the removal suite.
- [ ] SWIFT damage: either increase base values or add at least one direct face-damage action to threaten a clock against healing decks.
- [ ] Smoke Bomb: evaluate whether stealth as a SWIFT keyword serves any real purpose with the current card pool.
- [ ] VITAL tuning: the 61.7% win rate suggests either too much healing or too-easy removal condition (damaged = any minion that's been hit once). Worth testing if Execute/Domination Rite/Husk Reclaimer's "damaged" condition is the lever.
- [ ] First-mover mirror fix: MIGHTY and SWIFT mirrors need a structural answer. Current Coin is too weak. Options: larger Coin, second player draws an extra card, or matchup-specific adjustment.
- [ ] Re-sim after any SWIFT or VITAL changes — use the corrected harness (shuffle + unified AI).
