# PLAN_AI_ARCHETYPE — Archetype-Aware NPC AI + Trainer Dialogue System

> Status: **planning** | Author: bimahp | Date: 2026-06-26

---

## Goal

1. Make the NPC play like it understands its own deck (Mighty / Swift / Vital)
2. Add two difficulty tiers: **Noob** and **Pro** (Noob active now, Pro scaffolded)
3. Add **Trainer NPCs** in the world — talk-to-battle dialogue flow with camera tween,
   typewriter text, and Yes/No options — each trainer plays their archetype's starter deck

---

## What changes

### AI (NpcAI + wiring)

| File | Change |
|---|---|
| `ServerScriptService/Modules/NpcAI.lua` | Archetype detection, score layer, chain pre-pass, difficulty jitter, attack targeting |
| `ServerScriptService/Modules/DuelSession.lua` | Thread `difficulty` + `npcArchetype` into `runNpcTurn → NpcAI.takeTurn` |
| `ServerScriptService/BattleController.lua` | `StartTrainerBattle` remote handler; pass archetype + difficulty to `startPvE` |

### Trainer Dialogue (new files)

| File | Change |
|---|---|
| `StarterPlayer/StarterPlayerScripts/TrainerInteraction.lua` | LocalScript: ProximityPrompt detection → opens DialogueController |
| `StarterPlayer/StarterPlayerScripts/DialogueController.lua` | ModuleScript: typewriter, camera tween, movement lock, option buttons |
| `StarterGui/DialogueUI` | ScreenGui built in editor — DialoguePanel + OptionsContainer + ClickCapture |

---

## Architecture

### 1. Archetype detection

```lua
local function detectNpcArchetype(state, who)
    -- Count battleType occurrences across the NPC's deck.
    -- The NPC's active deck is stored in state[who].deck (list of card instances/ids).
    local counts = {}
    for _, card in ipairs(state[who].deck) do
        local bt = card.battleType or (Cards[card.cardId] and Cards[card.cardId].battleType)
        if bt and bt ~= "NEUTRAL" then
            counts[bt] = (counts[bt] or 0) + 1
        end
    end
    -- Also count hand + board for the rare case deck is nearly empty
    -- Return the dominant type; tie-break: MIGHTY > SWIFT > VITAL
    local best, bestN = "MIGHTY", 0
    for bt, n in pairs(counts) do
        if n > bestN then best, bestN = bt, n end
    end
    return best
end
```

Call once at the top of `takeTurn` and thread `archetype` into scoring helpers. The
detection is O(deck size) and safe to call each turn (deck shrinks but dominant type
stays stable).

### 2. Score layer

Add `archetypeBonus(state, who, opp, card, archetype, difficulty)` — called from
`scoreCard`, returns a delta (positive or negative). Pro difficulty uses full bonus
tables; Noob returns 0 from this function entirely (pure jitter-based play).

```lua
local function scoreCard(state, who, opp, card, archetype, difficulty)
    local base = ... -- existing action-verb scoring (unchanged)
    local bonus = archetypeBonus(state, who, opp, card, archetype, difficulty)
    return base + bonus
end
```

### 3. Difficulty jitter

Scale the existing `noisyPick` jitter by difficulty:

```lua
local JITTER = { noob = 5, pro = 0.5 }
```

Noob's ±5 jitter swamps most score differences → effectively random play. Pro's ±0.5
keeps relative ordering intact while avoiding fully deterministic repeating patterns.

### 4. `takeTurn` signature

```lua
function NpcAI.takeTurn(state, Logic, who, difficulty)
    difficulty = difficulty or "noob"
    local archetype = detectNpcArchetype(state, who)
    -- ... rest of turn with archetype + difficulty threaded through
end
```

---

## Mighty AI — Board Presence + Armor Stacking

### Scoring bonuses (Pro only)

