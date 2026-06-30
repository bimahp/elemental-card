# Hearthstone Card Pack System Specification

> **Project implementation note (2026-06-29):** This document remains a research
> reference, not the Elemental Card runtime contract. The current alpha vending
> machine uses one unified 132-card pool, five cards for 50 Crystal Shards,
> 70/25/5 common/rare/epic odds, a two-copy ownership cap, and duplicate conversion
> of 5/20/80 Crystal Dust. Purchases are committed atomically by
> `GachaTransaction`; the server validates vending-machine proximity and returns
> authoritative balances. The client uses a modal camera-space 3D
> Skip/Reveal/Next/Done/Claim sequence with rigid SurfaceGui card faces, clean backs,
> and delayed front-emblem fades. Shared art is warmed at login; the exact five
> rolled card images are callback-verified immediately before the 3D stage. The
> full reveal lifecycle also suppresses character movement and world prompts. See
> [PLAN_CARD_ACQUISITION.md](PLAN_CARD_ACQUISITION.md)
> for the implemented architecture and verification record.

> **Planned successor (2026-07-01):** [PLAN_MONETIZATION.md](PLAN_MONETIZATION.md)
> adds live server-computed per-draw odds, same-rarity duplicate protection, a
> leveled Vending Machine UI, and a policy-gated Developer Product mall for
> Crystal Shards. This work is planning-only until `DEV_STATUS.md` says otherwise.
> It is duplicate protection, not an Epic/Legendary dry-streak or guaranteed-rarity
> pity counter. The selected algorithm takes one ownership snapshot before all five
> draws, so same-pack over-cap repeats can still convert to Dust.

> Research reference for designing a digital trading-card pack and collection system.  
> This document describes Hearthstone's general pack-opening structure, reward cadence, rarity guarantees, pity rules, duplicate protection, and crafting support.

---

## 1. System Overview

Hearthstone uses a card-pack system where players acquire packs through:

- Gold purchases
- Rewards Track progression
- Quests and events
- Tavern Brawl rewards
- Ranked season rewards
- Expansion-launch promotions
- Real-money purchases

A normal pack functions similarly to a **five-item gacha pull**:

1. The player selects a pack type.
2. The game generates five random cards from that pack's eligible card pool.
3. At least one card is guaranteed to be Rare or better.
4. Pity and duplicate-protection rules are applied.
5. The player may keep, disenchant, or craft cards afterward.

---

## 2. Normal Pack Contents

A standard Hearthstone card pack contains:

| Property | Specification |
|---|---|
| Cards per pack | 5 |
| Minimum rarity | At least 1 Rare or better |
| Remaining cards | Usually Common, with chances to upgrade |
| Card pool | Determined by the selected pack type |
| Individual card selection | Not available |
| Post-opening choice | All generated cards are granted automatically |

A player does not choose one card from the five results. All five cards become part of the player's collection.

---

## 3. Pack Selection

Players normally choose which **pack pool** they want to open or purchase.

The player chooses the source pool, but not the specific cards.

### 3.1 Common Pack Types

| Pack type | Eligible contents |
|---|---|
| Expansion Pack | Cards from one specific expansion |
| Standard Pack | Cards from all sets currently legal in Standard |
| Wild Pack | Cards from eligible Wild sets |
| Class Pack | Cards belonging to one specific class |
| Golden Pack | Golden or other premium card variants |
| Catch-Up Pack | A variable number of cards intended to help incomplete collections |

### 3.2 Predetermined Reward Packs

Some packs are awarded directly by:

- Events
- Rewards Track milestones
- Ranked rewards
- Tavern Brawl
- Promotions
- Login rewards

In these cases, the reward itself may already specify the pack type.

---

## 4. Cards Per Pack

### 4.1 Normal Packs

A normal pack always contains exactly:

> **5 cards**

At least one of those cards must be Rare or better.

A basic low-roll pack may therefore contain:

- 4 Common cards
- 1 Rare card

Higher-rarity cards replace lower-rarity results when rarity upgrades occur.

### 4.2 Catch-Up Packs

Catch-Up Packs use a different structure.

They can contain approximately:

> **5 to 50 cards**

The number of cards depends on how incomplete the player's eligible collection is.

