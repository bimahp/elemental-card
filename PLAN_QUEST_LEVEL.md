# PLAN_QUEST_LEVEL — Onboarding Quest System

> Status: **implemented and validated** (2026-06-28).
> Repaired after live Studio review; headless migration checks and a direct Play-mode onboarding test pass. See implementation notes at the bottom.

---

## Context

Players who join for the first time have no guidance — they spawn in a card shop with no deck and no direction. This plan adds a linear onboarding quest that walks a new player from a blank slate to their first PvE win: choose an archetype via trainer dialogue, get their starter deck, return to Noob for the tutorial battle, and be rewarded with EXP + Crystal Shards (the renamed/consolidated currency). Supporting this are three new cross-cutting systems: a persistent quest tracker, a level/EXP progression system (currently backend-only), and a directional quest HUD arrow.

**Key decisions settled before planning:**
- Gold → **Crystal Shards** (Gold field removed and replaced, not a second currency)
- New players start with **no deck** (quest-gated; existing players skip onboarding via migration)
- Arrow is a **ScreenGui 2D directional indicator** (rotates at screen edge pointing toward target NPC)
- Level curve: **EXP table** generated as `floor(100 × 1.15^(n−1))` for n = 1..100
- Trainer models (`Workspace.Trainers.Trainer Mighty/Swift/Vital`) and their ProximityPrompts already exist in Studio

---

## Architecture Overview

### New Modules
| File | Role |
|---|---|
| `ReplicatedStorage/Modules/LevelConfig` | Precomputed EXP table (L1→100), shared server+client |
| `ReplicatedStorage/Modules/QuestConfig` | Quest ID constants + quest definitions registry; shared server+client |
| `ServerScriptService/Modules/QuestService` | Quest stage CRUD keyed by QuestConfig IDs; fires `QuestStateChanged` on every write |
| `StarterPlayer/StarterPlayerScripts/DialogueController` | ModuleScript: typewriter + camera tween + option buttons (shared by Noob and trainers) |
| `StarterPlayer/StarterPlayerScripts/TrainerInteraction` | LocalScript: trainer ProximityPrompt → dialogue → `ChooseStarterDeck` |
| `StarterPlayer/StarterPlayerScripts/QuestHUDController` | LocalScript: screen-space directional arrow, ! marks above NPCs, Noob dialogue dispatch |
| `StarterGui/DialogueUI` | ScreenGui: DialoguePanel + OptionsContainer |
| `StarterGui/QuestHUD` | ScreenGui: QuestArrow (▲ frame, rotated by controller) |

### Modified Files
| File | What changes |
|---|---|
| `ServerScriptService/Modules/SaveService` | Schema v3.1: safe v3.0 migration, `gold`→`crystalShards`, add `level`, add `quests{}`, new-player template has no deck/no collection; guarded `grantStarterDeck`, `getQuestState`, `setQuestStage`, `getFullSnapshot` APIs |
| `ServerScriptService/BattleController` | Noob TalkPrompt intercept; `ChooseStarterDeck` handler; `RequestTutorialBattle` handler; weak-matchup tutorial deck logic; tutorial flag; quest completion on battle end |
| `ServerScriptService/Modules/RewardService` | `gold`→`crystalShards` in reward payloads |
| `StarterPlayer/StarterPlayerScripts/NameplateController` | 3-row player nameplate: Title / Name / Level (yellow); reads `Player.Level` IntValue |
| `StarterGui/BattleUI/BattleUIController` | One authoritative `BattleOver` handler using the existing PostBattle panel; displays tutorial completion, EXP, Crystal Shards, and card drop |

### New remotes (added to `ReplicatedStorage/Remotes`)
| Name | Direction | Payload |
|---|---|---|
| `QuestStateChanged` | S→C | `{stage, chosenArchetype, level, crystalShards}` — fired on join + every mutation |
| `ChooseStarterDeck` | C→S | `trainerModelName: string` |
| `RequestTutorialBattle` | C→S | *(none)* |
| `ShowNoobDialogue` | S→C | `stage: string` |
| `LevelUp` | S→C | `{newLevel: number}` — reserved; no HUD consumer yet |
| `GetQuestSnapshot` | C→S (`RemoteFunction`) | Returns the current onboarding stage, archetype, level, and Crystal Shards; clients retry on join to avoid a lost initial RemoteEvent |

