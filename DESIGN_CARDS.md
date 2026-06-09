# DESIGN_CARDS — Elemental TCG: Card Catalog

---

## v0.4 Card Catalog (current — 2026-06-09)

32 unique cards. All decks are 30 cards (2× each identity card + 2× each neutral pool card). No Trainer or Equipment card type — equip effects live on action cards (`buff_friendly_minion` effect type).

### Neutral Pool (9 cards)

Shared across decks. Each archetype draws a subset of 7–8 for its pool.

| Card | Cost | Stats | Effect |
|---|---|---|---|
| Scrappy Squire | 1 | 2/2 | — |
| Riverbank Croc | 2 | 2/4 | — |
| Quickfoot Skitterling | 2 | 3/2 | — |
| Bramblewood Scout | 3 | 3/3 | Battlecry: look at top of deck, draw it |
| Wandering Blade | 3 | 3/4 | — |
| Ironclad Sentinel | 4 | 4/5 | **Taunt** |
| Frostmane Hexer | 4 | 3/4 | Deathrattle: deal 2 dmg to a random enemy minion |
| Skyreach Wyrm | 5 | 5/5 | — |
| Cragheart Behemoth | 6 | 6/7 | — |

Taunt was intentionally removed from Croc and Behemoth — neutral Taunt was warping tempo trades across all matchups.

---

### MIGHTY Deck (8 identity cards × 2 + 7 neutrals × 2 = 30)

**Identity:** Armor, direct removal, equip buffs. Invoker passives: effect damage +1/+2/+3; on-kill face damage 2/3 (tier 6/9).

**Neutral pool:** Squire, Croc, Scout, Wandering Blade, Sentinel, Wyrmling, Behemoth

| Card | Type | Cost | Stats | Effect |
|---|---|---|---|---|
| Reckless Brute | Monster | 2 | 3/2 | — |
| Bastion Defender | Monster | 3 | 2/4 | **Taunt**; Battlecry: gain 2 Armor |
| Warbound Raider | Monster | 4 | 4/4 | Battlecry: deal 2 dmg to a minion |
| Shield Wall | Action | 3 | — | Gain 5 Armor |
| Execute | Action | 2 | — | Destroy a damaged enemy minion |
| Iron Warmaul | Action | 3 | — | Give a friendly minion +3 Atk / +2 HP |
| Siege Volley | Action | 4 | — | Deal 4 damage, split randomly among enemies |
| Titan's Warplate | Action | 5 | — | Give a friendly minion +5 Atk / +2 HP |

*Note: Iron Warmaul was formerly "Warpath Roar" (3-dmg burn); Titan's Warplate was formerly "Beheading Strike" (destroy). Both converted to equip effects to reduce MIGHTY's removal density.*

---

### SWIFT Deck (7 identity cards × 2 + 8 neutrals × 2 = 30)

**Identity:** Draw, combo, tempo. Invoker passives: combo triggers on 1st card (tier 3); combo bonus ×1.5/×2 (tier 6/9).  
**Combo** = you've played at least one other card this turn before this one.

**Neutral pool:** Squire, Croc, Skitterling, Scout, Wandering Blade, Sentinel, Hexer, Wyrm

| Card | Type | Cost | Effect |
|---|---|---|---|
| Quick Slice | Action | 1 | Deal 2 dmg to a minion; Combo: also draw 1 |
| Smoke Bomb | Action | 1 | Give a friendly minion Stealth until it attacks |
| Calculated Strike | Action | 2 | Deal 1 dmg to a minion; Combo: deal 4 instead |
| Rapid Reflexes | Action | 2 | Draw 2 cards |
| Vanishing Act | Action | 3 | Return an enemy minion to their hand |
| Coordinated Strike | Action | 4 | Deal 4 dmg split randomly; Combo: deal 6 instead |
| Master Thief's Gambit | Action | 6 | Destroy an enemy minion; Combo: add a copy to your hand |

⚠️ **Balance concern (open):** SWIFT has zero identity minions — its entire board presence comes from the neutral pool. No SWIFT-specific body has ever been designed. This is a known weakness identified in sim results (SWIFT 41.7% win rate).

---

### VITAL Deck (8 identity cards × 2 + 7 neutrals × 2 = 30)

