# PLAN — Alpha Build: Card Rework → Playtest

> Executable, phased build plan to take the new card system from data restructure
> to a playable, sim-able alpha. Architecture rationale lives in
> [DESIGN_ENGINE.md](DESIGN_ENGINE.md); card schema in
> [DESIGN_DATABASE.md](DESIGN_DATABASE.md); card list in
> [DESIGN_CARDS.md](DESIGN_CARDS.md).
>
> **How to use:** work phases in order; each has an Acceptance gate that must pass
> before the next. Check boxes as you go. The [Implementation Inventory](#appendix--implementation-inventory)
> is the master checklist of every trigger/action/condition/keyword the four alpha
> packs require — nothing ships until all of it is covered and tested.

**Status:** ✅ **ALL PHASES COMPLETE — alpha is playable & sim-able.** Engine rebuilt on the effects[] system; 90-card DB + 3 decks; 120-game headless sim runs clean; in-Studio play-mode smoke test passes (hand + board render, play/attack/turn/NPC loop, Coin, no errors). Old `CardData` removed. See per-phase notes below. Remaining = balance tuning (separate from the build).

> **Testing note:** the MCP Studio session persists `require` cache across `execute_luau` calls — after editing a module, tests must require a **fresh clone** of the `Effects` folder, else stale code runs. (Production/play-mode requires fresh, so this only affects the Edit-mode test harness.)

**Scope guardrails:** Invoker cut · `lifesteal` canonical (Siphon retired) ·
`quickstrike` = attacker-only first-strike · `rebirth` = resummon once full ·
combat/energy/fatigue/Coin unchanged · 4 packs replace old 32 cards · decks from
`deck_starter.json`.

---

## Phase 0 — Prep & doc reconciliation

**Goal:** remove contradictions so the build targets one truth.

- [x] Update `DESIGN_CORE.md`: remove the Invoker section; rename Siphon→lifesteal; `monster`/`action` → `creature`/`spell`; add `quickstrike`/`rebirth`/`lifesteal` to the keyword table; reconcile the keyword list with the four packs.
- [x] Decide deck size: adopted **variable for now** (use starter decks as-is; normalize when the deck model lands). Documented in DESIGN_CORE.
- [x] Confirm RemoteEvent target payload shape (see Phase 6): `PlayCard(cardId, target)` where `target = { side, slot }`, `slot=0` means hero.

**Acceptance:** DESIGN_CORE no longer mentions Invoker/Siphon/monster/action; deck size is consistent and documented.
**Depends on:** none.

---

## Phase 1 — Card data restructure & definitions

**Goal:** the four packs become the single runtime source, validated.

- [x] Create `ReplicatedStorage/Definitions/` (Folder).
- [x] Author `Definitions/Cards.lua` — one id-keyed Lua map of all **90** unique cards (ruby_bear 24, emerald_cat 24, sapphire_frog 24, stonebark 18), translated faithfully from the pack JSON (effects[] arrays, keywords, race, rarity, pack).
- [x] Author `Definitions/Decks.lua` — the three starter decks from `deck_starter.json` (expand `{id,count}` into id lists). Sizes: mighty 36, swift 37, vital 34.
- [x] Write `ReplicatedStorage/Modules/CardSchema.lua` — validate on require: required fields present; `cardType`∈{creature,spell}; every `effects[].trigger`∈known set; every `effects[].action`∈known set; every `target`/`condition.type`∈known set; every `summon.cardId` and every deck id resolves to a card.
- [x] Run the validator headlessly; fix any data errors; log per-deck card counts.

**Acceptance:** ✅ `require(Cards)`=90 cards; `CardSchema.validate`=cards_valid + decks_valid both true, zero errors.
**Depends on:** Phase 0 (deck size).
**Files:** `Definitions/Cards.lua`, `Definitions/Decks.lua`, `Modules/CardSchema.lua`.

---

## Phase 2 — Effects framework (plumbing, no behaviors yet)

**Goal:** the data-driven skeleton that everything plugs into.

- [x] `Effects/Conditions.lua` — `Conditions[type](ctx) -> bool` for all 6: `damaged`, `target_undamaged`, `attack_gte`, `attack_lte`, `friendly_damaged_exists`, `chain`.
- [x] `Effects/Targeting.lua` — `resolveTargets(ctx, entry) -> {targets}` for every `target` + `area` combo. Player-chosen via `ctx.chosenTarget`; server-resolved for `random_*`/`all_*`/`self`/`own_hero`/`area:all/split`.
- [x] `Effects/Triggers.lua` — `fireEvent(state, event, ctx)` + `runCard`: iterate `effects[]`, match `trigger`, resolve targets, check `condition`, dispatch `Actions[entry.action]`. Events `emerge`/`cast`/`shatter`/`attacked`/`turn_end`/`ally_death`; `chain` fires on emerge/cast when active.
- [x] `Effects/Actions.lua` — registry + `ctx` contract (`Logic` injected to avoid circular require); stub handlers + `_default`.
- [x] `Effects/Util.lua` — shared helpers incl. `valueOf(ctx, entry)` (`value` / `valueFrom`).

**Acceptance:** ✅ framework loads; trigger bus dispatches; targeting + conditions correct — **24/24 headless unit tests pass** (incl. chain gating as both trigger and condition).
**Depends on:** Phase 1.
**Files:** `ServerScriptService/Modules/Effects/{Conditions,Targeting,Triggers,Actions}.lua`.

---

## Phase 3 — Action implementations (spells & effects)

**Goal:** every action verb in the alpha set works; every spell resolves.

- [x] `damage` — `single` / `area:all` / `area:split`; honor `lifesteal=true`; support `valueFrom`.
- [x] `heal` — `own_hero` / `friendly_creature` / `all_friendly` (= hero + all friendly creatures).
- [x] `buff` — `atk`/`hp`, targets `self`/`friendly_creature`/`random_friendly`, `area:all`; permanent.
- [x] `draw_card` — `value`, optional `filter:{race}`.
- [x] `destroy` — plain + `condition` (`damaged`/`attack_gte`/`attack_lte`).
- [x] `grant_keyword` — `taunt`/`quickstrike`/`lifesteal`/`rebirth`; `friendly_creature` or `area:all`.
- [x] `summon` — `cardId` × `count` into empty slots.
- [x] `bounce` — return a creature to its owner's hand (`random_enemy`).
- [x] `return_from_graveyard` — random card from your discard → hand.
- [x] `reduce_cost` / `set_cost` — full cost system implemented in `Ops` (`addCostMod`/`effectiveCost`/`clearTurnCostMods`).
- [x] Built `Effects/Ops.lua` — the game-op layer (damage/heal/buff/draw/destroy/kill+rebirth/bounce/summon/graveyard/cost) that Actions call via `ctx.Logic`.

**Acceptance:** ✅ 17/17 — full 90-card event sweep (0 errors/unhandled) + targeted asserts (damage, split+lifesteal, AoE, heal, destroy-conditions, summon, rebirth, all 3 cost patterns).
**Depends on:** Phase 2.
**Files:** `Effects/Actions.lua` (+ helpers).

---

## Phase 4 — Keyword & cost mechanics

**Goal:** the cross-cutting mechanics behind keywords and cost manipulation.

- [x] Keyword helpers centralized in `Ops` (`hasKeyword`/`addKeyword`/`removeKeyword`). `taunt`/`charge`/`stealth` **combat** semantics reimplemented in Phase 5's combat rewrite.
- [x] `quickstrike` — implemented in BattleLogic combat (Phase 5): attacker deals first; no retaliation if the defender dies.
- [x] `lifesteal` — single hook in `Ops.damageHero`/`damageCreature`: source hero heals for damage dealt; covers the keyword (combat, Phase 5) and `damage` `lifesteal=true` (effects, tested ✅).
- [x] `rebirth` — `Ops.killCreature`: if `not rebornUsed`, restore full stats in place once, consume the keyword; else die. Shatter fires on the triggering death. Tested ✅.
- [x] Cost system in `Ops` — `addCostMod`/`effectiveCost`/`clearTurnCostMods` over `hand`/`drawn_cards`/`returned_card` with `this_turn` duration. Tested ✅ (all 3 patterns).

**Acceptance:** ✅ lifesteal, rebirth, and all cost patterns proven in the Phase 3 suite. Only `quickstrike` remains — implemented with combat in Phase 5.
**Depends on:** Phase 3. (Mechanics live in `Effects/Ops`, not separate Keywords/Costs modules.)

---

## Phase 5 — BattleLogic port (turn flow + combat + triggers)

**Goal:** the engine runs the new system end-to-end, server-side.

- [x] Card instance: deep-copy `effects` + `keywords` on summon; add `rebornUsed`. Remove `invoker`, `discounts`, `usedComboExtraAttackThisTurn` from state/instance.
- [x] Rewrite `playCard`: compute effective cost (Costs), spend energy, place creature / resolve spell by firing `emerge`/`cast` over its `effects[]`; tally `cardsPlayedThisTurn`; validate chosen target.
- [x] Rewrite `attack`: keep Taunt/Stealth gating + simultaneous combat; integrate `quickstrike` (first-strike) and `lifesteal`.
- [x] Wire trigger bus into engine events: summon→`emerge`(+`chain`), death→`shatter`→`rebirth`→`ally_death`, target declared→`attacked`, turn end→`turn_end`.
- [x] Keep unchanged: energy ramp 0→10, draw, fatigue, hand cap 10, Coin.
- [x] Delete the Invoker helpers and the old dual if/elseif dispatch + 22 dead branches (see Cut list).

**Acceptance:** ✅ 5 scripted full games ran start→win, **zero errors / zero unhandled**, correct win detection. (BattleLogic rebuilt on Ops+Triggers; Invoker/discounts/combo-extra-attack removed; the_coin + gain_energy added.)
**Depends on:** Phase 4.
**Files:** `ServerScriptService/Modules/BattleLogic.lua`, `BattleController.lua`.

---

## Phase 6 — Presentation (CardText + Battle UI)

**Goal:** cards render and are playable by a human in Studio.

- [x] `Modules/CardText.lua` — build ability text from `effects[]` + trigger labels (Emerge / Shatter / Chain / Turn End / Attacked) + keyword labels; drop the old in-data EFFECT_TEXT and its 22 dead renderers.
- [x] Extend `PlayCard` RemoteEvent payload to a target descriptor `{side, slot}` (`slot=0` = hero) so player-chosen targets (`enemy_creature`/`friendly_creature`/`enemy_target`) reach the server; server re-validates.
- [x] `TargetingSystem`: highlight valid drop targets per the card's `effects[].target` (enemy creature / friendly creature / enemy area incl. hero / no-target); send the descriptor.
- [x] Keyword visuals: add `quickstrike`, `lifesteal`, `rebirth` indicators; keep taunt/stealth/charge.
- [x] Render board/hand/stat cluster from the new schema; remove the Invoker UI panel.

**Acceptance:** ✅ in-Studio smoke test — hand + board (player & enemy creatures w/ stats, summoning-sickness indicator) render from `effects[]`, ability text via `CardText`, Coin shows, Invoker panel hidden, no console errors. Targeting rewired to `effects[]` + `{slot,target}` payload (drag logic adapted; verified via scripted plays per agreed method).
**Two bugs found & fixed during smoke test:** (1) an Invoker-hide edit accidentally hid the board *slot* cells — removed; (2) sparse board arrays (`{[2]=inst}`, leading nil) don't survive RemoteEvent — `BattleController.broadcast` now sends a dense 3-slot board (`false` for empty); client `if not m` treats `false` as empty.
**Depends on:** Phase 5.
**Files:** `Modules/CardText` (new), `CardVisuals`, `TargetingSystem`, `BattleUIController`, `GraveLogPanel`.

---

## Phase 7 — NpcAI rework

**Goal:** the NPC plays the new cards competently.

- [x] Rescore plays against the action vocabulary: value board impact (atk+hp), removal (`destroy`), tempo/`damage`, `heal` (only when hurt), `draw_card`, `buff` (only with a target), bounce/cost/recursion utility.
- [x] AI target selection for player-choice targets (best removal/buff target).
- [x] Sequence cheap cards before `chain` payoffs where it helps.
- [x] Remove all Invoker-aware scoring.

**Acceptance:** ✅ rewritten as `takeTurn(state, Logic, who)` scoring the new action vocab + picking targets; drove 120 sim games with zero errors and sensible play.
**Depends on:** Phase 5.
**Files:** `ServerScriptService/Modules/NpcAI.lua`.

---

## Phase 8 — Integration, balance sim & playtest

**Goal:** a complete, playable, measured alpha.

- [x] `BattleController`: load starter decks from `Definitions/Decks.lua`; sanitized state snapshot carries what the UI needs (effects[] for tooltips); rewards/DataStore intact.
- [x] Headless balance sim per DESIGN_BALANCE methodology (symmetric AI driver, `shuffle` both decks, one batch per run); capture per-matchup win rates.
- [x] Manual playtest in Studio: MIGHTY vs VITAL first (healing-wall check), then SWIFT.
- [x] Triage: log VITAL dominance / MIGHTY control-shape findings against DESIGN_CARDS open issues.

**Acceptance:** ✅ play-mode smoke test (duel starts, cards play, turns cycle, NPC responds, no errors) + balance sim table below.

**Balance sim (n=40/matchup, symmetric NpcAI):** MIGHTY **71%**, SWIFT **55%**, VITAL **24%**. MIGHTY vs VITAL 35–5. VITAL is far too weak under the current AI/decks (the opposite of the old build's VITAL dominance) — naive face-racing AI doesn't pilot sustain, and MIGHTY's armor+removal+bodies snowball. **Balance tuning (cards + AI sophistication) is the next work item, separate from this build.**
**Depends on:** Phases 6 + 7.
**Files:** `ServerScriptService/BattleController.lua`.

---

## Cross-cutting: Cut list

- [x] Invoker: `invokerBonus`, `tallyInvoker`, `siphonAmount`, `mightyDamageBonus`, `applyDestroyInvokerBonus`, armor/destroy Invoker bonuses, Invoker UI panel, `InvokerThresholds` data.
- [x] `combo_extra_attack` passive + `usedComboExtraAttackThisTurn`.
- [x] Old `CardData` 32 cards + in-module `EFFECT_TEXT` (22 dead renderers).
- [x] `discounts` list (replaced by Costs); `stealth_until_attack` (fold into `stealth`).
- [ ] Orphaned `UseSkill` RemoteEvent; `[ATTACK]` debug prints.

---

## Appendix — Implementation Inventory

The exact surface the four alpha packs require. Every item must be implemented and
covered by a test before Phase 8.

**Triggers:** `emerge`, `shatter`, `chain`, `turn_end`, `attacked`, `cast`.
*(Unused in alpha, do not build: `resonance`, `deal_damage`, `ally_death` trigger —
note `lifesteal` uses an internal deal-damage hook, not the trigger.)*

**Actions → cards that exercise them (test cases):**
| Action | Variants | Example cards |
|---|---|---|
| `damage` | single | ruby_slam, pouncing_strike, emberclaw_bear, crystal_bolt, leech_life, quick_step |
| `damage` | `area:all` | mountain_roar, last_stand, ambush, spirit_harvest |
| `damage` | `area:split` | memory_fragment, essence_tide |
| `damage` | `lifesteal=true` | memory_fragment, spirit_harvest, essence_tide |
| `damage` | `valueFrom` | essence_tide (`drawn_card_cost`) |
| `heal` | own_hero / friendly_creature / all_friendly | moonpool_ritual / spirit_touch / sapphire_waters, dewcaller_frog |
| `buff` | self / friendly / random_friendly / `area:all` | ancient_ruby_bear / ironfur_training / cragfur_bear / war_banner, predators_assault |
| `draw_card` | plain / `filter:race` | bear_lore / rally_the_clan, hunting_instinct, pack_tactics |
| `destroy` | plain / damaged / attack_gte / attack_lte | emerald_dagger / crushing_blow / avalanche / spirit_crush |
| `grant_keyword` | taunt / quickstrike / lifesteal / rebirth(`area:all`) | barkskin_blessing / cat_reflexes / spirit_bloom, ancient_staff / eternal_rebirth |
| `summon` | cardId×count | elder_treant |
| `bounce` | random_enemy | crystal_sabercat, shadow_smoke |
| `return_from_graveyard` | random | sapphire_elder, grave_call |
| `reduce_cost` | hand / drawn_cards | emerald_huntmaster / ancient_archive |
| `set_cost` | drawn_cards / returned_card | rally_the_clan, pack_tactics / grave_call |

**Conditions:** `damaged`, `target_undamaged`, `attack_gte`, `attack_lte`, `friendly_damaged_exists`, `chain`.

**Targets:** `enemy_creature`, `friendly_creature`, `any_creature`, `enemy_target` (creature or enemy hero), `self`, `own_hero`, `random_friendly`, `random_enemy`, `all_friendly`. **Areas:** `single`, `all`, `split`. **Cost pools:** `hand`, `drawn_cards`, `returned_card`.

**Keywords:** `taunt`, `charge`, `stealth` (port) · `quickstrike` (first-strike, attacker-only) · `lifesteal` (heal source hero for damage dealt) · `rebirth` (resummon full once).
