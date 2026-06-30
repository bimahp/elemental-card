# PLAN — Reliable Asset Preloading + Branded Loading Screen

> Status: **Implemented and reworked against Roblox's documented preload contract (2026-06-30).** A real-device cold-cache test is still required.

## Problem

Card and UI art could be absent on a player's first join but appear after rejoining. The assets are dynamic, so scanning the initial GUI tree cannot discover all of them.

The earlier loader did pass an array to `ContentProvider:PreloadAsync`, but it decided success by polling `ImageLabel.IsLoaded` and retried/cancelled whole batches. That could report false failures even when `PreloadAsync` had processed the request.

## Implemented contract

- `AssetPreloader.preload` accepts only a dense numeric array. Dictionary and sparse tables are rejected.
- Every image request calls `PreloadAsync({ imageLabel }, callback)` with a literal one-element array.
- The callback's final `Enum.AssetFetchStatus` is primary. A concurrent documented
  `GetAssetFetchStatus(id) == Success` observation can complete an already-cached
  request when Studio does not return from `PreloadAsync`. `ImageLabel.IsLoaded`
  and `ContentProvider.RequestQueueSize` are not used.
- Each asset has its own retry and timeout. A failed asset cannot cancel or misclassify the rest of the batch.
- A bounded worker pool avoids flooding the request queue.
- Progress and final failures are reported by authored asset ID.

## Two-tier loading

Roblox recommends preloading only assets required immediately instead of an entire place or library. The client therefore uses two gates:

1. `AssetIds.startupList()` contains shared card chrome and common UI images. `ReplicatedFirst.LoadingScreen` gates only this small list.
2. `AssetIds.revealList(result.cards)` adds the exact artwork for the five cards returned by the server. `PackRevealController` completes this gate before creating and displaying the 3D card stage.

`AssetIds.criticalList()` remains available as the de-duplicated full-library list for audits and tooling; it is intentionally not the login gate.

The loading screen's functional layer still uses no remote assets. Its decorative
background remains best-effort. Workspace/Lighting is deliberately not bulk
preloaded because it competes with the essential queue and Roblox recommends
streaming non-essential world content normally.

## Runtime flow

1. Show the asset-free loading UI.
2. Retry callback-verified startup assets with four concurrent workers.
3. Release the loading screen after the bounded startup cycle.
4. On a successful pack purchase, show `Preparing cards…` and preload shared reveal art plus the exact five card artworks.
5. Continue to the burst and rigid 3D reveal. If an ID exhausts retries, log it and allow normal Roblox rendering/fallback behavior instead of trapping the player.

## Verification

- [x] Preload input is a dense array; dictionary-shaped inputs are rejected.
- [x] Each `PreloadAsync` call receives `{ imageLabel }`.
- [x] Completion uses the callback and documented fetch status, not `IsLoaded`.
- [x] Login gates `startupList()`, not all card art.
- [x] Pack reveal gates `revealList(result.cards)` before constructing SurfaceGuis.
- [x] Full-library `criticalList()` remains available for coverage audits.
- [x] Studio bounded-failure test: the session accepted the new scripts, rejected a
  dictionary input, reported 6/11 startup IDs as `Success`, and released the loading
  screen after five timed out. Roblox's own documented sample asset also failed to
  return from `PreloadAsync` in this Studio session, so this environment is not a
  valid cold-delivery success oracle. A later warmed-cache play run completed 11/11.
- [ ] Publish and test on the original device with a cold cache; confirm first-draw front/back/card chrome loads without rejoining.

## Main files

| Studio object | Responsibility |
|---|---|
| `ReplicatedStorage.Modules.AssetIds` | Shared IDs plus `startupList`, `revealList`, and full audit list |
| `ReplicatedStorage.Modules.AssetPreloader` | Array validation, callback status, per-ID retry, timeout, and progress |
| `ReplicatedFirst.LoadingScreen` | Branded startup UI and essential-asset gate |
| `StarterPlayer.StarterPlayerScripts.PackRevealController` | Exact-five preparation gate before 3D reveal |

## Tuning

- Startup and reveal: `attempts = 2`, `assetTimeout = 6`, `concurrency = 4`.
- Decorative loading background: `attempts = 2`, `assetTimeout = 4`, `concurrency = 1`.
- Workspace and Lighting are not bulk preloaded.

## References

- [Roblox ContentProvider API](https://create.roblox.com/docs/reference/engine/classes/ContentProvider)
- [Roblox load-time performance guidance](https://create.roblox.com/docs/performance-optimization/improve)
