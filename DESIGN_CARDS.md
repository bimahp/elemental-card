# DESIGN_CARDS — Elemental TCG: Card Catalog

Three archetypes share a neutral pool. Each deck is 30 cards: 2× each identity card + 2× each selected neutral card.

**Mechanic shorthands:**
- **Combo** (SWIFT): you've played at least one other card this turn. At Invoker tier 3, your first card of the turn also counts.
- **Siphon** (VITAL): any heal-on-damage or direct-heal effect. VITAL Invoker amplifies all Siphon by a flat bonus.
- **Armor** (MIGHTY): absorbs incoming damage before HP. No cap, no decay.

---

## Targeting Rules

- **"Damaged" condition** — any minion that has lost at least 1 HP at any point in the game (not current turn only).
- **"Most-damaged minion" auto-target** — targets the friendly minion with the lowest current HP. If tied, picks the first slot. Falls back to hero if no minions.
- **"Split randomly among enemies"** — includes the enemy hero as a valid target. If only 1 enemy minion exists, Double Swipe hits it twice.

---

## Neutral Pool (9 cards)

Each archetype uses a subset of 7–8 neutrals. No neutral card has Taunt (intentional — neutral Taunt warps tempo trades across all matchups).

| ID | Card | Cost | Stats | Keywords | Effect |
|---|---|---|---|---|---|
| `scrappy_squire` | Scrappy Squire | 1 | 2/2 | — | — |
| `riverbank_croc` | Riverbank Croc | 2 | 2/4 | — | — |
| `quickfoot_skitterling` | Quickfoot Skitterling | 2 | 3/2 | — | — |
| `bramblewood_scout` | Bramblewood Scout | 3 | 3/3 | — | Battlecry: look at the top card of your deck, then draw it |
| `wandering_blade` | Wandering Blade | 3 | 2/3 | **Charge** | — |
| `ironclad_sentinel` | Ironclad Sentinel | 4 | 4/5 | **Taunt** | — |
| `frostmane_hexer` | Frostmane Hexer | 4 | 3/4 | — | Deathrattle: deal 2 damage to a random enemy minion |
| `skyreach_wyrm` | Skyreach Wyrm | 5 | 5/5 | — | — |
| `cragheart_behemoth` | Cragheart Behemoth | 6 | 6/7 | — | — |

---

## MIGHTY Deck — 30 cards

**Identity:** Armor generation, direct removal, stat buffs that snowball a single threat.
**Neutral pool (7):** Scrappy Squire, Riverbank Croc, Bramblewood Scout, Wandering Blade, Ironclad Sentinel, Skyreach Wyrm, Cragheart Behemoth

### Monsters (3)

| ID | Card | Cost | Stats | Keywords | Effect |
|---|---|---|---|---|---|
| `bonk_bear` | Bonk Bear | 2 | 2/2 | **Taunt** | — |
| `chubby_bear` | Chubby Bear | 3 | 2/4 | — | Battlecry: gain 2 Armor |
| `grumpy_bear` | Grumpy Bear | 4 | 3/5 | **Taunt** | — |

### Actions (5)

| ID | Card | Cost | Effect |
|---|---|---|---|
| `big_bonk` | Big Bonk | 2 | Destroy a damaged enemy minion (damaged = any HP lost ever) |
| `extra_fluffy` | Extra Fluffy | 3 | Gain 5 Armor |
| `bonk_hammer` | Bonk Hammer | 3 | Give a friendly minion +1 Attack / +1 HP |
| `double_swipe` | Double Swipe | 4 | Deal 2 damage to two random enemy minions (hits same minion twice if only one exists) |
| `mega_helmet` | Mega Helmet | 5 | Give a friendly minion +2 Attack / +2 HP |

### Invoker Thresholds (MIGHTY)

| Tally | Passive |
|---|---|
| 3 | Effect damage +1 |
| 6 | Effect damage +2 (total); destroying an enemy minion also deals 2 face damage |
| 9 | Effect damage +3 (total); on-kill face damage 3 (total) |

---

## SWIFT Deck — 30 cards

**Identity:** Tempo, card draw, Combo payoffs. Bends Energy and positioning for short-term advantages.
**Neutral pool (8):** Scrappy Squire, Riverbank Croc, Quickfoot Skitterling, Bramblewood Scout, Wandering Blade, Ironclad Sentinel, Frostmane Hexer, Skyreach Wyrm

> **Open issue:** SWIFT has zero identity monsters — all board presence comes from the neutral pool. Cat-themed identity minions are planned but not yet designed. This is the primary cause of SWIFT's current 41.7% win rate.

