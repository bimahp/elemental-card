# Elemental TCG — Game Design

**Status:** game design of record; checked against the Studio place on 2026-10-29. Unresolved points are in §9.

**Owns:** the rules of a battle, decks, battle modes, forfeits, progression, onboarding and quests.
**Does not own:** cards, packs and creature families ([CARDS.md](CARDS.md)); currencies, rewards, prices and what is sold ([MONETIZATION.md](MONETIZATION.md)); code ([ARCHITECTURE.md](ARCHITECTURE.md)); screens and animation ([docs/UI.md](UI.md)); art ([docs/ART.md](ART.md)).

**Not built** marks a rule that is designed but not in the game. Every number is a starting value for tuning and lives in a config module, not in code.

---

## 1. Concept

A Roblox digital card battle game set inside a 3D TCG card shop. Players build 30-card decks, summon creatures onto a 3-slot board, spend Energy to play cards, and build **Battle Charge** from the creatures they keep alive. Battles happen at visible tables in a social shop; cards are collected through play.

### Pillars

- **Board presence.** What is on the field matters more than hand tricks.
- **Earned resources.** Energy ramps naturally; Charge comes only from creatures that survive your turn.
- **Readable state.** Board, Energy and Charge are readable at a glance at all times.
- **Social atmosphere.** A 3D card shop with visible duels.
- **No paid randomness.** Robux never buys a random outcome ([MONETIZATION.md](MONETIZATION.md) §1).

## 2. The world

The world of Elemental Crystal is powered by living crystal energy and populated entirely by creatures: animals, magical beasts, ancient beings, spirits and constructs. **Humans and the traditional fantasy races do not exist.** Each of the three Crystal Affinities is a creature family the player recognises on sight:

| Affinity | Crystal | Launch tribe | Fantasy |
|---|---|---|---|
| MIGHTY | Ruby | Bears | Warriors: chunky frontline combat creatures |
| SWIFT | Emerald | Cats | Rogues: sneaky, clever, agile |
| VITAL | Sapphire | Frogs | Healers: life magic, "my creatures keep coming back" |
| NEUTRAL | Quartz | Treants, Golems | Independent creatures outside the three affinities |

Tribes, future expansion tribes and the forbidden concepts are in [CARDS.md](CARDS.md) §3. The world is the hub: a card shop with nine Battle Tables, the Noob NPC, three Trainers, the Card Vending Machine and the Card Vendor.

## 3. The battle

### 3.1 Board and heroes

- Each player has a **hero** with **30 HP** and **3 open creature slots**. All slots are equal; every creature can attack and be attacked.
- A destroyed creature leaves its slot empty immediately.
- **Armor** is a hero resource (MIGHTY): it absorbs damage before HP, with no cap and no decay.
- The hero's HP is called "Core HP" in older docs and some UI labels; it has nothing to do with the removed Crystal Core.

### 3.2 Energy

- One universal pool, no types. The cap starts at 1 and rises by 1 each turn, to a maximum of 10.
- The pool refills to the cap at the start of each turn. Unused Energy is lost.

### 3.3 Turn structure

1. **Energy:** the cap rises by 1 and the pool refills.
2. **Draw:** draw 1 card (Fatigue if the deck is empty, §3.6).
3. **Main phase:** play cards and attack in any order while resources allow.
4. **End turn:** `turn_end` effects resolve, then creatures generate Battle Charge (§3.11), then play passes.

A **turn timer** of 60 seconds auto-ends a stalled turn. Two consecutive timeouts forfeit the battle. The timer is server-authoritative; the client only shows a countdown.

**Turn numbers count each player's turn**, not rounds: turn 1 is the first player's first turn, turn 2 the second player's first turn, turn 4 the second player's second turn. The Coin (§3.5) and battle validity (§5.5) use this count.

### 3.4 Opening hand and mulligan

- Each side is dealt **5 cards** and may redraw **at most one** of them, once. The redrawn card shuffles back into the deck and the top card replaces it in the same position (it can be the same card again). The choice is final.
- In PvP both mulligans are simultaneous: the first turn starts only when both players have confirmed or timed out (30 seconds; a timed-out player keeps their hand).
- The NPC always keeps its hand.
- The first player is random.

### 3.5 The Coin

The second player receives **the Coin** after the mulligan: a 0-cost NEUTRAL spell, "Gain 1 Energy this turn only." It is not part of the deck, is never collectible, and expires at the end of turn 2 if unused.

### 3.6 Drawing and Fatigue

