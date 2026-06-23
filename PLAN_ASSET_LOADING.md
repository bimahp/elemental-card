# PLAN — Reliable Asset Preloading + Branded Loading Screen

> Status: **Implemented & re-validated against the live Studio place (2026-06-22).** Pending one real-device first-join test before closing.
> Related: `DEV_STATUS.md` (module entries + Known Issues).

---

## Context

**Problem (reported):** On a non-Studio client (mobile / another device), card & UI art did **not** load on first join — the player had to leave and rejoin for art to appear.

**Diagnosis (verified via `GetProductInfo` on every asset, 2026-06-22):**
- Every gameplay asset (`[EC]`/`[SS]` card backgrounds, card art, ATK/HP/Energy icons, spell art, card-back, inventory icon, loading bg `99142567993225`) is **AssetType = Image (1)** and **owned by the place creator `2297144997`**.
- Rules out the three usual culprits: **not** Decal-vs-Image, **not** ownership/permission, **not** moderation.
- Symptom is the documented **transient cold-fetch failure cached as "failed" for the session** (DevForum reports match the exact "rejoin fixes it" pattern). Rejoin works because a fresh session re-issues the fetch.

**Why a loading screen alone is not the fix:** `ContentProvider:PreloadAsync` has **no built-in retry**, and with raw content-string IDs it assumes every ID is an image and fails at a high rate — passing **Instances** drops failures to ~0% (DevForum bug 2660912). The real fix is **preload-with-retry, using Instances**, behind a loading screen.

**Why a manifest is mandatory:** The failing card backgrounds/art/icons are created **dynamically at runtime** in `CardVisuals.buildCardFrame`/`updateCardFrame` — they don't exist as instances at join time, so a GUI-tree scan can't catch them. They must be enumerated.

