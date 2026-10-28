# PLAN_CARD_VENDOR — Card Merchant NPC: Craft/Buy + Recycle-for-Shards

> Status: **implemented and verified**, with Post-Ship Recycle UI V2 replacing the original My Cards destroy button | Author: bimahp (with Claude/Codex) | Date: 2026-07-11
>
> Implements a new DESIGN_ECONOMY.md §10.4 system: a "Card Merchant" NPC that
> sells a rotating selection of specific cards two ways — **Craft** (Card
> Fragments, new pricing) and **Buy** (Crystal Shards, §10.1 x2) — plus the
> **Recycle/Destroy** flow (§9) that gives Crystal Shards a real
> free-to-play income source for the first time. See DESIGN_ECONOMY.md §9/
> §10.4 for the locked numbers this implements.

## Why

`PLAN_ECONOMY_REVAMP.md` shipped Card Fragments but left Crystal Shards with
**no gameplay income path at all** (Robux only). DESIGN_ECONOMY.md §9/§10
already specified a recycle/craft system on paper, but none of it was ever
built. The user placed a "Card Merchant" NPC in `Workspace` and asked for a
Craft (Fragments) / Buy (Shards) choice per card — this only becomes a real
choice, not a pay-only feature, once Recycle gives Shards a free source.

## Decisions locked with the user (do not re-litigate)

1. **No auto-conversion.** Duplicate pack pulls stay exactly as-is today.
   Destroy is a deliberate, manual action — the only free source of Shards.
2. **Buy = §10.1 rates x2** (user tried x4, brought it back to x2): Common
   40 / Rare 160 / Epic 600 / Legendary 2,400 Crystal Shards. This
   *deviates* from DESIGN_ECONOMY.md's original §10.1 (20/80/300/1,200) —
   now documented as the Vendor's price in the new §10.4.
3. **Craft priced off pack cost-per-slot, not blind-roll EV** (literal EV
   premium would put Epic Craft past 2 months even at the daily Fragment
   cap — rejected as not fun): Common 500 / Rare 1,500 / Epic 4,000 /
   Legendary 15,000 Card Fragments.
4. **Legendary is fully wired** into every config/code path even though 0
   of 132 live cards use that rarity yet — falls out for free whenever a
   Legendary card ships.
5. **Vendor stock rotates:** 6 cards (3 Common / 2 Rare / 1 Epic), global
   (not per-player), resetting 3x/day at 00:00 / 08:00 / 16:00.

Full pricing rationale, EV math, and the Robux/USD sanity-check table live
in DESIGN_ECONOMY.md §10.4 (now the source of truth) — not duplicated here.

## Implementation Status

- [x] **Phase 0** — Adjacent fix: `GachaConfig.COST_CARD_FRAGMENTS` 160→200
- [x] **Phase 1** — Server transaction layer: `VendorConfig`,
      `VendorTransaction`, `VendorService`, `SaveService` wrappers
- [x] **Phase 2** — Remotes + `VendorController` (proximity/rate-limit wiring)
- [x] **Phase 3** — Card Merchant NPC dialogue trigger
- [x] **Phase 4** — Client `VendorUI` + `VendorUIController.lua`
- [x] **Phase 5** — Destroy action in `InventoryController` (**superseded by Post-Ship Recycle UI V2**)
- [x] **Phase 6** — Verification (headless + live) + doc sync

---

## Phase 0 — Adjacent fix

**Result (2026-07-11):** `ReplicatedStorage.Modules.GachaConfig.COST_CARD_FRAGMENTS`
was still `160` live while the (now-committed-in-spirit) DESIGN_ECONOMY.md
§5.2 already priced the Standard Pack at `200`. Bumped to `200` so pack cost
and the new Craft pricing math (anchored on 200/5=40 per slot) are
consistent with each other and the doc. Verified via `script_read`.

## Phase 1 — Server transaction layer

**Result (2026-07-11):** New `ReplicatedStorage/Modules/VendorConfig.lua`
centralizes every rate from DESIGN_ECONOMY.md §9/§10.4:
`CRAFT_COST_BY_RARITY`, `BUY_COST_BY_RARITY`, `DESTROY_VALUE_BY_RARITY`,
`RECYCLE_DECK_CHECK_THRESHOLD_BY_RARITY` (Common/Rare/Epic=2,
Legendary=1), `MAX_USEFUL_COPIES=2` (the flat Craft/Buy max useful copy
gate), `STOCK_SIZE`/`STOCK_RARITY_SPREAD`/`ROTATION_INTERVAL_SECONDS`.

