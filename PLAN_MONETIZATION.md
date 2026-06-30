# PLAN_MONETIZATION — Vending Machine Revamp + Robux Item Mall

> Status: **planning** | Author: bimahp | Date: 2026-07-01

---

## Context

Players currently have no way to spend Robux, and the Card Vending Machine is a
single flat purchase-confirm panel with no way to preview pack odds. This plan adds:

1. A revamped Vending Machine UI using the same page-stack ("leveled") navigation
   already proven in `InventoryUI` — pack select → pack detail → pack contents
   (odds browser) — instead of one static panel.
2. A dynamic duplicate-protection system ("pity" in the user's terms, but not a
   guaranteed-rarity/hard-pity counter): cards a
   player already owns 2 copies of are excluded from a rarity's weight, and that
   weight is redistributed across the rest of the tier, live, per player.
3. A persistent Crystal Shards / Crystal Dust HUD readout above the inventory icon.
4. An Item Mall — a Robux developer-product shop for 4 Crystal Shard bundles.

The product and gameplay decisions below were confirmed with the user. Technical
safeguards and API corrections added during review are called out as implementation
requirements rather than new product assumptions:
- Redistribution is **same-rarity only** (70/25/5 split stays fixed; only which
  card within a tier you can pull shifts).
- If an entire rarity tier is fully capped, rolls **fall through to allowing a
  3rd+ duplicate as Dust** (existing `GachaTransaction` behavior already handles
  this — no change needed there).
- Pack Content Details odds are **live, per-player, server-computed** — never a
  static flat number.
- A fully-capped card's tile is **removed from the Pack Content Details list**
  while another card in that rarity remains eligible. If the entire rarity is
  capped, fallback makes every card in that rarity possible again, so those cards
  must reappear with their live odds.
- Robux developer products are **not yet created** — this plan ends with exact
  Creator Dashboard setup steps and placeholder product IDs in code.
- Currency icons: reuse `AssetIds.Icons.ENERGY` as a placeholder for both Crystal
  Shards and Crystal Dust, per the user's explicit instruction.
- Odds shown in Pack Content Details are **per card draw**. Each of the five draws
  uses that distribution; this is not presented as the chance to see a card at
  least once somewhere in the full five-card pack.
- Duplicate protection uses one ownership snapshot taken before the five draws.
  Same-pack repeats can therefore still exceed the provisional two-copy cap and
  become Dust in `GachaTransaction`; the UI odds remain exact for every draw under
  that snapshot rule.

## Phase 0 — Production-safety prerequisite

Before enabling any Developer Product, remove the temporary SaveService test
override that sets every loaded profile's Crystal Shards to `125`. Leaving it in
place could overwrite paid currency on login. Verify fresh, existing, and
receipt-granted profiles retain their authoritative Shard balance across rejoin.

## Grounding (read directly from the live Studio place, not just docs)

- `ReplicatedStorage.Modules.GachaConfig` — confirmed: `COST_CRYSTAL_SHARDS=50`,
  `CARDS_PER_PULL=5`, `RARITY_WEIGHTS={common=70,rare=25,epic=5}`,
  `DUPE_DUST={common=5,rare=20,epic=80}`.
- `TestService.GachaAcquisitionSpec` (readable; the actual `GachaService`/
  `GachaTransaction` module bodies under `ServerScriptService.Modules` are **not**
  readable through this MCP connection while in Play mode — same isolation limit
  already known for `execute_luau`). Confirmed public contracts from the spec:
  - `GachaTransaction.apply(data, cost, rolledEntries) -> {ok, error?, cards, dustAwarded}`
    where `data = {crystalShards, crystalDust, collection}` (collection is a flat
    cardId list, e.g. `{"fleetpaw","fleetpaw"}`, not a count map). Atomic — failure
    leaves `data` untouched.
  - `GachaService.getPoolSummary() -> {total=132}`
  - `GachaService.generateRoll(rngFn) -> array of 5 entries` — `rngFn` is an
    injectable RNG stub for determinism (test passes `function(minimum) return minimum end`).
- `ReplicatedStorage.Definitions.Cards` — cards carry `rarity` (`"common"|"rare"|"epic"`)
  and `collectible` (bool) fields directly, e.g. `the_coin` has `collectible=false`.
