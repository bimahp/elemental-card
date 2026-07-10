# Card Economy & Currency Specification

> Finalized economy specification for TCG card acquisition, crafting, duplicate handling, and paid/unpaid currency separation.

> **Source of truth:** This document is authoritative for currencies, pack pricing,
> card destruction, crafting, duplicate protection, and paid economy products.
> [DESIGN_REWARD.md](DESIGN_REWARD.md) is authoritative for reward amounts,
> battle validity, caps, and anti-abuse rules. Older plans are implementation
> history and do not override either specification.

---

## 1. Design Goal

The game uses two currencies with a strict separation:

```text
Card Fragments = free gameplay currency used for random card packs
Crystal Shards = paid/destroy-card currency used for exact crafting and safe utility
```

The main design goals are:

- Give players free ways to earn random cards.
- Avoid paid random-card purchases.
- Allow paid progression through exact crafting, not gambling.
- Keep the economy easy to understand.
- Prevent indirect paid paths into random packs.
- Support future expansions with scalable pack pricing.

---

## 2. Core Rule

The economy must follow this rule permanently:

```text
Gameplay rewards -> Card Fragments -> Random Packs

Robux / Destroyed Cards / Explicit Shard Quests -> Crystal Shards -> Exact Crafting / Utility
```

There must be no direct or indirect conversion between the two currencies.

```text
Card Fragments cannot become Crystal Shards.
Crystal Shards cannot become Card Fragments.
Crystal Shards cannot open random packs.
Card Fragments cannot be bought with Robux.
```

The only allowed card-to-currency conversion is:

```text
Owned card -> Destroy manually -> Crystal Shards
```

---

## 3. Currency 1: Card Fragments

### 3.1 Definition

```text
Card Fragments
Type: Unpaid gameplay currency
Main purpose: Open random card packs / card rolls
```

Card Fragments are the free currency used for randomized card acquisition.

### 3.2 Sources

Card Fragments can come from:

- Valid public match rewards
- Valid Local and NPC battle rewards
- Daily quest rewards
- Weekly quest rewards, if added later
- Free event rewards, if added later
- Free progression rewards, if added later

Card Fragments must not come from:

- Robux purchase
- Crystal Shard purchase
- Paid daily reset
- Paid booster
- Paid battle pass reward, if a battle pass is added later
- Any paid subscription or premium multiplier

### 3.3 Uses

Card Fragments are used for:

- Core Mighty Pack
- Core Swift Pack
- Core Vital Pack
- Standard Pack
- Future expansion packs

Card Fragments must not be used for:

- Exact card crafting
- Cosmetic crafting
- Daily quest refresh
- Paid utility actions

---

## 4. Currency 2: Crystal Shards

### 4.1 Definition

```text
Crystal Shards
Type: Paid + destroy-card currency
Main purpose: Exact crafting and safe utility
```

Crystal Shards are the premium/crafting currency. They are allowed to be purchased with Robux because they only buy deterministic, known-value products.

### 4.2 Sources

Crystal Shards can come from:

- Destroying cards manually
- Mass destroying extra copies
- Robux purchases
- Fixed, explicitly configured quest rewards
- Fixed daily or weekly quest rewards, when the quest definition awards Shards

Crystal Shards must not come from:

- Random pack opening as an automatic reward
- Pack rolls, pity, or roll milestones
- Paid-to-random conversion
- Card Fragment conversion
- Events, promotions, compensation, or admin grants outside the approved quest system

### 4.3 Uses

Crystal Shards are used for:

- Crafting exact cards
- Crafting exact cosmetics
- Crafting exact premium variants
- Refreshing/changing daily quest objectives

Crystal Shards must not be used for:

- Random card packs
- Random cosmetic chests
- Random rerolls
- Any chance-based reward generator

---

## 5. Pack Costs

All card packs are purchased with Card Fragments only.

### 5.1 Launch Packs

| Pack | Contents | Cost |
| --- | --- | --- |
| Core Mighty Pack | 40 Mighty + 12 Neutral | 200 Card Fragments |
| Core Swift Pack | 40 Swift + 12 Neutral | 200 Card Fragments |
| Core Vital Pack | 40 Vital + 12 Neutral | 200 Card Fragments |
| Standard Pack | All 132 launch cards | 160 Card Fragments |