New `ServerScriptService/Modules/VendorTransaction.lua` (pure, mirrors
`GachaTransaction.lua`'s validate-then-mutate shape exactly): `craft`/`buy`
share one `directPurchase(data, currencyField, cardId, cost)` helper
(currency field is the only difference between the two); `destroy(data,
requests)` now powers Recycle UI V2: it aggregates duplicate request rows,
allows unused cards to be recycled all the way to zero, blocks only when the
remaining count would no longer satisfy a saved deck, then removes the
requested copies from the flat `data.collection` array and credits Shards
at `DESTROY_VALUE_BY_RARITY`.

New `ServerScriptService/Modules/VendorService.lua` (mirrors
`GachaService.lua`): rotation is **epoch-aligned and stateless** —
`getRotationBucket()` = `math.floor(os.time() / 28800)`, so every server
independently computes the identical 8-hour bucket with zero persisted/
synced state, landing exactly on 00:00/08:00/16:00 (same principle as
`SaveService.dayBucket()`). `getStockCardIds(bucket)` is a pure function of
the bucket number — seeds a `Random.new(bucket)` and partial-Fisher-Yates
picks `STOCK_RARITY_SPREAD` unique cards per rarity, so it's independently
testable headlessly without touching `os.time()`. `craftCard`/`buyCard`
re-validate the card is in the *current* stock (not just any card) before
delegating to `SaveService`.

`SaveService.lua`: added `local VendorTransaction = require(...)` alongside
the existing `GachaTransaction`/`ShopTransaction` requires, and three new
functions (`applyCardCraft`, `applyCardBuy`, `applyCardDestroy`) right after
`applyCardPackPurchase` — same shape (profile-active check → delegate to the
pure transaction → mark `Dirty` → fire a `QuestStateChanged` currency
refresh → prompt an immediate `profile:Save()`). Extracted the currency-
refresh-and-save tail into a shared local `commitVendorResult` helper since
all three new functions repeat it identically — `applyCardPackPurchase`
itself was left untouched (inlines the same steps) to keep this change a
pure addition with zero risk to the existing, already-verified pack-
purchase path. **No SaveService schema version bump needed** — Craft/Buy/
Destroy only mutate `cardFragments`/`crystalShards`/`collection`, all
already present in the v5.3 schema.

Verified via `script_read`/`script_grep` immediately after each edit (this
project's established `multi_edit` reliability check, per
`reference_multiedit_replaceall_unreliable`) — every new function present
exactly once, `VendorTransaction` require landed, no accidental duplication
of the pre-existing `applyCardPackPurchase`.

**Noted oddity, not a blocker:** `script_grep`'s reported line numbers for
`SaveService.lua` were consistently offset from `script_read`'s actual line
numbers for this file during this session (e.g. grep said line 704 for
`applyCardPackPurchase`, the real line was 770). Worked around by using
`script_grep` only to confirm a symbol's *existence/count*, never its line
number, and using unique text anchors (not line ranges) for every
`multi_edit` — consistent with this project's general stance of not
trusting tool-reported positions over direct content verification.

## Phase 2 — Remotes + VendorController

**Result (2026-07-11):** Created 4 new `RemoteFunction`s under
`ReplicatedStorage.Remotes` (`GetVendorStock`/`CraftCard`/`BuyCard`/
`DestroyCards`) via `execute_luau` `Instance.new` (real, persisted
DataModel instances — distinct from the ModuleScript-`require`-cache
isolation limitation, this is the same as using the Studio command bar).
New `ServerScriptService/VendorController.lua` mirrors `GachaController.lua`
exactly: proximity gate against `Workspace."Card Merchant".HumanoidRootPart`,
a `busy`/throttle guard, `xpcall`-wrapped handlers.

**A real bug caught before it shipped:** my first pass gated *all four*
remotes behind vendor-NPC proximity via one shared `guardedAction` helper.
`DestroyCards` is a collection-management action meant to be reachable from
`InventoryController` (browsable from anywhere, not just standing next to
the Vendor) — gating it behind proximity would have silently broken Destroy
everywhere except right next to the NPC. Caught by re-reading the plan's own
intent before verifying, not by live testing. Fixed by adding a
`requireProximity` boolean parameter to `guardedAction`: `true` for
Craft/Buy, `false` for Destroy.

## Phase 3 — Card Merchant NPC dialogue trigger + Phase 4 — Client VendorUI

**Result (2026-07-11):** Built together since the dialogue's only purpose is
opening the shop UI — splitting them into separate scripts would have meant
solving a cross-script "how does the dialogue tell the UI to open" problem
for no benefit. One new `StarterPlayer.StarterPlayerScripts.VendorUIController.lua`
(LocalScript) does both: a `ProximityPromptService.PromptTriggered` listener
filtered to `Workspace."Card Merchant"` (checked via `prompt:IsDescendantOf`,
simpler than `TrainerInteraction.lua`'s ancestor-walk since there's exactly
one Vendor, not a `Trainers` folder of many) opens a short flavor dialogue
via the existing generic `DialogueController` (fully reused, zero changes to
that module or to `TrainerInteraction.lua`), and its "Show me your wares"
option opens the shop UI locally.

New `StarterGui.VendorUI` ScreenGui is a `:Clone()` of `ItemMallUI` (editor-
first — preserves the real, already-tuned `UICorner`/`UIStroke`/
`TitleGradient`/font instances instead of hand-rebuilding them), renamed,
with its `Body` populated at runtime by the same pattern `ItemMallController`/
`InventoryController` already use (editor-authored shell instances, runtime-
built page content) — not a new pattern. Two pages: `Stock` (grid of the
current rotating stock, reusing `CardVisuals.buildCardFrame`/
`updateCardFrame` exactly as `InventoryController.makeCard` does, "Owned Max"
badge on maxed cards) → `Detail(cardId)` (card preview + Craft/Buy buttons,
greyed when maxed, inline status label for insufficient-currency/other
server-side errors returned from `CraftCard`/`BuyCard`). New
`UITheme.Accents.Vendor` (amber/bronze) added alongside the existing
Inventory/Vending/Mall/Deck/Matchmaking accents — distinct from all of them.
Reuses `AssetIds.VendingIcon` as a placeholder header icon (no dedicated
Vendor icon exists yet, same class of gap as the Card Fragment icon).
Closes on `BattleLoading`/`BattleSeated`/`UpdateBattleState`, same safety
net `ItemMallController` uses.

Also fixed the stale `TalkPrompt.ObjectText = "Noob"` on `Workspace."Card
Merchant"` (leftover from being cloned off the Noob template) → `"Card
Merchant"`.

**Simplification flagged, not a bug:** the Stock page's rotation-reset
label ("New stock in Xh Ym") is computed once when the page is fetched, not
a live ticking countdown like `MatchmakingController`'s elapsed-time label.
Acceptable for a value that only changes on an 8-hour cadence — a ticking
timer would be pure UI polish with no functional benefit here.

## Phase 5 — Destroy action in InventoryController (**superseded**)

**Original result (2026-07-11, now superseded by Recycle UI V2):**
`InventoryController.lua`'s existing `pages.MyCards()`
card-select handler (the same handler that already renders the preview card
on tap) gained a conditional "Destroy 1 Copy (+N Shards)" button using the
then-current protected-copy floor. One click fires `DestroyCards`
with `{{cardId, count=1}}`, shows the result in the existing `errorLabel`
(reused rather than building a new status label), calls `refreshData()`, and
re-shows `MyCards` so the grid's `xN` badge and the button's continued
presence/absence reflect the new count. New `VendorConfig` require added to
the top of the file alongside the existing `CardData`/`CardVisuals`/etc.
requires; `DestroyCards` added to the `rf` remotes table.

**Current behavior:** the per-card `My Cards` destroy button was removed.
Recycle is now a dedicated Inventory home menu; see Post-Ship Fix — Recycle
UI V2 below for the current source of truth.

**Scope simplification, disclosed not hidden:** destroys exactly 1 copy per
click (repeatable) rather than a quantity selector for destroying N at once.
The plan's original wording said "select one or more... confirm" — a
multi-select stepper was judged not worth the added UI complexity for this
pass; one-at-a-time still fully closes the loop.

## Phase 6 — Verification + doc sync

**Result (2026-07-11):** Headless (`execute_luau`, Edit mode, clone-and-
rename technique): 27/27 assertions — `VendorConfig` rate sanity (Craft/Buy/
Destroy tables incl. Legendary), `VendorService.getStockCardIds` determinism
(identical bucket → identical stock, different bucket → different stock,
exact 3/2/1 rarity spread, `the_coin` excluded), rotation-bucket epoch-
boundary math, and `VendorTransaction.craft/buy/destroy` atomicity
(insufficient-funds and already-maxed both fail with zero mutation; the
original destroy flow blocked protected copies before Recycle UI V2
superseded that rule).

**Live Studio Play** (`start_stop_play`, real connected test player
`darkmeta1207`, per this project's "prove it live, not just headless"
convention) — clean boot, zero script errors both runs:

- Real `ProximityPromptService.PromptTriggered` → `DialogueController`
  dialogue → "Show me your wares." → `VendorUI` opened, confirmed via
  direct `PlayerGui` instance inspection at every step (not just absence of
  errors): dialogue text, options, `VendorUI.Enabled`, 6 real stock cards
  rendered, live rotation label.
- Real `CraftCard` call correctly failed with "Not enough currency" against
  the real profile's actual 7 Card Fragments (< 500 Common cost).
- Real `BuyCard` call succeeded: `crystalShards` 1675→1075 (-600, exact Epic
  Buy cost), the target card's owned copies 1→2 in the real collection via
  `GetInventory` — and **persisted across a full Play-session stop/restart**
  (a genuine ProfileStore save, not just in-memory state).
- **A real bug found and fixed via live testing, not just inferred:** after
  a successful Craft/Buy, the Detail page re-rendered from the client's
  cached `currentStock` table (populated once when the Stock page first
  loaded) instead of re-fetching — so the Craft/Buy buttons stayed enabled
  even after the card became maxed, until the player backed out and back in.
  Fixed by calling `fetchStock()` again before the post-purchase
  `show("Detail", cardId, false)` re-render. Re-verified after the fix via
  direct `GetVendorStock`/`CraftCard`/`BuyCard` remote calls: server
  correctly reported `owned=2, maxed=true` and correctly rejected both
  Craft and Buy with "Already own the maximum useful copies" — confirming
  the bug was purely client-side display staleness, the server-side gate
  was never wrong.
- Real `DestroyCards` call succeeded on a genuine 3-copy duplicate
  (`sapphire_leech`, Common): gained exactly 2 Shards, collection 3→2,
  balance persisted. A second attempt at 2 copies (at the protection floor)
  correctly rejected with "Cannot destroy protected copies of...".
- **Proximity-gate split (the Phase 2 bug-fix) confirmed correct live, not
  just in code:** teleported the test character ~111 studs from the Vendor
  — `CraftCard` correctly rejected with "Move closer to the Card Merchant";
  `DestroyCards`, fired from the same distance, succeeded normally.
- `InventoryUI`'s "My Cards" page opened via a real HUD button click,
  selected a card with 2 owned copies (below the destroy-protection floor):
  preview rendered correctly, **no** Destroy button appeared (correct
  negative case) and no runtime error.

**Known verification gap, honestly disclosed:** the Destroy button's
*positive* case (button appearing on a 3+-copy card and being clicked for
real inside `InventoryUI`, as opposed to firing `DestroyCards` directly)
was not exercised, because after the other tests above the test profile had
no remaining 3+-copy card and insufficient Card Fragments (7) to roll a
fresh duplicate via a real pack purchase. The underlying `DestroyCards`
mechanism this button calls was independently verified for real (see above)
multiple times, and the button-spawn code path reuses the same `makeCard`/
`button()` helpers already proven live elsewhere on the same page — but the
literal "click the button in `InventoryUI` and watch it work" step is the
one piece carried forward as a follow-up, consistent with this project's
practice of naming exactly which slice stayed unverified rather than
rounding up to "fully verified."

**Also encountered, not a regression:** simulated `E`-key `ProximityPrompt`
triggering worked once, then failed on a second attempt after a Play-session
restart despite identical distance/prompt state (confirmed via a temporary
`ProximityPromptService.PromptTriggered` listener that never fired) — the
same class of test-harness flakiness already documented in
`PLAN_ECONOMY_REVAMP.md`'s Post-Ship Fix and Phase 6 sections for the
standing Noob's prompt. Worked around by testing the server-side contract
directly through the real remotes instead of re-fighting the input harness.

Docs: this file and `DEV_STATUS.md` updated phase-by-phase throughout
implementation (not just at the end), matching `PLAN_ECONOMY_REVAMP.md`'s
and `PLAN_MATCHMAKING.md`'s documentation discipline. `DESIGN_ECONOMY.md`
gained new §10.4 as the source of truth for the Vendor's rates.

---

## Post-Ship Fix — NPC Nameplate (2026-07-11)

**User-reported gap:** the Card Merchant had no name/title floating nameplate,
unlike every other NPC (Noob, the three Trainers). Root cause: the shared
`NameplateController.lua`/`NameplateService.lua` system (world-space
Part+SurfaceGui nameplates, driven by a static `NPC_DATA` table keyed by
model name) simply had no entry for `"Card Merchant"` and never scanned
`Workspace."Card Merchant"` — it only ever scanned `Workspace.Noob` and
`Workspace.Trainers`' children.

**Fix:** added `["Card Merchant"] = { displayName = "Card Merchant", title =
"Card Merchant" }` to `NameplateController.lua`'s `NPC_DATA` (same pattern
Noob uses — role name as the display name, not a personal name); added an
explicit `Workspace:WaitForChild("Card Merchant")` scan alongside the
existing Noob/Trainers scan. `NameplateService.lua` (server) gained a
matching `suppressDisplay` call so the Vendor's default Roblox
name/health-bar display is hidden the same way every other NPC's is.