**Identity:** Healing, Siphon (heal-on-damage), conditional removal. Invoker passives: Siphon +1/+2/+3; on-kill heal 2 (tier 6); on-ally-death heal 1 (tier 9).

**Neutral pool:** Squire, Skitterling, Scout, Sentinel, Hexer, Wyrm, Behemoth

| Card | Type | Cost | Stats | Effect |
|---|---|---|---|---|
| Soulsipper | Monster | 1 | 1/3 | Whenever this deals damage, restore that much Health to your hero |
| Marrow Gleaner | Monster | 2 | 2/4 | Whenever a friendly minion dies, restore 2 Health to your hero |
| Husk Reclaimer | Monster | 3 | 3/3 | Battlecry: destroy a damaged enemy minion |
| Wraithbound Cleric | Monster | 4 | 3/6 | Battlecry: restore 6 Health to your hero |
| Drain Essence | Action | 1 | — | Deal 2 dmg to a minion; restore 2 Health to your hero |
| Soothing Balm | Action | 1 | — | Restore 4 Health to your hero or your most-damaged minion |
| Mass Mending | Action | 3 | — | Restore 3 Health to your hero and all friendly minions |
| Domination Rite | Action | 4 | — | Take control of a damaged enemy minion |

---

## Invoker Thresholds Reference

| Archetype | Tier 3 | Tier 6 | Tier 9 |
|---|---|---|---|
| MIGHTY | Effect damage +1 | Effect damage +2; killing a minion deals 2 face dmg | Effect damage +3; face dmg 3 |
| SWIFT | Combo triggers on your 1st card of the turn | Combo bonus values ×1.5 | Combo bonus values ×2.0 |
| VITAL | Siphon heals +1 | Siphon heals +2; killing a minion restores 2 Health | Siphon heals +3; on-ally-death restore 1 Health |

Tally cap: 9. Tally increments on every card of that battleType played (monsters and actions).

---

> **⚠️ v0.2 catalog below — SUPERSEDED 2026-06-07.** Every card below is being
> redesigned around the v0.4 ruleset. Kept for historical/flavor reference only —
> stats, costs, and skills are no longer valid.

## System Notes

- Four battle types: **MIGHTY** (red), **SWIFT** (yellow), **TOUGH** (green), **VITAL** (blue)
- Types define energy generation and skill costs — no type has advantage over another
- All monsters summon freely (no energy cost) — 1 from hand per turn
- **KO Damage = Monster's max HP** — HP values carry strategic weight
- **Skill 2** on each monster is locked until Mastery 1 is reached through play
- Equipment dies with the monster it is attached to
- Trainer cards are free to play — cost is the card slot itself

---

## Stat Framework

| Role    | HP Range | Generate | Notes                                          |
|---------|----------|----------|------------------------------------------------|
| Scout   | 3–5      | +1       | Cheap to kill, cheap to replace, early board   |
| Fighter | 6–8      | +1       | Backbone, consistent pressure                  |
| Anchor  | 9–10     | +2       | High KO risk when killed, high energy output   |

**Skill cost targets:**
- 1 energy → 1 damage (fast, repeatable, often has minor secondary effect)
- 2 energy → 2–3 damage (standard efficiency)
- 3 energy → 3–4 damage (premium)
- 5 energy → 6 damage (mastery finisher)

---

## Image Prompt Format

> "Anime-style TCG card illustration. [Subject]. [Mood/atmosphere]. Vibrant colors, detailed digital art, fantasy card game style. Portrait orientation, no text, no card borders."

---

# SHARED CARDS
*(These 3 Equipment and 3 Trainer cards appear in all four starter decks)*

> **Trainer breakdown per deck:** 3 shared (Potion, Quick Draw, Retreat) + 1 unique (typed Energy Crystal)

---

## Shared Equipment

### Iron Shield
**Type:** Equipment
**Effect:** Equip to a monster. That monster gains +2 max HP (also heals 2 immediately).

*"Simple survivability. Raises KO value too — consider that before equipping."*

---

### Combat Crest
**Type:** Equipment
**Effect:** Equip to a monster. All of that monster's skills deal +1 damage.

*"Pure offense. Stacks with passive ATK effects."*

---

### Energy Coil
**Type:** Equipment
**Effect:** Equip to a monster. That monster generates +1 additional energy of its type per turn.

*"Engine accelerator. Best on your Anchor."*

---

## Shared Trainers

