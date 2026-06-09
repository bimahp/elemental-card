# DEV_STATUS — Elemental TCG: Implementation Status

> Last updated: 2026-06-09
> Phase: **v0.4 Implemented — Hearthstone-Pattern Ruleset**

> ✅ The codebase has been **fully rewritten** to the v0.4 design: MIGHTY/SWIFT/VITAL battle types (TOUGH merged into VITAL), universal Energy (Hearthstone-style ramp), 3-slot board, direct face damage (monsters attack hero, gated only by Taunt), monster/action card dichotomy (no Trainer/Equipment types), and persistent Invoker passive tallies. The v0.2 system (typed energy pools, 5-slot board, skill-based KO damage) has been fully replaced.
>
> **Note: BattleUI and BattleController are NOT yet updated for v0.4.** They still implement the v0.2 ruleset. The v0.4 modules (`CardData`, `BattleLogic`, `NpcAI`) are complete and verified via headless simulation only — not yet wired to the live game loop.
>
> **Simulation status:** 90-game cross-archetype sim run (n=15 per matchup per seat). Results after AI bias fixes: VITAL 61.7%, MIGHTY 46.7%, SWIFT 41.7%. See `DESIGN_BALANCE.md` for full breakdown.

This file tracks the real state of the codebase — what's built, where it lives, what's broken, and what's still TBD. Update this file after every meaningful session.

---

## System Status

### ✅ Card Data Module
**Location:** `ReplicatedStorage.Modules.CardData`  
**State:** Complete — v0.4

- `CardData.Cards` — 32 unique cards: 9 neutral monsters + 8 MIGHTY (3 monsters, 5 actions) + 7 SWIFT (0 monsters, 7 actions) + 8 VITAL (4 monsters, 4 actions)
- `CardData.Decks = { MIGHTY=30, SWIFT=30, VITAL=30 }` — 2 copies of each identity card + 2 copies of each neutral pool card
- Card shapes: `{id, name, cardType="monster"|"action", battleType, cost, atk?, hp?, keywords?, effect?}`
- Effect shape: `{trigger?, type, value?, target?, atk?, hp?, keyword?, condition?, ...}`
- `CardData.InvokerThresholds` — MIGHTY/SWIFT/VITAL thresholds at tiers 3/6/9
- `CardData.NeutralPool`, `CardData.Tokens` tables
- Full card list in `DESIGN_CARDS.md` → v0.4 section

---

### ✅ Battle Logic Module
**Location:** `ServerScriptService.Modules.BattleLogic`  
**State:** Complete — v0.4 rewrite (~37k chars)

Key functions:
- `newSide(deckList)` / `newMonsterInstance(card)` / `newBattle(playerDeck, npcDeck)`
- `playCard(state, who, cardId, slotOrTarget)` — handles both monster summons and action casts; tallies Invoker; routes to trigger dispatchers
- `attack(state, who, attackerSlot, targetSlot)` — Hearthstone-style attack, Taunt/Stealth gating, combo extra-attack support
- `startTurn` / `endTurn` — energy ramp, Coin, temp-keyword expiry, attackedThisTurn reset, card draw
- `applyMonsterTriggerEffect(state, who, slot, effect, ctx)` — battlecry/deathrattle/on_X dispatcher (all trigger types)
- `applyActionEffect(state, who, effect, cardBattleType)` — action effect dispatcher (all effect types); `cardBattleType` passed for MIGHTY damage bonus
- `dealDamageToHero` / `dealDamageToMonster` / `killMonster` / `healHero` / `gainArmor`
- `mightyDamageBonus(side, battleType)` — adds MIGHTY Invoker `damageBonus` to effect damage values
- `applyDestroyInvokerBonus(state, who, side)` — VITAL `destroyHealBonus` + MIGHTY `destroyFaceDamage` on minion kill
- `invokerBonus(side, battleType, key)` / `tallyInvoker(state, who, battleType)` — Invoker passive system; nil-guarded for neutral cards
- `comboActive(side)` / `comboScaledValue(side, val)` / `siphonAmount(side, base)` — archetype mechanic helpers
- `pickAnyOccupiedSlot(side, excludeSlot)` / `pickEnemyTarget(oppSide, mode, param)` — targeting helpers
- `shuffle(t)` / `drawCard` / `checkWin`

