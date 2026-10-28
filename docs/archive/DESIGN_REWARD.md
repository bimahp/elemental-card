> **Archived 2026-10-28 — do not use.** Merged into [MONETIZATION.md](../MONETIZATION.md) §3–4 and [GAME_DESIGN.md](../GAME_DESIGN.md) §5.4–5.5. Kept only until the merge is reviewed; the doc of record wins on any difference.

# Battle Reward & Valid Battle Specification

> Finalized battle reward rules for Card Fragments, valid battle detection, forfeit handling, local/NPC rewards, daily caps, and anti-abuse monitoring.

> **Source of truth:** This document is authoritative for reward values, battle
> validity, caps, forfeits, and reward abuse controls. Currency behavior, pack
> pricing, crafting, and paid products are owned by
> [DESIGN_ECONOMY.md](DESIGN_ECONOMY.md). Older plans are implementation history
> and do not override either specification.

---

## 1. Design Goal

Battle rewards should support this economy:

```text
Card Fragments = unpaid gameplay currency
Card Fragments are used to open random card packs
Core Pack cost = 200 Card Fragments
```

The battle reward system must:

- Reward real gameplay.
- Make matchmaking the main battle-based progression source.
- Keep daily and weekly quests as the primary Card Fragment source.
- Let Local and NPC battles feel rewarding without becoming farmable.
- Punish early forfeits without punishing innocent opponents too much.
- Prevent abuse from friends, alts, bots, and repeated match-fixing.
- Keep rules simple enough for players and implementable on the server.

---

## 2. Core Pack Cost

```text
1 Core Pack = 200 Card Fragments
```

This applies to:

```text
Core Mighty Pack
Core Swift Pack
Core Vital Pack
```

Future pack costs may differ, but this battle reward document assumes:

```text
Core Pack cost = 200 Card Fragments
```

---

## 3. Battle Mode Categories

The game has three battle modes:

```text
1. Matchmaking Battle
2. Local Battle
3. NPC Battle
```

Each mode has different reward rules.

| Battle Type | Card Fragment Role | Main Purpose |
| --- | --- | --- |
| Matchmaking | Main battle reward source | Real PvP progression |
| Local Battle | Small reward under global cap | Friendly play / practice |
| NPC Battle | Small repeat reward + first-clear bonus | Tutorial / practice |

---

## 4. Final Reward Values

### 4.1 Matchmaking

```text
Valid matchmaking win = 3 Card Fragments
Valid matchmaking loss = 1 Card Fragment
Winner vs early forfeiter = 2 Card Fragments
Early forfeiter = 0 Card Fragments
```

| Matchmaking Result | Card Fragments |
| --- | ---: |
| Valid win | 3 |
| Valid loss | 1 |
| Win because opponent early-forfeits | 2 |
| Early forfeit loss | 0 |

Reasoning:

```text
A quick battle ending is already a benefit to the winner.
Therefore, early-forfeit wins should reward less than a full valid win.
```

---

### 4.2 Local Battle

```text
Local win = 1 Card Fragment
Local loss = 0 Card Fragments
```

| Local Result | Card Fragments |
| --- | ---: |
| Win | 1 |
| Loss | 0 |

Local battle should be rewarding but not efficient for farming.

---

### 4.3 NPC Battle

```text
NPC win = 1 Card Fragment
NPC loss = 0 Card Fragments
First-time NPC clear = 50 Card Fragments
Fixed card reward = removed
```

| NPC Result | Card Fragments |
| --- | ---: |
| Win | 1 |
| Loss | 0 |
| First-time clear | 50 |

Fixed card rewards are removed because choosing which card to grant is difficult and may create balance problems.

---

## 5. Daily Quest Card Fragment Rewards

Daily quests are a major Card Fragment source.

```text
3 daily quests
Each quest = 30 Card Fragments
Total = 90 Card Fragments/day
```

| Daily Quest | Card Fragments |
| --- | ---: |
| Quest 1 | 30 |
| Quest 2 | 30 |
| Quest 3 | 30 |
| Total | 90 |

Daily quests alone give:

```text
90 / 200 = 0.45 Core Pack/day
```

This means:

```text
Daily quests alone = 1 Core Pack every 2.22 days
```

---

## 6. Daily Caps

Daily caps are used mostly to prevent bots, abuse, and extreme farming.

