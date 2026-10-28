# Elemental TCG — Code Architecture

**Status:** architecture of record; module tree, remotes, constants and persistence checked against the Studio place on 2026-10-29.

**Owns:** where code lives, the module layout, the battle engine, networking, persistence and the tooling rules.
**Does not own:** rules ([GAME_DESIGN.md](GAME_DESIGN.md)); card fields and effect vocabulary ([CARDS.md](CARDS.md) §5); values ([MONETIZATION.md](MONETIZATION.md)); screens ([docs/UI.md](UI.md)).

---

## 1. Where the code is

- **All game code lives in the Roblox Studio place.** There is no Rojo and no code in this repo; it is read and changed through the Roblox Studio MCP.
- This repo holds the docs, the card data ([data/](../data/)), the vendored ProfileStore source ([vendor/](../vendor/)) and, outside git, the art in `assets/`.
- **Editor-first UI.** Every UI element is a real instance authored in Studio under `StarterGui`. Code clones, fills and switches state; it does not build GUI with `Instance.new`.

## 2. Principles

1. **The server is the authority.** Clients send intents; the server validates every action, owns all state and broadcasts sanitized, per-player views. Clients never send a battle id.
2. **Cards are data.** Behaviour comes from `effects[]`. A new card mechanic needs only a new `Actions` handler and/or a new condition or trigger, never edits to combat, turn flow or a big switch. If a new card forces a change to `BattleLogic`'s core, the abstraction has leaked.
3. **Animation never affects rules.** The server resolves immediately and never waits for the client. A skipped or late animation snaps to the authoritative state.
4. **One config surface per system.** Shared values live in one module read by server and client (`ChargeConfig`, `RewardConfig`, `GachaConfig`, `VendorConfig`, `LevelConfig`, `TitleConfig`, `QuestConfig`, `AssetIds`).
5. **Pure rules, one mutator.** Rule modules (`RewardService`, `VendorTransaction`, `GachaTransaction`, `TitleService`) compute plans without touching profiles; `SaveService` is the only module that mutates a profile.
6. **Remote functions answer** `{ ok = true, data = … }` or `{ ok = false, error = … }`.

## 3. Module layout