### QuestConfig — Scale-ready quest registry

All quest IDs are string constants in one shared module. Both server and client always reference `QuestConfig.IDs.*` — never inline strings.

```lua
QuestConfig.IDs = {
    ONBOARDING = "quest_onboarding",
    -- Future: DAILY_BATTLE = "quest_daily_battle"
}
QuestConfig.Defs = {
    [QuestConfig.IDs.ONBOARDING] = {
        stages = { "intro", "find_trainer", "deck_chosen", "complete" },
    },
}
```

SaveService stores quests as a sparse map: `data.quests["quest_onboarding"] = { stage = "...", archetype = nil|"MIGHTY"|"SWIFT"|"VITAL" }`.

### Quest Stage Machine
```
"intro"          → new player; ! above Noob; arrow → Noob
"find_trainer"   → talked to Noob; ! above all three trainers; arrow → nearest trainer
"deck_chosen"    → picked a deck (archetype stored); ! above Noob; arrow → Noob
"complete"       → tutorial battle resolved (win or lose); all quest HUD hidden; normal PvE unlocked
```

---

## Phase 1 — Schema, Currency & Level Foundation

**Goal:** Backend foundation. No visible UI changes yet except nameplate level.

### 1.1 SaveService (schema v3.1)
- `CURRENT_VERSION = { major=3, minor=1 }`
- Minor migration `"3.0->3.1"`:
  - Adds any retired `gold` balance to `crystalShards`, then removes `gold`.
  - Recalculates `level` from saved EXP.
  - Players predating onboarding skip it with stage `"complete"`.
  - Profiles created by the broken rollout remain in onboarding only when they genuinely have no cards/decks; owned data is never routed through a starter replacement.
- Legacy v2 profiles are upgraded in place through the same v3.1 repair (`"major_preserved"`) instead of taking the destructive major-reset branch. Collection, decks, active deck, EXP, archetype, and PvP record are retained; Gold is converted to Crystal Shards and existing players skip onboarding.
- New-player TEMPLATE: `collection={}`, `decks={}`, `activeDeckId=false`, `crystalShards=0`, `exp=0`, `level=1`, `quests={["quest_onboarding"]={stage="intro",archetype=nil}}`
- `ensureDeckDefaults` guard: `if data.activeDeckId == false then return end` — prevents auto-creating deck for new players
- `SaveService.grantStarterDeck(player, archetype)`: refuses profiles that already own cards/decks; otherwise builds the starter collection, creates the deck entry, and sets `activeDeckId`
- `SaveService.getQuestState(player, questId)` → `{stage, archetype}`
- `SaveService.setQuestStage(player, questId, stage, archetype?)` — marks dirty
- `SaveService.getFullSnapshot(player)` → `{level, crystalShards, quests}`
- `applyRewards`: `rewards.crystalShards` (replaces `rewards.gold`)
- `checkLevelUp(player, data)`: fires `LevelUp{newLevel}` + updates `Player.Level` IntValue
- `onPlayerAdded`: creates `IntValue("Level")` in player, fires `QuestStateChanged` with initial state

### 1.2 LevelConfig (`ReplicatedStorage/Modules/LevelConfig`)
```lua
-- EXP_TABLE[n] = EXP needed to advance from level n to n+1
-- base = floor(100 × 1.15^(n-1))
LevelConfig.expForLevel(n)          -- → EXP needed for level n
LevelConfig.levelFromExp(totalExp)  -- → current level
LevelConfig.expIntoLevel(totalExp)  -- → (expIntoThisLevel, neededForNext)
```

### 1.3 QuestService (`ServerScriptService/Modules/QuestService`)
Thin wrapper over SaveService. Always uses `QuestConfig.IDs.*` constants. Fires `QuestStateChanged` after every write.