- `StarterGui.InventoryUI.InventoryController` (full source read) — the page-stack
  pattern to copy: `pageStack = {}` (array of `{page, arg}`), `pages = {}` table of
  page-render functions, `show(page, arg, push)` / `goBack()`, `backBtn.Visible =
  #pageStack > 1`, `gui.Enabled` gates the whole modal. Card grid + detail pattern:
  `makeCard(parent, cardId, w, h)` wraps `CardVisuals.buildCardFrame` +
  `updateCardFrame`; left `ScrollingFrame` with `UIGridLayout`, right detail `Frame`
  populated on cell `Activated`.
- `StarterGui.Hud.HudController` + `TopRightAnchor` (full source read) —
  `TopRightAnchor` is a `Frame`, `AnchorPoint=(1,0)`, `Position={1,-12},{0,12}`,
  `AutomaticSize=X`, child `UIListLayout` is `FillDirection=Horizontal,
  HorizontalAlignment=Right, SortOrder=LayoutOrder, Padding=8`. Currently holds one
  `InventoryButton` (`ImageButton`, 60×60, `Icon`+`Outline` children).
  `HudController` only toggles `anchor.Visible` during battle states — it does not
  own the inventory dialog (that lives in `InventoryController`), so the new
  currency bar gets **its own** controller script, not added to `HudController`.
- `StarterPlayer.StarterPlayerScripts.VendingMachineController` (full source read) —
  currently: `ProximityPrompt.Triggered` → `openVendingUI()` (flat `VendingMachineUI.Panel`,
  no page stack) → `OpenBtn.Activated` → `OpenCardPack:InvokeServer()` →
  `applyBalance(result)` → `revealController:Open(result, onClaimed)`
  (`PackRevealController.new(packUI)`). Balance comes from `GetQuestSnapshot`
  (RemoteFunction) and `QuestStateChanged` (RemoteEvent), both already returning
  `crystalShards`/`crystalDust`.
- `Workspace["Card Vending Machine"]` — single decorative model, one
  `InteractionAnchor/ProximityPrompt`, one `OfferDisplay/PackOfferSurface`. No
  per-pack-type data exists in the world yet — confirms "only Standard Pack for now"
  is the actual current state, not a design simplification.
- `ReplicatedStorage.Modules.AssetIds` (full source read) — `Icons.ENERGY =
  "rbxassetid://114305689596215"`, `InventoryIcon`, no Shards/Dust/pack-logo icons
  exist yet.

## Architecture

### A. Currency HUD bar (`StarterGui/Hud`)

- Add a new sibling `Frame "CurrencyBar"` to `StarterGui.Hud`, anchored top-right
  above `TopRightAnchor` (`AnchorPoint=(1,0)`, `Position={1,-12},{0,12}`), holding
  two pill badges (`ShardsBadge`, `DustBadge`) each with an `ImageLabel` icon
  (`AssetIds.Icons.ENERGY` placeholder, swap later) + `TextLabel` count, styled
  like the reference image (rounded pill, icon left, number right).
- Move `TopRightAnchor`'s `Position` down to clear the new bar's height (e.g.
  `{1,-12},{0,68}` — exact offset finalized in editor against the built badge height).
- New `StarterGui/Hud/CurrencyBarController` (LocalScript) — separate from
  `HudController` per its own "visibility only" scope comment. Subscribes to
  `QuestStateChanged.OnClientEvent` (already fires `crystalShards`/`crystalDust`
  on every mutation) and an initial `GetQuestSnapshot:InvokeServer()` on join,
  same pattern as `VendingMachineController.applyBalance`. Formats counts with a
  small local `formatCount(n)` helper (≥1000 → `"10.2K"` style, matching the
  reference image) — kept local to this one script since it's the only consumer.

### B. Item Mall icon + dialog

- Add `ItemMallButton` (`ImageButton`, 60×60, same `Icon`+`Outline` layered-outline
  convention as `InventoryButton`) to `TopRightAnchor`, icon
  `rbxassetid://116103174023688`. Set `ItemMallButton.LayoutOrder = 0` and bump
  `InventoryButton.LayoutOrder = 1` so the mall icon sits left of the bag (confirmed:
  `UIListLayout` is `SortOrder=LayoutOrder`, left-to-right).