```text
ReplicatedStorage/
  Definitions/
    Cards              132 pack cards + the_coin, id-keyed (runtime canonical)
    Decks              3 starter decks, generated from data/deck_starter.json
    CrystalCores       orphaned (Crystal Core removed)
  Modules/
    CardSchema         validates cards and decks on load
    CardText           ability text from effects[]; playTarget(card)
    CardData           client shim: Cards + CardText helpers
    CardCost           shared cost helper: canPay, getCostParts, failureReason (all 3 cost models)
    CardTraits         has(card, trait), legacy passive traits
    ChargeConfig       Charge-producing types, MAX_SLOTS = 2, Battle Type palette
    RewardConfig       every reward value, cap and validity constant
    GachaConfig        pack price, rarity weights, duplicate rules
    VendorConfig       Craft / Buy / Recycle rates, stock rotation
    ShopConfig         Robux products (legacy bundle sizes)
    LevelConfig        EXP table, levels 1–100
    QuestConfig        quest ids and stage definitions
    TitleConfig        title catalog and milestone requirements
    AssetIds           image manifest: startup list, exact-five reveal list, audit list
    AssetPreloader     dense-array preload with per-id retries
    UITheme            shared UI theme values
  Remotes/             (§7)

ReplicatedFirst/
  LoadingScreen        branded loading; gates only immediately needed images

ServerScriptService/
  Modules/
    Effects/
      Triggers         fireEvent dispatch; playBlock pre-play check
      Actions          Actions[action] handler registry
      Targeting        resolves target/area; guards chosen descriptors
      Conditions       Conditions[type] gates
      Ops              state mutations: damage, heal, kill + rebirth, draw, costs, Charge ops, anim events
      Util             BOARD_SIZE, opp, valueOf, …
    ChargeState        authoritative two-slot Battle Charge state machine
    BattleLogic        state, turn flow, combat; delegates effects to Effects/
    NpcAI              effects-aware play scoring and attack choice
    BattleRegistry     Battles[battleId], player index, spectators, perspective relabel
    DuelSession        per-battle loop: deal, mulligan, turns, timers, human/NPC handoff
    TableManager       table/seat ownership, chained seating, NPC bench
    Matchmaker         cross-server queue, destination selection, match creation, reconnect
    ServerRegistry     per-server free-table heartbeat (hint only)
    RewardService      pure battle-reward classifier
    SaveService        ProfileStore wrapper; the only profile mutator
    QuestService       quest stage reads/writes
    TitleService       title reconciliation and equip validation
    GachaService, GachaTransaction       pack rolls and atomic purchase
    VendorService, VendorTransaction     stock rotation; craft / buy / recycle
    ShopTransaction                      receipt dedupe and grants
  Packages/
    ProfileStore       vendored (loleris, pinned 45c9847; source copy in vendor/)
  BattleController     thin remote wiring for battles, matchmaking and rewards
  InventoryService     GetInventory
  DeckService          deck remotes and validation
  GachaController      proximity-checked, rate-limited pack purchase
  VendorController     Vendor remotes (Craft/Buy need proximity; Recycle does not)
  RobuxShopController  ProcessReceipt, persisted acknowledgement
  PlayerStatusController  GetPlayerStatus / EquipTitle
  NameplateService     NPC nameplates

StarterPlayer/StarterPlayerScripts/
  DialogueController   shared typewriter + camera dialogue (Noob, Trainers, Vendor)
  TrainerInteraction   onboarding starter-deck choice
  QuestHUDController   quest arrow, ! marks, Noob dialogue
  VendingMachineController, PackRevealController, CameraCardStage   pack purchase and 3D reveal
  VendorUIController   Card Vendor dialogue and shop
  MatchmakingController, MulliganController, ItemMallController
  PlayerStatusUIController, NameplateController

StarterGui/
  BattleUI/            BattleUIController + Modules: CardVisuals, BattleDirector, PhaseRegistry,
                       EffectVisuals, TargetingSystem, CardPreviewController, GraveLogPanel, UXMode,
                       SeatedOverlayController, PostBattleController
  SharedUI/            UIComponents (shared widgets built on UITheme)
  MulliganUI, MatchmakingUI, PlayerStatusUI, InventoryUI (Card Library + Recycle),
  VendingMachineUI, PackOpenUI, VendorUI, ItemMallUI, DialogueUI, QuestHUD,
  Hud (HudController, CurrencyBarController)

Workspace/
  Battle Stations/     1–9: the tables (Chair 1, Chair 2, Table); TableManager adds a TablePrompt
  Noob, Trainers/ (Trainer Mighty / Swift / Vital), Card Merchant (the Card Vendor), Card Vending Machine

TestService/           GachaOddsSpec, GachaAcquisitionSpec, ShopTransactionSpec, PlayerStatusSpec
```

## 4. The battle engine

### 4.1 Card instances

On summon, the definition's `effects` and `keywords` are deep-copied into the instance, so buffs and granted keywords never touch the shared definition.

```lua
{ cardId, name, atk, hp, maxHp, tempAtk, battleType, race,
  keywords = {...}, effects = {...},
  attackedThisTurn, summonedThisTurn, rebornUsed }
```

Each side also holds the Charge state (`chargeSlots`, `currentChargeSlot`, `chargeSeq`, pending Charge events), `chargeCostMods`, the graveyard (`deadAllies`) and Fatigue.

### 4.2 Triggers

`Triggers.fireEvent(state, event, ctx)` is the single dispatch. It finds the cards the event concerns, walks their `effects[]`, and calls `Actions[entry.action](ctx)` for each entry whose trigger matches and whose condition passes. Handlers receive `{ state, sourceWho, source, entry, targets, event }`.

| Event | Whose effects fire |
|---|---|
| `emerge`, `cast` | the summoned creature / the spell |
| `shatter` | the dying creature |
| `deal_damage`, `take_damage` | the dealer / the damaged creature |
| `attacked` | the defender |
| `turn_end` | all of that owner's creatures |
| `ally_death` | the surviving allies |

