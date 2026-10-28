# Elemental TCG — Economy and Monetization

**Status:** economy and monetization design of record; checked against the Studio place on 2026-10-29. Unresolved points are in §10.

**Owns:** both currencies, every way to earn and spend them, reward values and caps, pack products, duplicate protection, the Card Vendor, Recycle and the Robux shop.
**Does not own:** battle validity, forfeits and penalties ([GAME_DESIGN.md](GAME_DESIGN.md) §5); EXP and levels (GAME_DESIGN §6); card sets ([CARDS.md](CARDS.md)); shop icon art prompts ([docs/ART.md](ART.md) §8).

**Not built** marks a rule that is designed but not in the game. All values live in `RewardConfig`, `GachaConfig`, `VendorConfig` and `ShopConfig`.

---

## 1. Principles

1. **Robux never buys a random outcome, directly or through any chain of conversions.** Random cards are bought only with currency earned in play.
2. **Paid value buys exact, known items.** Robux buys Crystal Shards; Shards buy exact cards and safe utility.
3. **The two currencies never convert into each other.** No route leads from Robux to more random-pack currency.
4. **Paying never weakens a free player.** Nothing sold takes anything from players who do not buy.

```text
Gameplay rewards                     -> Card Fragments -> random packs, Vendor Craft
Robux / Recycle / fixed Shard quests -> Crystal Shards -> Vendor Buy, exact utility
```

This keeps the game clear of Roblox's paid-random-item concerns, and is also the more defensible structure from an Islamic-law risk view: paid value buys known items, and random packs come only from gameplay. (This is a design principle, not a fatwa.)

## 2. Currencies

| | **Card Fragments** | **Crystal Shards** |
|---|---|---|
| Type | Free gameplay currency | Paid and Recycle currency |
| Earned from | Valid battles, first NPC clears, daily and weekly quests, free events and progression | Robux, Recycle, explicitly configured Shard quest rewards |
| Spent on | Random pack products; Vendor **Craft** | Vendor **Buy**; daily quest refresh; exact cosmetics |
| Never | Bought with Robux or Shards; earned from any paid boost, pass or subscription | Opens random packs; converts into Fragments; comes from pack rolls, pity or admin grants outside the quest system |
| HUD colour | Warm gold | Cyan |

**Crystal Dust is removed** and must not appear in any schema, UI, reward or flow.

## 3. Battle rewards

| Mode | Result | Card Fragments |
|---|---|---:|
| Matchmaking | Valid win | 3 |
| Matchmaking | Valid loss | 1 |
| Matchmaking | Win against an early forfeiter | 2 |
| Matchmaking | Early forfeit | 0 |
| Local | Win / loss | 1 / 0 |
| NPC | Repeat win / loss | 1 / 0 |
| NPC | First clear (once per opponent archetype) | 50 |

- **First clear** is the first win against an NPC playing each archetype's deck: the tutorial, the Noob or a Trainer. It pays 50 *instead of* the normal win reward, outside both caps.
- An NPC fallback found through matchmaking pays **Matchmaking** rates and gives no NPC first-clear bonus.
- Every granted Fragment also gives 15 EXP (GAME_DESIGN §6.1), so a first clear is worth 750 EXP.
- Fixed card drops from NPCs are removed: choosing which card to grant is a balance problem.
- Validity and forfeits are defined in [GAME_DESIGN.md](GAME_DESIGN.md) §5.4–5.5.

### 3.1 Daily caps

- Matchmaking, Local and repeat NPC rewards share one **global cap of 200 Card Fragments a day**: at most one 200-Fragment pack a day from battles.
- Repeat NPC rewards also stop at **10 a day**.
- First NPC clears and quest rewards do not count against either cap.
- The day resets at 00:00 UTC.
- **Not built:** a message when the cap is reached ("Daily battle Card Fragment limit reached. You can still play for EXP, rank, and quests."). Today the Result panel just shows 0. EXP stops at the cap too (GAME_DESIGN §9.1).
- **A same-opponent reward cooldown is deferred** until after alpha; its rules must be written here before it is built.

### 3.2 Why these numbers

