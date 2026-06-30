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
| [DESIGN_CARD_ACQUISITION.md](DESIGN_CARD_ACQUISITION.md) | Pack-system research reference and project implementation note |
| [IDEA_CARD_BATTLE.md](IDEA_CARD_BATTLE.md) | Battle UX & animation spec |
| [IDEA_MATCHMAKING.md](IDEA_MATCHMAKING.md) | Matchmaking architecture notes |
| [DEV_STATUS.md](DEV_STATUS.md) | Current implementation state |
| [PLAN_ASSET_LOADING.md](PLAN_ASSET_LOADING.md) | Reliable asset preloading and branded loading screen validation |
| [PLAN_BATTLE_CHARGE.md](PLAN_BATTLE_CHARGE.md) | Crystal Core removal and two-slot Battle Charge migration |
| [PLAN_BATTLE_CHARGE_USAGE.md](PLAN_BATTLE_CHARGE_USAGE.md) | Charge costs on cards, hybrid/pure-Charge cost models, CardTraits/CardCost shared modules |
| [PLAN_BATTLE_CHARGE_V2.md](PLAN_BATTLE_CHARGE_V2.md) | Board-generated Battle Charge, redesigned packs/starters, and new Charge interaction actions |
| [PLAN_BATTLE_TARGET.md](PLAN_BATTLE_TARGET.md) | Explicit spell `playTarget` targeting revamp and drag/drop zone model |
| [PLAN_CARD_ACQUISITION.md](PLAN_CARD_ACQUISITION.md) | Implemented Card Vending Machine, atomic purchase flow, reveal UI, and verification |
| [PLAN_MONETIZATION.md](PLAN_MONETIZATION.md) | Planned duplicate-aware pack odds, Vending Machine UI revamp, currency HUD, and policy-gated Robux Shard mall |

---

## Project Structure (Roblox)

```
ReplicatedStorage/
  Definitions/
    Cards                 ← 132 pack cards across 4 packs + the_coin (id-keyed Lua map, effects[] schema); spells carry explicit playTarget; 29 carry pure chargeCost
    Decks                 ← 3 starter decks expanded from deck_starter.json
    CrystalCores          ← orphaned (Crystal Core removed; replaced by Battle Charge)
  Modules/
    CardSchema            ← Validator: fields, trigger/action/target/playTarget vocabs, playTarget compatibility, chargeCost, deck ids
    CardText              ← getAbilityDisplay(cardId), playTarget(card)
    CardData              ← client shim: Cards + CardText getAbilityDisplay/playTarget
    ChargeConfig          ← Battle Type palette + Charge-producing rules (server + client SSOT)
    CardTraits            ← has(card, trait) — legacy passive-trait helper; corrupted support retained for compatibility
    CardCost              ← shared server+client cost helper: canPay, getCostParts, failureReason (all 3 cost models)
    AssetIds              ← Gameplay/UI image manifest; startup, exact-reveal, and full-audit lists
    AssetPreloader        ← Dense-array preload contract; callback-verified per-ID retries
    GachaConfig           ← Shared pack cost/count/odds/Dust/distance/cooldown configuration
  Remotes/
    PlayCard, DeclareAttack, EndTurn, Forfeit, StandUp, ReadyUp
    PlayCard opts: {slot=N}, {target={side,slot}}, or {zone="enemy_board"|...}
    GetDecks, CreateDeck, SaveDeckCards, RenameDeck, DeleteDeck, SetActiveDeck
    OpenCardPack, GetQuestSnapshot
    UpdateBattleState, BattleOver, BattleSeated, BattleUnseated, BattleLoading
    (StartDuel, UseSkill, UsePlayerSkill, UseCore orphaned migration artifacts)

ReplicatedFirst/
  LoadingScreen           ← Branded loading GUI; gates only immediately needed shared assets

ServerScriptService/
  Modules/
    Effects/
      Triggers            ← fireEvent dispatch bus
      Actions             ← Actions[action] handler registry (incl. charge slot effects and hand charge-tax)
      Targeting           ← resolveTargets for all target/area combos
      Conditions          ← Conditions[type] gate checks
      Ops                 ← game-op mutation layer (damage/heal/buff/draw/kill/cost/charge/…)
      Util                ← shared helpers (valueOf, creatureTargets, opp, …)
    ChargeState           ← authoritative two-slot Battle Charge state machine
    BattleLogic           ← State, turn flow, combat, end-turn board Charge generation; delegates effects to Effects/
    NpcAI                 ← effects[]-aware NPC scoring and targeting (no Core)
    BattleRegistry        ← Battles[battleId], reverse index, perspective relabel
    DuelSession           ← Per-battle turn loop, human/NPC handoff, turn timers
    RewardService         ← Mode-aware reward payload policy (persistence-free)
    TableManager          ← Table/seat ownership, chained seating, PvE NPC bench
    GachaTransaction      ← Atomic shard/card/Dust mutation with same-pack two-copy enforcement
    GachaService          ← Unified 132-card weighted roll generator
    SaveService           ← ProfileStore wrapper: schema v5.0, canonical-ID reset, decks, quests, currency, atomic pack purchase, autosave
  Packages/
    ProfileStore          ← vendored session-locked DataStore lib (loleris, pinned 45c9847)
  BattleController        ← Thin remote-wiring → Registry/Session/TableManager + SaveService (v5)
  InventoryService        ← GetInventory RemoteFunction → player's saved collection
  DeckService             ← Deck remotes → create/save/rename/delete/set-active validation
  GachaController         ← Proximity-validated, throttled OpenCardPack server boundary
  NpcSit                  ← retired (Disabled)

StarterPlayer/
  StarterPlayerScripts/
    ChairInteraction      ← retired/removed — seating moved to TableManager
    VendingMachineController ← prompt ownership, authoritative purchase, and modal lifecycle
    PackRevealController     ← gameplay-modal 3D reveal; movement/prompt lock, burst, controls, results
    CameraCardStage          ← camera-space Parts, live SurfaceGui faces, projection and cleanup

StarterGui/
  BattleUI/
    BattleUIController    ← Board render, hero card + Charge slots/animation, hand, camera, post-battle screen
    Modules/
      CardVisuals         ← buildCardFrame / updateCardFrame; spell circle; left emblems (TC_type ← ChargeConfig)
      CardPreviewController ← Board card hover/hold preview
      TargetingSystem     ← Drag-to-play via playTarget zones, zone-drop opts, and drag-to-attack (Core targeting removed)
      GraveLogPanel       ← Discard history
      UXMode              ← Desktop/Mobile reactive toggle
  Hud/                    ← world HUD (top-right icon anchor; hidden in battle)
    HudController         ← anchor visibility per battle state
    TopRightAnchor        ← hosts world icons (Inventory icon = layered outline)
  InventoryUI/           ← Card Library page stack: Home, My Cards, Deck List, Deck Editor (no Core Select)
    InventoryController   ← collection browser + Core-free, Charge-aware deck builder client
  VendingMachineUI/      ← pack confirmation, cost, authoritative balance and errors
  PackOpenUI/            ← Crystal burst, rigid 3D card stack, five-card results and Claim

Workspace/
  Battle Tables/
    Battle Table 1, 2     ← each: Chair 1/Seat, Chair 2/Seat, runtime surface TablePrompt
  Noob                    ← standing PvE NPC (anchored); TalkPrompt
  Card Vending Machine/   ← named InteractionAnchor prompt + separate world OfferDisplay
  (BenchNpc)              ← transient Noob clone seated opposite during a PvE battle
```
(The old `DuelTable`/`NPCChair`/`PlayerChair` rig was retired.)