`chain` is not its own event: it is `emerge`/`cast` gated by `cardsPlayedThisTurn >= 2`. Cost modifiers (`hand`, `drawn_cards`, `returned_card`) are tracked by `Ops`; the effective cost is the base minus reductions, or the set value, never below 0.

### 4.3 Playing a card

`BattleLogic.playCard` checks and pays Energy and the effective Charge cost atomically through `CardCost`, then fires the triggers. For spells, `Triggers.playBlock` first dry-runs the effects (targets and conditions only) and returns a player-facing reason such as *No Wounded Ally*; a blocked spell is refused before anything is spent. The reason reaches the client in a transient `warnings` array on the next state broadcast.

### 4.4 Targeting

- `playTarget` (spell field) decides the drop surface; effect `target`s decide what the rules resolve.
- Chosen targets arrive as `PlayCard(cardId, { target = { side, slot } })` from the client's perspective (`slot = 0` is a hero); zone drops as `PlayCard(cardId, { zone = "enemy_board" })`; creatures as `{ slot = N }`.
- The server remaps perspective to battle seats and rejects malformed descriptors, illegal target kinds, Stealthed enemy targets and zones that do not match the spell's `playTarget`, all before the card is consumed. `Targeting` guards chosen descriptors again; random and area targets resolve on the server.
- `chosenZone` is threaded through resolution for future zone-aware effects.

### 4.5 Battle Charge

`ChargeState` owns `init`, `gainCharge`, `canSpendCharge`, `spendCharge`, `canGainWithoutReplace`, `destroySlot`, `drainCharge` and the change events. End-turn board generation uses `canGainWithoutReplace`, so it never replaces a slot. `ChargeConfig` is the shared list of producing types.

## 5. Battle sessions

- `BattleRegistry` keeps `Battles[battleId]` and a reverse index by player, and produces per-recipient views in which the recipient's own seat is always `player`.
- `DuelSession.start` deals the hands and opens the mulligan stage (`OfferMulligan`, `RedrawMulliganCard`, `ConfirmMulligan`, per-seat timeout tokens, `MULLIGAN_TIMEOUT_SECONDS = 30`), then grants the Coin and runs the turn loop. Human turns are guarded by a token-based timer (`TURN_TIMEOUT_SECONDS = 60`, `MAX_TIMEOUTS_BEFORE_FORFEIT = 2`); NPC turns run `NpcAI.takeTurn` after a 0.7 s pause. `state.turnNumber` increases by one per player turn.
- Battle modes on the record: `battle.mode` is `"pvp"` or `"pve"`; `battle.matchmaking` marks matchmaking battles (real or NPC fallback); `battle.isTutorial` marks the onboarding battle; `battle.difficulty` is always `"noob"` today. `RewardService` derives the reward category (Matchmaking / Local / NPC) from these.
- `TableManager` owns table state (FREE, RESERVED, OCCUPIED), seating and each `TablePrompt.Enabled`. While a player is seated or in battle, the client hides all world prompts for itself with `ProximityPromptService.Enabled = false` (`BattleUIController.setTablePromptsSuppressed`) and never writes a prompt's own `Enabled`, so the server's table state always wins.
- Seating uses the chair's `SeatWeld` with chained `awaitSeated` and no anchoring; jumping and controls are blocked while seated. **`TableManager` alone moves the character off the chair** after the battle; the client never teleports it, so a late callback cannot drag a Seat through the weld.

## 6. Presentation

- The server records an ordered, perspective-relabelled **event log** (`animEvents`, via `Ops.recordAnim`) and sends it with each `UpdateBattleState`, then clears it.
- The client's `BattleDirector` is a FIFO queue of phases with one `isLocked()` input gate, a per-phase timeout and a `skip()` that cancels tracked tweens. `PhaseRegistry` holds one handler per phase type (`draw`, `play`, `attack`, `turn_banner`, `cast_reveal`, `effect`), mirroring the server's `Actions` registry.
- `EffectVisuals.resolveVisualArchetype(entry, card)` picks an effect's VFX from its action, target and area, with an optional `card.vfx` override. Only `projectile` has a handler so far.