- Drawing from an empty deck deals Fatigue damage to your hero instead: 1, then 2, then 3, and so on.
- **Hand limit: 10 cards** (`Ops`). A card drawn into a full hand is burned: it leaves the deck and never enters the hand.
- A creature bounced to a full hand, or a card returned from the graveyard to a full hand, is lost: it goes neither to the hand nor back to the graveyard.

### 3.7 Card types and costs

- **Creature:** summoned to an empty slot. It cannot attack the turn it is summoned (summoning sickness) unless it has **Charge**.
- **Spell:** resolves immediately and goes to the graveyard.
- A card costs **Energy**, **Battle Charge**, or both: Energy-only, hybrid (Energy + Charge), or pure-Charge (`cost = 0` plus a printed Charge cost).
- Abilities are an ordered list of triggered effects; a card with none is a vanilla body ([CARDS.md](CARDS.md) §5).
- **A spell whose effects would all do nothing is refused before it is played** (no valid target, unmet condition): it stays in hand and nothing is spent. A creature is never refused this way; its body is the point, so a fizzled Emerge is allowed.

### 3.8 Combat

- A creature attacks once per turn, at the enemy hero or any enemy creature.
- **Taunt** forces attacks onto Taunt creatures first. Spell effects ignore Taunt.
- **Stealth** creatures cannot be attacked or targeted by enemy effects until they attack.
- Two fighting creatures deal their ATK to each other simultaneously, with full retaliation even if it kills the attacker. Exception: a **Quickstrike** attacker deals damage first and takes no retaliation if the defender dies.
- A creature at 0 HP is destroyed.
- The server resolves combat immediately; animation is presentation only and never delays or changes the result.

### 3.9 Keywords

Static, always-on creature properties:

| Keyword | Effect |
|---|---|
| **Taunt** | Attacks must target this creature first. Spells bypass Taunt. |
| **Stealth** | Cannot be targeted by enemy attacks or targeted effects until it attacks. |
| **Charge** | Can attack the turn it is summoned. |
| **Quickstrike** | When attacking a creature, deals its damage first; no retaliation if the defender dies. Attacker only. |
| **Lifesteal** | Damage it deals heals your hero by that much (also `lifesteal` on damage effects). The old word "Siphon" is retired. |
| **Rebirth** | The first time it dies, it stays in its slot at full HP, keeping its buffs, and loses Rebirth. Its Shatter still fires on that death. No card prints Rebirth today; it is only granted by effects. |

Signature trigger names: **Emerge** (on summon), **Shatter** (on death), **Chain** (another card was already played this turn). The full trigger, action and target vocabulary is in [CARDS.md](CARDS.md) §5.

### 3.10 Effect order

An attack on a creature resolves in this order:

1. The defender's `attacked` effects fire.
2. The attacker deals its damage. A defender that survives fires `take_damage`. A defender at 0 HP fires Shatter; then, if it still has Rebirth, it returns at full HP and nothing else happens; otherwise it leaves the board and `ally_death` fires on its owner's surviving creatures.
3. The attacker's `deal_damage` fires.
4. The defender retaliates with the ATK it had before the attack (unless Quickstrike killed it), and the same death steps apply to the attacker.

Spell damage follows step 2. Effects on one card resolve top to bottom.

### 3.11 Battle Charge

Battle Charge is a second hero resource beside Energy. It replaced the removed Crystal Core hero power: **there is no hero power**, and decks do not choose a Core.

- Each hero has **two Charge Slots**. Each slot holds one Battle Type (MIGHTY, SWIFT or VITAL) and an amount. Exactly one occupied slot is the **current** slot.
- **Board generation.** At the end of your turn, after `turn_end` effects, each non-NEUTRAL creature you control generates **+1 Charge of its Battle Type**, checked left to right. A matching type stacks; an empty slot fills; a third type generates nothing while both slots are occupied. Board generation never replaces an occupied slot.
- **NEUTRAL never produces or occupies Charge**, and neither does the Coin. Playing a card never grants Charge by itself.
- **Direct gains** (`gain_charge`) follow the same rule except that a third distinct type replaces the inactive slot.
- **Spending** leaves the current slot in place unless the spent slot reaches zero; an emptied slot hands "current" to the other occupied slot.
- A card's Charge cost is validated and paid before the card resolves, so a card cannot pay with Charge it generates later.
- Effects can also destroy a slot, drain Charge, or tax Charge costs in a hand ([CARDS.md](CARDS.md) §5).
- Charge is server-authoritative. Animation never affects it; a skipped or late animation snaps to the real state.

### 3.12 Winning

Reduce the opposing hero from 30 HP to 0, or win by the opponent's forfeit (§5.4).

