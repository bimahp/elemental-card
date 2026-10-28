# PLAN_PLAYER_STATUS - Player Status and Titles

**Status:** Implemented and verified in Roblox Studio on 2026-08-25.

## Delivered Experience

- A dedicated `Profile` icon (asset `134348501295873`) occupies the
  far-left HUD slot, with Deck centered and Matchmaking rightmost, and follows
  the HUD's battle visibility lifecycle.
- `PlayerStatusUI` is a safe-area, input-sinking modal with desktop bounds,
  landscape-mobile sizing, loading/error/retry states, and Overview/Titles tabs.
- Overview shows identity, equipped title, archetype, level and EXP progress,
  PvP record/win rate, unique collectible progress, and trainer first clears.
- Titles explains locked requirements and permits only owned titles to be equipped.
- The equipped title persists and replicates through `Player.EquippedTitleId`;
  every client resolves it through `TitleConfig` for the world nameplate.

## Data and Interfaces

Schema v5.4 adds `ownedTitles = { beta_tester = true }` and
`equippedTitle = "beta_tester"`. The v5.3 -> v5.4 migration is non-destructive.
`TitleService.reconcile` retroactively evaluates completed onboarding archetype,
all three trainer clears, 10/50 PvP wins, and 50/100 unique collectible cards.
Unlocks remain owned after they are earned.

- `GetPlayerStatus` returns `{ok=true,data=status}` or `{ok=false,error=...}`.
- `EquipTitle(titleId)` uses the same envelope and rejects malformed, unknown,
  and locked IDs server-side.
- `TitleConfig` is shared metadata; `TitleService` owns pure rules; `SaveService`
  remains the only profile mutation owner.
- `the_coin` remains explicitly non-collectible. Runtime totals are derived from
  `Definitions.Cards`.

## Initial Titles

| ID | Requirement |
|---|---|
| `beta_tester` | Available to all players |
| `mighty_disciple` | Complete onboarding with MIGHTY |
| `swift_disciple` | Complete onboarding with SWIFT |
| `vital_disciple` | Complete onboarding with VITAL |
| `trainer_champion` | Defeat all three trainers |
| `duelist` | Win 10 PvP battles |
| `battle_veteran` | Win 50 PvP battles |
| `crystal_collector` | Own 50 unique collectible cards |
| `crystal_archivist` | Own 100 unique collectible cards |

## Verification

- `TestService.PlayerStatusSpec` passes migration preservation, default and
  retroactive unlocks, thresholds, idempotency, permanent unlocks, equip
  validation, duplicate/non-collectible counting, and max-level progress.
- Live profile response verified level 12, nine catalog titles, and 132
  collectible cards.
- Live equip changed both `EquippedTitleId` and the world nameplate to
  `Swift Disciple`; the test then restored `Beta Tester`.
- Locked, unknown, and malformed equip requests returned authoritative errors.
- Desktop and simulated 760x420 landscape-mobile layouts reported no text
  overflow; Titles produced nine rows in a clipped scrolling canvas.
- `PlayerStatusUITest` is a Studio-only `BindableFunction` for deterministic
  open/close/tab/refresh/viewport checks when simulated clicks are unavailable.