- New `StarterGui/ItemMallUI` (ScreenGui, editor-built, same `Scrim`/`Dialog`/
  `TitleBar`+`BackButton`/`Body` shape as `InventoryUI` for visual/behavioral
  consistency — this is the "leveled UI architecture" the user is referencing).
  - Page `Home`: one category button, "Crystal Shards".
  - Page `Bundles`: 4 product cards (icon, "N Shards", "M Robux", Buy button),
    reading from a new shared config (see below). Back returns to `Home`.
- New `StarterPlayer/StarterPlayerScripts/ItemMallController` (LocalScript) —
  copies the `pageStack`/`show`/`goBack` pattern verbatim from `InventoryController`
  (small enough to duplicate rather than extract a premature shared module, matching
  how `InventoryController` itself doesn't share this pattern with anything yet).
  Wires `ItemMallButton.Activated` → open. Buy button click → directly calls
  `MarketplaceService:PromptProductPurchase(player, productId)` (purchase prompting
  is client-initiated; no purchase-grant remote is used). A bundle whose
  `productId` is `0` is visibly disabled and can never reach the prompt. Listens to
  `QuestStateChanged` to live-refresh the displayed Shards balance while the dialog
  is open (granting happens via `ProcessReceipt` server-side, which already fires
  `QuestStateChanged` through the existing currency-mutation path).
- New `ReplicatedStorage/Modules/ShopConfig` — shared bundle definitions:
  ```lua
  ShopConfig.Bundles = {
      { id = "shards_50",   productId = 0, shards = 50   }, -- FILL IN productId
      { id = "shards_250",  productId = 0, shards = 250  }, -- FILL IN productId
      { id = "shards_500",  productId = 0, shards = 500  }, -- FILL IN productId
      { id = "shards_1000", productId = 0, shards = 1000 }, -- FILL IN productId
  }
  ```
  `productId` starts at a placeholder and gets filled in once the products exist
  (see setup steps at the end). Robux prices are not stored in this config. The
  client retrieves each player's live `PriceInRobux` with
  `MarketplaceService:GetProductInfoAsync(productId, Enum.InfoType.Product)` under
  `pcall`, so the label matches regional/optimized pricing. If lookup fails, the
  product card shows an unavailable state instead of a guessed price.

### B.1 Paid-random-item policy gate

- Add a server-owned policy lookup using
  `PolicyService:GetPolicyInfoForPlayerAsync(player)` and expose only the required
  result through a new `GetMonetizationPolicy` RemoteFunction. Cache the result for
  the player's session and rate-limit the remote. `ItemMallButton.Visible` defaults
  to `false` in the editor so it cannot flash before the response arrives.
- Until the lookup succeeds, fail closed: keep `ItemMallButton` hidden and prevent
  `ItemMallController` from opening the dialog through any code path.
- If `ArePaidRandomItemsRestricted == true`, keep the Item Mall button/dialog
  unavailable. The player may still use Shards earned through the game's unpaid
  progression path at the Vending Machine. This is the selected policy treatment;
  paid and earned Shards are currently one fungible balance, so historical paid
  Shards are not source-tracked.
- Policy gating controls purchase access only. `ProcessReceipt` must still grant
  any legitimate pending receipt; never strand a completed payment because the
  player's current policy result changed.

### C. Server: ProcessReceipt + atomic Shard grant

- New `ServerScriptService/Modules/ShopTransaction` — mirrors the existing
  `GachaTransaction.apply` shape:
  `ShopTransaction.grant(data, purchaseId, productId, shardAmount) ->
  {ok, error?, alreadyGranted?, crystalShards}`, a pure validate-then-commit
  function over the profile data table. It checks and records `purchaseId` in the
  same synchronous mutation that grants Shards
  (testable the same way `GachaAcquisitionSpec` tests `GachaTransaction`).
- `SaveService` gets one **minor** schema migration (v5.0 → v5.1, non-destructive,
  following the existing `MINOR_MIGRATIONS` pattern already used for past minor
  bumps): add `data.purchaseHistory = {}` (set of already-granted Roblox
  `PurchaseId` strings) to every profile. This is required for idempotent
  `ProcessReceipt` handling — Roblox can call the callback more than once for the
  same purchase (retries, server restarts), so granting must check-and-record the
  `PurchaseId` atomically with the Shard credit, exactly like `GachaTransaction`
  already does validate-then-commit-once for card pulls.
- New `ServerScriptService/RobuxShopController` (Script) — sets
  `MarketplaceService.ProcessReceipt`:
  1. Look up `productId` in `ShopConfig.Bundles`; unknown id → `NotProcessedYet`
     (defensive; should not happen).
  2. If the player isn't currently in the server / profile isn't loaded yet →
     return `NotProcessedYet`. Roblox automatically re-invokes `ProcessReceipt`
     later (including after the player rejoins) — this is the standard, simpler
     mechanism for the offline case, not the PvP anti-rage-quit flag pattern (that
     pattern solves a different problem: resolving an already-started battle
     outcome, not a deferred purchase grant).
  3. Delegate to a single authoritative SaveService entry point,
     `applyDeveloperProductReceipt(player, purchaseId, productId, shardAmount)`.
     A receipt found in the profile as loaded from persistent storage is already
     granted and may return `Enum.ProductPurchaseDecision.PurchaseGranted` without
     granting again.
  4. Otherwise, `ShopTransaction.grant` records `PurchaseId` and credits Shards in
     one mutation. SaveService owns a per-session pending-receipt state: if the
     forced save fails, a retry must re-attempt persistence without granting Shards
     again, and an in-memory-but-unconfirmed ID must not be mistaken for an already
     persisted receipt. Only after confirmed persistence does SaveService report
     success. Then fire
     `QuestStateChanged` so open HUD/Item Mall/Vending UI update live and return
     `Enum.ProductPurchaseDecision.PurchaseGranted`. On mutation or save failure,
     return `Enum.ProductPurchaseDecision.NotProcessedYet` and do not report a
     successful purchase to the client.
  5. Unknown or retired product IDs return `NotProcessedYet` and emit a prominent
     server warning/telemetry event. Product handlers for previously sold IDs must
     remain in the catalog so legitimate delayed receipts do not become stranded.

### D. Dynamic duplicate-aware odds ("pity") — server odds engine

Both the actual roll and the displayed odds must use **the same exclusion logic**
so the UI never lies. Ownership snapshot is taken once from the player's persisted
`collection` (not re-evaluated mid-pull) — this keeps the model simple and matches
how `GachaTransaction.apply` already independently absorbs same-pull duplicate
collisions into Dust. Under the selected snapshot-once rule, same-pack repeats can
also become Dust even when other cards in that rarity remain eligible.

- Extend `GachaService.generateRoll(rngFn, ownedCounts?)` — new optional 2nd
  param, `nil`/omitted behaves exactly as today (keeps
  `GachaAcquisitionSpec`'s existing no-arg call passing unchanged). When provided
  (`{[cardId]=count}`), each of the 5 independent slot picks:
  1. Picks a rarity via the existing weighted roll over `RARITY_WEIGHTS`.
  2. Builds the eligible pool = cards in that rarity where
     `(ownedCounts[cardId] or 0) < 2`.
  3. If eligible pool is empty (whole tier capped), falls back to the **full**
     rarity pool (allows the 3rd+ copy → `GachaTransaction` converts to Dust as
     today).
  4. Picks uniformly within the eligible (or fallback) pool via `rngFn`.
- New `GachaService.computeDisplayOdds(ownedCounts) -> { [cardId] = {percent,
  rarity, owned} }`. Mirrors the same eligible-pool/fallback logic per rarity so
  per-draw percentages are exactly what `generateRoll` would produce: `percent =
  RARITY_WEIGHTS[rarity] / #eligiblePool` per remaining card, 0 (omitted from the
  result entirely, per the "remove tile" decision) for capped cards unless the
  whole tier fell back, in which case the tier's weight is spread evenly across
  every card in that tier (signals "you will hit guaranteed dupes here").
- New RemoteFunction `GetPackOdds` (added in `ReplicatedStorage/Remotes`), handled
  in the existing `ServerScriptService/GachaController` Script (same file that
  already owns `OpenCardPack`) — reads the invoking player's `collection` via
  `SaveService`, builds `ownedCounts`, calls `GachaService.computeDisplayOdds`,
  returns `{ok=true, packId="standard", cards={...}}`.
- `GachaController`'s `OpenCardPack` handler passes the same player's
  `ownedCounts` into `GachaService.generateRoll` so the actual pull honors the
  same exclusion the player just saw.

### E. Vending Machine UI revamp (page-stack navigation)

Restructures `VendingMachineUI` from a flat `Panel` into the same `Dialog`
(`TitleBar`+`BackButton`/`Body`)/`Scrim` shape as `InventoryUI`, and rewrites
`VendingMachineController` to use the `pageStack`/`show`/`goBack` pattern (copied
from `InventoryController`, same reasoning as the Item Mall controller above —
small enough to duplicate, not worth extracting yet).

Flow, replacing today's single `openVendingUI()`:

1. `ProximityPrompt.Triggered` → `show("PackSelect")`.
2. **`pages.PackSelect()`** — grid of pack logo tiles (today: one tile, "Standard
   Pack", using a new placeholder `AssetIds.PackArt.standard` — no real pack-logo
   asset exists yet, flagged the same way other placeholder art is flagged in
   `DEV_STATUS.md`). Tap → `show("PackDetail", "standard")`.
3. **`pages.PackDetail(packId)`** — pack image + name + two buttons:
   - "Pack Content Details" → `show("PackContents", packId)`.
   - "Open (50 Shards)" → same logic as today's `OpenBtn.Activated`: calls
     `OpenCardPack:InvokeServer()`, `applyBalance`, then
     `revealController:Open(result, onClaimed)` (unchanged — `PackRevealController`
     and the whole reveal/claim flow are reused as-is).
4. **`pages.PackContents(packId)`** — `GetPackOdds:InvokeServer()` on enter; left
   `ScrollingFrame`/`UIGridLayout` of card tiles (same `makeCard`-style helper as
   `InventoryUI`, reusing `CardVisuals.buildCardFrame`/`updateCardFrame`) each with
   a percentage overlay (for example `"0.8333%"`, top-of-cell badge, mirroring the
   existing owned-count badge technique at `InventoryController.lua:211` but
   positioned at the top instead of bottom-right). A capped card is omitted while
   its rarity still has an eligible alternative; if that entire rarity is capped,
   fallback makes all cards in the tier possible and they are all rendered again.
   The list re-flows whenever eligibility changes.
   Right-side detail panel shows the selected card (via `makeCard`) plus its
   **per card draw** odds
   line and a short adapted disclaimer (not copied verbatim from the reference
   image): *"Cards you already own 2 copies of are excluded from these odds — that
   chance is shared across the rest of the rarity. Your odds are unique to your
   collection."* Also show: *"Each of the five card draws uses the odds shown.
   Percentages are rounded, so displayed values may not total exactly 100%."* Back
   → `PackDetail`. The descriptive `Pack Content Details` control remains visible
   and accessible before the player can spend Shards; a standalone `(i)` icon is
   not used as the only disclosure entry point.

`Card Vending Machine.OfferDisplay` world `SurfaceGui` text stays as-is (still
accurate: "CARD PACK · 50 CRYSTAL SHARDS").

## Files touched (summary)

| File | Change |
|---|---|
| `StarterGui/Hud` (+ new `CurrencyBar`, `CurrencyBarController`) | New currency readout above `TopRightAnchor`; `TopRightAnchor` repositioned down |
| `StarterGui/Hud/TopRightAnchor` | New `ItemMallButton`; `LayoutOrder` set on both icons |
| `StarterGui/ItemMallUI` (new) + `StarterPlayer/StarterPlayerScripts/ItemMallController` (new) | Robux bundle shop, page-stack pattern copied from `InventoryController` |
| Server policy gate + client visibility handling | Hide and hard-disable Item Mall while policy is unknown or `ArePaidRandomItemsRestricted` is true |
| `ReplicatedStorage/Modules/ShopConfig` (new) | 4 bundle definitions, placeholder `productId`s |
| `ServerScriptService/Modules/ShopTransaction` (new) | Atomic, idempotent Shard grant |
| `ServerScriptService/RobuxShopController` (new) | `MarketplaceService.ProcessReceipt` handler |
| `ServerScriptService/Modules/SaveService` | Remove the temporary 125-Shard login override; minor migration v5.0→v5.1 adds `purchaseHistory`; add persisted receipt API |
| `ServerScriptService/Modules/GachaService` | `generateRoll` gains optional `ownedCounts`; new `computeDisplayOdds` |
| `ServerScriptService/GachaController` | New `GetPackOdds` RemoteFunction handler; `OpenCardPack` now threads `ownedCounts` through |
| `ReplicatedStorage/Remotes` | New `GetPackOdds` and `GetMonetizationPolicy` RemoteFunctions |
| `ReplicatedStorage/Modules/AssetIds` | New `ItemMallIcon`, placeholder `PackArt.standard` |
| `StarterGui/VendingMachineUI` + `StarterPlayer/StarterPlayerScripts/VendingMachineController` | Restructured to `Dialog`/page-stack shape; new `PackSelect`/`PackDetail`/`PackContents` pages; `OpenCardPack` call and `PackRevealController` reuse unchanged |

`PackRevealController`, `CameraCardStage`, `CardVisuals`, `GachaTransaction`,
`GachaConfig` are all reused unmodified.

## Developer Product setup (must be done by the user — not API-creatable)

For each of the 4 bundles, in Roblox Studio: **Home → Monetization → Developer
Products → Create**, or via the Creator Dashboard for the experience:

| Name | Price (Robux) | Shards granted |
|---|---:|---:|
| Crystal Shards x50 | 99 | 50 |
| Crystal Shards x250 | 449 | 250 |
| Crystal Shards x500 | 849 | 500 |
| Crystal Shards x1000 | 1599 | 1000 |

These are Creator Dashboard **default** prices. After creation, copy each product's
numeric ID into `ShopConfig.Bundles[i].productId`
(currently placeholder `0`). `MarketplaceService.ProcessReceipt` can only be set
**once** per game session — if any other system later needs receipt processing,
extend `RobuxShopController`'s single handler rather than adding a second one.
The in-experience labels come from MarketplaceService at runtime, not this table.

## Verification

1. **Headless**: extend `TestService` with a `ShopTransactionSpec` (mirrors
   `GachaAcquisitionSpec`'s shape) covering: fresh grant, duplicate `PurchaseId`
   no-op, invalid product/amount atomicity, save failure returning
   `NotProcessedYet`, retry after failure, reconnect dedupe, and unknown/retired
   product behavior. Add `GachaOddsSpec` (or extend
   `GachaAcquisitionSpec`) asserting: raw `computeDisplayOdds` percentages sum to
   ~100% across all cards, each rarity sums to its configured 70/25/5 weight, a
   capped card is excluded, an all-capped tier falls back correctly, and
   `generateRoll(rngFn, ownedCounts)` never returns a capped card
   while eligible alternatives exist in the pre-pack snapshot. Also assert that
   same-pack repeats follow the documented snapshot rule and can become Dust.
2. **Studio Play**: HUD currency bar updates live after a vending purchase; Item
   Mall remains hidden while policy is unresolved/restricted, opens only when
   allowed, placeholder products stay disabled, and live product-price lookup has
   an unavailable fallback. Buy prompts `PromptProductPurchase` (full receipt flow
   needs a published place and test purchases cost real Robux); Vending Machine flow
   PackSelect → PackDetail → PackContents → Back → Back → Open → existing reveal
   sequence end-to-end; pull a card to 2 copies and confirm it both drops out of
   `PackContents` and stops appearing in subsequent rolls (use the dust/duplicate
   summary screen to confirm no 3rd copy is added to the collection while
   alternatives exist, while same-pack over-cap repeats are reported as Dust).
3. **Published test place**: with low-price test products, verify a successful
   receipt persists before acknowledgement, survives rejoin, never double-grants,
   and updates all three currency consumers. Test allowed, restricted, and failed
   policy lookup states. Confirm Pack Content Details is reachable before Open,
   includes every currently possible card, labels odds per draw, and shows the
   rounding disclaimer.
