# Project memory

Owner decisions for every agent (Claude and Codex), newest first. Instructions are in [CLAUDE.md](CLAUDE.md); status is in [docs/HANDOFF.md](docs/HANDOFF.md). Record a decision here when the owner makes one that a future session could otherwise re-open.

## Game code in the repo — user decision, 2026-10-29

Same concept as ant-verse: `src/` at the repo root mirrors every script in the place and is the source of truth. Code is changed in `src/`, pushed into Studio through the MCP, and checked by checksum on both sides. This replaces "all game code lives only in Studio". Still no Rojo.

## UI/UX infrastructure from ant-verse — user decision, 2026-10-29

From [docs/research/ANTVERSE_UI_INFRASTRUCTURE.md](docs/research/ANTVERSE_UI_INFRASTRUCTURE.md) §7:

- **Editor-first stays the rule, and the code is migrated to meet it.** Screen by screen into authored kit templates; the battle goes last, with its own plan. Code only clones, fills, positions and animates.
- **Scale decides size, mode decides layout.** Every layer is authored at 1280 × 720 with one `UIScale` and the 80 px tap / 26 px text floors. The battle keeps its separate mobile grid, chosen by `PreferredInput` and screen size, never by last input.
- **Layers:** HUD, Panels and Popups. The world panels (Card Library, Vending Machine, Card Vendor, Item Mall, Matchmaking, Profile, and the new Settings) move into Panels under one `PanelCoordinator` (one panel open; Escape goes back). Built: Escape turned out to belong to the Roblox menu, so gamepad B goes back and a keyboard key is open ([UI §11](docs/UI.md)). BattleUI, PackOpen and Mulligan stay their own ScreenGuis.
- **Versioning:** every UI change is an idempotent Studio migration script kept in this repo, plus a JSON export of each changed root.
- **Settings:** Music and SFX volume, UI size (80–130%), faster battle animations. Nothing else until it does something.
- **Saves:** settings ship with a **major** schema bump that wipes profiles. The owner approved the wipe ("this is unreleased game").
- **Dialogue:** one dialogue config with speakers (name tag, portrait) and conversations by id; the server sends ids; conversations queue. Keep the typewriter, camera tween and focus mode. Option buttons become a kit template.
- **Order:** foundations first (kit folder, scale controller, input detection, coordinator, movement lock, feedback toast), then one small panel converted end to end to prove the pipeline, then the larger screens, battle last.

## Docs of record — user decision, 2026-10-28

The docs follow the ant-verse pattern, with every doc in `docs/`: six docs of record (`GAME_DESIGN`, `CARDS`, `MONETIZATION`, `ARCHITECTURE`, `UI`, `ART`), a lean `HANDOFF`, build records in `plans/`. Only `README`, `CLAUDE` and `AGENTS` stay at the root, where GitHub, Claude Code and Codex look for them. The old `DESIGN_*`, `IDEA_*`, `DEV_STATUS` and `FOUND_BUGS` were merged and moved to `docs/archive/`. Card data moved to `data/`. `assets/` (card images and other art) is gitignored. The owner is revisiting the project with a new inspiration; the merged docs are the baseline for it.

## Player Status and titles — 2026-08-25

Titles are permanent cosmetic milestones that never change gameplay. One equipped title shows on the world nameplate. The Profile icon sits far left in the HUD, Deck centre, Matchmaking right.

## Recycle and Legendary deck limit — user decision, 2026-07-11

The My Cards destroy button was too hidden and the protected-copy rule confusing. Recycle is its own Card Library page with multi-select queueing. **No protected-copy floor**: unused cards can be recycled to zero; the only block is a recycle that would break a saved deck ("Cant add card, used on deck"). Legendaries are max 1 per deck; other rarities max 2.

## Card Vendor — user decision, 2026-07-11 (do not re-litigate)

- No automatic duplicate conversion; Recycle is a deliberate manual action and the only free Shard source.
- **Buy = twice the original base crafting rate** (the owner tried ×4 and brought it back to ×2): 40 / 160 / 600 / 2,400 Shards.
- **Craft is priced off a pack's cost per card slot**, not blind-roll expected value (that would put an Epic past two months at the daily cap, which is not fun): 500 / 1,500 / 4,000 / 15,000 Card Fragments.
- Legendary is wired everywhere although no Legendary exists yet.
- Stock is 6 cards (3 Common, 2 Rare, 1 Epic), global, rotating at 00:00 / 08:00 / 16:00.

## Economy revamp scope — user decision, 2026-07-10

Card Fragments replaced Crystal Dust. An NPC fallback found through matchmaking pays Matchmaking rates. **Deferred on purpose:** daily quests (the next step after the revamp), abuse-monitoring metrics (a `TODO` in `BattleController`), the full four-product pack catalog, and the same-opponent reward cooldown (after alpha).

## Matchmaking disconnects — user decision, 2026-07-10

A disconnect in a matchmaking battle pauses the seat instead of forfeiting; only the normal turn-timeout streak (2 timeouts) forfeits. Local PvP keeps instant forfeit on disconnect.

## Abandon detection — 2026-06-21

Penalise rage-quits reliably by marking both players in-match (force-saved) at match start and resolving a still-marked match as a loss on the player's next login, not at disconnect.

## Battle Charge sockets — user decision

The two Charge sockets on the hero card must be as prominent as the board ATK/HP emblems, never tiny dots.

## Editor-first UI — user decision

Build every UI as real `StarterGui` instances in Studio, not in code. Image-icon outlines use a layered dark copy of the image, not `UIStroke`.

## Working style — user decision

The owner wants direct, unvarnished critique of design ideas, not validation. Flag architecture corrections mid-build instead of deciding silently.
