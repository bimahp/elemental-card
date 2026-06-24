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
| [PLAN_ASSET_LOADING.md](PLAN_ASSET_LOADING.md) | Reliable asset preloading and branded loading screen validation |
| [PLAN_BATTLE_CHARGE.md](PLAN_BATTLE_CHARGE.md) | Crystal Core removal and two-slot Battle Charge migration |
| [PLAN_BATTLE_CHARGE_USAGE.md](PLAN_BATTLE_CHARGE_USAGE.md) | Charge costs on cards, CORRUPTED trait, hybrid/pure-Charge cost models, CardTraits/CardCost shared modules |

---

## Project Structure (Roblox)

```
ReplicatedStorage/
  Definitions/
    Cards                 ← 90 cards across 4 packs (id-keyed Lua map, effects[] schema); 2 carry chargeCost (ruby_mauler hybrid, rubyhide_bear Corrupted pure-charge)
    Decks                 ← 3 starter decks expanded from deck_starter.json
    CrystalCores          ← orphaned (Crystal Core removed; replaced by Battle Charge)
  Modules/
    CardSchema            ← Validator: fields, trigger/action/target vocabs, chargeCost, deck ids
    CardText              ← getAbilityDisplay(cardId), targetClass(card), canHitFace(card)
    ChargeConfig          ← Battle Type palette + Charge-producing rules (server + client SSOT)
    CardTraits            ← has(card, trait) — scans effects[] for passive trait by action name (e.g. "corrupted")
    CardCost              ← shared server+client cost helper: canPay, getCostParts, failureReason (all 3 cost models)
    AssetIds              ← Gameplay/UI image asset manifest (+ ChargeEmblems); criticalList() preload gate
    AssetPreloader        ← Instance-based image preloader with retry
  Remotes/
    PlayCard, DeclareAttack, EndTurn, Forfeit, StandUp, ReadyUp
    GetDecks, CreateDeck, SaveDeckCards, RenameDeck, DeleteDeck, SetActiveDeck
    UpdateBattleState, BattleOver, BattleSeated, BattleUnseated, BattleLoading
    (StartDuel, UseSkill, UsePlayerSkill, UseCore orphaned migration artifacts)

ReplicatedFirst/
  LoadingScreen           ← Branded zero-remote-asset loading GUI; preloads critical art

ServerScriptService/
  Modules/
    Effects/
      Triggers            ← fireEvent dispatch bus
      Actions             ← Actions[action] handler registry (incl. gain_charge)
      Targeting           ← resolveTargets for all target/area combos
      Conditions          ← Conditions[type] gate checks
      Ops                 ← game-op mutation layer (damage/heal/buff/draw/kill/cost/charge/…)
      Util                ← shared helpers (valueOf, creatureTargets, opp, …)
    ChargeState           ← authoritative two-slot Battle Charge state machine
    BattleLogic           ← State, turn flow, combat, +1 played Charge; delegates effects to Effects/
    NpcAI                 ← effects[]-aware NPC scoring and targeting (no Core)
    BattleRegistry        ← Battles[battleId], reverse index, perspective relabel
    DuelSession           ← Per-battle turn loop, human/NPC handoff, turn timers
    RewardService         ← Mode-aware reward payload policy (persistence-free)
    TableManager          ← Table/seat ownership, chained seating, PvE NPC bench
    SaveService           ← ProfileStore wrapper: profile lifecycle, schema v1.3 (Core-free decks), decks/active deck, migration, autosave
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
    BattleUIController    ← Board render, hero card + Charge slots/animation, hand, camera, post-battle screen
    Modules/
      CardVisuals         ← buildCardFrame / updateCardFrame; spell circle; left emblems (TC_type ← ChargeConfig)
      CardPreviewController ← Board card hover/hold preview
      TargetingSystem     ← Drag-to-play and drag-to-attack (Core targeting removed)
      GraveLogPanel       ← Discard history
      UXMode              ← Desktop/Mobile reactive toggle
  Hud/                    ← world HUD (top-right icon anchor; hidden in battle)
    HudController         ← anchor visibility per battle state
    TopRightAnchor        ← hosts world icons (Inventory icon = layered outline)
  InventoryUI/           ← Card Library page stack: Home, My Cards, Deck List, Deck Editor (no Core Select)
    InventoryController   ← collection browser + Core-free, Charge-aware deck builder client

Workspace/
  Battle Tables/
    Battle Table 1, 2     ← each: Chair 1/Seat, Chair 2/Seat, runtime surface TablePrompt
  Noob                    ← standing PvE NPC (anchored); TalkPrompt
  (BenchNpc)              ← transient Noob clone seated opposite during a PvE battle
```
(The old `DuelTable`/`NPCChair`/`PlayerChair` rig was retired.)
