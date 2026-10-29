# Elemental TCG — Status and Handoff

**Last updated:** 2026-10-29. Docs checked against the Studio place; granted Charge now lifts summoning sickness (`Ops.addKeyword`); prompts hide while seated; old `Battle Tables` removed.

Keep this file short: current state, what is next, how work is done. History belongs in git and in [plans/](plans/), not here.

---

## 1. Where the game stands

Alpha, playable in Studio, not public. SaveService schema **v5.4**.

| Area | State | Design |
|---|---|---|
| Battle engine: effects[], two-slot board-generated Battle Charge, explicit `playTarget` targeting | Built | [GAME_DESIGN §3](GAME_DESIGN.md), [CARDS §5](CARDS.md) |
| 132 cards in 4 sets, 3 starter decks, deck builder | Built | [CARDS](CARDS.md), [GAME_DESIGN §4](GAME_DESIGN.md) |
| Battle presentation Director, mulligan, turn timer | Built | [UI §4–8](UI.md) |
| NPC, Local and cross-server Matchmaking battles; reconnect | Built, published multi-server test pending | [GAME_DESIGN §5](GAME_DESIGN.md) |
| Card Fragments, battle rewards, caps, forfeit ladder, Result UI | Built | [MONETIZATION §3](MONETIZATION.md) |
| Vending Machine (one Standard Pack, live odds, 3D reveal) | Built | [MONETIZATION §5](MONETIZATION.md) |
| Card Vendor (Craft/Buy) and Recycle | Built | [MONETIZATION §6–7](MONETIZATION.md) |
| Robux Shard shop (hidden where paid random items are restricted) | Built with legacy bundle sizes; real-purchase test pending | [MONETIZATION §8](MONETIZATION.md) |
| Trainer battles after onboarding | Built | [GAME_DESIGN §8](GAME_DESIGN.md) |
| Onboarding quest, levels, titles, Profile panel | Built | [GAME_DESIGN §6–7](GAME_DESIGN.md) |
| Daily quests and quest refresh | **Not built** | [MONETIZATION §4](MONETIZATION.md) |
| Core Mighty/Swift/Vital pack products | **Not built** | [MONETIZATION §5](MONETIZATION.md) |
| Archetype-aware AI, Noob/Pro tiers | **Not built** (planning) | [plans/PLAN_AI_ARCHETYPE.md](plans/PLAN_AI_ARCHETYPE.md) |
| UI infrastructure: layers, scaling, kit, coordinator, movement lock, feedback, settings, dialogue ids | **Not built** | [UI §10](UI.md), [ARCHITECTURE §12](ARCHITECTURE.md) |
| Abuse monitoring, spectating, mastery, trading, ranked | **Not built** | — |

## 2. Next

1. **The owner is revisiting the project with a new inspiration.** Settle the new direction in the docs of record first, then plan.
   - UI/UX infrastructure: designed in [UI §10](UI.md) and [ARCHITECTURE §12](ARCHITECTURE.md) (from [research/ANTVERSE_UI_INFRASTRUCTURE.md](research/ANTVERSE_UI_INFRASTRUCTURE.md)). Building [PLAN_UI_FOUNDATIONS](plans/PLAN_UI_FOUNDATIONS.md): steps 1–6 are done (export and checks, `ReplicatedStorage.Kit` and `UIKit`, the Panels/Popups/PanelBackdrop layers, UI scaling and the `UXMode` fix, `PanelCoordinator`, `MovementLock`); next is step 7, feedback. Settings ship with a profile wipe (approved). Open: [UI §11](UI.md).
2. Work through the open decisions: [GAME_DESIGN §9](GAME_DESIGN.md) and [MONETIZATION §10](MONETIZATION.md).
3. Then the queued work from before the pause: daily quests, then [PLAN_AI_ARCHETYPE](plans/PLAN_AI_ARCHETYPE.md).

## 3. Checked in Studio

On 2026-10-29 the docs were checked against the place ("Crystal Element Battle Cards", placeId 73986817887222): configs, battle rules, rewards, saves, matchmaking, cards and decks. The docs now follow the code. What is still unverified:

- [ ] Anything that needs a published place: cross-server teleport, reconnect, real Robux purchases.
- [ ] UI layout numbers in [UI.md](UI.md) beyond the spot checks (mobile switch at 800 px, attack timings).

## 4. Known issues