### Potion
**Type:** Trainer
**Effect:** Heal 3 HP to your Core.

*"Core recovery. Doesn't save a dying monster, but claws back damage you've already taken. Pairs well with a stable board — pop it when you're safe, not when you're panicking."*

---

### Quick Draw
**Type:** Trainer
**Effect:** Draw 2 cards.

*"Hand refuel. Helps you find monsters when the board is empty."*

---

### Retreat
**Type:** Trainer
**Effect:** Return one of your monsters from the board to your hand. It returns at full HP. The slot becomes empty immediately.

*"One-time insurance against a KO. Denies the opponent the Core damage they were going for — but you lose that monster's generation until you re-summon it. Use it to save a high-HP Anchor, not a Scout."*

---
---

# MIGHTY DECK
**Color:** Red | **Identity:** Power, Aggression, Burst

*Build a board of aggressive monsters, generate MIGHTY energy fast, and convert it into raw damage. End games before the opponent's engine gets going.*

**Deck List (20 cards):**
- Battle Imp ×3
- Charged Hound ×3
- Iron Berserker ×3
- Drake Whelp ×3
- Potion ×1
- Quick Draw ×1
- Retreat ×1
- Energy Crystal (Mighty) ×1
- Iron Shield ×1
- Combat Crest ×1
- Energy Coil ×1
- Battle Axe ×1

---

## MIGHTY Monsters

### Battle Imp — Scout
| Stat     | Value          |
|----------|----------------|
| HP       | 4              |
| Type     | MIGHTY         |
| Generate | +1 MIGHTY/turn |

**Passive:** None

**Skill 1 — Quick Jab**
- Cost: 1 MIGHTY
- Effect: Deal 1 damage to target enemy.

*"The opener. Costs nothing to keep spamming once you have generation."*

**Image Prompt:**
> "Anime-style TCG card illustration. A small mischievous battle imp with glowing crimson eyes, tiny curved horns, and crackling red energy around its clawed hands. Floats mid-air with a chaotic, eager expression. Bold red and black color palette, faint ember sparks in the background. Vibrant colors, detailed digital art, fantasy card game style. Portrait orientation, no text, no card borders."

---

### Charged Hound — Fighter
| Stat     | Value          |
|----------|----------------|
| HP       | 6              |
| Type     | MIGHTY         |
| Generate | +1 MIGHTY/turn |

**Passive (On Summon):** When summoned from hand, deal 1 damage to any target enemy.

**Skill 1 — Savage Bite**
- Cost: 2 MIGHTY
- Effect: Deal 2 damage to target enemy.

*"Enters the board dealing damage. Tempo value from the moment it arrives."*

**Image Prompt:**
> "Anime-style TCG card illustration. A sleek, powerful battle hound with a body crackling with red energy, war markings etched across its flanks. Leaping forward mid-sprint with red energy trails blazing behind its paws. Fierce, predatory expression. Dark rocky battlefield beneath. Vibrant colors, detailed digital art, fantasy card game style. Portrait orientation, no text, no card borders."

---

### Iron Berserker — Fighter
| Stat     | Value          |
|----------|----------------|
| HP       | 7              |
| Type     | MIGHTY         |
| Generate | +1 MIGHTY/turn |

**Passive:** When this monster is hit by a skill, its next skill used this turn deals +1 damage.

**Skill 1 — Raging Slash**
- Cost: 2 MIGHTY
- Effect: Deal 3 damage to target enemy.

*"Punishes the opponent for attacking it. Best damage output per energy of any MIGHTY Fighter."*

**Image Prompt:**
> "Anime-style TCG card illustration. A heavily armored warrior berserker, armor cracked and battle-scarred with glowing red energy pulsing through the damage lines. Wild eyes, fists clenched, enormous broadsword raised. The more damaged the armor looks, the more intense the expression. Red energy surges visible through every crack. Vibrant colors, detailed digital art, fantasy card game style. Portrait orientation, no text, no card borders."

---

### Drake Whelp — Anchor
| Stat     | Value          |
|----------|----------------|
| HP       | 10             |
| Type     | MIGHTY         |
| Generate | +2 MIGHTY/turn |

**Passive:** None

**Skill 1 — Power Fang**
- Cost: 3 MIGHTY
- Effect: Deal 4 damage to target enemy.