At a 50% win rate matchmaking pays about 2 Fragments a match, so battles alone need about 100 matches per pack: deliberately slow. A normal player (daily quests plus two hours of matchmaking at 5–12 minutes a match) earns 110–138 Fragments a day, about 0.55–0.69 of a pack. Uncapped farming would reach 1.2–2.9 packs a day from matchmaking, 2.4 from Local and 3.6 from NPC wins, which is why the caps exist. Adding weekly quests of 400–500 Fragments a week would bring an active player to about one pack a day.

### 3.3 Abuse monitoring — Not built

Track forfeiter-side patterns (early forfeits per day, time and turn before forfeit, meaningful actions, repeated losses to one player, new accounts) and winner-side patterns (share of wins from early forfeits, repeated or new-account opponents). Flag, for example, a player whose daily wins are more than 50% early forfeits with at least 10 such wins. At launch: monitor only, never punish automatically. A `TODO` marks the spot in `BattleController`.

## 4. Quests

### 4.1 Daily quests — Not built

Three a day, **30 Card Fragments each** (90 a day, 0.45 of a pack).

### 4.2 Quest refresh — Not built

- Costs **5 Crystal Shards**, at most **3 times a day**.
- Only an uncompleted quest can be refreshed, and only its objective changes; the reward stays the same.
- A refresh never resets completed quests or the daily completion reward. Otherwise Robux → Shards → extra Fragments → random packs, which §1 forbids.

### 4.3 Weekly quests — Not built

Recommended total 400–500 Card Fragments a week.

## 5. Pack products

Pack products are bought with Card Fragments only and contain 5 cards.

| Product | Draws from | Cost | State |
|---|---|---:|---|
| **Standard Pack** | All 132 cards | **200** (see §10.1) | Built: the only product in the Vending Machine today |
| Core Mighty Pack | 40 MIGHTY + 12 NEUTRAL | 200 | Not built |
| Core Swift Pack | 40 SWIFT + 12 NEUTRAL | 200 | Not built |
| Core Vital Pack | 40 VITAL + 12 NEUTRAL | 200 | Not built |

Each of the 5 cards rolls its rarity independently: **Common 70%, Rare 25%, Epic 5%** (`GachaConfig.RARITY_WEIGHTS`). There is no guaranteed Rare slot and no Legendary weight yet. Then one card is picked uniformly from the eligible cards of that rarity (§5.2).

The Vending Machine shows live, server-calculated per-card odds before purchase; the UI never implies a guarantee the server does not give.

### 5.1 Expansions — Not built

Future sets go into **named expansion pools**, never one ever-growing global pool. Their price ages: latest expansion 400, previous 300, older expansions and Core packs 200.

### 5.2 Duplicate protection

- **Common, Rare, Epic:** no third copy of a card until the player owns 2 of every card of that rarity in the product's pool.
- **Legendary:** no duplicate until the player owns 1 of every Legendary in the pool.
- Ownership is global by card id, so a NEUTRAL card owned from one product counts in every product.
- Once a rarity is complete, extra duplicates may appear. They are added to the collection; there is no automatic conversion. Players recycle them by hand (§6).

Built (`GachaService`): for each slot, only cards the player owns fewer than 2 of are eligible; when none are left in that rarity, the whole rarity is eligible again. **Ownership is read once per pack**, so one pack can still give a third copy (for example, a card owned once rolled twice). Fix that before Legendaries ship.

## 6. Recycle (built)

Recycle turns owned cards into Crystal Shards. It is always a deliberate, manual action from the Card Library's **Recycle** page; duplicates are never converted automatically.

| Rarity | Shards per card |
|---|---:|
| Common | 2 |
| Rare | 8 |
| Epic | 30 |
| Legendary | 120 |

- Players queue copies on the left, see the total on the right, and press Recycle Selected.
- **There is no protected-copy floor:** an unused card can be recycled to zero.
- **Deck safety is the only block.** If recycling would leave fewer copies than any single saved deck uses, the server rejects it with "Cant add card, used on deck".
- One-click "recycle all extras" is **not built**.

## 7. The Card Vendor (built)

The Card Vendor NPC (nameplate title "Card Merchant") sells a rotating stock of exact cards two ways:

```text
Roll  (Fragments, random) -> cheapest per card, no certainty
Craft (Fragments, exact)  -> guaranteed, a real premium over rolling
Buy   (Shards, exact)     -> guaranteed, costs Shards instead of time
```