### 5.2 Why Standard Pack Is Cheaper

The Standard Pack has weaker targeting because it contains all cards:

```text
40 Mighty
40 Swift
40 Vital
12 Neutral
= 132 total cards
```

A player who wants one battle type has less control when opening Standard Packs.

Therefore:

```text
Targeted Core Pack = 200 Fragments
Broad Standard Pack = 160 Fragments
```

### 5.3 Future Expansion Pack Pricing

Use a simple aging model:

| Pack Age | Cost |
| --- | --- |
| Latest expansion | 400 Card Fragments |
| Previous expansion | 300 Card Fragments |
| Old expansion / Core pack | 200 Card Fragments |

Example:

```text
Season 1:
- Core Mighty Pack = 200
- Core Swift Pack = 200
- Core Vital Pack = 200
- Season 1 Expansion Pack = 400

Season 2:
- Core Mighty Pack = 200
- Core Swift Pack = 200
- Core Vital Pack = 200
- Season 1 Expansion Pack = 300
- Season 2 Expansion Pack = 400

Season 3:
- Core Mighty Pack = 200
- Core Swift Pack = 200
- Core Vital Pack = 200
- Season 1 Expansion Pack = 200
- Season 2 Expansion Pack = 300
- Season 3 Expansion Pack = 400
```

This makes newer content feel more valuable without selling paid random packs.

---

## 6. Daily Quest Refresh

Daily quests can be refreshed using Crystal Shards.

### 6.1 Refresh Rule

```text
Daily Quest Refresh
Cost: 5 Crystal Shards
Limit: 3 refreshes per day
Can only refresh an uncompleted quest
Only changes the quest objective
Does not reset completed quest rewards
Does not refresh the final daily completion reward
Does not create extra Card Fragments
```

### 6.2 Safe Example

```text
Before refresh:
- Quest: Win 3 matches
- Reward: 30 Card Fragments

Pay 5 Crystal Shards

After refresh:
- Quest: Play 15 cards
- Reward: 30 Card Fragments
```

The reward stays the same. Only the objective changes.

### 6.3 Unsafe Example

Do not allow this:

```text
Pay Crystal Shards
-> Reset completed daily quests
-> Earn another full set of Card Fragments
-> Open more random packs
```

This creates an indirect paid-random path:

```text
Robux -> Crystal Shards -> Extra Card Fragments -> Random Packs
```

That must be avoided.

---

## 7. Match Reward System

Battle reward values and validity rules are owned by
[DESIGN_REWARD.md](DESIGN_REWARD.md). The economy depends on these locked launch
values:

| Battle result | Card Fragments |
| --- | ---: |
| Valid matchmaking win | 3 |
| Valid matchmaking loss | 1 |
| Win against an early forfeiter | 2 |
| Early forfeit loss | 0 |
| Local Battle win | 1 |
| Local Battle loss | 0 |
| NPC Battle win | 1 |
| NPC Battle loss | 0 |
| First-time NPC clear | 50 |

Normal matchmaking, Local Battle, and repeat NPC battle rewards share one global
cap of `200 Card Fragments/day`. First-time NPC clear rewards and quest rewards do
not consume this battle cap. A same-opponent reward cooldown is deferred until
after alpha and is not a launch rule.

---

## 8. Daily Quest Rewards

| Reward | Card Fragments |
| --- | ---: |
| Quest 1 | 30 |
| Quest 2 | 30 |
| Quest 3 | 30 |
| Total daily quest reward | 90 |

Daily quests provide `0.45` of a 200-Fragment Core Pack per day. Quest objectives
may be refreshed, but refreshes never reset rewards or create additional Card
Fragment payouts.

---

## 9. Destroying Cards

Duplicates are not automatically converted. Players manually destroy cards to receive Crystal Shards.

### 9.1 Protected Copies

The game should protect useful copies by default.

