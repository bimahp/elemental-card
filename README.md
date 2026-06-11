# Elemental TCG

A Roblox digital card battle game set inside a 3D TCG card shop. Players challenge NPC opponents at tables, engage in turn-based card battles, and collect cards as rewards.

**Engine:** Roblox Studio | **Language:** Luau | **Phase:** v0.1

---

## Documentation

| File | Purpose |
|---|---|
| [DESIGN_CORE.md](DESIGN_CORE.md) | Rules, archetypes, mechanics — single source of truth |
| [DESIGN_CARDS.md](DESIGN_CARDS.md) | Full card catalog — all three decks |
| [DESIGN_BALANCE.md](DESIGN_BALANCE.md) | Simulation methodology and current balance findings |
| [DESIGN_UI.md](DESIGN_UI.md) | Battle UI layout and presentation |
| [DESIGN_PROGRESSION.md](DESIGN_PROGRESSION.md) | Rewards, mastery, collection |
| [DEV_STATUS.md](DEV_STATUS.md) | Current implementation state |

---

## Project Structure (Roblox)

```
ReplicatedStorage/
  Modules/
    CardData              ← All card definitions + 3 starter decks
  Remotes/
    StartDuel, PlayCard, Attack, EndTurn, Forfeit
    UpdateBattleState, BattleOver

ServerScriptService/
  Modules/
    BattleLogic           ← Rules engine
    NpcAI                 ← Rule-based NPC turn logic
  BattleController        ← Server authority: state, RemoteEvents, DataStore, rewards
  NpcSit                  ← NPC seated pose

StarterPlayer/
  StarterPlayerScripts/
    ChairInteraction      ← ProximityPrompt, Challenge/Leave GUI, movement lock

StarterGui/
  BattleUI/
    BattleUIController    ← Board render, hand, camera, post-battle screen

Workspace/
  Noob                    ← NPC humanoid (R6, seated)
  NPCChair                ← NPC seat
  PlayerChair             ← Player seat
  DuelTable               ← Table with ProximityPrompt
```