| Issue | Priority |
|---|---|
| The editor-first rule is not met: client code builds most UI (about 364 GUI `Instance.new` call sites; [research §3.2](research/ANTVERSE_UI_INFRASTRUCTURE.md)) | High |
| In Studio Play on 2026-10-29, the Noob's `TalkPrompt` (NPC battle) did not trigger from E or `InputHoldBegin`, though enabled, in range and with prompts on; the Card Merchant and table prompts worked. Unexplained; check by hand ([plan step 6](plans/PLAN_UI_FOUNDATIONS.md)) | Medium |
| In 1 of 4 Play runs on 2026-10-29, `UXMode` started as Mobile on a desktop window and then switched to Desktop on its own. The cause was not caught; `UXMode` now logs the viewport and input behind every decision | Low |
| The game has no music or sound effects ([UI §11](UI.md)) | Medium |
| A card named "Stonebark Pack" (swapped with the set name) ships in the SWIFT starter; renaming needs a save migration ([CARDS §6](CARDS.md)) | Medium |
| One pack can give a third copy: duplicate protection reads ownership once per pack ([MONETIZATION §5.2](MONETIZATION.md)) | Low |
| Cross-server matchmaking and reconnect never tested in a published place (Studio cannot teleport between instances) | Medium |
| No full multi-turn battle played through simulated clicks to a real reward | Medium |
| No two-player Local Server PvP smoke (sit, ready, timers, forfeit, disconnect) | Medium |
| Robux shop uses legacy bundle sizes; no real published purchase yet | Medium |
| Balance unknown: last simulations predate board-generated Charge | Medium |
| Archived or unauthorized **sound** assets spam the console (`rbxassetid://1914538756`, `150463355`) | Medium |
| Asset preloading needs a real-device cold-cache test | Low |
| Orphaned remotes and `CrystalCores` ([ARCHITECTURE §11](ARCHITECTURE.md)) | Low |
| Placeholder icons: Card Fragment reuses the old Dust icon; the Vendor reuses the Vending icon | Low |
| One stray empty image (`rbxassetid://0`) | Low |
| NPC foot orientation (Z rotation) | Low |
| Recycle's positive in-UI click path was never exercised live (the remote was) | Low |

## 5. How work is done

- **Code lives in `src/`** and is pushed into Studio through the Roblox Studio MCP ([ARCHITECTURE §1](ARCHITECTURE.md)). Confirm the right place is open (`list_roblox_studios`) before any edit; another project's place may be the one connected. Compare checksums before and after every push ([scripts/README.md](../scripts/README.md)).
- **Editor-first UI:** build UI as real instances in Studio, never `Instance.new` in code. Every UI change is a migration script in the repo plus an export ([ARCHITECTURE §12.1](ARCHITECTURE.md)).
- **Before building:** the design is settled in the doc of record; large work gets a plan in [plans/](plans/).
- **After building:** test pure modules headless and player-facing paths in Studio Play through real remotes; know the tooling limits in [ARCHITECTURE §10](ARCHITECTURE.md); update the doc of record and this file in the same session; remind the owner to save the place.
- **Saves:** a schema minor bump needs a migration; a major bump wipes profiles and needs the owner's explicit yes.

## 6. Build records

Plans are build records: how something was built and verified, with its decisions at the time. They never override a doc of record.

| Plan | What | State |
|---|---|---|
| [PLAN_BACKEND](plans/PLAN_BACKEND.md) | Server-owned battles, PvP, ProfileStore saves, inventory, deck builder | Done |
| [PLAN_BATTLE_CHARGE](plans/PLAN_BATTLE_CHARGE.md) | Crystal Core removed; two-slot Battle Charge | Done, superseded by V2 |
| [PLAN_BATTLE_CHARGE_USAGE](plans/PLAN_BATTLE_CHARGE_USAGE.md) | Charge costs, `CardCost`, Corrupted trait | Done |
| [PLAN_BATTLE_CHARGE_V2](plans/PLAN_BATTLE_CHARGE_V2.md) | Board-generated Charge, new Charge actions, redesigned packs | Done |
| [PLAN_BATTLE_TARGET](plans/PLAN_BATTLE_TARGET.md) | Explicit spell `playTarget`, zone drops | Done |
| [PLAN_QUEST_LEVEL](plans/PLAN_QUEST_LEVEL.md) | Onboarding quest, levels, dialogue, quest HUD | Done |
| [PLAN_CARD_ACQUISITION](plans/PLAN_CARD_ACQUISITION.md) | First Vending Machine (Shard packs, Dust) | Obsolete |
| [PLAN_ASSET_LOADING](plans/PLAN_ASSET_LOADING.md) | Asset preloading, loading screen | Done; device test pending |
| [PLAN_MONETIZATION](plans/PLAN_MONETIZATION.md) | Vending revamp, live odds, Robux Item Mall | Obsolete economy; UI still in use |
| [PLAN_CARD_BATTLE_REVAMP](plans/PLAN_CARD_BATTLE_REVAMP.md) | Event log, BattleDirector, mulligan | Done |
| [PLAN_MATCHMAKING](plans/PLAN_MATCHMAKING.md) | Cross-server queue, NPC fallback, reconnect | Done; published test pending |
| [PLAN_ECONOMY_REVAMP](plans/PLAN_ECONOMY_REVAMP.md) | Card Fragments, rewards, caps, Result UI | Done |
| [PLAN_CARD_VENDOR](plans/PLAN_CARD_VENDOR.md) | Card Vendor, Craft/Buy, Recycle | Done |
| [PLAN_PLAYER_STATUS](plans/PLAN_PLAYER_STATUS.md) | Profile panel, titles, nameplates | Done |
| [PLAN_AI_ARCHETYPE](plans/PLAN_AI_ARCHETYPE.md) | Archetype AI, Noob/Pro, trainer dialogue | Planning |
| [PLAN_UI_FOUNDATIONS](plans/PLAN_UI_FOUNDATIONS.md) | UI pipeline, kit, layers, scale, coordinator, movement lock, feedback; Matchmaking panel | Steps 1–6 of 9 done |

[archive/](archive/) holds the pre-2026-10-28 design docs, `DEV_STATUS` and `FOUND_BUGS`, kept only until the merge is reviewed. Do not use them.
