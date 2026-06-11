# DESIGN_BALANCE — Elemental TCG: Balance Reference

## Simulation Methodology

All balance work uses headless simulation against the **actual game modules** (CardData, BattleLogic, NpcAI), not a paper model.

**Rules — follow exactly or results are invalid:**

1. Load modules via `execute_luau` with `datamodel_type="Server"`. Play mode must be running — restart with `start_stop_play({is_start=true})` if you hit "Server datamodel not available."
2. Use a symmetric AI driver mirroring NpcAI heuristics for both sides (NpcAI itself is hardcoded to play the `"npc"` side only).
3. **Run all variants inside ONE script execution** via a shared `runBatch(n, opts)` helper. Never compare results from separate `execute_luau` calls — Roblox's `math.random` resets to the same state at each fresh execution, making cross-call comparisons invalid.
4. **Always call `Logic.shuffle()` on both decks** before dealing initial hands. Matches what BattleController does at game start. Skipping it means every game plays an identical card sequence.
5. At n=50, expect ~±10 percentage points of noise. Never draw conclusions from gaps smaller than that. Use n=150–200 to distinguish close variants.

---

## Current Balance State

### Setup
- 90-game sim, n=15 per matchup per seat
- Post AI-bias fix (see AI Bias section below)
- Three archetypes: MIGHTY, SWIFT, VITAL
- **Note:** Overall win rates and cross-matchup table predate the MIGHTY card changes (Bonk Bear/Grumpy Bear Taunt redistribution, Chubby Bear Taunt removal, Wandering Blade → 2/3 Charge, buff item nerfs). Re-sim required for updated cross-matchup data.

### Overall Win Rates

| Archetype | Win Rate |
|---|---|
| VITAL | **61.7%** — dominant |
| MIGHTY | 46.7% |
| SWIFT | 41.7% — weakest |

### Cross-Matchup Detail (first-named = first seat)

| Matchup | First-seat win% |
|---|---|
| MIGHTY vs SWIFT | 73.3% |
| MIGHTY vs VITAL | 60.0% |
| SWIFT vs MIGHTY | 80.0% |
| SWIFT vs VITAL | 46.7% |
| VITAL vs MIGHTY | 66.7% |
| VITAL vs SWIFT | 86.7% |

### Mirror First-Mover Advantage

| Archetype | First-seat wins | Second-seat wins | n | Notes |
|---|---|---|---|---|
| MIGHTY | 22 — 44% | 28 — 56% | 50 | Within 50/50 noise — first-seat advantage eliminated |
| SWIFT | 12/15 — 80% | 3/15 | 15 | Predates card changes; needs re-sim |
| VITAL | 8/15 — 53% | 7/15 | 15 | Healthy |

### Root Cause Analysis

**VITAL is dominant** because:
- Healing + Siphon Invoker compounding is difficult to race through
- VITAL mirror is healthy (53%), suggesting the issue is matchup-specific, not raw stats
- The `damaged`-condition removal was removed (Husk Reclaimer, Domination Rite) — verify via re-sim after CardData is updated

**SWIFT is the weakest** because:
- Zero identity monsters — board is 100% neutral pool, shared by every deck
- No reliable face damage to race VITAL's healing
- Combo payoffs too small to close games against 30 HP heroes
- Hide and Sneak (Stealth) nearly useless — current removal pool is condition-based, not targeted-targeted

**First-mover advantage in SWIFT mirror is broken** because:
- VITAL's healing from behind is a real comeback mechanism; MIGHTY and SWIFT have no equivalent
- The Coin (+1 Energy turn 1) is confirmed insufficient as the only offset
- **MIGHTY mirror is now resolved** — Taunt redistribution (Bonk Bear 2/2 Taunt, Grumpy Bear 3/5 Taunt) brought first-seat wins to ~44% (n=50, within 50/50 noise)

### Open Questions

- Re-sim after SWIFT cat minions are added — this is the primary structural fix and will shift the entire table
- Re-sim after VITAL CardData changes land (Spirit Recall + Guardian Spirit replacing Husk Reclaimer + Domination Rite)
- If VITAL remains dominant post-changes, the Siphon Invoker thresholds (particularly tier 6 "destroy ally heals 2") are the next lever
- SWIFT mirror first-mover advantage still unresolved — test after cat minions are added

---

## AI Bias Reference

The NpcAI had three bugs that made MIGHTY look stronger than it was before the balance fixes. Documented here so future investigations don't repeat them.

**Bug 1 — heal scoring at full health:** `scoreAction` for `restore_health` used `score = 18 + math.min(missing, value) * 2`. When `missing = 0`, score stayed at 18 (positive). AI would cast heals on a full-health hero. Fix: if `effectiveMissing <= 0`, score `-35` instead.

**Bug 2 — `buff_friendly_minion` unscored:** Iron Warmaul / Titan's Warplate had no handler, fell through to `else` at score 18 regardless of board state. AI played equips into an empty board. Fix: explicit handler scoring `(atk*3 + hp*2)` minus 20 penalty if board is empty.

**Bug 3 — structural ordering bias:** Play loop tried `bestAffordableMonsterInHand` first, only fell through to actions if no monster was available. MIGHTY's greedy curve play exactly matched this ordering. Fix: unified candidate pool — all affordable monsters and actions scored on the same scale each iteration, highest score wins.
