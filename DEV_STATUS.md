# DEV_STATUS — Elemental TCG: Implementation State

> Last updated: 2026-06-12

---

## Module Status

| Module | Location | Status |
|---|---|---|
| CardData | `ReplicatedStorage.Modules.CardData` | ✅ Complete |
| BattleLogic | `ServerScriptService.Modules.BattleLogic` | ✅ Complete |
| NpcAI | `ServerScriptService.Modules.NpcAI` | ✅ Complete |
| BattleController | `ServerScriptService.BattleController` | ✅ Complete (v0.4) — includes coin flip random seat; turn/end-battle coroutines are identity-checked so a stale callback from a previous battle is ignored |
| BattleUI + BattleUIController | `StarterGui.BattleUI` | ✅ Complete (v0.5) — hand cards and monster attacks both use press-and-drag targeting with highlighted drop zones (see [IDEA_CARD_BATTLE.md](IDEA_CARD_BATTLE.md)); `UpdateBattleState` always re-hides any leftover Post-Battle overlay |
| NpcSit | `ServerScriptService.NpcSit` | ✅ Complete |
| ChairInteraction | `StarterPlayer.StarterPlayerScripts.ChairInteraction` | ✅ Complete |

**The game is playable for manual testing.** All modules implement the current ruleset (universal Energy, 3-slot board, direct face attacks, Invoker system). Player starts as MIGHTY vs VITAL NPC. See open issues below for remaining gaps.

---

## CardData — Detail

- 32 unique cards: 9 neutral + 8 MIGHTY (3 monsters, 5 actions) + 7 SWIFT (0 monsters, 7 actions) + 8 VITAL (4 monsters, 4 actions)
- 3 starter decks: MIGHTY (30), SWIFT (30), VITAL (30)
- `InvokerThresholds` for all 3 archetypes at tiers 3/6/9

All locked card changes applied: new MIGHTY IDs (bonk_bear, chubby_bear, grumpy_bear, etc.), VITAL's Guardian Spirit and Spirit Recall, wandering_blade ID fixed, Double Swipe implemented as 2 hits of 2. Verified via headless sim: all 3 decks are exactly 30 cards, all IDs resolve.

---

## BattleLogic — Detail

Full rules engine implementing:
- Universal Energy ramp, Coin, Fatigue
- `playCard` — monster summons (requires explicit slot 1–3) and action casts, Invoker tally, trigger dispatch
- `attack` — Hearthstone-style direct face attacks, Taunt/Stealth gating; full retaliation damage is always applied to the attacker, even if it is lethal (mutual destruction is possible)
- `startTurn` / `endTurn` — energy ramp, temp keyword expiry, attackedThisTurn + summonedThisTurn reset
- **Summoning Sickness** — monsters set `summonedThisTurn = true` on summon; cleared by `startTurn`; monsters with the `charge` keyword are exempt (`summonedThisTurn = false` on summon)
- All monster trigger types: `gain_armor`, `scry_draw`, `damage`, `destroy`, `take_control`, `restore_health`, `bounce`, `steal_card_copy`, `gain_keyword_on_combo`, `buff_self_on_trigger`, `armor_scaling_atk`, `combo_extra_attack`, and others
- All action effect types: `gain_armor`, `buff_friendly_minion`, `damage`, `damage_random_split` (supports `hits`/`hitSize`/`includeFace`/`minionOnly`), `damage_then_combo_draw`, `damage_and_heal_hero`, `bounce`, `draw_card`, `grant_keyword`, `restore_health`, `take_control`, `destroy`, `destroy_then_combo_copy`, `return_dead_ally_to_hand`, and others
- Invoker helpers: `tallyInvoker`, `invokerBonus`, `mightyDamageBonus`, `applyDestroyInvokerBonus`
- Archetype mechanic helpers: `comboActive`, `comboScaledValue`, `siphonAmount`

---

## NpcAI — Detail

Architecture:
- **Phase 1 — unified card-play loop:** Single candidate pool of all affordable monsters (if slot open) and actions, scored via `scoreMonster` and `scoreAction`. `noisyPick` selects with DEFAULT_NOISE=0.35 jitter. Loops until nothing scores above threshold or budget is exhausted.
- **Phase 2 — attack phase:** Every non-exhausted attacker picks a target via `chooseAttackTarget` (lethal > clean kill > even trade > safe poke > face).

Known limitation: AI does not explicitly sequence cards for Combo — Combo fires naturally when cheap cards exist but is not deliberately set up.

---

## RemoteEvents

| Event | Direction | Payload |
|---|---|---|
| `StartDuel` | Client → Server | — |
| `PlayCard` | Client → Server | cardId, targetSlot |
| `DeclareAttack` | Client → Server | attackerSlot, targetSlot |
| `EndTurn` | Client → Server | — |
| `Forfeit` | Client → Server | — |
| `UpdateBattleState` | Server → Client | sanitized state snapshot |
| `BattleOver` | Server → Client | `{ winner, rewards }` |

---

## DataStore

```
Key: "ElementalTCG_v2"  (per player by UserId)
{
  exp   = number,
  gold  = number,
  cards = { cardId, cardId, ... }
}
```

---

## Known Issues

| Issue | Priority | Notes |
|---|---|---|
| SWIFT has zero identity monsters | 🔴 High | Cat minion cards need to be designed and added to CardData |
| `UseSkill` RemoteEvent orphaned | 🟢 Low | Leftover from old ruleset, safe to delete |
| NPC foot orientation | 🟢 Low | Testing Z-axis rotation fix |
| Avatar thumbnails in info widgets | 🟢 Low | Placeholder box — no `GetUserThumbnailAsync` call yet |