**Skill 2 — Devastation** *(Unlocks: Mastery 1)*
- Cost: 5 MIGHTY
- Effect: Deal 6 damage to target enemy.

*"The centerpiece. High energy output, strongest single hits in the deck. Opponent must deal with it — KO value 10 makes ignoring it dangerous for both sides."*

**Image Prompt:**
> "Anime-style TCG card illustration. A compact but powerful young dragon with bold crimson-red scales, small wings spread assertively, radiating intense red energy from its eyes and wingbases. Despite being young it carries unmistakable raw power. Battle-worn rocky arena backdrop with red energy shimmering in the air. Vibrant colors, detailed digital art, fantasy card game style. Portrait orientation, no text, no card borders."

---

## MIGHTY Unique Equipment

### Battle Axe
**Type:** Equipment
**Effect:** Equip to a monster. When this monster's skill KOs an enemy, gain 2 MIGHTY energy.

*"Reward for aggression. Chase kills with this equipped and your energy snowballs."*

---

## MIGHTY Unique Trainer

### Energy Crystal (Mighty)
**Type:** Trainer
**Effect:** Gain 1 MIGHTY energy.

*"Small MIGHTY ramp. Closes the gap on a Devastation turn or lets you squeeze out one extra Savage Bite. One copy keeps it from snowballing."*

---
---

# SWIFT DECK
**Color:** Yellow | **Identity:** Speed, Card Advantage, Tempo

*Generate SWIFT energy and turn it into multiple small actions per turn. Draw more than your opponent, pressure with cheap repeated skills, and use Storm Drake's on-summon burst to stay ahead on energy.*

**Deck List (20 cards):**
- Spark Rat ×3
- Storm Runner ×3
- Thunder Hawk ×3
- Storm Drake ×3
- Potion ×1
- Quick Draw ×1
- Retreat ×1
- Energy Crystal (Swift) ×1
- Iron Shield ×1
- Combat Crest ×1
- Energy Coil ×1
- Speed Boots ×1

---

## SWIFT Monsters

### Spark Rat — Scout
| Stat     | Value         |
|----------|---------------|
| HP       | 4             |
| Type     | SWIFT         |
| Generate | +1 SWIFT/turn |

**Passive:** None

**Skill 1 — Zap**
- Cost: 1 SWIFT
- Effect: Deal 1 damage to target enemy. Draw 1 card.

*"Every Zap is a 2-for-1: chip damage AND hand replenishment. Use it whenever you have 1 SWIFT to spare."*

**Image Prompt:**
> "Anime-style TCG card illustration. A small electric rat-like creature with bright yellow crackling fur standing on end from static charge. Glowing yellow bolt markings on its cheeks. Tiny but fierce, mid-leap with yellow sparks flying off its body. Electric aura, dark stormy background. Vibrant colors, detailed digital art, fantasy card game style. Portrait orientation, no text, no card borders."

---

### Storm Runner — Fighter
| Stat     | Value         |
|----------|---------------|
| HP       | 6             |
| Type     | SWIFT         |
| Generate | +1 SWIFT/turn |

**Passive:** After this monster uses a skill, gain 1 SWIFT energy.

**Skill 1 — Volt Dash**
- Cost: 2 SWIFT
- Effect: Deal 2 damage to target enemy.

*"Net cost of Volt Dash is 1 SWIFT after the passive refund. Effectively a discount skill every single time."*

**Image Prompt:**
> "Anime-style TCG card illustration. A lean athletic humanoid in a sleek yellow-and-black energy exosuit, caught mid-stride at blinding speed. Motion blur and crackling yellow electricity trail behind. Speed lines radiate from the figure. The ground beneath each footstep erupts with a small yellow shockwave. Pure kinetic energy. Vibrant colors, detailed digital art, fantasy card game style. Portrait orientation, no text, no card borders."

---

### Thunder Hawk — Fighter
| Stat     | Value         |
|----------|---------------|
| HP       | 7             |
| Type     | SWIFT         |
| Generate | +1 SWIFT/turn |

**Passive (On Summon):** When summoned from hand, deal 1 damage to any target enemy.

**Skill 1 — Talon Strike**
- Cost: 2 SWIFT
- Effect: Deal 3 damage to target enemy.

*"Highest damage-per-energy of any SWIFT Fighter. On Summon chip plus a strong skill makes it immediately threatening."*

