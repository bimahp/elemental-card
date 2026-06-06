# DEV_LOG — Elemental TCG: Session Build History

Chronological record of what was built each session. Most recent sessions at the top.

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