```lua
QuestService.getStage(player, questId)               -- → stage string
QuestService.getArchetype(player, questId)           -- → "MIGHTY"|"SWIFT"|"VITAL"|nil
QuestService.setStage(player, questId, stage, arch?) -- validates stage, marks dirty, broadcasts
```

### 1.4 Nameplate level display (`NameplateController`)
- Player nameplates: 3-row layout — Title (NPC-only) / Name / Level `"Level N"` (yellow, players only)
- `PART_HEIGHT_PLAYER = 3.0` (taller than NPC parts)
- LevelLabel binds to `Player.Level.Changed` for live updates
- `register()` returns `part, sg` so the LocalScript can wire the Level IntValue watcher

---

## Phase 2 — Dialogue System (Client)

**Goal:** Reusable typewriter dialogue with camera tween and option buttons.

### DialogueUI (StarterGui)
```
ScreenGui "DialogueUI" (Enabled=false, ResetOnSpawn=false, IgnoreGuiInset=true)
├── ClickCapture     TextButton, transparent, full-screen, ZIndex=2
└── DialoguePanel    Frame, 62% width, bottom-center, AutomaticSize=Y
    ├── DialogueText TextLabel, 80px, GothamMedium, TextWrapped
    └── OptionsContainer  Frame, AutomaticSize=Y, UIListLayout (Visible=false)
```

### DialogueController (ModuleScript)
Public API:
```lua
DialogueController:Open(targetModel, data, onAction)
-- data = { Segments={string,...}, Options={{Label, Action},...} }
DialogueController:Close()
DialogueController.IsOpen  -- bool
```
- `Open`: `WalkSpeed=0`, `CameraType=Scriptable`, tween ~8 studs from HRP, typewriter 0.035s/char
- Click/E during typing → skip to full text; during waiting → advance segment
- After last segment → build option buttons in OptionsContainer
- Option click: **`Close()` first**, then callback — allows callback to safely call `Open()` again
- `Close`: restore WalkSpeed, `CameraType=Custom`, disconnect connections

### TrainerInteraction (LocalScript)
- `ProximityPromptService.PromptTriggered` → only opens if `currentStage == "find_trainer"`
- `findTrainerModel(prompt)`: walks ancestors until direct child of `workspace.Trainers`
- Dialogue → CHOOSE → confirmation dialogue → CONFIRM fires `ChooseStarterDeck:FireServer(modelName)` → CANCEL re-opens trainer dialogue
- Listens to `QuestStateChanged` to cache `currentStage`; closes dialogue if stage advances past `"find_trainer"`

### Noob Dialogue (inside QuestHUDController)
- `ShowNoobDialogue` remote carries `stage` string; controller opens appropriate text via `DialogueController`
- Stage `"intro"` / `"find_trainer"`: "Go talk to a trainer" — no options
- Stage `"deck_chosen"`: "Ready for battle?" — Yes fires `RequestTutorialBattle:FireServer()`, No closes
- Both quest clients request `GetQuestSnapshot` with retry on startup, so joining at `find_trainer` or `deck_chosen` cannot miss the initial state.

---

## Phase 3 — Quest HUD (Arrow + Exclamation Marks)

**Goal:** Visual guidance for the player at every quest stage.

### QuestHUD (StarterGui)
```
ScreenGui "QuestHUD" (Enabled=true, ResetOnSpawn=false, IgnoreGuiInset=true)
└── QuestArrow   Frame (52×52), gold background, "▲" TextLabel
                 AnchorPoint=0.5/0.5; Rotation + Position set by controller each frame
```

### QuestHUDController (LocalScript)
- `! marks`: integrated as a `QuestMark` row above the title inside each NPC's scalable nameplate `SurfaceGui`. QuestHUD toggles these rows by the nameplate's `TargetModelName` attribute; no separate BillboardGui is created.
- `Directional arrow` (RenderStepped):
  - Finds nearest target NPC; projects to screen
  - Hides when NPC is on-screen and within 35 studs
  - Otherwise clamps to screen edge with 80px margin via `clampToEdge(cx, cy, dx, dy, margin, vpX, vpY)`
  - Rotation: `math.deg(math.atan2(dy, dx)) + 90` maps screen direction to GUI rotation (▲ at 0° = up)