**Image Prompt:**
> "Anime-style TCG card illustration. A fierce hawk made entirely of living yellow electricity, shaped into a bird of prey in a steep power dive. Talons crackling with energy, eyes blazing white-gold. Yellow lightning trails arc behind the wings. Dark storm sky backdrop with distant lightning bolts. Vibrant colors, detailed digital art, fantasy card game style. Portrait orientation, no text, no card borders."

---

### Storm Drake — Anchor
| Stat     | Value         |
|----------|---------------|
| HP       | 10            |
| Type     | SWIFT         |
| Generate | +2 SWIFT/turn |

**Passive (On Summon):** When summoned from hand, immediately gain 1 SWIFT energy.

**Skill 1 — Thunder Strike**
- Cost: 3 SWIFT
- Effect: Deal 4 damage to target enemy.

**Skill 2 — Chain Lightning** *(Unlocks: Mastery 1)*
- Cost: 2 SWIFT
- Effect: Deal 2 damage to two different target enemies.

*"On Summon gives 1 SWIFT back — offsets part of its first Thunder Strike cost. Chain Lightning punishes opponents who field multiple weak monsters."*

**Image Prompt:**
> "Anime-style TCG card illustration. A powerful dragon built from storm clouds and living electricity — dark body with electric yellow and white arcs crackling between wings, spine, and jaw. It roars with lightning bursting outward from its open jaws. Thunder clouds spiral around it. Dominant, fearsome presence against a storm sky. Vibrant colors, detailed digital art, fantasy card game style. Portrait orientation, no text, no card borders."

---

## SWIFT Unique Equipment

### Speed Boots
**Type:** Equipment
**Effect:** Equip to a monster. After this monster uses any skill, draw 1 card.

*"Turns every skill use into a card draw. Best on Storm Runner — draw on every discounted Volt Dash."*

---

## SWIFT Unique Trainer

### Energy Crystal (Swift)
**Type:** Trainer
**Effect:** Gain 1 SWIFT energy.

*"Nudges you over the cost threshold for Chain Lightning or a second Volt Dash. In a draw-heavy deck this is mostly bridge energy — filling the 1-gap when generation falls short."*

---
---

# TOUGH DECK
**Color:** Green | **Identity:** Defense, Healing, Sustain

*Put durable monsters on the board, heal through incoming damage, and grind the opponent down with passive healing and damage reduction. Ancient Treant's end-of-turn heal keeps the whole board healthy.*

**Deck List (20 cards):**
- Sproutling ×3
- Vine Brute ×3
- Stone Turtle ×3
- Ancient Treant ×3
- Potion ×1
- Quick Draw ×1
- Retreat ×1
- Energy Crystal (Tough) ×1
- Iron Shield ×1
- Combat Crest ×1
- Energy Coil ×1
- Thorn Bark ×1

---

## TOUGH Monsters

### Sproutling — Scout
| Stat     | Value         |
|----------|---------------|
| HP       | 5             |
| Type     | TOUGH         |
| Generate | +1 TOUGH/turn |

**Passive:** None

**Skill 1 — Thorn Jab**
- Cost: 1 TOUGH
- Effect: Deal 1 damage to target enemy. Heal this monster 1 HP.

*"The self-heal extends how long Sproutling stays on board. More turns alive = more TOUGH generation."*

**Image Prompt:**
> "Anime-style TCG card illustration. A small round plant creature with a large sturdy green leaf sprouting from its head, stubby root-legs, and cheerful determined eyes. Dewdrops on its leaves, sitting in rich dark soil with small flowers around it. Soft green forest light filtering through branches above. Vibrant colors, detailed digital art, fantasy card game style. Portrait orientation, no text, no card borders."

---

### Vine Brute — Fighter
| Stat     | Value         |
|----------|---------------|
| HP       | 6             |
| Type     | TOUGH         |
| Generate | +1 TOUGH/turn |

**Passive:** None

**Skill 1 — Vine Whip**
- Cost: 2 TOUGH
- Effect: Deal 2 damage to target enemy.

*"Reliable mid-range fighter. No frills — strong HP and solid damage output."*

**Image Prompt:**
> "Anime-style TCG card illustration. A large quadruped creature with a body made entirely of thick intertwined vines and dark wood, glowing green eyes peering out from a vine-woven head. It stands in a powerful, grounded stance with thick trunk-like legs and vine tendrils trailing behind. Dense ancient forest in the background. Strong and natural. Vibrant colors, detailed digital art, fantasy card game style. Portrait orientation, no text, no card borders."