## 4. Decks

- A battle deck is exactly **30 cards**. It may mix any owned cards of any Battle Type.
- **Copy limit:** 2 per card; **1 per Legendary** (built 2026-07-11). No Legendary cards exist yet.
- A hero holds only two Charge Slots, so the deck builder warns (without blocking) when a deck has more than two Charge-producing types: `3 Charge Types - Hero Slots: 2`. NEUTRAL does not count.
- Drafts may be saved incomplete or invalid; only a valid 30-card deck can be set active or used in battle. Every profile always has one active valid deck. A player can keep at most **12 decks** (`SaveService`).
- The three **starter decks** (Ruby Bear, Emerald Cat, Sapphire Frog; 30 cards each) come from [data/deck_starter.json](../data/deck_starter.json). A new player receives one in onboarding (§7.1). The Noob NPC plays a random starter deck.

## 5. Battle modes

| Mode | How it starts | Rewards ([MONETIZATION.md](MONETIZATION.md) §3) |
|---|---|---|
| **NPC battle** | Talk to the Noob NPC, or to a Trainer and choose Battle (after onboarding); the server seats both sides at a free table and starts at once | Small repeat reward; first clear per opponent archetype |
| **Local battle** | Sit at a Battle Table; both seated players press Ready | Small reward |
| **Matchmaking** | Press Find Opponent in the Matchmaking panel | The main battle reward |

### 5.1 Tables

Battle Tables are server-owned (FREE, RESERVED, OCCUPIED). NPC and matchmaking battles use any free table; if none is free, the player is told "All tables are busy right now". One `[E] Sit` prompt per table; the server picks the empty chair. Seated players see Ready and Leave Seat (there is no Stand Up prompt). Movement and the table's prompts are locked while seated, and the server moves the character beside the chair when the battle ends.

### 5.2 Matchmaking

- One global queue across all servers. Any server may pair two queued players and pick the destination server; the destination server makes the final table decision ("the queue and the destination server are truth; the server registry is only a hint").
- After **60 seconds** in the queue without an opponent, the player gets an **NPC fallback** battle through the same pipeline. It pays Matchmaking rates.
- If a matched opponent has not arrived at the destination server **30 seconds** after the first player, the player who arrived gets an NPC fallback instead.
- A player in an early-forfeit cooldown (§5.4) cannot join the queue and is told how long is left.
- Cross-server teleport has not been tested in a published place yet ([docs/HANDOFF.md](HANDOFF.md)).

### 5.3 Spectating — Not built

Players outside a battle will see the board, hero HP and turn on the table surface, with full card text on click.

### 5.4 Disconnects and forfeits

- **Matchmaking battle** (including an NPC fallback): a disconnect *pauses* the seat instead of forfeiting. The player can reconnect (same or another server) and resume. A disconnected seat's turns run out on the normal turn timer, so two consecutive timeouts forfeit it.
- **Local and NPC battles:** a disconnect forfeits at once.
- **Abandon:** a player in a PvP or matchmaking battle is marked at match start. If they leave and do not reconnect, the loss is recorded on their next login, so rage-quits and crashes always count. An abandoned NPC fallback records no loss.
- **Early forfeit** (Matchmaking only): forfeiting before the forfeiter's side is valid (§5.5). Two consecutive turn timeouts count as a forfeit. The forfeiter gets nothing; the opponent gets the reduced early-forfeit reward. Early forfeits today escalate a matchmaking cooldown:

| Early forfeits today | Penalty |
|---|---|
| 1st | Warning |
| 2nd | 2-minute matchmaking cooldown |
| 3rd | 5 minutes |
| 4th | 15 minutes |
| 5th and later | 30 minutes |

The counter resets at 00:00 UTC (`RewardConfig.FORFEIT_COOLDOWN_LADDER`). Winners are never punished for receiving early forfeits at launch.

- A forfeit after the battle became valid counts as a normal win and loss.

### 5.5 Valid battle

A **Matchmaking** battle must be **valid** to pay its normal reward; Local and NPC battles always pay (see §9.4). A player's side is valid when they made **at least 2 meaningful actions** **or** the battle reached **turn 4** (§3.3) (`RewardConfig.VALID_ACTIONS`, `VALID_TURN`).

- Built: a meaningful action is a successful card play or attack.
- **Not built:** counting damage dealt, enemy targeting and ending a turn after spending Energy as meaningful actions; the AFK check; the player-facing line "Rewards require a real battle. Very early surrender, AFK, or repeated farming will not give rewards."

## 6. Progression