Verified live: `[NameplateController] NPC nameplates registered: 5 NPCs`
(was 4), and direct inspection of the real `NameplatePart`/`SurfaceGui`
confirmed `TitleLabel.Text == "Card Merchant"`, `NameLabel.Text == "Card
Merchant"`, `Humanoid.DisplayDistanceType == "None"`,
`Humanoid.HealthDisplayType == "AlwaysOff"` — matching every other NPC
exactly.

**Follow-up hardening (2026-07-11, Codex):** user reported the Card Merchant
still had no visible nameplate. `NameplateController.lua` was hardened so the
NPC data is keyed by `"Card Merchant"` only, duplicate NPC registrations are
guarded, `Workspace."Card Merchant"` is scanned directly, and
`Workspace.ChildAdded` retries registration if the model/head appears after
the initial scan. `NameplateService.lua` remains aligned with the `Card
Merchant` model name for default Roblox name/health suppression. Verified by
source inspection/compile in Edit mode; live client was not available in this
turn.

---

## Post-Ship Fix — Recycle UI V2 (2026-07-11)

**User-requested UX change:** the destroy button inside `My Cards` was too
hidden and the protected-copy rule was confusing. The old one-card button is
removed from `pages.MyCards()` and replaced with a dedicated `Recycle` menu
on the Inventory home screen.

