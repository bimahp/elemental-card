# Elemental TCG

A Roblox card battle game set inside a 3D TCG card shop. Players challenge NPC opponents at tables, engage in turn-based card battles, and collect cards as rewards.

**Engine:** Roblox Studio  
**Language:** Luau  
**Current phase:** v0.3 — Structural Redesign **IN DESIGN** (pivoting away from
the typed-energy/5-slot v0.2 system after playtesting surfaced structural
problems; see `DESIGN_CORE_V3.md` and `DEV_LOG.md` Session 9). v0.2
("functionally complete, fully playable" per `DEV_STATUS.md`) remains the last
working build while the rewrite is designed and prototyped.

---

## Documentation Index

| File | Purpose |
|------|---------|
| [README.md](README.md) | This file — project overview and doc index |
| [DESIGN_CORE_V3.md](DESIGN_CORE_V3.md) | **⭐ v0.3 redesign spec (current direction)** — universal energy, 3-slot board, 3 battle types, Player Skill system — supersedes the docs below it |
| [DEV_STATUS.md](DEV_STATUS.md) | Implementation state of the **v0.2** build — what's built, script locations, known issues |
| [DEV_LOG.md](DEV_LOG.md) | Session-by-session build history (see Session 9 for the v0.3 pivot rationale) |
| [DESIGN_ROADMAP.md](DESIGN_ROADMAP.md) | Phase plan — v0.1/v0.2 scope (pre-pivot) |
| [DESIGN_CORE.md](DESIGN_CORE.md) | ⚠️ v0.2 — superseded by `DESIGN_CORE_V3.md`. Game concept, resource system, element identities, deck rules |
| [DESIGN_BATTLE.md](DESIGN_BATTLE.md) | ⚠️ v0.2 — superseded by `DESIGN_CORE_V3.md`. Turn structure, combat rules, win condition |
| [DESIGN_UI.md](DESIGN_UI.md) | Battle UI layout, board presentation, post-battle screen (largely reusable — board slot count will need adjusting for the 3-slot redesign) |
| [DESIGN_CARDS.md](DESIGN_CARDS.md) | ⚠️ v0.2 — superseded by `DESIGN_CORE_V3.md`. All 96 cards across 4 decks; full catalog rewrite pending |
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