## 7. Networking

| Remote | Dir | Payload / notes |
|---|---|---|
| `PlayCard` | C→S | `cardId, opts` (`{slot}`, `{target={side,slot}}` or `{zone}`) |
| `DeclareAttack` | C→S | `attackerSlot, targetSlot` |
| `EndTurn`, `Forfeit`, `StandUp`, `ReadyUp` | C→S | none |
| `OfferMulligan` | S→C | the dealt 5-card hand |
| `RedrawMulliganCard` | RF | 1-based hand index → `true, newCardId` or `false, reason`; once per seat |
| `ConfirmMulligan` | C→S | none |
| `UpdateBattleState` | S→C | sanitized view; `costMods`; `animEvents`; timer (`serverNow`, `turnStartedAt`, `turnEndsAt`, `turnDuration`, `timeoutStreaks`); `warnings`; Charge fields |
| `BattleOver` | S→C | `{ winner, rewards }` with the reward plan (record, Fragments, first-clear bonus, EXP) |
| `BattleLoading`, `BattleSeated`, `BattleUnseated` | S→C | table flow overlays |
| `JoinMatchmaking`, `CancelMatchmaking` | C→S | none |
| `MatchmakingUpdate` | S→C | `queued`, `cancelled`, `matched` |
| `BattleReconnected` | S→C | full view, resumes an active matchmaking battle |
| `Notify` | S→C | free-roam toast |
| `GetInventory` | RF | the player's collection |
| `GetDecks`, `CreateDeck`, `SaveDeckCards`, `RenameDeck`, `DeleteDeck`, `SetActiveDeck` | RF | deck management |
| `OpenCardPack` | RF | pack purchase |
| `GetVendorStock`, `CraftCard`, `BuyCard`, `DestroyCards` | RF | Vendor and Recycle (`DestroyCards` aggregates rows before validating) |
| `GetQuestSnapshot`, `QuestStateChanged`, `ChooseStarterDeck`, `RequestTutorialBattle`, `ShowNoobDialogue` | mixed | onboarding |
| `StartTrainerBattle` | C→S | Trainer model name; only after onboarding is complete |
| `LevelUp` | S→C | `{ newLevel }`; the level also replicates as a `Level` IntValue on the Player |
| `GetPackOdds` | RF | live per-card odds for the Vending Machine |
| `GetMonetizationPolicy` | RF | `{ itemMallAllowed, arePaidRandomItemsRestricted }` from `PolicyService` |
| `GetPlayerStatus`, `EquipTitle` | RF | Profile panel; equipped title replicates as the Player attribute `EquippedTitleId` |

**Orphaned, no handler:** `StartDuel`, `UseSkill`, `UsePlayerSkill`, `UseCore`. Delete in a cleanup pass.

Battle remotes are lightly rate-limited and derive the seat server-side. Shop remotes check proximity to their NPC or machine (except `DestroyCards`, reachable from the Card Library anywhere).

## 8. Matchmaking

- **Queue:** a `MemoryStoreQueue` (`MM_Queue_v2`) shared by all servers, with two HashMaps: `MM_QueueState_v2` (per-player tokenized queue state, so cancel and requeue cannot collide) and `MM_PendingMatches_v2` (match records, 180 s TTL). Each server with queued players polls every 4–6 s (jittered); empty servers make no queue reads. MemoryStore pops are atomic, so only one server gets a pair.
- **Registry:** each server publishes its free-table count to a `MemoryStoreSortedMap` every 10 seconds. It is only a hint for choosing a destination.
- **Destination is truth:** the chosen server re-checks its own tables when players arrive and finds another table if the hinted one is gone. A partner who has not arrived within 30 s turns the match into an NPC fallback for the player who did.
- **No public server with a free table:** the match is not created (`no_public_destination`) and the players stay queued for the next poll. `ReserveServer` is not used.
- **Reconnect:** `activeMatch` stores the battle's `jobId` and mode. On login, a player with an active matchmaking battle is teleported (`TeleportAsync` to that JobId) or re-seated on the same server (`BattleRegistry.reconnectSeat`) and receives `BattleReconnected`.
- In unpublished Studio Play `game.JobId` is empty; `ServerRegistry` guards for it.

