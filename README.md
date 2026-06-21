# Elemental TCG

A Roblox digital card battle game set inside a 3D TCG card shop. Players challenge NPC opponents at tables, engage in turn-based card battles, and collect cards as rewards.

**Engine:** Roblox Studio | **Language:** Luau | **Phase:** v0.1

---

## Documentation

| File | Purpose |
|---|---|
| [DESIGN_CORE.md](DESIGN_CORE.md) | Rules, archetypes, mechanics — single source of truth |
| [DESIGN_DATABASE.md](DESIGN_DATABASE.md) | Card data schema, effect structure, data architecture |
| [DESIGN_ENGINE.md](DESIGN_ENGINE.md) | Battle engine architecture and rework plan |
| [DESIGN_CARDS.md](DESIGN_CARDS.md) | Card design philosophy and pack catalog pointers |
| [DESIGN_BEAST.md](DESIGN_BEAST.md) | Affinities, races, and tribe structure |
| [DESIGN_ART.md](DESIGN_ART.md) | Art direction and visual identity |
| [DESIGN_UI.md](DESIGN_UI.md) | Battle UI layout and presentation |
| [DESIGN_PROGRESSION.md](DESIGN_PROGRESSION.md) | Rewards, mastery, collection |
| [IDEA_CARD_BATTLE.md](IDEA_CARD_BATTLE.md) | Battle UX & animation spec |
| [IDEA_MATCHMAKING.md](IDEA_MATCHMAKING.md) | Matchmaking architecture notes |
| [DEV_STATUS.md](DEV_STATUS.md) | Current implementation state |

---

## Project Structure (Roblox)

```
ReplicatedStorage/
  Definitions/
    Cards                 ← 90 cards across 4 packs (id-keyed Lua map, effects[] schema)
    Decks                 ← 3 starter decks expanded from deck_starter.json
    CrystalCores          ← 6 alpha deck-bound Core definitions + scaling
  Modules/
    CardSchema            ← Validator: fields, trigger/action/target vocabs, deck ids
    CardText              ← getAbilityDisplay(cardId), targetClass(card), canHitFace(card)
  Remotes/
    PlayCard, DeclareAttack, EndTurn, Forfeit, StandUp, ReadyUp, UseCore
    GetDecks, CreateDeck, SaveDeckCards, RenameDeck, DeleteDeck, SetActiveDeck
    UpdateBattleState, BattleOver, BattleSeated, BattleUnseated, BattleLoading
    (StartDuel, UseSkill, UsePlayerSkill orphaned migration artifacts)

ServerScriptService/
  Modules/
    Effects/
      Triggers            ← fireEvent dispatch bus
      Actions             ← Actions[action] handler registry
      Targeting           ← resolveTargets for all target/area combos
      Conditions          ← Conditions[type] gate checks
      Ops                 ← game-op mutation layer (damage/heal/buff/draw/kill/cost/…)
      Util                ← shared helpers (valueOf, creatureTargets, opp, …)
    BattleLogic           ← State, turn flow, combat; delegates effects to Effects/
    NpcAI                 ← effects[]-aware NPC scoring and targeting
    BattleRegistry        ← Battles[battleId], reverse index, perspective relabel
    DuelSession           ← Per-battle turn loop, human/NPC handoff, turn timers
    RewardService         ← Mode-aware reward payload policy (persistence-free)
    TableManager          ← Table/seat ownership, chained seating, PvE NPC bench
    SaveService           ← ProfileStore wrapper: profile lifecycle, schema v1.2, decks/active deck, migration, autosave
  Packages/
    ProfileStore          ← vendored session-locked DataStore lib (loleris, pinned 45c9847)
  BattleController        ← Thin remote-wiring → Registry/Session/TableManager + SaveService (v5)
  InventoryService        ← GetInventory RemoteFunction → player's saved collection
  DeckService             ← Deck remotes → create/save/rename/delete/set-active validation
  NpcSit                  ← retired (Disabled)

StarterPlayer/
  StarterPlayerScripts/
    ChairInteraction      ← retired/removed — seating moved to TableManager

StarterGui/
  BattleUI/
    BattleUIController    ← Board render, Core panel/preview/drag, hand, camera, post-battle screen
    Modules/
      CardVisuals         ← buildCardFrame / updateCardFrame; spell circle; left emblems
      CardPreviewController ← Board card hover/hold preview
      TargetingSystem     ← Drag-to-play, drag-to-attack, and Core targeting highlights
      GraveLogPanel       ← Discard history
      UXMode              ← Desktop/Mobile reactive toggle
  Hud/                    ← world HUD (top-right icon anchor; hidden in battle)
    HudController         ← anchor visibility per battle state
    TopRightAnchor        ← hosts world icons (Inventory icon = layered outline)
  InventoryUI/           ← Card Library page stack: Home, My Cards, Deck List, Core Select, Deck Editor
    InventoryController   ← collection browser + deck builder client

Workspace/
  Battle Tables/
    Battle Table 1, 2     ← each: Chair 1/Seat, Chair 2/Seat, runtime surface TablePrompt
  Noob                    ← standing PvE NPC (anchored); TalkPrompt
  (BenchNpc)              ← transient Noob clone seated opposite during a PvE battle
```
(The old `DuelTable`/`NPCChair`/`PlayerChair` rig was retired.)