Monster trigger types: `gain_armor`, `scry_draw`, `damage`, `destroy`, `take_control`, `restore_health`, `restore_health_eq_damage_dealt`, `restore_health_on_ally_death`, `bounce`, `steal_card_copy`, `return_dead_ally_to_hand`, `summon_copy_of_highest_cost_dead`, `gain_keyword_on_combo`, `conditional_self_buff_on_play`, `buff_self_on_trigger`, `armor_scaling_atk` (passive), `combo_extra_attack` (passive)

Action effect types: `gain_armor`, `buff_friendly_minion`, `damage`, `damage_random_split`, `damage_then_combo_draw`, `damage_and_heal_hero`, `damage_eq_cards_played`, `damage_reduction`, `gain_armor_eq_damage_taken`, `bounce`, `draw_card`, `grant_keyword`, `restore_health`, `restore_health_and_draw`, `take_control`, `destroy`, `destroy_then_combo_copy`, `destroy_then_draw_per_hp`, `destroy_all`, `buff_target_and_gain_armor`, `buff_all_allies_and_gain_armor`, `gain_armor_and_summon`, `damage_hero_eq_armor_half`, `discover_dead_ally_copy`

---

### ✅ NPC AI Module
**Location:** `ServerScriptService.Modules.NpcAI`  
**State:** Complete — v0.4 rewrite (rule-based, noisy-argmax)

Architecture:
- **Phase 1 — unified card-play loop:** Each iteration builds a single candidate pool of all affordable monsters (if a board slot is open) and all affordable actions. Each is scored on a comparable scale via `scoreMonster(card)` and `scoreAction(card, side, oppSide, Logic)`. `noisyPick(candidates, noise)` selects the best with DEFAULT_NOISE=0.35 jitter. Loops until nothing scores above threshold / budget exhausted.
- **Phase 2 — attack phase:** Every non-exhausted attacker picks a target via `chooseAttackTarget` (lethal > clean kill > even trade > safe poke > face). Two passes to catch combo extra-attack re-arms.

Key scoring notes:
- `restore_health`: scores positively only when `effectiveMissing > 0` (checks hero OR most-damaged minion for `hero_or_minion`/`all_friendly` targets); scores `-35` at full health — will not waste heals
- `buff_friendly_minion`: `(atk*3 + hp*2)` bonus, minus 20 if board empty — will not play equips with nothing to buff
- `destroy`/`take_control`: penalized -40 if no valid target on board
- `damage` variants: +2000 score for lethal face shots
- `scoreMonster`: `10 + atk*2 + hp*1.5 + hp/cost*3` — produces values in the 18–35 range, comparable to action baseline of 18

Known limitations: AI does not sequence cards specifically for combo (does not guarantee "play a cheap card first to enable combo on the next"). Combo fires naturally when cheap cards exist but is not explicitly targeted.

---

### ⚠️ Battle Controller (Server)
**Location:** `ServerScriptService.BattleController`  
**State:** NOT YET UPDATED — still implements v0.2 ruleset (typed energy, skill-based combat, 5-slot board). Must be rewritten for v0.4 before the game is playable again.

### ⚠️ Battle UI
**Location:** `StarterGui.BattleUI` + `BattleUIController`  
**State:** NOT YET UPDATED — still renders v0.2 state (5-slot board, typed energy display, UseSkill remote). Must be rewritten for v0.4.

---

## V0.4 Module Status Summary

| Module | Location | v0.4 Status |
|---|---|---|
| CardData | RS.Modules.CardData | ✅ Complete |
| BattleLogic | SSS.Modules.BattleLogic | ✅ Complete |
| NpcAI | SSS.Modules.NpcAI | ✅ Complete |
| BattleController | SSS.BattleController | ❌ Needs rewrite |
| BattleUI / BattleUIController | StarterGui | ❌ Needs rewrite |

---

### 🗄️ Battle Controller (Server) — v0.2 reference
**Location:** `ServerScriptService.BattleController`  
**State:** v0.2 (outdated)