Players with fewer cards receive more cards, while established players receive fewer.

Catch-Up Packs are primarily an onboarding and returning-player mechanic rather than a normal repeatable pack format.

---

## 5. Rarity Structure

Hearthstone's primary collectible rarities are:

1. Common
2. Rare
3. Epic
4. Legendary

Normal deck-copy limits are:

| Rarity | Maximum copies in a deck |
|---|---:|
| Common | 2 |
| Rare | 2 |
| Epic | 2 |
| Legendary | 1 |

Because Legendary cards have a one-copy deck limit, duplicate protection treats them differently from other rarities.

---

## 6. Legendary Pity System

Hearthstone uses both an introductory guarantee and a recurring hard-pity limit.

### 6.1 First-Ten-Packs Guarantee

For each eligible expansion pack type:

> The player is guaranteed to receive at least one Legendary card within the first 10 packs opened from that expansion.

The Legendary may appear before the tenth pack.

This guarantee is tracked separately for each eligible pack set.

### 6.2 Recurring Legendary Hard Pity

After the introductory guarantee:

> A normal Legendary is guaranteed within a maximum of 40 packs since the previous normal Legendary.

The Legendary may appear at any point before the fortieth pack.

### 6.3 Average Legendary Rate

The approximate average is:

> **1 Legendary per 20 packs**

This is an average, not a guarantee.

The hard-pity ceiling prevents the player from exceeding the maximum dry streak.

### 6.4 Simplified Legendary Rules

| Rule | Value |
|---|---:|
| Average Legendary frequency | Approximately 1 per 20 packs |
| First Legendary guarantee | Within first 10 packs of an eligible expansion |
| Recurring hard pity | Within 40 packs after the previous Legendary |
| Duplicate Legendary protection | Active until all eligible Legendaries are owned |

---

## 7. Epic Pity System

Epic cards also have a hard-pity rule.

> At least one normal Epic is guaranteed within every 10 packs.

The approximate average occurrence is around:

> **1 Epic per 5 packs**

The exact card may appear earlier, but the player should not exceed the 10-pack dry-streak limit.

### 7.1 Simplified Epic Rules

| Rule | Value |
|---|---:|
| Average Epic frequency | Approximately 1 per 5 packs |
| Hard pity | Maximum 10 packs without an Epic |
| Duplicate protection | Active until two copies of every eligible Epic are received |

---

## 8. Minimum Pack Guarantee

Every normal pack guarantees:

> **At least one Rare or better card**

This prevents a pack from containing five Common cards.

The Rare slot may upgrade into:

- Epic
- Legendary
- Premium cosmetic variants, depending on pack rules

Additional cards in the same pack may also independently upgrade.

---

## 9. Duplicate Protection

Duplicate protection reduces the chance that players repeatedly receive unusable extra copies before completing a rarity tier.

### 9.1 Common, Rare, and Epic Protection

For non-Legendary cards:

> The player will not receive a third copy of a card until they have received two copies of every eligible card of that rarity in the pack pool.

Example:

- The player owns two copies of Common Card A.
- The player owns only one copy of Common Card B.
- Common Card B remains eligible before a third copy of Card A is generated.

### 9.2 Legendary Protection

For Legendary cards:

> The player will not receive a duplicate Legendary until they have received every eligible Legendary in that pack pool.

Because only one Legendary copy can be used in a deck, the protection threshold is one copy rather than two.

### 9.3 Previously Owned Cards

Duplicate protection generally remembers cards that the player has previously obtained, including cards that were later:

- Disenchanted
- Converted into crafting resources
- Removed from the active collection by the player

This prevents players from repeatedly disenchanting one card to manipulate the duplicate-protection system.

### 9.4 Protection Summary

| Rarity | Protected ownership threshold |
|---|---:|
| Common | 2 copies of every eligible Common |
| Rare | 2 copies of every eligible Rare |
| Epic | 2 copies of every eligible Epic |
| Legendary | 1 copy of every eligible Legendary |

Once the relevant rarity collection is complete, duplicates of that rarity may appear normally.

---

## 10. Premium Card Variants

Hearthstone can include premium cosmetic versions of cards, such as:

- Golden cards
- Signature cards