**Chicken-and-egg (the loading screen's own background is also an asset):** The screen's functional layer uses **zero remote assets** — solid `BackgroundColor3` fill, default-font text, Frame-based progress bar (all render instantly). The background **image** is layered on top at full transparency and faded in only if/when it loads; if it never loads, the player keeps the solid color. So the screen can never be blank/broken.

**Outcome:** Art present on the **first** join (no rejoin), plus a branded loading screen as the vehicle that buys time to preload + retry.

---

## Approach (as built)

Three new client modules + one mechanical refactor.

- **`ReplicatedStorage.Modules.AssetIds`** — single source of truth for all gameplay image IDs; `criticalList()` returns the de-duped flat list the loading screen gates on.
- **`ReplicatedStorage.Modules.AssetPreloader`** — `preload(ids, opts)` builds a temp `ImageLabel` per id, `PreloadAsync`es the **Instances**, then re-preloads any failed asset up to `attempts` rounds (linear backoff), with progress callback + summary. `preloadInstances(insts)` = best-effort warm of existing instances.
- **`ReplicatedFirst.LoadingScreen`** — removes default GUI; builds the asset-free branded screen; preloads bg image (non-blocking fade-in), critical list (gated, with progress), and environment textures/mesh-part textures (best-effort); gates release on critical preload + `game.Loaded` with a **~12s hard timeout / continue-anyway**; fades out.
- **`StarterGui.BattleUI.Modules.CardVisuals`** — sources its IDs from `AssetIds` (no hardcoded `rbxassetid` strings).

**Design decisions:** two tiers (gameplay = critical/retried/gating; environment = best-effort/non-gating); gate timeout 12s; preload Instances never strings; single source of truth over a duplicated manifest.

---

## Checklist

### Investigation
- [x] Confirm no existing preloading in the place (`script_grep` → zero `PreloadAsync`)
- [x] Web research: PreloadAsync best practice, retry, Instances-vs-strings failure rate
- [x] Asset-health audit: `GetProductInfo` on every referenced ID (type + owner)
- [x] Rule out Decal-vs-Image / ownership / moderation
- [x] Verify loading bg `99142567993225` is Image-type and owned

### Implementation
- [x] `AssetIds` module + `criticalList()`
- [x] `AssetPreloader` (Instances + per-asset retry + progress + summary; best-effort `preloadInstances`)
- [x] `ReplicatedFirst.LoadingScreen` (asset-free screen, bg fade-in, gated critical + best-effort env, timeout/continue, fade-out)
- [x] Refactor `CardVisuals` to consume `AssetIds`
- [x] Update `DEV_STATUS.md` (module entries + Known Issues)

### Verification
- [x] Headless: `criticalList()` → 11 unique IDs; preload resolved 11/11
- [x] Headless: CardVisuals rebuilds creature/spell/back frames with correct resolved IDs (behavior-identical)
- [x] Studio play: `[LoadingScreen] preloaded 11/11 critical assets`, no failures, screen fades out cleanly (no hang)
- [x] Failure injection: bogus ID fails gracefully after retries in ~1.7s (`ok=false, loaded=1, failed=1`), no block
- [x] Codex re-validation (2026-06-22): Studio object map contains `ReplicatedStorage.Modules.AssetIds`, `ReplicatedStorage.Modules.AssetPreloader`, `ReplicatedFirst.LoadingScreen`, and `StarterGui.BattleUI.Modules.CardVisuals`; only `AssetPreloader` calls `PreloadAsync`; `CardVisuals` requires `AssetIds` and has no hardcoded `rbxassetid://` strings; `criticalList()` returns 11 IDs; Play mode printed `[LoadingScreen] preloaded 11/11 critical assets`; `PlayerGui.LoadingScreen` was destroyed after release.
- [x] Codex asset-reference scan (2026-06-22): editor-placed `StarterGui` image assets are covered by the critical list (`DeckPanel` energy icon, HUD inventory icon/outline). Workspace decor contains many third-party cafe/baseplate/noob texture IDs that are intentionally **not** critical; the current best-effort environment warm scans `ImageLabel`, `ImageButton`, `Decal`, `Texture`, and `MeshPart` under `Workspace`/`Lighting`.
- [ ] **Real-device first-join test** — publish, join on the non-Studio device that originally failed (ideally fresh / cache-cleared), confirm art present on the **first** join with no rejoin *(only this proves the original bug fixed — Studio joins with a warm cache and can't reproduce it)*
- [ ] Save the Studio place to persist the three new scripts

---

## Critical files
| File | Change |
|---|---|
| `ReplicatedStorage.Modules.AssetIds` | NEW — id source of truth + `criticalList()` |
| `ReplicatedStorage.Modules.AssetPreloader` | NEW — preload + retry utility (Instances) |
| `ReplicatedFirst.LoadingScreen` | NEW — branded screen, solid-color fallback, run preloader, timeout/continue |
| `StarterGui.BattleUI.Modules.CardVisuals` | REFACTOR — source IDs from `AssetIds` |
| `DEV_STATUS.md` | docs — new module entries + Known Issues |

> Scripts live in the Studio place (not the repo) — created via the Studio MCP. Save the place to persist.

## Out of scope (logged in DEV_STATUS Known Issues)
- Generating/wiring missing card art (separate 🔴 issue).
- 🟡 Archived/unauthorized **sound** assets (`1914538756` archived, `150463355` unauthorized) — still present in the 2026-06-22 Codex Play check; sounds, not images.
- 🟢 Stray `rbxassetid://0` empty image — harmless leftover from the audit.
- 🟢 Workspace decor `SpecialMesh.TextureId` assets are not included in the current best-effort environment warm. Gameplay/UI image loading is covered; this only affects non-critical cafe props.
- Balance tuning.

## Tuning knobs (constants in `LoadingScreen` / `AssetPreloader`)
- `GATE_TIMEOUT = 12` — max hold before continue-anyway
- `BG_TIMEOUT = 4` — max wait on decorative bg image
- `attempts = 3` — critical preload retry rounds
- backoff `0.35 * round` between retry rounds