| Situation | Card / Effect | Delta |
|---|---|---|
| Own board has < 3 creatures | Any creature | +3 |
| Own board has < 3 creatures | Taunt creature | +5 (fills board AND forces trades) |
| Own board has taunt creature already | Additional taunt creature | +1 only (diminishing) |
| `gain_armor` effect on own hero | Own HP < 28 | +4 |
| `gain_armor` effect on own hero | Own HP ≥ 28 | −2 (waste — already healthy) |
| `buff` targeting own board / ally | 2+ friendlies alive | +2 |
| `buff` targeting own board / ally | 0–1 friendlies | 0 (no mass payoff) |
| Creature with `take_damage` trigger (rumbleclaw, scarback) | Own HP < 20 | +2 (triggers sooner when taking hits) |

### Mighty attack behavior

**Pro**: Follow existing priority (lethal → clean kill → even trade → poke → face)
with one addition: when the board is full and trade targets exist, trade aggressively
to generate Charge from the surviving creature. Never attack face when a dangerous
enemy creature is alive and untapped.

**Noob**: Random valid target (Taunt still respected, everything else random).

### Mighty Noob mistakes

- Plays armor spells even at full HP
- Does not prioritize filling the board
- Attacks face even when enemy board is threatening

---

## Swift AI — Chain Sequencing + Stealth + Quickstrike

### Chain pre-pass (Pro only)

Before the normal score-and-play loop, if `cardsPlayedThisTurn == 0`:

```
chainCards = cards in hand where any effect has trigger="chain" AND card is affordable
enablers   = all other affordable cards (non-chain), sorted by cost ascending

if chainCards is non-empty AND enablers is non-empty:
    -- Play the cheapest enabler first to unlock chain for the chain card
    force-play enablers[1]
    -- Normal loop then runs; chain cards will now score with the chain bonus
```

This is a one-time pre-pass per turn, not recursive. It sacrifices card-play ordering to
unlock the chain bonus. Enabler selection: cheapest affordable card that is NOT itself a
chain-trigger card.

### Chain trigger bonus (Pro only)

When scoring a card whose effect has `trigger="chain"` AND `cardsPlayedThisTurn >= 1`:

```
+4 bonus (on top of the action's normal score)
```

This stacks with normal action scoring so the AI urgently completes the chain.

### Scoring bonuses (Pro only)

| Situation | Card / Effect | Delta |
|---|---|---|
| `grant_keyword` with `keyword="stealth"` | Any HP level | +3 |
| Creature that already has `stealth` keyword | Any | +2 (safe attacker, hard to remove) |
| `reduce_cost` effect | Hand has chain-trigger card | +3 (enabler value) |
| `reduce_cost` effect | Hand has no chain card | +1 (still useful tempo) |
| `draw_card` effect | Hand size ≤ 3 | +2 (refill for chain turns) |
| `draw_card` effect | Hand size ≥ 6 | 0 (hand nearly full) |
| Creature with `charge` keyword | | +1 (can attack immediately, acts as poke/chain setup) |

### Swift attack behavior

**Pro**: Follow existing priority order. Additional rule: **prefer using a quickstrike
creature** when trading into an enemy with ATK >= own quickstrike ATK (the quickstrike
creature kills first, takes no retaliation). Stealthed own creatures should attack face
or the weakest enemy to preserve their stealth value; do NOT use stealth creatures to
trade into a wall where they will die without payout.

Concretely in `aiAttack` Pro Swift:
1. Lethal targets (same as always)
2. Favorable quickstrike trade: own creature has `quickstrike` AND enemy creature ATK <
   own creature HP after dealing first-strike damage
3. Clean kill (same as always)
4. Stealthed own creature: prefer face damage to the hero over suicidal trades
5. Rest of priority unchanged

**Noob**: Random valid target.

### Swift Noob mistakes

- Plays chain cards first (wastes the trigger — no chain bonus)
- Does not value stealth creatures differently
- Attacks randomly (no quickstrike trade preference)

---

## Vital AI — Strategic Healing

### Heal threshold (differs by difficulty)

**Pro**:

```lua
local function healScore(ownHp, maxHp)
    if ownHp >= maxHp - 2 then return -1 end  -- full/near-full: waste
    if ownHp < maxHp * 0.4 then return +4 end -- critical: emergency
    if ownHp < maxHp * 0.65 then return +2 end -- damaged: good
    return 0                                   -- mild damage: neutral
end
```

Applied to any `heal` action targeting `own_hero`.

**Noob**: Heal always scores +1 regardless of HP. Heals even at full HP (common
beginner mistake, wastes a card for 0 net value).

### Scoring bonuses (Pro only)

| Situation | Card / Effect | Delta |
|---|---|---|
| `heal` with `area:"all"` or targeting friendlies | 2+ damaged allies | +3 |
| `heal` with `area:"all"` or targeting friendlies | 0 damaged allies | −2 (wasted AoE) |
| `lifesteal` keyword on creature | Any HP level | +3 (deals damage AND heals simultaneously) |
| `lifesteal=true` on `damage` effect | | +2 |
| `rebirth` keyword on creature | Enemy board has attacker | +3 (resilient blocker) |
| `rebirth` keyword on creature | Board is empty | +1 (less relevant) |
| `return_from_graveyard` effect | Graveyard (deadAllies) non-empty | +3 |
| `return_from_graveyard` effect | Graveyard empty | −3 (impossible to resolve, or already gated by playBlock) |
| Creature with `shatter` heal effect (moonbelly) | Board has dangerous attacker | +2 (will die → heal) |

### Vital attack behavior

**Pro**: Follow existing priority. Additional rule: **prefer lifesteal attacker** when
both a lifesteal creature and a non-lifesteal creature can make the same quality trade
(same kill, same trade outcome). Attacking with lifesteal = free HP even if it's just
face poke.

**Noob**: Random valid target.

### Vital Noob mistakes

- Heals even at full 30 HP
- Does not prefer lifesteal attackers
- Does not recognize return_from_graveyard as useless with empty graveyard

---

## DuelSession changes

`runNpcTurn` passes difficulty through:

```lua
-- DuelSession.lua
local difficulty = self.difficulty or "noob"
NpcAI.takeTurn(state, BattleLogic, "npc", difficulty)
```

`self.difficulty` set in `DuelSession.start(battleState, opts)` where `opts.difficulty`
comes from `BattleController.startPvE`.

---

## BattleController changes

`startPvE(player, opts)` already exists. Add `opts.difficulty` ("noob" | "pro"):

```lua
-- Example: two talk prompts or proximity prompts trigger different difficulties
BattleController.startPvE(player, { difficulty = "pro" })
```

The difficulty is stored on the `DuelSession` object and passed to `NpcAI.takeTurn`
each turn. No persistence needed — difficulty is per-session.

---

## Headless test plan

Run the headless sim with difficulty as a variable:

| Matchup | Expected direction |
|---|---|
| Noob Mighty vs Noob Swift | Roughly even (both random) |
| Pro Mighty vs Noob Mighty | Pro wins majority (board fill + armor awareness) |
| Pro Swift vs Noob Swift | Pro wins majority (chain turns more consistent) |
| Pro Vital vs Noob Vital | Pro wins majority (no wasted heals, lifesteal priority) |
| Pro Vital vs Pro Mighty | Should improve from current 11–4 Mighty-favored |
| Pro Vital vs Pro Swift | Should stay contested |

Track also: average `cardsPlayedThisTurn` for Swift Pro vs Noob (chain turns should
show higher averages).

---

---

## Trainer Dialogue System

### Studio setup (Workspace — no Lua file)

The three trainer models already exist in `Workspace/Trainers/`:

| Model name | Archetype |
|---|---|
| `MightyTrainer` | `MIGHTY` |
| `SwiftTrainer` | `SWIFT` |
| `VitalTrainer` | `VITAL` |

Each model needs one child: a `ProximityPrompt` with `ActionText = "Talk"` and
`MaxActivationDistance = 8`. Name convention is the contract — strip `"Trainer"` suffix
and uppercase to get the archetype string.