- **Stock:** 6 cards (3 Common, 2 Rare, 1 Epic), the same for every player and every server, rotating three times a day at 00:00, 08:00 and 16:00 UTC. Legendary Craft and Buy prices are set, but the stock has no Legendary slot yet (`VendorConfig.STOCK_RARITY_SPREAD`).
- Craft and Buy need the player near the Vendor (8 studs); Recycle works anywhere.
- **Craft and Buy stop once the player owns 2 copies** of that card (see §10.3 for Legendaries).

| Rarity | Craft (Card Fragments) | Days at the 200/day cap | Buy (Crystal Shards) | Buy ÷ Recycle value |
|---|---:|---:|---:|---:|
| Common | 500 | 2.5 | 40 | 20× |
| Rare | 1,500 | 7.5 | 160 | 20× |
| Epic | 4,000 | 20 | 600 | 20× |
| Legendary | 15,000 | 75 | 2,400 | 20× |

- **Craft** is priced from a pack's cost per card slot (200 / 5 = 40), scaled by rarity. Pricing it as a premium over the blind-roll expected cost was rejected: tens of thousands of Fragments for one Epic.
- **Buy** is twice the original base crafting rate. The owner tried ×4 and settled on ×2, so funding one Buy from Recycle takes 20 recycled copies of the same rarity.

## 8. Robux shop

Crystal Shards are sold as Developer Products. Design launch shop:

| Shards | Robux | Roughly buys |
|---:|---:|---|
| 100 | 99 | 2 Commons at Vendor Buy prices |
| 320 | 299 | 2 Rares |
| 700 | 599 | 1 Epic, with change |
| 1,300 | 999 | 2 Epics |
| 3,000 | 1,999 | 1 Legendary, with change |

These bundles were sized for the old base crafting rate (99 Robux ≈ one chosen Rare). At Vendor Buy prices every bundle buys half as much (§10.2).

A 25-Shard product for 29 Robux may be added later as a cheaper entry point. The bundle art ladder is single shard, small stack, pouch, satchel, chest, grand coffer ([docs/ART.md](ART.md) §8).

**The built shop still sells legacy bundles** of 50, 250, 500 and 1,000 Shards (`ShopConfig`; their Robux prices are set in the Creator Dashboard, not in code). It must be updated to this table, and a published real-purchase test is still pending.

**The Item Mall is hidden** for any player whose `PolicyService` reports `ArePaidRandomItemsRestricted`, even though Shards never buy randomness (§10.5).

### 8.1 What may be sold

Allowed for Robux or Shards: Crystal Shards, exact starter decks, exact battle-type bundles, exact cards, exact cosmetic skins, card backs, board skins, premium card upgrades, daily quest refresh.

Never sold: random packs, random cosmetic chests, rerolls, Shards that open packs or become Fragments, or any paid reset that creates extra Fragments.

## 9. Not built from the older design

- **Exact crafting of any card with Shards** at 20 / 80 / 300 / 1,200 (Common to Legendary). The Vendor's Buy (twice these rates, rotating stock) is the only exact Shard purchase built. See §10.2.
- **Premium card variants** and cosmetics.

## 10. Open decisions

1. **Standard Pack price.** The design priced it at **160** ("cheaper because it is less targeted"); the live config was raised to **200** on 2026-07-11 to match the Core Packs and the Vendor's Craft math, under a mistaken belief that the doc already said 200. Keep 200 (simplest while it is the only product), or return to 160 once Core Packs exist?
2. **General Shard crafting** (§9). If it is built at the base rate, Vendor Buy at twice the price becomes pointless. Drop the general craft, or price it above Vendor Buy? Whichever wins, re-size the Robux bundles (§8) against the real Shard prices.
3. **Legendary copies.** Decks now allow 1 Legendary copy, but Craft and Buy still allow owning 2. Lower the Vendor limit to 1 for Legendaries?
4. **Recycle floor.** The older design protected the first 2 copies (1 for Legendary) and planned a "mass destroy extras" button; the built Recycle has no floor and only blocks deck-breaking recycles. Confirm the built rule is the design.
5. **Item Mall in restricted regions.** The shop is hidden wherever paid random items are restricted. Shards buy only exact items, so the shop could stay open there; hiding it is the safer reading. Keep it hidden, or show it?
