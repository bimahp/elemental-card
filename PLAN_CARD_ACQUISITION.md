# PLAN — Card Vending Machine (Gacha)

## Implementation status — completed and verified 2026-06-29

> Successor planning note (2026-07-01): `PLAN_MONETIZATION.md` plans the next
> Vending Machine UI, live per-draw odds, same-rarity duplicate protection, and
> policy-gated Robux Shard mall. Those additions are not part of this completed
> implementation record. The successor must also remove the temporary `125`
> Shard-on-login test override below before any paid currency is enabled.

The implementation now uses the display name's canonical card ID throughout and
SaveService schema **v5.0**. The earlier v4.1-only notes below are historical; v5.0
performs the intentional profile reset required by the canonical-ID migration.

Final architecture corrections made during review:

- `ReplicatedStorage.Modules.GachaConfig` is the shared source for cost, pack size,
  odds, duplicate Dust, interaction distance, and server cooldown.
- `ServerScriptService.Modules.GachaTransaction` validates and commits shard
  deduction, collection additions, and Dust as one synchronous transaction.
- Same-pack repeats use provisional ownership counts, so a collection can never
  exceed two copies; later repeats in that pull become Dust.
- `GachaController` validates distance to
  `Workspace.Card Vending Machine.InteractionAnchor`, applies a cooldown, and uses
  `xpcall` so the per-player rolling lock always clears.
- The prompt is attached to that dedicated front anchor. A separate
  `OfferDisplay` carries the world SurfaceGui so it cannot hide or intercept the
  ProximityPrompt.
- The client fetches an authoritative snapshot whenever the panel opens and uses
  the balances returned by `OpenCardPack`; it never guesses the post-purchase
  balance locally.
- `VendingMachineController` owns the prompt lock, `PackRevealController` owns the
  modal state, and `CameraCardStage` owns client-only 3D cards and camera projection.
- Five thin Parts carry live front/back SurfaceGuis. They rotate rigidly around Y;
  front emblems remain hidden until 80% and fade to their authored opacity.
- Before constructing those SurfaceGuis, `PackRevealController` callback-verifies
  the shared reveal assets and exact artwork for the five server-returned cards.
  It shows a modal `Preparing cards…` progress state during this bounded gate.
- The reveal is a gameplay modal, not only a GUI modal: PlayerModule movement is
  disabled, movement/jump actions are sunk at high priority, and all current or
  newly-added ProximityPrompts are locally suppressed until Claim/cleanup. Original
  prompt and jump states are restored afterward, including across respawn.
- The opening Crystal burst scales from the current viewport diagonal: 36–58
  large Energy-emblem particles travel beyond the screen edges on desktop/mobile.
- A padded transparent front adorner and the existing summary gutters preserve
  intentionally overflowing emblems without exposing them on the card back.
- `TestService.GachaAcquisitionSpec` deterministically verifies the 132-card pool,
  five-card generation, insufficient-funds atomicity, invalid-roll atomicity, and
  the same-pack duplicate cap/Dust conversion.
- **Temporary testing override:** SaveService sets Crystal Shards to **125** after
  each successful profile load, before broadcasting the initial snapshot. This is
  intentionally not production economy behavior.

## Context

Players have Crystal Shards (from PvE wins, tutorial completion) but no way to spend them. This plan adds a Card Vending Machine in the world that lets players spend 50 Crystal Shards to pull 5 random cards from a unified pool of all 132 alpha pack cards. The machine is already placed in Workspace.

**Locked decisions:**
- Cost: 50 Crystal Shards per pull → 5 cards
- Pool: all 4 packs unified (ruby_bear + emerald_cat + sapphire_frog + stonebark); collectible only (excludes `the_coin`)
- Odds: common 70%, rare 25%, epic 5% — configurable table
- Duplicates: cards owned ≥ 2 copies → convert to **Crystal Dust** (new separate currency), rarity-dependent: common=5, rare=20, epic=80
- Crystal Dust: stubbed for future crafting — tracked in SaveService schema now, no spending mechanic this plan
- Pack animation: screen-space Crystal burst followed by a camera-space 3D stack
- Reveal UI: explicit Skip and Reveal/Next/Done controls, fifth-card summary, and Claim
- Card backs reveal no type, rarity, text, border, or offset emblem information

---

## Architecture