There is no stat inflation: stronger play comes from collection and deckbuilding, never from upgraded numbers.

### 6.1 Player level

- Account level 1–100 on the shared `LevelConfig` curve: the EXP to go from level *n* to *n*+1 is `floor(100 × 1.15^(n−1))`.
- Battle EXP = **Card Fragments granted × 15**, computed after the daily caps (see §9 for the conflict this causes).
- Level 100 shows as a stable maximum.

### 6.2 Titles

Permanent cosmetic milestone unlocks. They never alter cards, Energy, Charge, rewards, matchmaking or rules. One owned title is equipped at a time and shows on the world nameplate.

| Title | Requirement |
|---|---|
| Beta Tester | Every player |
| Mighty / Swift / Vital Disciple | Complete onboarding with that archetype |
| Trainer Champion | First-clear all three NPC archetypes (any NPC counts: tutorial, Noob or Trainer; the in-game text says "Defeat all 3 trainers", §9.5) |
| Duelist | 10 PvP wins |
| Battle Veteran | 50 PvP wins |
| Crystal Collector | 50 unique collectible cards |
| Crystal Archivist | 100 unique collectible cards |

Duplicates and the Coin do not count toward collection titles. A title stays owned if the collection later shrinks.

### 6.3 Player Status

The Profile panel shows identity, equipped title, archetype, level and EXP, PvP record and win rate, unique collectible progress and NPC first clears.

### 6.4 Creature mastery — Not built

The original idea: a creature gains mastery as it is played, unlocking cosmetics (borders, art variants, animations), never stats or cost changes. Its main reward was a "Skill 2 slot", which no longer exists since skills were removed. Needs a redesign before it is built (§9).

### 6.5 Later — Not built

Seasonal titles, seasonal ranked ladders, tournaments with prizes, weekly quests, named expansion pools, card trading between players.

## 7. Onboarding and quests

### 7.1 Onboarding (built)

One linear quest: a new player starts with no deck and is guided by `!` marks above NPCs and an on-screen arrow.

1. **intro** — talk to the Noob.
2. **find_trainer** — talk to one of the three Trainers (Mighty, Swift, Vital) and confirm; the server grants that starter deck and collection.
3. **deck_chosen** — talk to the Noob again for the tutorial battle. The tutorial NPC plays the starter weak to the player's choice: MIGHTY faces VITAL, SWIFT faces MIGHTY, VITAL faces SWIFT (`TUTORIAL_WEAK_DECK` in `BattleController`). Winning it earns that archetype's NPC first clear.
4. **complete** — the tutorial battle ends (win, loss or forfeit); normal play unlocks, including Trainer battles.

Dialogue uses one shared system: typewriter text, a camera tween and option buttons.

### 7.2 Daily quests — Not built

Three daily quests worth 30 Card Fragments each. An uncompleted quest's objective may be changed for Crystal Shards; the rules that keep this from becoming a paid route to random packs are in [MONETIZATION.md](MONETIZATION.md) §4.

## 8. NPC opponents

- **Noob:** the standing practice NPC; plays a random starter deck.
- **Trainers** (Mighty, Swift, Vital): after onboarding, their dialogue offers Battle. Each plays its archetype's starter and sits at the table as that Trainer.
- First clears are tracked per opponent **deck** archetype, whichever NPC plays it.
- Today's AI scores each play by action and prefers clean kills, then lethal, even trades, safe pokes and face; it does not sequence Chain. `NpcAI` already has Noob and Pro jitter values, but every battle starts as Noob.
- **Archetype-aware AI and a used Pro tier: Not built.** Planned in [docs/plans/PLAN_AI_ARCHETYPE.md](plans/PLAN_AI_ARCHETYPE.md).

## 9. Open decisions

Each needs an owner decision; until then the rule above stands.

1. **EXP after the battle cap.** EXP is computed from Fragments *after* the daily cap, so a capped player earns no EXP, but the reward design promised "after the cap, EXP may continue". Choose one.
2. **Creature mastery** (§6.4) needs a new unlock now that skills are gone, or should be cut.
3. **Local battle disconnect** forfeits at once while matchmaking pauses. Confirm this split is wanted.
4. **Validity for Local and NPC battles.** Only Matchmaking checks validity, so an instant forfeit at a Local table still pays the winner 1 Fragment (inside the 200 a day cap). Gate Local and NPC too, or accept it?
5. **Trainer Champion.** It unlocks on first clears against each archetype's deck from any NPC, while its in-game text says "Defeat all 3 trainers". Change the text, or track Trainer wins separately?
6. **Spectating** (§5.3): keep in scope or drop.