---

### Stone Turtle — Fighter
| Stat     | Value         |
|----------|---------------|
| HP       | 7             |
| Type     | TOUGH         |
| Generate | +1 TOUGH/turn |

**Passive:** Incoming skill damage to this monster is reduced by 1 (minimum 1 damage always dealt).

**Skill 1 — Shell Slam**
- Cost: 3 TOUGH
- Effect: Deal 3 damage to target enemy.

*"Hardest Fighter to kill in any starter deck. Damage reduction plus 7 HP means the opponent needs serious investment to KO it."*

**Image Prompt:**
> "Anime-style TCG card illustration. A massive turtle with a shell made entirely of thick mossy stone and carved runes, ancient beyond measure. Heavy, immovable presence. Its eyes glow faintly gold with quiet authority. Small ferns and moss grow from the shell surface. It stands in a shallow forest pond, completely unhurried. Timeless, immovable. Vibrant colors, detailed digital art, fantasy card game style. Portrait orientation, no text, no card borders."

---

### Ancient Treant — Anchor
| Stat     | Value         |
|----------|---------------|
| HP       | 10            |
| Type     | TOUGH         |
| Generate | +2 TOUGH/turn |

**Passive:** At the end of your turn, heal 1 HP to another ally (your choice).

**Skill 1 — Nature's Wrath**
- Cost: 3 TOUGH
- Effect: Deal 4 damage to target enemy.

**Skill 2 — Ancient Blessing** *(Unlocks: Mastery 1)*
- Cost: 2 TOUGH
- Effect: Heal all your monsters 3 HP.

*"The board-sustaining centerpiece. End-of-turn heal compounds over long games. Ancient Blessing can swing a losing board back to stable."*

**Image Prompt:**
> "Anime-style TCG card illustration. An enormous ancient treant — a living tree in humanoid form, bark skin covered in glowing emerald runes, massive root-feet planted deep, branch-arms spread wide. A weathered face is visible in the bark — aged, noble, protective. Smaller creatures and spirits nestle in the branches. Towering above a lush ancient forest. Golden evening light, leaves of every shade of green. Vibrant colors, detailed digital art, fantasy card game style. Portrait orientation, no text, no card borders."

---

## TOUGH Unique Equipment

### Thorn Bark
**Type:** Equipment
**Effect:** Equip to a monster. Whenever this monster takes skill damage, deal 1 damage to the attacker.

*"Punishes repeated chip attacks. Best on Stone Turtle — already hard to kill, now makes attacking it cost the attacker too."*

---

## TOUGH Unique Trainer

### Energy Crystal (Tough)
**Type:** Trainer
**Effect:** Gain 1 TOUGH energy.

*"TOUGH ramp in the highest-cost deck. Shell Slam and Nature's Wrath both cost 3 — this shaves one turn off your ramp curve. Not explosive, but the deck doesn't need explosive."*

---
---

# VITAL DECK
**Color:** Blue | **Identity:** Control, Disruption, Energy Denial

*Drain the opponent's energy pool, reduce incoming damage, and win by denying their ability to use skills. Sea Leviathan's on-summon disruption can cripple an opponent's setup at a critical moment.*

**Deck List (20 cards):**
- Water Sprite ×3
- Tide Hunter ×3
- Frost Guardian ×3
- Sea Leviathan ×3
- Potion ×1
- Quick Draw ×1
- Retreat ×1
- Energy Crystal (Vital) ×1
- Iron Shield ×1
- Combat Crest ×1
- Energy Coil ×1
- Frost Lens ×1

---

## VITAL Monsters

### Water Sprite — Scout
| Stat     | Value         |
|----------|---------------|
| HP       | 4             |
| Type     | VITAL         |
| Generate | +1 VITAL/turn |

**Passive:** None

**Skill 1 — Splash**
- Cost: 1 VITAL
- Effect: Deal 1 damage to target enemy. Draw 1 card.

*"Same role as Spark Rat — cheap damage with a draw. Keeps hand size healthy while chipping the board."*