The existing card-table **Noob NPC is kept** as-is for quick testing. Trainers are an
additional entry point that runs through the dialogue flow before landing in the same
`startPvE` pipeline.

---

### DialogueUI (StarterGui — built in editor)

```
ScreenGui  "DialogueUI"  (Enabled = false, ResetOnSpawn = false, ZIndexBehavior = Sibling)
├── ClickCapture       TextButton, transparent, Size 1,0 / 1,0, ZIndex 2
│                      Full-screen invisible button: click during TYPING = skip to end;
│                      click during WAITING = advance to next segment
└── DialoguePanel      Frame, anchored bottom-center
    ├── DialogueText   TextLabel, wrapping, GothamMedium, large enough to hold 2–3 lines
    └── OptionsContainer  Frame, UIListLayout vertical (FillDirection=Vertical),
                           Visible=false, children are created/destroyed dynamically
```

No name plate or BillboardGui needed — the camera tween and typewriter text in the
ScreenGui are the full presentation.

---

### DialogueController.lua  `StarterPlayer/StarterPlayerScripts/DialogueController.lua`

Adapted from the diskmon reference. Key differences from that version:

- No `RequestDialogue` server call — dialogue data is defined client-side and passed in
- No `RewardSelectionUI` or `_partialClose` — not needed here
- No `NPCRegistry` — caller passes the trainer model directly
- Option `Action = "BATTLE"` fires `StartTrainerBattle` RemoteEvent then closes
- Option `Action = "CLOSE"` just closes

Public API (same shape as reference):

```lua
DialogueController:Open(trainerModel, dialogueData)
-- trainerModel: the Model instance from Workspace.Trainers
-- dialogueData: { Segments = {string,...}, Options = {{Label, Action},...} }

DialogueController:Advance()   -- called by ClickCapture or E-key
DialogueController:Close()
DialogueController.IsOpen      -- bool
```

Internal behaviour (matches reference):

| Step | What happens |
|---|---|
| `Open` | Freeze player (`WalkSpeed = 0`), hide character (LocalTransparencyModifier), tween camera toward trainer's HumanoidRootPart |
| Camera tween | `CameraType = Scriptable`; compute a position ~8 studs back, 2 studs high, 2.5 studs to the side; `TweenService` Quad 0.5 s |
| Typewriter | `task.spawn` loop, one character per 0.035 s; click-to-skip sets full text immediately |
| Options | Built dynamically in `OptionsContainer` after last segment finishes |
| `Close` | Tween camera back, restore `CameraType = Custom`, unfreeze player, show character, clear UI |

Constants (tune in implementation):

```lua
local TYPEWRITE_SPEED  = 0.035   -- seconds per character
local CAM_TWEEN_TIME   = 0.5
local CAM_DISTANCE     = 8
local CAM_HEIGHT_OFFSET = 2.0
local CAM_SIDE_OFFSET  = 2.5
```

---

### TrainerInteraction.lua  `StarterPlayer/StarterPlayerScripts/TrainerInteraction.lua`

LocalScript. Responsibilities:
1. Detect ProximityPrompt triggers on Trainers folder models
2. Look up static dialogue for that trainer
3. Wire E-key `Advance` while dialogue is open