| Rarity | Protected Copies | Extra Copies Can Be Destroyed |
| --- | ---: | --- |
| Common | First 2 | Copy #3+ |
| Rare | First 2 | Copy #3+ |
| Epic | First 2 | Copy #3+ |
| Legendary | First 1 | Copy #2+ |

### 9.2 Destroy Values

| Destroyed Card | Crystal Shards Gained |
| --- | ---: |
| Common | 2 |
| Rare | 8 |
| Epic | 30 |
| Legendary | 120 |

### 9.3 Manual Destroy

Players can destroy cards manually.

Recommended warnings:

```text
This card is currently used in a deck.
Destroying it may make that deck invalid.
```

```text
You only own 1 usable copy of this card.
Are you sure you want to destroy it?
```

### 9.4 Mass Destroy Extras

Add:

```text
Mass Destroy Extra Copies
```

This should only destroy copies above the useful limit:

```text
Common/Rare/Epic: keep 2 copies
Legendary: keep 1 copy
```

---

## 10. Crafting with Crystal Shards

Crafting is deterministic. Players choose the exact card they want.

### 10.1 Crafting Costs

Use a 10:1 craft-to-destroy ratio.

| Craft Target | Crystal Shard Cost |
| --- | ---: |
| Common | 20 |
| Rare | 80 |
| Epic | 300 |
| Legendary | 1,200 |

### 10.2 Economy Meaning

```text
Destroy 10 duplicate Commons -> Craft 1 chosen Common
Destroy 10 duplicate Rares -> Craft 1 chosen Rare
Destroy 10 duplicate Epics -> Craft 1 chosen Epic
Destroy 10 duplicate Legendaries -> Craft 1 chosen Legendary
```

This makes duplicates useful without making crafting too fast.

### 10.3 Paid Crafting

Because Crystal Shards can be bought with Robux, players can pay for exact progress.

Allowed:

```text
Robux -> Crystal Shards -> Craft exact card
```

Not allowed:

```text
Robux -> Crystal Shards -> Random pack
```

---

## 11. Crystal Shard Shop Pricing

Crystal Shards can be sold as Developer Products.

Recommended launch pricing:

| Product | Crystal Shards | Robux | Intended Use |
| --- | ---: | ---: | --- |
| Tiny Shard Pack | 25 | 29 | Quest refreshes / small crafting |
| Small Shard Pack | 100 | 99 | Craft 1 Rare + leftover |
| Medium Shard Pack | 320 | 299 | Craft 1 Epic + leftover |
| Large Shard Pack | 700 | 599 | Craft 2 Epics + utility |
| Legendary Shard Pack | 1,300 | 999 | Craft 1 Legendary + leftover |
| Ultimate Shard Pack | 3,000 | 1,999 | Heavy crafting |

### 11.1 Recommended Initial Shop

For launch, use this simplified shop:

| Product | Crystal Shards | Robux |
| --- | ---: | ---: |
| 100 Shards | 100 | 99 |
| 320 Shards | 320 | 299 |
| 700 Shards | 700 | 599 |
| 1,300 Shards | 1,300 | 999 |
| 3,000 Shards | 3,000 | 1,999 |

The optional 25-Shard product can be added later if players need a cheaper entry point.

### 11.2 Price Meaning

```text
99 Robux ~= craft 1 chosen Rare
299 Robux ~= craft 1 chosen Epic
999 Robux ~= craft 1 chosen Legendary
```

This is clearer and safer than selling random pack pulls.

---

## 12. Duplicate Protection for Packs

Random packs should use duplicate protection.

### 12.1 Non-Legendary Rule

For Common, Rare, and Epic cards:

```text
Do not grant copy #3 of a card until the player has received 2 copies of every card of that rarity in the selected pool.
```

### 12.2 Legendary Rule

For Legendary cards:

```text
Do not grant a duplicate Legendary card until the player has received 1 copy of every Legendary card in the selected pool.
```

### 12.3 Neutral Cards

Neutral cards are shared globally. If a Neutral card appears in multiple packs, ownership should be tracked globally by card ID.

Example:

```text
Player gets 2 copies of Neutral Card A from Core Mighty Pack.
When opening Core Swift Pack, Neutral Card A is already treated as owned.
```