- `QuestStateChanged` → `setTargets(stage)` → rebuilds ! marks + arrow targets
- `ShowNoobDialogue.OnClientEvent` → opens Noob dialogue via DialogueController
- NPC models resolved via `WaitForChild` in a `task.spawn`; cached `currentStage` replayed after ready

**Target NPC mapping:**
| Stage | ! Marks | Arrow target |
|---|---|---|
| `intro` | Noob | Noob |
| `find_trainer` | All three trainers | Nearest trainer |
| `deck_chosen` | Noob | Noob |
| `complete` | none | hidden |

---

## Phase 4 — Tutorial Battle & Quest Completion

**Goal:** Wire the tutorial battle and complete the onboarding loop.

### BattleController changes

**Noob TalkPrompt intercept:**
```lua
local stage = QuestService.getStage(player, QuestConfig.IDs.ONBOARDING)
if stage ~= "complete" then
    Remotes.ShowNoobDialogue:FireClient(player, stage)
    if stage == "intro" then
        QuestService.setStage(player, QuestConfig.IDs.ONBOARDING, "find_trainer")
    end
    return
end
TblMgr.handleTalkToNpc(player)  -- normal PvE
```

**`ChooseStarterDeck.OnServerEvent`:**
- Guard: stage must be `"find_trainer"`
- Extract archetype: `trainerModelName:match("Trainer (%a+)"):upper()`
- Validate archetype is in `COUNTER_DECK` table
- `Save.grantStarterDeck(player, archetype)`
- `QuestService.setStage(player, IDs.ONBOARDING, "deck_chosen", archetype)`

**`RequestTutorialBattle.OnServerEvent`:**
- Guard: stage must be `"deck_chosen"`; player must not be in a battle or seated
- Weak-matchup lookup: `TUTORIAL_WEAK_DECK = { MIGHTY="vital", SWIFT="mighty", VITAL="swift" }`; the tutorial NPC deliberately uses the archetype weak to the player's starter.
- `tutorialPending[player.UserId] = true`
- `TblMgr.handleTalkToNpc(player, npcDeckKey)`

**`startPvE`:**
- Reads `tutorialPending[human.UserId]` → sets `battle.isTutorial = true`

**`endBattle` (PvE path):**
- After `Save.applyRewards`: if `battle.isTutorial` → `QuestService.setStage("complete")`
- `BattleOver` payload includes `isTutorialComplete = battle.isTutorial or nil`

**Cleanup:** `tutorialPending[player.UserId] = nil` in `PlayerRemoving`

---

## Phase 5 — Polish & End-to-End

### Currency rename audit
- `RewardService`: `PVE_WIN_GOLD` → `PVE_WIN_CRYSTALSHARDS`; `gold` field → `crystalShards`
- No runtime `gold` references remain in the Edit DataModel after the v3.1 migration

### Post-battle rewards display (`BattleUIController`)
The existing PostBattle panel is the single result surface:
- Win/Loss header
- "Tutorial Complete!" when `data.isTutorialComplete`
- `+N EXP`, `+N Crystal Shards`, and card drop
- `r.message` for PvP results

The legacy duplicate handler and `BattleResultOverlay` were removed. The active Script Editor document is synchronized with the DataModel source so Play mode uses this repaired handler.

### SaveService guard (deferred polish)
`getActiveBattleDeck` already rejects players with `activeDeckId = false`, so table ProximityPrompts naturally fail during onboarding. Client-side suppression of table prompts during `"intro"`/`"find_trainer"` stages is deferred.