**Image Prompt:**
> "Anime-style TCG card illustration. A gentle translucent water sprite — a small humanoid figure made of flowing blue-cyan water, a calm serene face visible within the liquid form. Floats above a still pond, dewdrops and small fish orbit it. Soft blue glow, peaceful and ethereal mood. Vibrant colors, detailed digital art, fantasy card game style. Portrait orientation, no text, no card borders."

---

### Tide Hunter — Fighter
| Stat     | Value         |
|----------|---------------|
| HP       | 6             |
| Type     | VITAL         |
| Generate | +1 VITAL/turn |

**Passive:** Whenever this monster uses a skill, the target loses 1 energy of their most abundant type.

**Skill 1 — Undertow**
- Cost: 2 VITAL
- Effect: Deal 2 damage to target enemy.

*"Passive + skill together: every Undertow costs the target 2 VITAL AND drains 1 energy from their pool. Repeated uses cripple the opponent's skill budget."*

**Image Prompt:**
> "Anime-style TCG card illustration. A sleek aquatic hunter in water-woven teal armor, crouching in a precise attack stance with one hand extended forward. Water trails follow the hand in a fluid, pulling motion. Deep teal and dark blue color scheme. Underwater ruins visible in the background. Focused, predatory expression. Vibrant colors, detailed digital art, fantasy card game style. Portrait orientation, no text, no card borders."

---

### Frost Guardian — Fighter
| Stat     | Value         |
|----------|---------------|
| HP       | 7             |
| Type     | VITAL         |
| Generate | +1 VITAL/turn |

**Passive:** Incoming skill damage to this monster is reduced by 1 (minimum 1 damage always dealt).

**Skill 1 — Ice Strike**
- Cost: 2 VITAL
- Effect: Deal 2 damage to target enemy. Target loses 1 energy of their most abundant type.

*"Tanky AND disrupts. Difficult to kill due to damage reduction, and every attack drains the opponent. Combine with Frost Lens for double energy drain per attack."*

**Image Prompt:**
> "Anime-style TCG card illustration. An armored guardian encased in thick ice crystal plate armor, geometric frost formations growing from the pauldrons and helm. Standing in a firm defensive stance, one arm raised with a glowing blue ice shield. Frosty breath visible in the cold air. Ice cavern backdrop with light refracting through crystal walls. Imposing, cold, immovable. Vibrant colors, detailed digital art, fantasy card game style. Portrait orientation, no text, no card borders."

---

### Sea Leviathan — Anchor
| Stat     | Value         |
|----------|---------------|
| HP       | 10            |
| Type     | VITAL         |
| Generate | +2 VITAL/turn |

**Passive (On Summon):** When summoned from hand, target enemy loses 2 energy of their most abundant type.

**Skill 1 — Tidal Crush**
- Cost: 3 VITAL
- Effect: Deal 4 damage to target enemy.

**Skill 2 — Hydro Vortex** *(Unlocks: Mastery 1)*
- Cost: 2 VITAL
- Effect: Deal 2 damage to target enemy. Target loses 3 energy of their most abundant type.

*"On Summon immediately disrupts the opponent's engine. Hydro Vortex can deny a key skill the opponent was building toward."*

**Image Prompt:**
> "Anime-style TCG card illustration. A young but already immense sea serpent emerging from dark ocean depths, coiling upward through churning deep water. Dark blue-black scales with bioluminescent teal markings along the spine. Despite being a hatchling it is already massive — large intelligent eyes, powerful coiled body. Deep ocean abyss fading below, filtered light from above. Vibrant colors, detailed digital art, fantasy card game style. Portrait orientation, no text, no card borders."

---

## VITAL Unique Equipment

### Frost Lens
**Type:** Equipment
**Effect:** Equip to a monster. Whenever this monster uses any skill, the target loses 1 energy of their most abundant type.

*"Stacks with Tide Hunter and Frost Guardian passives. A Frost Guardian with Frost Lens drains 2 energy per Ice Strike."*

---

## VITAL Unique Trainer

### Energy Crystal (Vital)
**Type:** Trainer
**Effect:** Gain 1 VITAL energy.

*"Fills the gap for a second drain skill on the same turn. Ice Strike + Undertow together cost 4 VITAL — this gets you there one turn sooner without being a free 2-for-1."*

---
---

# Summary Tables

## All Starter Monsters