### Actions (7)

| ID | Card | Cost | Effect |
|---|---|---|---|
| `quick_scratch` | Quick Scratch | 1 | Deal 2 damage to a minion; **Combo:** also draw 1 card |
| `hide_and_sneak` | Hide and Sneak | 1 | Give a friendly minion Stealth until its next attack |
| `surprise_pounce` | Surprise Pounce | 2 | Deal 1 damage to a minion; **Combo:** deal 4 instead |
| `cat_nap` | Cat Nap | 2 | Draw 2 cards |
| `hide_and_seek` | Hide and Seek | 3 | Return an enemy minion to their hand |
| `sharp_claws` | Sharp Claws | 4 | Deal 4 damage split randomly among enemies including hero; **Combo:** deal 6 instead |
| `cat_burglar` | Cat Burglar | 6 | Destroy an enemy minion; **Combo:** add a copy of it to your hand |

### Invoker Thresholds (SWIFT)

| Tally | Passive |
|---|---|
| 3 | The Combo condition counts the card being played — your first card of the turn triggers Combo |
| 6 | Combo bonus values increased by 50% |
| 9 | Combo bonus values increased by 100% (total) |

---

## VITAL Deck — 30 cards

**Identity:** Sustain, Siphon (heal-on-damage), persistence, resurrection.
**Neutral pool (7):** Scrappy Squire, Quickfoot Skitterling, Bramblewood Scout, Ironclad Sentinel, Frostmane Hexer, Skyreach Wyrm, Cragheart Behemoth

### Monsters (4)

| ID | Card | Cost | Stats | Keywords | Effect |
|---|---|---|---|---|---|
| `soulsipper` | Soulsipper | 1 | 1/3 | — | Whenever this minion deals damage, restore that much Health to your hero (Siphon) |
| `marrow_gleaner` | Marrow Gleaner | 2 | 2/4 | — | Whenever a friendly minion dies, restore 2 Health to your hero (Siphon) |
| `guardian_spirit` | Guardian Spirit | 3 | 1/4 | **Taunt** | Deathrattle: restore 3 Health to your hero |
| `wraithbound_cleric` | Wraithbound Cleric | 4 | 3/6 | — | Battlecry: restore 6 Health to your hero (Siphon) |

### Actions (4)

| ID | Card | Cost | Effect |
|---|---|---|---|
| `soothing_balm` | Soothing Balm | 1 | Restore 4 Health to your hero or your most-damaged minion (auto-targeted: lowest current HP minion, hero if none) (Siphon) |
| `drain_essence` | Drain Essence | 1 | Deal 2 damage to an enemy minion; restore 2 Health to your hero (Siphon) |
| `mass_mending` | Mass Mending | 3 | Restore 3 Health to your hero and all friendly minions (Siphon) |
| `spirit_recall` | Spirit Recall | 4 | Return a friendly minion from your discard pile to your hand |

### Invoker Thresholds (VITAL)

| Tally | Passive |
|---|---|
| 3 | All Siphon effects restore +1 Health |
| 6 | Siphon +2 Health (total); destroying an enemy minion also restores 2 Health to your hero |
| 9 | Siphon +3 Health (total); whenever a friendly minion dies, also restore 1 Health to your hero |

---

## Deck Composition Summary

| Archetype | Identity cards | Neutral pool cards | Total unique | Deck (2× each) |
|---|---|---|---|---|
| MIGHTY | 8 (3 monsters, 5 actions) | 7 | 15 | 30 |
| SWIFT | 7 (0 monsters, 7 actions) | 8 | 15 | 30 |
| VITAL | 8 (4 monsters, 4 actions) | 7 | 15 | 30 |

---

## Open Design Issues

| Issue | Priority | Notes |
|---|---|---|
| SWIFT has no identity monsters | 🔴 High | Cat minions needed. Zero SWIFT board presence without them. Primary fix for 41.7% win rate. |
| SWIFT cannot threaten face | 🔴 High | No reliable direct hero pressure to race VITAL's healing. Cat minion design should address this. |
| VITAL dominant (61.7%) | 🟡 Medium | Monitor after SWIFT improves — may be partly an artifact of SWIFT being too weak. Siphon Invoker compounding is the lever to tune if it persists. |
| First-mover advantage in mirrors | 🟡 Medium | MIGHTY and SWIFT mirrors ~80% first-seat wins. Coin insufficient. Structural answer needed. |