### New Files
| File | Type | Role |
|---|---|---|
| `ReplicatedStorage/Modules/GachaConfig` | ModuleScript | Shared cost, odds, Dust, distance, and cooldown constants |
| `ServerScriptService/Modules/GachaService` | ModuleScript | Weighted pool and five-card roll generation |
| `ServerScriptService/Modules/GachaTransaction` | ModuleScript | Pure atomic purchase and duplicate conversion |
| `ServerScriptService/GachaController` | Script | Wires `OpenCardPack` RemoteFunction; follows InventoryService/DeckService pattern |
| `StarterPlayer/StarterPlayerScripts/VendingMachineController` | LocalScript | ProximityPrompt → purchase UI → fires remote → triggers pack open |
| `StarterPlayer/StarterPlayerScripts/PackRevealController` | ModuleScript | Modal reveal state, burst, controls, summary, and Claim |
| `StarterPlayer/StarterPlayerScripts/CameraCardStage` | ModuleScript | Rigid local Parts, SurfaceGui faces, projection, dimming, and cleanup |
| `StarterGui/VendingMachineUI` | ScreenGui (editor-built) | Purchase confirmation panel |
| `StarterGui/PackOpenUI` | ScreenGui (editor-built) | Full-screen modal card reveal and result overlay |
| `TestService/GachaAcquisitionSpec` | ModuleScript | Deterministic acquisition regression tests |

### Modified Files
| File | Change |
|---|---|
| `ServerScriptService/Modules/SaveService` | Schema v5.0; delegates one atomic purchase to `GachaTransaction` and immediately schedules persistence |
| `ReplicatedStorage/Remotes` | Add `OpenCardPack` RemoteFunction |
| `Workspace/Card Vending Machine` | Add named `InteractionAnchor/ProximityPrompt` (8 studs) and separate `OfferDisplay` SurfaceGui |

---

## Phase 1 — SaveService (superseded by schema v5.0)

Crystal Dust was introduced in v4.1. The canonical-ID migration subsequently
bumped the active schema to v5.0 and intentionally resets every older profile.

Final purchase API:
```lua
SaveService.applyCardPackPurchase(player, cost, rolledEntries)
-- Returns {ok, error?, cards, dustAwarded, crystalShards, crystalDust, cost}
```

This validates every rolled ID and available balance before mutating profile data,
then commits shards, cards, and Dust together.

`getFullSnapshot` (used by `QuestStateChanged`) should also include `crystalDust` so clients can display it later.

---

## Phase 2 — GachaService

```lua
-- Config constants (top of module)
local COST_CRYSTAL_SHARDS = 50
local CARDS_PER_PULL      = 5

local RARITY_WEIGHTS = { common = 70, rare = 25, epic = 5 }

local DUPE_DUST = { common = 5, rare = 20, epic = 80 }
```

**Pool building** (runs once on `require`):
- `require(ReplicatedStorage.Definitions.Cards)` → iterate all entries
- Skip `collectible == false`
- Bucket into `pool.common`, `pool.rare`, `pool.epic` by `card.rarity`

**`GachaService.roll(player)` → `{ ok, error?, cards, dustAwarded, crystalShards, crystalDust }`**

1. Generate 5 weighted entries without touching player data.
2. Pass all entries to `SaveService.applyCardPackPurchase`.
3. `GachaTransaction` counts existing and pending copies together.
4. The first two copies are added; every later copy becomes rarity Dust.
5. Commit the complete purchase and return authoritative balances.

---

## Phase 3 — GachaController (Script)

Thin wrapper following `DeckService.lua` / `InventoryService.lua` pattern:

```lua
-- Validate proximity, rate-limit, and prevent double-invoke
local rolling = {}

RemoteFunction "OpenCardPack":
OnServerInvoke = function(player)
    if rolling[player.UserId] then return {ok=false, error="Already rolling"} end
    rolling[player.UserId] = true
    local ok, result = xpcall(function()
        return GachaService.roll(player)
    end, debug.traceback)
    rolling[player.UserId] = nil -- always cleared
    return ok and result or {ok=false, error="Pack service temporarily unavailable"}
end
```

PlayerRemoving: `rolling[player.UserId] = nil`

---

## Phase 4 — VendingMachineUI (editor-built via execute_luau)

```
ScreenGui "VendingMachineUI" (Enabled=false, ResetOnSpawn=false)
└── Panel   Frame, center-screen, ~400×280, dark semi-transparent bg, UICorner 12px
    ├── Title        TextLabel  "Card Pack"  (Fredoka One, large)
    ├── Subtitle     TextLabel  "Draw 5 cards · All Alpha Sets"
    ├── CostRow      Frame (horizontal)
    │   ├── CostIcon ImageLabel  (Crystal Shards icon from AssetIds)
    │   └── CostText TextLabel   "50 Crystal Shards"
    ├── BalanceText  TextLabel   "Balance: —"  (populated by controller on open)
    ├── OpenBtn      TextButton  "Open Pack"   (archetype green, SWIFT color)
    └── CloseBtn     TextButton  "✕"           (top-right corner)
```