Premium variants normally provide visual or cosmetic value rather than increased gameplay power.

This preserves competitive fairness:

> A premium card is not stronger than the normal version of the same card.

Premium cards may have separate appearance rates, guarantees, or pack types depending on the current product.

---

## 11. Crafting and Disenchanting

The pack system is supported by a crafting economy.

### 11.1 Disenchanting

Players can convert unwanted cards into crafting currency, commonly called Arcane Dust.

Typical reasons include:

- Receiving duplicates after protection ends
- Receiving cards for unwanted decks
- Converting premium copies
- Rebuilding a collection around another archetype

### 11.2 Crafting

Players can spend crafting currency to directly create a specific card.

This acts as an additional anti-frustration system.

The complete acquisition structure is therefore:

> Random pack acquisition + pity + duplicate protection + deterministic crafting

Pity guarantees a rarity, while crafting allows the player to eventually obtain an exact desired card.

---

## 12. Pack Purchase Cost

A normal pack traditionally costs:

> **100 gold**

Therefore:

| Gold earned | Equivalent normal packs |
|---:|---:|
| 100 | 1 |
| 500 | 5 |
| 1,000 | 10 |
| 5,000 | 50 |

Players may also buy pack bundles with real money.

The value of those bundles varies by expansion and promotion.

---

## 13. Free-to-Play Pack Acquisition

Hearthstone does not normally provide one guaranteed free pack opening every day.

Instead, players earn:

- Experience
- Rewards Track levels
- Gold
- Direct pack rewards
- Event rewards
- Seasonal rewards

Players then decide when to spend their gold.

### 13.1 Estimated Weekly Pack Income

For a consistent free-to-play player who completes most quests and progresses through a full expansion Rewards Track:

| Player activity | Approximate packs per week |
|---|---:|
| Occasional player | 1–3 |
| Completes most quests | 4–5 |
| Completes quests and weekly Tavern Brawl | 5–6 |
| Active during major events | Temporarily higher |

A practical baseline is:

> **Approximately 5 packs per week for an active free player**

Since each normal pack contains five cards:

> **5 packs × 5 cards = approximately 25 generated card results per week**

This number includes duplicates and does not mean 25 unique cards.

---

## 14. Expansion-Cycle Estimate

Using an example 16-week expansion cycle:

- Approximately 5,400 gold from the core free progression
- Approximately 54 purchasable packs from that gold
- Approximately 16 directly awarded packs
- Approximately 70 pack equivalents in total

Calculation:

> 70 packs ÷ 16 weeks = 4.375 packs per week

Adding one weekly Tavern Brawl pack gives:

> 4.375 + 1 = approximately 5.375 packs per week

Rounded practical estimate:

> **5–6 packs per week for an engaged free player**

Promotions, special events, launch rewards, and Twitch drops can increase the total, but they should not be treated as guaranteed permanent income.

---

## 15. Typical Player Opening Behaviour

Although the average income can be expressed weekly, many players do not open packs at a steady weekly rate.

A common behaviour pattern is:

1. Complete daily and weekly quests.
2. Save gold throughout the expansion.
3. Open occasional reward packs immediately.
4. Spend most saved gold when the next expansion launches.
5. Open approximately 50–80 packs at launch.
6. Craft missing cards needed for specific decks.

Therefore, the economic system feels more like a seasonal collection cycle than a daily summon ritual.

---

## 16. Example Pack-Opening Flow

```text
Player chooses expansion pack
        ↓
System checks pack-specific pity counters
        ↓
System generates five card rarities
        ↓
Guarantee at least one Rare or better
        ↓
Apply Epic and Legendary pity rules
        ↓
Select cards from eligible pool
        ↓
Apply duplicate protection
        ↓
Determine premium variants
        ↓
Reveal five cards
        ↓
Add cards to collection
        ↓
Update pity counters and ownership history
```

---

## 17. Required Persistent Data

A similar implementation would need to save at least:

```text
PlayerCollection
- CardId
- NormalCopiesOwned
- PremiumCopiesOwned
- EverOwnedCount

PackProgress
- PackTypeId
- TotalPacksOpened
- PacksSinceNormalEpic
- PacksSinceNormalLegendary
- FirstTenLegendaryCompleted

Currency
- Gold
- CraftingCurrency
```