### 6.1 Global Battle Reward Cap

```text
Daily global battle Card Fragment cap = 200
```

The global cap is shared by normal rewards from:

```text
- Matchmaking Battle
- Local Battle
- Repeat NPC Battle
```

Matchmaking can earn the full cap when no other battle mode has consumed part of
it. The maximum normal battle income is therefore one 200-Fragment Core Pack per
day. Daily and weekly quests do not consume the battle cap.

First-time NPC clear rewards are one-time progression bonuses and do not consume
the battle cap.

After the cap:

```text
- No more Card Fragments from normal battle rewards
- EXP may continue
- Ranked/MMR may continue
- Quest progress may continue
- Cosmetic/social progress may continue
```

Player-facing message:

```text
Daily battle Card Fragment limit reached.
You can still play for EXP, rank, and quests.
```

---

### 6.2 NPC Repeat Sub-Cap

```text
Daily repeat NPC Card Fragment cap = 10
```

Meaning:

```text
Maximum repeat NPC reward = 10 Fragments/day
```

Repeat NPC rewards stop at 10 Fragments even when room remains under the global
battle cap. First-time NPC clear rewards do not count against either cap.

---

## 7. Same-Opponent Reward Cooldown

Alpha does not impose a same-opponent reward limit. The shared 200-Fragment battle
cap is the launch protection for Matchmaking and Local Battle rewards.

A same-opponent reward cooldown is planned after alpha. Its duration and counting
rules must be specified here before implementation; no historical `2 battles/day`
value is authoritative.

---

## 8. Valid Matchmaking Battle

A matchmaking battle must be valid to give full win/loss rewards.

### 8.1 Player-Facing Rule

```text
Rewards require a real battle.
Very early surrender, AFK, or repeated farming will not give rewards.
```

Do not expose all anti-abuse details to players.

---

### 8.2 Server-Side Valid Battle Rule

A matchmaking battle is valid if:

```text
- Battle is public matchmaking.
- Player is not AFK.
- Player performed meaningful actions.
- Turn 4 was reached OR meaningful battle activity was reached.
- Global daily battle Card Fragment cap is not exceeded.
```

---

### 8.3 Meaningful Actions

A player should be considered active if they perform meaningful gameplay actions.

Meaningful actions include:

```text
- Playing a card
- Summoning a monster
- Attacking
- Using a skill/spell
- Dealing damage
- Targeting an enemy
- Ending turn after spending energy
```

Recommended rule:

```text
Player must perform at least 2 meaningful actions
to qualify for normal matchmaking rewards.
```

---

### 8.4 Turn Requirement

A strict turn requirement alone is not enough.

Use this instead:

```text
Normal win/loss reward requires:
Turn 4 reached OR meaningful activity threshold reached
```

This allows real short matches while blocking fake instant matches.

---

## 9. Forfeit Handling

Forfeit rules should punish the quitter, but still compensate the opponent.

### 9.1 Early Forfeit

An early forfeit means:

```text
The player forfeits before the battle becomes valid.
```

Early forfeit result:

| Player | Reward |
| --- | --- |
| Early forfeiter | 0 Card Fragments |
| Opponent | 2 Card Fragments |

This is lower than a normal win.

```text
Normal win = 3
Early-forfeit win = 2
```

Reason:

```text
The winner already benefits from a quick match ending.
```

---

### 9.2 Forfeit After Valid Battle

If a player forfeits after the battle already became valid:

| Player | Reward |
| --- | --- |
| Forfeiter | Valid loss reward = 1 |
| Opponent | Valid win reward = 3 |

This avoids punishing normal strategic surrender after the game is clearly lost.

---

### 9.3 Disconnect

Disconnect should use reconnect grace.

```text
If player disconnects:
- Give 60 seconds to reconnect.
- If player returns, continue battle.
- If player does not return, treat as forfeit.
```

---

## 10. Forfeit Punishment

Early forfeits should have escalating punishment.

### 10.1 Early Forfeit Penalty Ladder

| Early Forfeits Today | Penalty |
| --- | --- |
| 1st | Warning |
| 2nd | 2-minute matchmaking cooldown |
| 3rd | 5-minute matchmaking cooldown |
| 4th | 15-minute matchmaking cooldown |
| 5th+ | 30-minute matchmaking cooldown |

