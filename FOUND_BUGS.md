### Critical

### Major

### Fixed
- ~~Card Battle Revamp post-review blockers (PvP mulligan timeout stall, partial
  `animEvents` replay, skip cancellation, `cast_reveal` frame restore).~~
  Fixed 2026-07-09 in live Studio: `DuelSession` now tracks mulligan timeout
  tokens per seat; `BattleUIController` queues phases from the full ordered
  `animEvents` list; `BattleDirector.skip()` cancels active tracked phase work
  and drops queued phase handlers; `PhaseRegistry.cast_reveal` restores Size and
  ZIndex and uses cancellation-aware delay/tween helpers.
- ~~Damage from fail to draw is not lethal, i had 0 HP because drawn from empty deck, and only dead after i try to attack with my creature that still on board (maybe then its triggered the health check)~~
  Root cause: `Logic.checkWin` was only ever called from `DuelSession.afterHumanAction` (after a `PlayCard`/`DeclareAttack`) and from `runNpcTurn` after the NPC's own actions — never after `Logic.startTurn` (draw/Fatigue) or after `Logic.endTurn` (turn_end effects). A hero could hit 0 HP from Fatigue at the start of a turn and the battle would keep running until the next human action happened to route through the existing check. Fixed by adding a `checkAndEnd` call right after `Logic.startTurn` in `startSeatTurn`, and after `Logic.endTurn` in both `humanEndTurn` and `runNpcTurn` (`ServerScriptService/Modules/DuelSession.lua`). Verified headless: a side with an empty deck and 1 HP is now correctly ended at the draw step with no further broadcast/timer/NPC-turn spawned for the dead side; normal turns are unaffected.
