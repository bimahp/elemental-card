> **Archived 2026-10-28 — do not use.** Merged into [GAME_DESIGN.md](../GAME_DESIGN.md) §6 and [MONETIZATION.md](../MONETIZATION.md). Kept only until the merge is reviewed; the doc of record wins on any difference.

# DESIGN_PROGRESSION — Elemental TCG: Progression & Rewards

## Overview

Progression is built around monster mastery and incremental collection. No stat inflation — stronger play comes from better deckbuilding and mastery unlocks, not upgraded numbers.

This document owns mastery, EXP, and account-level progression. Currency and card
acquisition are owned by [DESIGN_ECONOMY.md](DESIGN_ECONOMY.md); battle and quest
reward values are owned by [DESIGN_REWARD.md](DESIGN_REWARD.md).

---

## Battle Rewards

The backend reward policy must implement [DESIGN_REWARD.md](DESIGN_REWARD.md).
Locked Card Fragment values are `3/1` for valid matchmaking win/loss, `2/0` for
winner/loser on an early forfeit, `1/0` for Local Battle, and `1/0` for repeat NPC
battles. A first-time NPC clear awards `50 Card Fragments`; fixed NPC card drops
are removed.

Normal Matchmaking, Local, and repeat NPC rewards share a global
`200 Card Fragments/day` cap. Repeat NPC rewards also have a 10-Fragment daily
sub-cap. Quest rewards and first-time NPC clear bonuses are outside the battle cap.

---

## NPC Progression Rewards

NPCs may define one-time first-clear progression rewards. They do not grant fixed
card drops. Repeat wins grant the Card Fragment reward defined in
[DESIGN_REWARD.md](DESIGN_REWARD.md).

---

## Monster Mastery System

Monsters gain mastery through use in battles.

### What Mastery Does NOT Do
- Does not increase HP or base stats
- Does not change Energy costs

### What Mastery Unlocks
- **Mastery 1:** Skill 2 slot unlocked — the primary mastery reward (planned feature, not yet implemented)
- **Higher mastery (future):** Additional skills added to the card's pool, cosmetic upgrades (card border, art variants, animations)

### Mastery Tracking
- Mastery is tied to the individual card instance in the player's collection
- Each time the monster is played onto the board in a duel counts toward mastery
- Specific mastery thresholds are TBD pending playtesting

---

## Player EXP and Leveling

Player level is separate from monster mastery and tracks overall account
progression. Levels use the shared `LevelConfig` curve and cap at level 100.
Player Status displays EXP within the current level; level 100 is rendered as a
stable maximum state.

---

## Cosmetic Titles

Titles are permanent cosmetic milestone unlocks. They never alter card stats,
Energy, Battle Charge, rewards, matchmaking, or battle rules.

- Every player owns `Beta Tester`.
- Completing onboarding grants the matching elemental disciple title.
- Clearing all three trainers grants `Trainer Champion`.
- 10 and 50 PvP wins grant `Duelist` and `Battle Veteran`.
- Owning 50 and 100 unique collectible cards grants `Crystal Collector` and
  `Crystal Archivist`; duplicates and the non-collectible Coin do not count.
- Once unlocked, a title remains owned if collection size later decreases.
- One owned title is equipped at a time and appears on the world nameplate.

---

## Currency and Collection Progression

- **Card Fragments:** unpaid gameplay currency used only for random card packs.
- **Crystal Shards:** deterministic currency used for exact card/cosmetic crafting
  and safe utility. Shards may come from Robux, manual card destruction, or fixed
  quest rewards, but never from pack rolls or Fragment conversion.
- **Crystal Dust:** removed from the game and must not appear in new schemas, UI,
  rewards, or acquisition flows.

---

## Card Collection

Players collect cards through:

- Card Fragment packs
- Exact Crystal Shard crafting
- Starter/onboarding grants
- Player trading (planned)
- Tournament rewards (planned)

---

## Planned Progression Features (Post-v0.1)

- Additional level and seasonal cosmetic titles
- Seasonal ranked ladders
- Tournament entry and prize pools
- Additional named expansion pools
- Weekly quests
- Card trading between players