```lua
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage      = game:GetService("ReplicatedStorage")
local UserInputService       = game:GetService("UserInputService")

local DialogueController = require(script.Parent.DialogueController)
local StartTrainerBattle = ReplicatedStorage.RemoteEvents:WaitForChild("StartTrainerBattle")

local TRAINERS_FOLDER = workspace:WaitForChild("Trainers")

-- Static dialogue data per trainer name
local DIALOGUES = {
    MightyTrainer = {
        Segments = {
            "Greetings, challenger! I am Gronak of the Ruby Bears.",
            "My bears are armored and unstoppable. Do you dare face them?",
        },
        Options = {
            { Label = "I accept your challenge!", Action = "BATTLE" },
            { Label = "Not right now.",           Action = "CLOSE"  },
        },
    },
    SwiftTrainer = {
        Segments = {
            "Oh? You noticed me. That is… unexpected.",
            "Emerald Cats strike before you can blink. Ready?",
        },
        Options = {
            { Label = "Let's go!",    Action = "BATTLE" },
            { Label = "Maybe later.", Action = "CLOSE"  },
        },
    },
    VitalTrainer = {
        Segments = {
            "Croaker, at your service. The Sapphire Frogs never fall.",
            "Healing flows endlessly here. Think you can outlast us?",
        },
        Options = {
            { Label = "I'll try!",    Action = "BATTLE" },
            { Label = "Not today.",   Action = "CLOSE"  },
        },
    },
}

ProximityPromptService.PromptTriggered:Connect(function(prompt)
    local model = prompt.Parent
    if not model or not TRAINERS_FOLDER:FindFirstChild(model.Name) then return end
    local dialogue = DIALOGUES[model.Name]
    if not dialogue then return end

    -- Inject BATTLE action: fire remote then close
    local enriched = { Segments = dialogue.Segments, Options = {} }
    for _, opt in dialogue.Options do
        local copy = { Label = opt.Label, Action = opt.Action }
        table.insert(enriched.Options, copy)
    end

    DialogueController:Open(model, enriched, function(action)
        if action == "BATTLE" then
            StartTrainerBattle:FireServer(model.Name)
        end
    end)
end)

UserInputService.InputBegan:Connect(function(input, processed)
    if processed then return end
    if input.KeyCode == Enum.KeyCode.E and DialogueController.IsOpen then
        DialogueController:Advance()
    end
end)
```

The `onAction` callback is a small addition to `DialogueController:Open` not in the
reference; it avoids the reference's `RequestDialogue` pattern while keeping option
dispatch clean.

---

### BattleController — `StartTrainerBattle` handler

```lua
-- New RemoteEvent: StartTrainerBattle (Client → Server), payload: trainerName (string)

local TRAINER_ARCHETYPE = {
    MightyTrainer = "MIGHTY",
    SwiftTrainer  = "SWIFT",
    VitalTrainer  = "VITAL",
}

local ARCHETYPE_DECK = {
    MIGHTY = "Mighty Starter",
    SWIFT  = "Swift Starter",
    VITAL  = "Vital Starter",
}

RemoteEvents.StartTrainerBattle.OnServerEvent:Connect(function(player, trainerName)
    -- Validate input
    local archetype = TRAINER_ARCHETYPE[trainerName]
    if not archetype then return end

    -- Prevent double-battle
    if BattleRegistry.PlayerBattle[player.UserId] then return end

    local npcDeckName = ARCHETYPE_DECK[archetype]
    startPvE(player, {
        npcDeckName = npcDeckName,
        difficulty  = "noob",       -- hardcoded until Pro trainers are added
        archetype   = archetype,    -- passed through to DuelSession → NpcAI
    })
end)
```

`startPvE` is updated to accept `opts.npcDeckName` (picks a specific starter deck instead
of randomizing) and `opts.archetype` (stored on the DuelSession for `NpcAI.takeTurn`).

---

### DuelSession — archetype + difficulty wiring

```lua
-- DuelSession stores opts on self at start:
self.difficulty   = opts.difficulty or "noob"
self.npcArchetype = opts.archetype  or nil   -- nil = auto-detect from deck

-- runNpcTurn:
NpcAI.takeTurn(state, BattleLogic, "npc", self.difficulty)
-- NpcAI.takeTurn internally calls detectNpcArchetype if self.npcArchetype is nil,
-- but can accept an explicit hint in a future refinement.
```

---

## Out of scope

- Pro-difficulty Trainer NPC characters in the world (difficulty param is ready; wire
  when design is locked)
- Trainer name plates, idle animations, or talk animations (model-side polish)
- Archetype-specific camera angles per trainer (current plan uses the same generic tween)
- Card-draw look-ahead beyond the Swift chain pre-pass (full tree search)
- Balance tuning of base card stats (separate Known Issue item)