## 9. Persistence

- **ProfileStore**, store `"PlayerProfiles"`, key `Player_<UserId>`. Session-locked: `StartSessionAsync` on join, migrate before `Reconcile`, `EndSession` on leave, kick on a stolen session.
- **Schema v5.4:** `_version`, `archetype`, `collection` (card-id multiset), `decks`, `activeDeckId`, `cardFragments`, `crystalShards`, `purchaseHistory`, `exp`, `level`, `pvp` (wins, losses), `activeMatch` (with `jobId`, `mode`), `quests`, `dailyRewards` (day-bucketed `battleFragments`, `npcFragments`, `forfeitCount`), `matchmakingCooldownUntil`, `pveFirstClear` (per archetype), `ownedTitles`, `equippedTitle`.
- **Migrations:** minor bumps run a `MINOR_MIGRATIONS` step and keep data; a major bump is a guarded hard reset to a fresh profile (`ALLOW_MAJOR_RESET`); a profile from a newer version is served as-is.
- **Saving:** a dirty flag pools saves every 60 seconds; ProfileStore's own autosave (about 300 seconds) is the backstop. Pack purchases, rewards and the start of a PvP match force a save.
- **Abandon detection:** `beginMatch` (PvP and matchmaking battles, at mulligan start) flags the players with `battleId`, `jobId`, `mode` and `startedAt`, and force-saves. On the next login a still-set flag first tries to reconnect (§8); otherwise it records a PvP loss (no penalty for an NPC fallback). Flags older than an hour skip the reconnect attempt. Exactly one loss either way.
- **Daily counters** (`dailyRewards`) use a UTC day bucket and reset lazily on the next read.
- **New players** start empty; onboarding grants the chosen starter collection and active deck. A profile that finished onboarding but has no deck gets the Mighty starter back.

## 10. Testing and tooling

- Specs live in `TestService` (for example `GachaOddsSpec`, `GachaAcquisitionSpec`, `ShopTransactionSpec`, `PlayerStatusSpec`). Pure modules are tested headless with `execute_luau`; anything touching a real `Player`, profile or client UI is tested in Studio Play through real remotes.
- **`execute_luau` runs in an isolated VM**, in Edit and Play, Server included. It cannot read live module state (for example `SaveService` profiles). Use in-script `print` plus `get_console_output`, or real remotes.
- **`multi_edit` with `replace_all` can silently apply only some occurrences** while reporting success. Always verify `Script.Source` afterwards.
- **`screen_capture` may not show `PlayerGui` UI.** Verify UI through instance properties (`Visible`, `AbsolutePosition`, `AbsoluteSize`, `Text`).
- **Luau has a 200-local limit per function.** `BattleUIController` hit it; group new references into tables and scope one-time setup in `do … end`.
- Cross-server teleport and reconnect cannot be exercised in Studio; they need a published-place test.

## 11. Legacy

| Item | State |
|---|---|
| `Definitions/CrystalCores`, `UseCore` | Orphaned since the Battle Charge migration |
| `StartDuel`, `UseSkill`, `UsePlayerSkill` remotes | Orphaned |
| `NpcSit`, `ChairInteraction` | Retired (scripts disabled); replaced by `TableManager` |
| Code comments | Many scripts cite `DESIGN_REWARD.md`, `DESIGN_ECONOMY.md` and other archived docs; read them as pointers to MONETIZATION and GAME_DESIGN |
| `corrupted` trait, `CardTraits` | Kept for schema compatibility; no current card uses it |
| `Gacha*` names | The pack system; "gacha" names are historical, nothing is paid-random |
| Removed for good | Invoker, Crystal Core hero power, the old 32-card `CardData`, Equipment, `combo_extra_attack`, Crystal Dust |