SurfaceGui on the separate non-interactive `OfferDisplay` part:
- `"CARD PACK · 50 CRYSTAL SHARDS"` — readable without covering the E prompt

---

## Phase 5 — PackOpenUI, PackRevealController, and CameraCardStage

```
ScreenGui "PackOpenUI" (Enabled=false, ResetOnSpawn=false, DisplayOrder=100)
└── Root          full-screen modal frame and global input sink
    ├── InputBlocker  transparent modal button below all reveal content
    ├── BurstLayer    transient screen-space Energy-emblem particles
    ├── CardStack     five separate back/front card layers
    ├── HintText
    ├── Controls
    │   ├── SkipBtn
    │   └── PrimaryBtn  "Reveal" / "Next" / "Done"
    └── Summary
        ├── Results    horizontal ScrollingFrame; centered when space permits
        ├── DustLabel
        └── ClaimBtn
```

**Reveal sequence:**
1. After the server commits the purchase, emit a short radial Energy-emblem burst.
2. Show five face-down, depth-separated camera-space Parts with `cards[1]` on top.
   Each back is `mkBack`; each front is the unchanged live `CardVisuals` frame on
   a padded SurfaceGui adorner.
3. Reveal rotates the rigid card 180° around Y while lifting it toward the camera.
   The back/front surfaces exchange at the edge-on midpoint. Emblems remain hidden
   through 80%, then fade in without resizing or reflowing any card content.
4. Next moves cards one through four right with a small roll, destroys each once
   offscreen, then automatically rotates the following card.
5. The fifth card remains face-up and changes the primary button to Done. Only
   Done opens all five fronts with New, Added Copy, or Converted to Dust status.
   Narrow displays use horizontal touch scrolling.
6. Claim closes the overlay and releases the vending interaction lock. Skip goes
   directly to this summary from any stable reveal state.

The ScreenGui root is transparent during the 3D stage. A temporary local camera
ColorCorrectionEffect dims the world without dimming AlwaysOnTop card surfaces;
the normal ScreenGui background returns for the 2D summary. Rewards are already
committed when animation begins, and renderer failures fall back to that summary.
Character movement and world prompts remain locked through Preparing, the 3D
sequence, and the summary; Claim or controller destruction performs restoration.

---

## Phase 6 — VendingMachineController (LocalScript)

```lua
-- Startup
local vm     = workspace:WaitForChild("Card Vending Machine")
local anchor = vm:WaitForChild("InteractionAnchor")
local prompt = anchor:WaitForChild("ProximityPrompt")
local OpenCardPack = RS.Remotes:WaitForChild("OpenCardPack")

-- Open purchase panel and take local ownership of the machine prompt
`prompt.Triggered` → disable prompt, enable panel, invoke `GetQuestSnapshot`

-- Purchase
OpenBtn.Activated:
  OpenBtn.Active = false  -- prevent double-tap
  local result = OpenCardPack:InvokeServer()
  if not result.ok:
    show result.error in WarnLabel
    OpenBtn.Active = true
    return
  apply authoritative result.crystalShards/result.crystalDust
  keep prompt disabled
  VendingMachineUI.Enabled = false
  PackRevealController:Open(result, onClaimed)

-- onClaimed closes PackOpenUI and re-enables the prompt
```

---

## Verification

1. **Deterministic spec:** pool=132, five cards generated, one owned + five
   identical rolls ends at two copies and awards 20 common Dust. Per-card New,
   Added Copy, conversion, and Dust fields are asserted.
2. **Play mode:** verify 0°/45°/90°/135°/180° geometry, fixed 132×178 GUI
   dimensions, clean backs, delayed emblems, projected size across FOV changes,
   full Reveal/Next/Done progression, Skip, responsive summary, cleanup, and reopen.
3. **Security/edge checks:** server distance validation, cooldown, pending-roll
   guard, and exception cleanup are active. Insufficient funds return authoritative
   balances without mutation.
4. **Gameplay-modal regression (2026-06-30):** with 14 enabled world prompts before
   opening, the reveal reduced enabled prompts to 0; a held W input for 1.2 seconds
   produced 0 studs of character movement; controller cleanup restored all 14.
   At 1701×857, the viewport-scaled burst emitted 56 particles.

---

## Out of scope
- Multiple distinct banners / pack types
- Guaranteed-rarity/hard-pity system (for example, guaranteed Epic every N pulls;
  the successor plan's duplicate protection is a different mechanic)
- Crystal Dust spending mechanic (stubbed only)
- 3D vending machine dispense animation
- Pack opening history