The counter resets daily.

---

### 10.2 No Immediate Winner Punishment

At launch, do not punish the winner for receiving many early-forfeit wins.

Instead:

```text
Winner vs early forfeiter always gets 2 Card Fragments
as long as the global daily battle cap allows it.
```

Use monitoring metrics first. Punishment for suspicious winners can be defined later after real data is available.

---

## 11. Abuse Monitoring Metrics

Track suspicious patterns from both sides:

```text
1. Forfeiter-side abuse
2. Winner-side abuse
```

This is necessary because alt farming may use many throwaway accounts to feed one main account.

---

### 11.1 Forfeiter-Side Metrics

Track:

```text
- Early forfeits per day
- Consecutive early forfeits
- Average time before forfeit
- Average turn before forfeit
- Meaningful actions before forfeit
- Repeated losses to the same player
- New-account status
```

Possible future punishment triggers:

```text
- Too many early forfeits in one day
- Repeated early forfeits with zero meaningful actions
- Repeated early forfeits against the same winner
```

---

### 11.2 Winner-Side Metrics

Track:

```text
- Number of wins caused by enemy early forfeit
- Percentage of wins caused by enemy early forfeit
- Early-forfeit wins from repeated opponents
- Early-forfeit wins from new accounts
- Average match duration of wins
- Opponent meaningful action count before forfeit
```

Monitoring flag examples:

```text
Flag player if:
- More than 50% of daily wins are enemy early forfeits
AND
- At least 10 early-forfeit wins in one day
```

Stronger suspicious signals:

```text
- 10+ early-forfeit wins in one day
- 5+ early-forfeit wins from very new accounts
- Multiple early-forfeit wins from repeated opponent clusters
```

At launch:

```text
Only monitor these metrics.
Do not automatically punish the winner yet.
```

---

## 12. Reward Calculations

### 12.1 Matchmaking Expected Reward

Matchmaking rewards:

```text
Win = 3
Loss = 1
```

Expected reward per match:

```text
Expected reward = win_rate x 3 + loss_rate x 1
```

| Win Rate | Expected Fragments / Match |
| --- | ---: |
| 40% | 1.8 |
| 50% | 2.0 |
| 60% | 2.2 |
| 70% | 2.4 |

At 50% win rate:

```text
0.5 x 3 + 0.5 x 1 = 2 Fragments/match
```

---

### 12.2 Matches Needed for One Core Pack

Core Pack cost:

```text
200 Card Fragments
```

| Win Rate | Fragments / Match | Matches Needed for 1 Core Pack |
| --- | ---: | ---: |
| 40% | 1.8 | 112 |
| 50% | 2.0 | 100 |
| 60% | 2.2 | 91 |
| 70% | 2.4 | 84 |

Battle-only progression is intentionally slow.

---

### 12.3 Normal 2-Hour Player Estimate

Assume full match cycle includes:

```text
Queue + loading + mulligan/start + battle + reward screen
```

Estimated cycle times:

| Scenario | Average Cycle Time |
| --- | --- |
| Fast match | 5 minutes |
| Normal match | 8 minutes |
| Slow match | 12 minutes |

At 50% win rate:

| Average Match Cycle | Matches in 2 Hours | Match Fragments | Pack Equivalent |
| --- | ---: | ---: | ---: |
| 5 minutes | 24 | 48 | 0.24 pack |
| 8 minutes | 15 | 30 | 0.15 pack |
| 12 minutes | 10 | 20 | 0.10 pack |

---

### 12.4 Daily Quest + 2-Hour Matchmaking Estimate

Daily quests give:

```text
90 Fragments/day
```

At 50% win rate:

| Average Match Cycle | Daily Quest Reward | Match Reward | Total/Day | Pack Equivalent |
| --- | ---: | ---: | ---: | ---: |
| 5 minutes | 90 | 48 | 138 | 0.69 pack |
| 8 minutes | 90 | 30 | 120 | 0.60 pack |
| 12 minutes | 90 | 20 | 110 | 0.55 pack |

A normal active player earns roughly:

```text
0.55-0.69 Core Pack/day
```

without weekly quests.

---

### 12.5 24-Hour Matchmaking Farming Estimate

At 50% win rate:

| Average Match Cycle | Matches / 24h | Fragments / 24h | Core Packs / 24h |
| --- | ---: | ---: | ---: |
| 5 minutes | 288 | 576 | 2.88 |
| 8 minutes | 180 | 360 | 1.80 |
| 12 minutes | 120 | 240 | 1.20 |

Without a cap, nonstop matchmaking could still generate:

```text
1.2-2.9 Core Packs/day
```

Therefore:

```text
Global daily battle cap = 200 Fragments
```

This limits combined normal battle rewards to:

```text
1 Core Pack/day maximum
```

---

## 13. Local Battle Abuse Calculation

Local battle:

```text
Win = 1
Loss = 0
```

If uncapped, local battle is highly abusable.

Example:

```text
1 local win every 3 minutes
= 20 wins/hour
= 480 wins/day
= 480 Fragments/day
= 2.4 Core Packs/day
```

Therefore:

```text
Local Battle rewards share the 200-Fragment global battle cap.
Same-opponent cooldown = deferred until after alpha.
```

---

## 14. NPC Battle Abuse Calculation

NPC battle:

```text
Win = 1
Loss = 0
```

If uncapped, NPC battle is highly farmable.

Example:

```text
1 NPC win every 2 minutes
= 30 wins/hour
= 720 wins/day
= 720 Fragments/day
= 3.6 Core Packs/day
```

Therefore:

```text
Daily repeat NPC cap = 10 Fragments
```

First-time NPC clear rewards are allowed because they are one-time only.

---

## 15. Weekly Quest Recommendation

Current daily quest reward:

```text
90 Fragments/day
= 630 Fragments/week
= 3.15 Core Packs/week
```

Daily quests + 2 hours/day of normal matchmaking:

```text
Approximately 110-138 Fragments/day
= 770-966 Fragments/week
= 3.85-4.83 Core Packs/week
```

If the target is around 1 Core Pack/day for active players, add weekly quests later.

Recommended weekly reward:

```text
Weekly quests total = 400-500 Card Fragments/week
```

With weekly quests:

```text
Daily quests + normal matchmaking + weekly quests
~= 6-7 Core Packs/week
~= around 1 Core Pack/day
```

---

## 16. Final Locked Rules

### 16.1 Matchmaking

```text
Valid win = 3 Card Fragments
Valid loss = 1 Card Fragment
Enemy early-forfeit win = 2 Card Fragments
Early forfeiter = 0 Card Fragments
Matchmaking rewards consume the global 200-Fragment battle cap
```

### 16.2 Local Battle

```text
Local win = 1 Card Fragment
Local loss = 0 Card Fragments
Uses the global 200-Fragment battle cap
Same-opponent reward cooldown is deferred until after alpha
```

### 16.3 NPC Battle

```text
NPC win = 1 Card Fragment
NPC loss = 0 Card Fragments
First-time NPC clear = 50 Card Fragments
Repeat NPC daily cap = 10 Card Fragments
Fixed card reward = removed
```

### 16.4 Daily Quests

```text
3 daily quests
Each quest = 30 Card Fragments
Total = 90 Card Fragments/day
```

### 16.5 Core Pack Cost

```text
Core Pack = 200 Card Fragments
```

### 16.6 Global Battle Cap

```text
Matchmaking, Local Battle, and repeat NPC rewards share a global cap of
200 Card Fragments/day.
First-time NPC clear rewards and quest rewards do not consume this cap.
Repeat NPC rewards also have their own 10-Fragment daily sub-cap.
```

### 16.7 Same-Opponent Cooldown

```text
No same-opponent reward cooldown at alpha launch.
Add a cooldown later after its duration and counting rules are specified.
```

### 16.8 Valid Battle Requirement

```text
A valid matchmaking battle requires:
- Public matchmaking
- Not AFK
- At least 2 meaningful actions
- Turn 4 reached OR meaningful activity threshold reached
- Global daily battle cap not exceeded
```

### 16.9 Forfeit Rules

```text
Early forfeiter:
- 0 Card Fragments
- Warning/cooldown ladder
- No daily quest progress

Winner vs early forfeiter:
- 2 Card Fragments
- No winner punishment at launch
- Monitor suspicious patterns
```

---

## 17. One-Sentence Summary

```text
Players earn small Card Fragment rewards from battles under one shared 200-Fragment daily cap, while daily and future weekly quests provide most collection progression.
```
