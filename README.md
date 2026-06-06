# Elemental TCG

A Roblox card battle game set inside a 3D TCG card shop. Players challenge NPC opponents at tables, engage in turn-based card battles, and collect cards as rewards.

**Engine:** Roblox Studio  
**Language:** Luau  
**Current phase:** v0.1 — Core Battle Loop (in progress, functionally complete)

---

## Documentation Index

| File | Purpose |
|------|---------|
| [README.md](README.md) | This file — project overview and doc index |
| [DEV_STATUS.md](DEV_STATUS.md) | **Current implementation state** — what's built, script locations, known issues |
| [DEV_LOG.md](DEV_LOG.md) | Session-by-session build history |
| [DESIGN_ROADMAP.md](DESIGN_ROADMAP.md) | Phase plan — v0.1 scope, v0.2 planning |
| [DESIGN_CORE.md](DESIGN_CORE.md) | Game concept, resource system, element identities, deck rules |
| [DESIGN_BATTLE.md](DESIGN_BATTLE.md) | Turn structure, combat rules, win condition |
| [DESIGN_UI.md](DESIGN_UI.md) | Battle UI layout, board presentation, post-battle screen |
| [DESIGN_CARDS.md](DESIGN_CARDS.md) | All 96 cards across 4 decks with stats and art prompts |
| [DESIGN_PROGRESSION.md](DESIGN_PROGRESSION.md) | EXP/Gold rewards, drop pools, monster mastery system |

---

## Quick Start — What Works Right Now

1. Open the project in Roblox Studio
2. Press **Play**
3. Walk up to the **DuelTable** — a ProximityPrompt appears
4. Press it → Challenge/Leave GUI appears
5. Click **Challenge** → battle starts against the Fire NPC (Noob)
6. Play cards from your hand, End Turn, Attack
7. NPC takes its turn automatically (rule-based AI)
8. Win → get +50 EXP, +25 Gold, 1 random Fire card drop
9. Click **Continue** → return to world

---

## Project Structure (Roblox)

```
ReplicatedStorage/
  Modules/
    CardData          ← All card definitions + Fire Deck
  Remotes/
    StartDuel, PlayCard, DeclareAttack, EndTurn
    UpdateBattleState, BattleOver, Forfeit

ServerScriptService/
  Modules/
    BattleLogic       ← Rules engine (shuffle, draw, play, attack, win check)
    NpcAI             ← Rule-based NPC turn logic
  BattleController    ← Server authority: state, RemoteEvents, DataStore, rewards
  NpcSit              ← Noob humanoid seated pose + Heartbeat maintenance

StarterPlayer/
  StarterPlayerScripts/
    ChairInteraction  ← ProximityPrompt, Challenge/Leave GUI, movement lock

StarterGui/
  BattleUI/
    BattleUIController ← Board render, hand cards, camera lock, log, post-battle

Workspace/
  Noob              ← NPC humanoid (R6, seated at NPCChair)
  NPCChair          ← Model (IsNPCSeat=true attribute)
  PlayerChair       ← Model (IsPlayerSeat=true attribute)
  DuelTable         ← Model with ProximityPrompt on tabletop Part
```

---

## Design Pillars

- **Board presence** over hand tricks — what's on the field matters
- **Resource engines** — monsters generate elements each turn; economy is earned
- **Monster progression** — mastery unlocks alternative skills/cosmetics (not stat inflation)
- **Readable board state** — fast scan from across the room in 3D world
- **Social atmosphere** — battles happen inside a visible 3D card shop