| Monster          | Deck  | Role    | HP | Gen          | KO Dmg | Skill 1 Cost | Skill 1 Effect          |
|------------------|-------|---------|----|--------------|--------|--------------|-------------------------|
| Battle Imp       | MIGHTY| Scout   | 4  | +1 MIGHTY    | 4      | 1 MIGHTY     | 1 damage                |
| Charged Hound    | MIGHTY| Fighter | 6  | +1 MIGHTY    | 6      | 2 MIGHTY     | 2 damage                |
| Iron Berserker   | MIGHTY| Fighter | 7  | +1 MIGHTY    | 7      | 2 MIGHTY     | 3 damage                |
| Drake Whelp      | MIGHTY| Anchor  | 10 | +2 MIGHTY    | 10     | 3 MIGHTY     | 4 damage                |
| Spark Rat        | SWIFT | Scout   | 4  | +1 SWIFT     | 4      | 1 SWIFT      | 1 damage + draw 1       |
| Storm Runner     | SWIFT | Fighter | 6  | +1 SWIFT     | 6      | 2 SWIFT      | 2 damage (net 1 cost)   |
| Thunder Hawk     | SWIFT | Fighter | 7  | +1 SWIFT     | 7      | 2 SWIFT      | 3 damage                |
| Storm Drake      | SWIFT | Anchor  | 10 | +2 SWIFT     | 10     | 3 SWIFT      | 4 damage                |
| Sproutling       | TOUGH | Scout   | 5  | +1 TOUGH     | 5      | 1 TOUGH      | 1 dmg + heal self 1     |
| Vine Brute       | TOUGH | Fighter | 6  | +1 TOUGH     | 6      | 2 TOUGH      | 2 damage                |
| Stone Turtle     | TOUGH | Fighter | 7  | +1 TOUGH     | 7      | 3 TOUGH      | 3 damage                |
| Ancient Treant   | TOUGH | Anchor  | 10 | +2 TOUGH     | 10     | 3 TOUGH      | 4 damage                |
| Water Sprite     | VITAL | Scout   | 4  | +1 VITAL     | 4      | 1 VITAL      | 1 damage + draw 1       |
| Tide Hunter      | VITAL | Fighter | 6  | +1 VITAL     | 6      | 2 VITAL      | 2 dmg + drain 1 energy  |
| Frost Guardian   | VITAL | Fighter | 7  | +1 VITAL     | 7      | 2 VITAL      | 2 dmg + drain 1 energy  |
| Sea Leviathan    | VITAL | Anchor  | 10 | +2 VITAL     | 10     | 3 VITAL      | 4 damage                |

## KO Damage by Board State

All decks use 4 unique monsters × 3 copies. The 4 unique HP values per deck:

| Deck  | Scout HP | Fighter 1 HP | Fighter 2 HP | Anchor HP | Sum of Unique |
|-------|----------|--------------|--------------|-----------|---------------|
| MIGHTY| 4        | 6            | 7            | 10        | 27            |
| SWIFT | 4        | 6            | 7            | 10        | 27            |
| TOUGH | 5        | 6            | 7            | 10        | 28            |
| VITAL | 4        | 6            | 7            | 10        | 27            |

Core HP = 30. Decks are not forced to sum to 30 — balance comes from mechanics, costs, and passives.

## Shared vs Unique Card Reference

| Card                      | MIGHTY | SWIFT | TOUGH | VITAL |
|---------------------------|--------|-------|-------|-------|
| Iron Shield               | ✅     | ✅    | ✅    | ✅    |
| Combat Crest              | ✅     | ✅    | ✅    | ✅    |
| Energy Coil               | ✅     | ✅    | ✅    | ✅    |
| Potion                    | ✅     | ✅    | ✅    | ✅    |
| Quick Draw                | ✅     | ✅    | ✅    | ✅    |
| Retreat                   | ✅     | ✅    | ✅    | ✅    |
| Battle Axe                | ✅     | —     | —     | —     |
| Speed Boots               | —      | ✅    | —     | —     |
| Thorn Bark                | —      | —     | ✅    | —     |
| Frost Lens                | —      | —     | —     | ✅    |
| Energy Crystal (Mighty)   | ✅     | —     | —     | —     |
| Energy Crystal (Swift)    | —      | ✅    | —     | —     |
| Energy Crystal (Tough)    | —      | —     | ✅    | —     |
| Energy Crystal (Vital)    | —      | —     | —     | ✅    |