### End-to-end flow
```
Fresh join
  → Lv 1 nameplate
  → ! above Noob, arrow pointing to Noob
  → talk to Noob → "Go find a trainer" → stage: intro → find_trainer
  → arrow to nearest trainer, ! above all three
  → talk Trainer Mighty → dialogue → confirm
  → ChooseStarterDeck fires → server grants Mighty Starter, stage: deck_chosen
  → arrow back to Noob, ! above Noob
  → talk Noob → "Ready for battle?" → Yes
  → RequestTutorialBattle fires → NPC uses Swift Starter (weak to Mighty)
  → battle plays → BattleOver fires with rewards + isTutorialComplete=true
  → PostBattle panel: "Victory!" / "Tutorial Complete!" / +EXP / +Shards
  → next Noob talk → normal random PvE
```

---

## Implementation Notes (deviations from original plan)

1. **Tutorial deck keys**: The tutorial intentionally favors the player: `MIGHTY→"vital"`, `SWIFT→"mighty"`, and `VITAL→"swift"`, using lowercase keys matching the `Decks` module.

2. **Tutorial flag threading**: `tutorialPending[UserId]` local table in BattleController (not a parameter to `startPvE`) — avoids modifying the TableManager signature. Consumed and cleared inside `startPvE` before `Session.start`.

3. **BattleUIController result handling**: An open Script Editor draft contained two `BattleOver` handlers and a legacy `r.gold` reference even after the DataModel source was edited. The draft and DataModel are now synchronized to one PostBattle handler using `crystalShards`.

4. **DialogueController close-before-callback**: Option buttons call `Close()` first, then the user callback. This allows callbacks that re-open the dialogue (e.g., Cancel → back to trainer options) to work without being killed by a second `Close()`.

5. **`activeDeckId = false` sentinel**: New-player template uses boolean `false` (not `nil`) so Reconcile doesn't overwrite it with the default string value, and `ensureDeckDefaults` can detect and skip new players explicitly.

6. **QuestHUD arrow**: Uses a `▲` TextLabel in a rotated Frame rather than an image asset. Rotation formula: `math.deg(math.atan2(dy, dx)) + 90` where dy/dx are screen-space offsets from viewport center.

7. **LevelUp remote**: Created and wired in SaveService but has no client consumer yet. Reserved for a future player info panel.

8. **Dialogue lifecycle repair**: Optionless dialogue closes after its final advance, exact movement values are restored, and camera callbacks wait for restoration before opening confirmation. The duplicate trainer prompt/E-key implementation was consolidated into one stage-routed controller.

9. **Validation**: Headless cases cover v2 preservation plus v3.0→v3.1 existing, fresh broken-rollout, owned broken-rollout, and `deck_chosen` profiles. Direct Play validation covered state recovery, all three trainer markers, optionless dialogue closure, movement/camera restoration, 30-card starter grant, HUD retargeting, tutorial start, loss completion, archetype preservation, and the final Crystal Shards result panel.

10. **Swift starter correction**: `sudden_death` replaces `vanishing_pounce` in `Decks.swift`; `shardleaf` remains in its original slot. Sudden Death replaces the deleted `blurred_assault` card in the Swift pack, while Vanishing Pounce remains collectible outside the starter.

11. **Quest mark layout**: NPC nameplates use three rows (`!` / title / name) at 3.4 studs high. The quest row occupies 36% of the plate with a 48 px mark, keeping the indicator large, camera-facing, and scaled consistently with the existing nameplate system.

12. **Chair exit placement**: BattleUI records the occupied Seat CFrame during pre-battle and battle-state events. On `BattleUnseated` or `BattleOver`, the owning client waits for the SeatWeld to release, then moves the character 3.5 studs along the previous chair's local side while preserving pivot height and facing. This prevents post-battle overlap with the chair and avoids server/client character-ownership snapback.

13. **Intentional v4.0 save reset**: SaveService's schema version is bumped from v3.1 to v4.0 with the guarded major-reset path enabled. Existing profiles are wiped instead of applying the obsolete `sudden_death` card-ID repair.

14. **Dialogue focus mode**: Opening shared NPC dialogue temporarily disables every world `ProximityPrompt`, hides the player and all non-active characters/nameplates, hides the quest arrow, and applies depth-of-field, dimming, and a subtle highlight to the active NPC. Closing dialogue restores each prompt, character, nameplate, HUD, camera, and lighting state.
