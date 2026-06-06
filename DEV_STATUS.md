# DEV_STATUS — Elemental TCG: Implementation Status

> Last updated: 2026-06-06  
> Phase: **v0.1 — Core Battle Loop**

This file tracks the real state of the codebase — what's built, where it lives, what's broken, and what's still TBD. Update this file after every meaningful session.

---

## System Status

### ✅ Card Data Module
**Location:** `ReplicatedStorage.Modules.CardData`  
**State:** Complete for Fire Deck

- All 14 unique Fire Deck cards defined with full stats
- Fire Deck list defined (24 cards, 2-copy limit)
- `CardData.getCardText(cardId)` helper implemented
- Other decks (Nature, Lightning, Water) — defined in DESIGN_CARDS.md but **not yet in Lua** (out of v0.1 scope)

---

### ✅ Battle Logic Module
**Location:** `ServerScriptService.Modules.BattleLogic`  
**State:** Complete

Key functions:
- `newBattle(playerDeck, npcDeck)` — initial state
- `shuffle(t)` — Fisher-Yates
- `canAfford / spendCost`
- `drawCard(state, who)`
- `generatePhase(state, who)`
- `summonMonster(state, who, cardId, slot)`
- `declareAttack(state, who)` — mutual damage + retaliation
- `playSkill / playSupport / useMonsterSkill`
- `endTurn(state, who)` — resets temp ATK boosts, end-of-turn effects
- `startTurnPhases(state, who)` — energy+1, draw, generate
- `checkWin(state)` — returns `"player"` or `"npc"` if core HP ≤ 0
- `killActive(state, who)` — destroys active, auto-promotes from bench
- `dealDamage(state, targetWho, amount)`

---

### ✅ NPC AI Module
**Location:** `ServerScriptService.Modules.NpcAI`  
**State:** Complete (rule-based, intentionally simple)

Priority order per action:
1. Summon highest-level affordable monster (active → bench)
2. Play highest-cost affordable skill card
3. Play support/field support/equipment
4. Use active monster's built-in skill
5. Attack with active monster
6. End turn

NPC does not hold cards for combos, count cards, or evaluate board states.

---

### ✅ Battle Controller (Server)
**Location:** `ServerScriptService.BattleController`  
**State:** Complete

- `loadData / saveData` — DataStore `ElementalTCG_v1`
- `seatPlayer` — calls `seat:Sit(hum)` server-side
- `unseatPlayer` — sets `hum.Sit=false` only (WalkSpeed restored client-side on Continue)
- `broadcast(player, state)` — sanitized state (NPC hand hidden), fires `UpdateBattleState`
- `endBattle(player, state, winner)` — awards rewards, fires `BattleOver`
- `runNpcTurn(player, state)` — async via `task.spawn`, 0.7s delay
- Handles: `StartDuel`, `PlayCard`, `DeclareAttack`, `EndTurn`, `Forfeit` RemoteEvents

**DataStore keys:**
```
ElementalTCG_v1 → { exp, gold, cards[] } keyed by Player.UserId
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
**State:** Complete with layout refinements ongoing

**Board structure (two anchored sections):**
```
EnemySection  (AnchorPoint top,    h=380px)
  EnemyHandRow    — card backs, same size as player hand cards
  EnemyBenchRow   — 3 board slots (BW×BH)
  EnemyActiveRow  — 1 board slot  (BW×BH, same as bench)
────── divider (centered, 2px) ──────
PlayerSection (AnchorPoint bottom, h=380px)
  PlayerActiveRow — 1 board slot  (BW×BH)
  PlayerBenchRow  — 3 board slots (BW×BH)
  PlayerHandRow   — HandScroll with player hand cards (HW×HH, bigger)
```

**Card sizes (desktop):**
- Board slots: BW=86, BH=108 (all 8 uniform — active same as bench)
- Hand cards: HW=93, HH=128 (player hand and enemy backs, same)

**Info widgets:**
- EnemyInfoWidget — top-right, dark red, shows NPC name + HP + elements
- PlayerInfoWidget — bottom-left, dark green, shows player name + HP + elements
- ActionButtons — bottom-right: Attack (red), End Turn (green), Forfeit (dark red)
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
| Card Drop | 1 random card from Fire NPC drop pool |

Drop pool = all unique Fire Deck cards (14 cards, equal weight).

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
| `PlayCard` | Client → Server | cardId, targetWho, targetSlot |
| `DeclareAttack` | Client → Server | — |
| `EndTurn` | Client → Server | — |
| `Forfeit` | Client → Server | — |
| `UpdateBattleState` | Server → Client | sanitized state snapshot |
| `BattleOver` | Server → Client | { winner, rewards } |

All in `ReplicatedStorage.Remotes/`.

---

## Known Issues

| Issue | Status | Notes |
|-------|--------|-------|
| NPC foot orientation | 🔧 In progress | Testing Z-axis π rotation |
| Avatar photo in info widgets | ⏳ Placeholder | Shows empty box — no thumbnail API call yet |
| Turn order (who goes first) | 📋 TBD design | Currently always player first |
| Deck-out loss rule | 📋 TBD design | Currently no loss on empty deck |
| Max hand size | 📋 TBD design | Currently no cap |
| Max Equipment per monster | 📋 TBD design | Currently unlimited |
| Max Field Supports in play | 📋 TBD design | Currently unlimited |

---

## Out of Scope for v0.1

- Deck building UI
- Card collection / inventory UI
- Multiple NPCs
- Player vs Player duels
- Card packs / shop
- Monster mastery tracking in DataStore
- Nature, Lightning, Water NPC decks
- Persistent card unlocks shown to player