- `loadData / saveData` — DataStore renamed to `ElementalTCG_v2` (breaking change from v0.1's `ElementalTCG_v1`, intentional — old saves target the deprecated card system)
- `seatPlayer` — calls `seat:Sit(hum)` server-side
- `unseatPlayer` — sets `hum.Sit=false` only (WalkSpeed restored client-side on Continue)
- `broadcast(player, state)` — sends the new sanitized state shape: 5-slot board array (`board = {monster|nil, ...}` ×5) and typed `energy` table per side (NPC hand hidden), fires `UpdateBattleState`
- `endBattle(player, state, winner)` — awards rewards (now drawn from `CardData.Decks.MIGHTY`), fires `BattleOver`
- `runNpcTurn(player, state)` — async via `task.spawn`, 0.7s delay
- `Remotes.PlayCard` — now routes by `cardType`: `Monster` → `summonMonster`, `Trainer` → `playTrainer`, `Equipment` → `attachEquipment`
- `Remotes.UseSkill` (**new RemoteEvent**) — server-validated skill resolution: `UseSkill:FireServer(monsterSlot, skillNum, targetSlot)`
- `Logic.startTurn` (renamed from `startTurnPhases`)
- **Removed:** `DeclareAttack` / `playSkill` / `playSupport` handlers — replaced entirely by the skill-based combat model (the `DeclareAttack` RemoteEvent instance still exists in `ReplicatedStorage.Remotes` but is now orphaned/unused)

**DataStore keys:**
```
ElementalTCG_v2 → { exp, gold, cards[] } keyed by Player.UserId
```

---

### ✅ NPC Sit Behavior
**Location:** `ServerScriptService.NpcSit`  
**State:** Functionally complete — pose tuning ongoing

- Noob teleported directly to NPC seat via `hrp.CFrame` (no walk animation)
- `seat:Sit(humanoid)` called immediately
- R6 joint angles set manually via Motor6D C0 on Right Hip / Left Hip
- Pose maintained every 6 Heartbeat frames
- NPC faces PlayerSeat via `CFrame.lookAt`
- Arms slightly lowered to resting position

**Known issue:** Foot orientation — currently testing Z-axis rotation (π) to fix backward feet. See [DEV_LOG.md](DEV_LOG.md).

Current sitting joint angles:
```lua
Right Hip: CFrame.new(1,-1,0) * CFrame.fromEulerAnglesXYZ(-π/2, π/2, π)
Left Hip:  CFrame.new(-1,-1,0) * CFrame.fromEulerAnglesXYZ(-π/2, -π/2, π)
```

---

### ✅ Chair Interaction (Client)
**Location:** `StarterPlayer.StarterPlayerScripts.ChairInteraction`  
**State:** Complete

- Listens for `DuelTablePrompt` ProximityPrompt on the DuelTable tabletop Part
- On trigger: teleports player to PlayerSeat position, locks movement (WalkSpeed=0), shows Challenge/Leave GUI
- Challenge: fires `StartDuel` to server (server handles actual sitting)
- Leave: unlocks movement, hides GUI
- BattleOver handler: closes GUI only — movement NOT restored here (done in BattleUI ContinueBtn)

---

### ✅ Battle UI
**Location:** `StarterGui.BattleUI` (ScreenGui) + `BattleUIController` (LocalScript)  
**State:** Complete — v0.2 rewrite + iterative card-size tuning pass

**Board structure — simplified to ONE open row of 5 slots per side (no Active/Bench distinction), reusing the old GUI frames:**
```
EnemySection  (AnchorPoint top,    h=440px)
  EnemyHandRow    — card backs (HW×HH), h=162px
  EnemyBenchRow   — repurposed: all 5 enemy board slots (BW×BH), h=188px
  EnemyActiveRow  — legacy frame, hidden (Visible=false), shrunk to h=60px (kept only so the
                    vertical UIListLayout retains a consistent slot — otherwise unused)
────── divider (centered, 2px) ──────
PlayerSection (AnchorPoint bottom, h=440px)
  PlayerActiveRow — legacy frame, hidden, h=60px (see above)
  PlayerBenchRow  — repurposed: all 5 player board slots (BW×BH), h=188px
  PlayerHandRow   — HandScroll with player hand cards (HW×HH), h=162px
```
Each section's vertical `UIListLayout` has `Padding = UDim.new(0, 12)` — gives clean visual
separation/margin between the board row and the hand row (added per user feedback after the
initial rewrite had them touching).

**Card sizes — board slots intentionally LARGER than hand cards** (board is the focal point:
monster stats/skills/HP need to be readable at a glance; tuned across 3 iterative passes per
user feedback — first flipping the board>hand relationship, then enlarging both with row
margin, then enlarging both again):
- Board slots: `BW = sm and 104 or 128`, `BH = sm and 144 or 172` (mobile/desktop)
- Hand cards: `HW = sm and 90 or 108`, `HH = sm and 124 or 146` (mobile/desktop)
- `sm` = `workspace.CurrentCamera.ViewportSize.X < 800`
- All proportional text-size ratios (`BW*0.088`, `HH*0.16`, `HW*0.1`, etc. in `mkSlot`/
  `fillSlot`/`buildCard`/`mkBack`) scale automatically with these constants — no separate
  tuning needed, text stays readable at all sizes via `math.max(8, ...)` floors.

**Skill selection UI:** click a board slot → highlight → "Use Skill" button appears →
fires `UseSkill:FireServer(monsterSlot, skillNum, targetSlot)`.

**Info widgets:**
- EnemyInfoWidget — top-right, dark red, shows NPC name + Core HP
- PlayerInfoWidget — bottom-left, dark green, shows player name + Core HP
- ActionButtons — bottom-right: Use Skill, End Turn (green), Forfeit (dark red) — `Attack`
  button repurposed/relabeled as `Use Skill` for the new skill-based combat model
- BattleLog — left side above PlayerInfoWidget, 228×240px, auto-scrolls

**Camera:** Scriptable, locked to player head looking at NPC seat during battle.  
**Character visibility:** All parts hidden except arms during battle.  
**Post-battle overlay:** Shows WIN/LOSE + rewards. Continue restores movement.

---

### ✅ Rewards + DataStore
**Location:** `ServerScriptService.BattleController`  
**State:** Complete

| Reward | Amount |
|--------|--------|
| EXP | +50 on win |
| Gold | +25 on win |
| Card Drop | 1 random card from NPC drop pool |

Drop pool = all unique cards from `CardData.Decks.MIGHTY` (the NPC's deck), equal weight.

---

### ✅ Post-Battle Screen
**Location:** `StarterGui.BattleUI.PostBattle` (Frame inside BattleUI)  
**State:** Complete

- Shown after `BattleOver` event
- Displays result + rewards (or "Better luck next time" on loss)
- Continue button: hides overlay, stops camera, restores `WalkSpeed=16 / JumpPower=50 / Sit=false`

---

## RemoteEvents

| Event | Direction | Payload |
|-------|-----------|---------|
| `StartDuel` | Client → Server | — |
| `PlayCard` | Client → Server | cardId, targetSlot — server routes by `cardType` (Monster/Trainer/Equipment) |
| `UseSkill` | Client → Server | monsterSlot, skillNum, targetSlot — **new in v0.2**, drives all combat |
| `EndTurn` | Client → Server | — |
| `Forfeit` | Client → Server | — |
| `UpdateBattleState` | Server → Client | sanitized state: 5-slot board arrays + typed energy tables per side |
| `BattleOver` | Server → Client | { winner, rewards } |
| ~~`DeclareAttack`~~ | — | **Orphaned** — instance still exists in `ReplicatedStorage.Remotes` from v0.1 but has no server handler; superseded by `UseSkill`. Safe to delete in a future cleanup pass. |

All in `ReplicatedStorage.Remotes/`.

---

## Known Issues

| Issue | Status | Notes |
|-------|--------|-------|
| `DeclareAttack` RemoteEvent orphaned | 🧹 Cleanup TBD | Instance still exists in `ReplicatedStorage.Remotes` from v0.1; no longer fired by client or handled by server. Safe to delete. |
| NPC foot orientation | 🔧 In progress | Testing Z-axis π rotation |
| Avatar photo in info widgets | ⏳ Placeholder | Shows empty box — no thumbnail API call yet |
| Turn order (who goes first) | 🔴 High-priority TBD | Hardcoded to player-first in `BattleController` (`Logic.startTurn(state,"player")`) — not actually a coin flip as `DESIGN_BATTLE.md` claims. The new "Opening Turn Rules" (`DESIGN_BATTLE.md`, balance fix from `DESIGN_BALANCE.md`) assume a *randomized* first/second seat — under the current hardcoded order they apply backwards: the human player always gets the Turn-1 restriction, the NPC always gets "Second Wind". Resolve before this stops disadvantaging the human player, and definitely before PvP. |
| Deck-out loss rule | 📋 TBD design | Currently no loss on empty deck |
| Max hand size | 📋 TBD design | Currently no cap |
| Max Equipment per monster | 📋 TBD design | Currently unlimited |

---

## Out of Scope for v0.2

- Deck building UI
- Card collection / inventory UI
- Multiple NPCs
- Player vs Player duels
- Card packs / shop
- Monster mastery tracking in DataStore (Skill 2 unlock mechanic — designed in `DESIGN_PROGRESSION.md` but not yet wired into gameplay)
- SWIFT, TOUGH, VITAL NPC decks (NPC always plays MIGHTY; the other 3 decks are fully defined in `CardData` and playable by the human player, just not used by the AI yet)
- Persistent card unlocks shown to player