### 12.4 After Completion

After a rarity is completed in the selected pool:

```text
Extra duplicates may appear.
Player can manually destroy them for Crystal Shards.
```

---

## 13. Future Expansion Rules

Do not merge every future card into one permanent global pool. Use named expansion pools.

### 13.1 Core Pools

Always available:

```text
Core Mighty Pack
Core Swift Pack
Core Vital Pack
Standard Pack
```

### 13.2 Expansion Pools

Future examples:

```text
Crystal Rebellion Pack
Ancient Wilds Pack
Shadow Rift Pack
```

Expansion packs should age down in cost over time:

```text
Latest expansion = 400 Fragments
Previous expansion = 300 Fragments
Old expansion = 200 Fragments
```

This prevents the total card pool from becoming too diluted.

---

## 14. Store Product Types

Allowed Robux / Crystal Shard products:

```text
- Crystal Shards
- Exact starter deck
- Exact battle-type bundle
- Exact card crafting
- Exact cosmetic skins
- Exact premium card backs
- Exact board skins
- Exact card premium upgrade
- Daily quest refresh
```

Avoid:

```text
- Paid random packs
- Paid random cosmetic chests
- Paid reroll systems
- Crystal Shards opening packs
- Crystal Shards converting to Card Fragments
- Paid reset that creates extra Card Fragments
```

---

## 15. Compliance and Islamic-Law Risk Notes

This system is designed to avoid paid random-item paths.

### 15.1 Roblox-Safer Structure

Roblox paid random-item concerns are avoided by ensuring:

```text
Robux cannot buy random card outcomes.
Paid currency cannot buy random card outcomes.
Paid utility cannot create extra random-pack currency.
```

### 15.2 Islamic-Law-Safer Structure

The system is also more defensible from an Islamic-law risk perspective because:

```text
Paid value buys exact known items.
Random packs are obtained only through gameplay-earned Card Fragments.
Players are not paying Robux for unknown card outcomes.
```

This is not a fatwa, but it follows the safer design principle:

```text
Paid monetization = deterministic
Random acquisition = unpaid gameplay
```

---

## 16. Final Locked Specification

### Currencies

```text
Card Fragments:
- Unpaid only
- Earned from valid battles, daily quests, weekly quests, and free progression
- Used to open random card packs
- Cannot be bought
- Cannot be converted from Crystal Shards

Crystal Shards:
- Paid + card-destroy + explicit quest currency
- Earned by destroying cards or fixed Shard quests
- Bought with Robux
- Used for exact crafting and daily quest refresh
- Cannot open random packs
- Cannot convert into Card Fragments
```

### Pack Costs

```text
Core Mighty Pack: 200 Card Fragments
Core Swift Pack: 200 Card Fragments
Core Vital Pack: 200 Card Fragments
Standard Pack: 160 Card Fragments
Latest Expansion Pack: 400 Card Fragments
Previous Expansion Pack: 300 Card Fragments
Old Expansion Pack: 200 Card Fragments
```

### Daily Quest Refresh

```text
Cost: 5 Crystal Shards
Limit: 3 refreshes per day
Only changes uncompleted quest objective
Does not reset rewards
Does not create extra Card Fragments
```

### Destroy Values

```text
Common = 2 Crystal Shards
Rare = 8 Crystal Shards
Epic = 30 Crystal Shards
Legendary = 120 Crystal Shards
```

### Crafting Costs

```text
Common = 20 Crystal Shards
Rare = 80 Crystal Shards
Epic = 300 Crystal Shards
Legendary = 1,200 Crystal Shards
```

### Crystal Shard Shop

```text
100 Shards = 99 Robux
320 Shards = 299 Robux
700 Shards = 599 Robux
1,300 Shards = 999 Robux
3,000 Shards = 1,999 Robux
```

---

## 17. One-Sentence Summary

```text
Players earn Card Fragments through gameplay to open random packs, while Crystal Shards come only from Robux, destroyed cards, or explicit fixed quest rewards and are used only for exact crafting and safe utility.
```