`EverOwnedCount` is important because disenchanting a card should not reset its duplicate-protection status.

---

## 18. Suggested Pack-Generation Order

A safe implementation order is:

1. Identify the selected pack pool.
2. Load the player's pity state for that pool.
3. Determine whether Epic or Legendary pity must trigger.
4. Generate the remaining rarity slots.
5. Ensure at least one slot is Rare or better.
6. For each rarity, build a duplicate-protected candidate pool.
7. Select the specific card.
8. Determine whether it becomes a premium variant.
9. Grant all cards.
10. Update collection history and pity counters.
11. Save the transaction atomically.
12. Display the reveal animation.

The server should decide all results.

The client should only:

- Request the opening
- Play animations
- Display server-returned results

---

## 19. Design Strengths

Hearthstone's system reduces gacha frustration through several overlapping protections:

1. Every pack contains a Rare or better.
2. A new expansion grants an early Legendary within ten packs.
3. Legendary dry streaks cannot exceed the hard-pity limit.
4. Epic dry streaks cannot exceed the Epic hard-pity limit.
5. Duplicate protection helps players complete a rarity before receiving excessive copies.
6. Crafting allows deterministic acquisition of exact cards.
7. Players choose the pack pool they want to invest in.
8. Premium versions provide cosmetic excitement without gameplay power.

No single protection is responsible for the full experience.

The system works because all of them operate together.

---

## 20. Design Risks

A comparable system can create problems when the total collection is small.

For example, a game with only 90 launch cards and an income of five packs per week produces:

> 5 packs × 5 cards × 4 weeks = 100 card results per month

With strong duplicate protection, players may complete a large percentage of a small collection very quickly.

Possible consequences:

- Pack excitement drops rapidly.
- Crafting currency loses value.
- New-player and veteran collections converge too quickly.
- Monetization becomes difficult without aggressive expansion releases.
- Duplicate protection exhausts eligible pools frequently.
- Players stop caring about Common and Rare pulls.

A smaller card game may need:

- Fewer free packs per week
- Smaller packs
- More cosmetic variants
- More cards at launch
- Seasonal collection resets
- Expansion-specific pack pools
- Alternative rewards alongside cards
- Carefully limited crafting
- A slower duplicate-protection threshold

---

## 21. Reference Baseline for a New TCG

A Hearthstone-like starting baseline could be:

| Feature | Reference value |
|---|---:|
| Cards per pack | 5 |
| Minimum rarity | 1 Rare or better |
| First-expansion Legendary guarantee | Within 10 packs |
| Legendary average | Approximately 1 per 20 packs |
| Legendary hard pity | 40 packs |
| Epic average | Approximately 1 per 5 packs |
| Epic hard pity | 10 packs |
| Non-Legendary duplicate protection | Until two copies of each rarity are received |
| Legendary duplicate protection | Until one copy of each Legendary is received |
| Active F2P pack income | Approximately 5 packs per week |
| Normal pack cost | 100 gold |
| Exact-card acquisition | Crafting system |

These values should be treated as reference points rather than values that must be copied directly.

---

## 22. Sources

- Blizzard Support — Card Pack Opening Probabilities and pack rules  
  https://us.battle.net/support/en/article/32545

- Hearthstone — Duplicate Protection Update, Patch 17.0  
  https://hearthstone.blizzard.com/en-us/blog/23357896/ashes-of-outland-patch-17-0-march-26

- Hearthstone — Rewards Track and progression announcements  
  https://hearthstone.blizzard.com/en-us/news/

---

## 23. Summary

Hearthstone's pack system can be summarized as:

> **Choose a card pool → open five cards → guarantee a minimum Rare → apply Epic and Legendary pity → apply duplicate protection → allow unwanted cards to become crafting currency.**

An active free-to-play player can generally earn the equivalent of approximately:

> **5–6 normal packs per week**

The core anti-frustration systems are:

- First-ten-packs Legendary guarantee
- Legendary hard pity
- Epic hard pity
- Duplicate protection
- Deterministic crafting

Together, these systems make random acquisition feel significantly more controlled than an unrestricted gacha system.