**Current Recycle behavior:** `Recycle` uses the same split layout language
as the card library/deck builder: owned cards on the left, queued cards on
the right, a `Recycle Selected` action, `Clear`, selected count, and total
Crystal Shards. Left-clicking a card queues one copy; clicking a queued row
removes one copy from the queue. The UI shows owned and queued counts on
the card badges.

**Current rules:** Recycle has no protected-copy floor. Unused cards can be
recycled to zero. Deck safety is the only blocker: when a queued recycle
would leave a card below its rarity threshold (Common/Rare/Epic=2,
Legendary=1), the code checks the maximum copies required by any single
saved deck. If the remaining count is still enough for that deck, the
selection is allowed silently; if not, the UI/server reject with a blocking
popup that says `Cant add card, used on deck` and has a `Confirm` button.
`DestroyCards` now aggregates
duplicate `{cardId, count}` rows before validating so multi-row requests
cannot bypass deck safety.

**Deck rule update:** Legendary cards are now max 1 copy in decks; Common,
Rare, and Epic remain max 2. `SaveService` validation and the deck-builder
add button both use this rarity-aware max.

**Verification:** headless tests covered recycle-to-zero for unused cards,
owned=2/deck-uses=1 allowing recycle 1, owned=2/deck-uses=2 blocking recycle
1 with `Cant add card, used on deck`, duplicate request aggregation in both
blocked and successful cases, shard totals, Legendary max-1 deck rejection,
and Common max-2 deck acceptance. `InventoryController` source also compiled
via `loadstring`, and source scans confirmed the old `DestroyButton` /
`Destroy 1 Copy` UI was removed. Follow-up source checks confirmed the
used-on-deck branch now opens the popup instead of writing the inline status
label, and the popup is cleaned up when Inventory closes.

---

## Explicitly out of scope this pass

- One-click "recycle every unused extra" automation. Recycle UI V2 supports
  deliberate multi-select batching, not automatic bulk cleanup.
- Per-player-tailored rotation — stock is global/deterministic this pass.
- Abuse-monitoring metrics (standing DESIGN_REWARD §11 deferred item,
  unrelated scope creep to pull in here).
