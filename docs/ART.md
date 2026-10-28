# Elemental TCG — Art Direction

**Status:** art direction of record, merged 2026-10-28 from the former `DESIGN_ART`, the creature rules of `DESIGN_BEAST` and the icon prompts in `DESIGN_ECONOMY`. The rendering style follows the art actually made: all 132 card prompts and every icon prompt are **stylized low-poly**, so the old guide's "painterly" direction is retired.

**Owns:** the look of cards, creatures, icons and UI art, and the prompt library.
**Does not own:** which creature families exist ([CARDS.md](CARDS.md) §3); UI layout ([UI.md](UI.md)).

Source art and exports live in `assets/` (gitignored). Each card's prompt and uploaded asset id are in [data/pack_*.json](../data/) (`image_prompt`, `image_asset`).

---

## 1. Core vision

A magical, crystal-powered world of creatures. It should feel adventurous, collectible, optimistic and full of discovery: a world players want to explore and collect, not a medieval war to win.

Crystal energy is a living force of nature that shapes ecosystems, creatures and magic: crystal forests, caverns, floating islands, mountains, rivers, ruins and storms. **Magic comes from crystal formations,** not from abstract elemental forces. Every image shows the crystal world somewhere: structures, shards, veins, faceted surfaces, prism light.

## 2. Rendering style

**Stylized low-poly fantasy art:** clean polygonal forms, crisp planar shading, bold faceted geometry, a strong readable silhouette, faceted crystal accents, controlled glow.

- Premium collectible quality, family-friendly, readable at card and icon size.
- **Not:** photorealistic, anime, comic book, grimdark, horror, hyper-realistic, excessively violent.
- **Light comes from magic.** Hierarchy: near-white crystal core, then affinity glow, then saturated crystal body, then a darker supporting environment. The focal point is usually the brightest area. No flat or dull ambient light.

## 3. Creatures

Creatures are the heart of the game. Players should get attached to them the way they do to monster companions.

- Every creature is distinct, memorable, cute, cool or majestic, collectible and recognisable from its silhouette.
- **Eyes matter most:** large, readable eyes, strong expression, clear personality. A card should be identifiable from the face alone.
- Crystals grow as a natural part of the creature, never as random spikes stuck on.
- **Affinity creatures are upright, bipedal animal characters** with expressive forepaws (the card prompts' "upright, bipedal fantasy bear, not a normal four-legged bear and not a human"). The animal always dominates: about 70–90% animal, 10–30% humanoid influence; an animal that gained intelligence, never a human in an animal costume. Avoid a human body with an animal head, human anatomy with animal skin, or human facial proportions.
- Role words such as "guardian" or "ranger" may flavour a card; a human profession is never the creature's identity ([CARDS.md](CARDS.md) §3.3).
- No humans or fantasy races, ever.
- Appeal: charming, expressive, confident, adventurous, heroic.

## 4. Card artwork

Card art is **3:4 vertical**. The lower part sits under the translucent description panel, so the focal point lives in the upper area.

### 4.1 Creature cards

- The creature is always the hero. Keep the face, upper body and defining action in the upper 80%; the lowest 20% is safe ground (feet, terrain) under the panel.
- The face sits in the upper middle. Best framing: hero shot, bust or three-quarter; full body only if the face stays high. Avoid tiny subjects, distant cameras and low faces.
- The environment supports the creature and never dominates.

### 4.2 Spell cards

- The magical event is the hero, not the caster. Centre-weighted; the effect fills about 60–80% of the image and reads at thumbnail size.
- Characters are optional and only give scale.
- Energetic: crystal shards, energy trails, shockwaves, swirling particles, crystal fractures, bright bursts. No static scenes.
- An object-themed spell (a crystal orb, relic or compass) treats the object as the hero, like magical product photography.

### 4.3 Card prompt template

Every card's prompt in the pack JSON follows four parts:

```text
Subject: Create a vertical 3:4 fantasy card illustration of <Name>, <who it is and what it is doing>. <Body rule, e.g. "an upright, bipedal fantasy bear creature … not a normal four-legged bear and not a human.">

Style: Render it as stylized low-poly fantasy art with clean polygonal forms, crisp planar shading, a strong readable silhouette, faceted <affinity colour> accents, and <scene lighting>.

Composition: Keep the face, upper body, and defining action within the upper 80% of the image. Use the lowest 20% for <ground detail>, keeping the full artwork complete but safe beneath a translucent description panel.

Output: Family-friendly, <clearly ursine / feline / …>, no humans, no photorealism, no text, no logo, no border, no card frame, no UI.
```

## 5. Colour identity

| Affinity | Colour | Crystal | Represents | Motifs |
|---|---|---|---|---|
| MIGHTY | `#A50E0E` | Ruby | Strength, impact, toughness | Ruby spikes, crystal eruptions, shattering fragments, shockwaves |
| SWIFT | `#0D652D` | Emerald | Speed, agility, precision, adaptation | Emerald vines, crystal leaves, wind-carved crystal, feathers, speed trails |
| VITAL | `#174EA6` | Sapphire | Life, protection, restoration | Healing blooms, sapphire barriers, fountains, shields, currents |
| NEUTRAL | `#9AA0A6` | Quartz | Balance, utility, ancient magic | White crystal, floating geometry, relics, constructs, prisms |

The same hex values are the UI type colours ([UI.md](UI.md) §6.3).

## 6. Emotion

Every card communicates one or more of: wonder, adventure, discovery, courage, friendship, growth, magic.

## 7. Brand consistency

The crystal resource icons set the game's visual identity. UI, card art, VFX, status icons and abilities share one language: crystal effects, glowing internal light, faceted gem forms, bright focal highlights and clean silhouettes. The shared reference for icons is the Elemental TCG card back (`[EC] Card - Background 4.png`).

## 8. Icon prompt library

All icons are square 1:1 on a transparent background, composed for a **circular crop**: the full silhouette inside an imaginary central circle, corners kept empty, no visible circle drawn.

- **Pack icons** are buyable shop tiles, not card-cover illustrations.
- **Battle Type emblems** are one matching family: compact sticker-like icons with a thick white outer cutline, a black inner rim or drop shadow, and one centred low-poly crystal object.
- **Currency and bundle icons** follow one ladder: single shard, small stack, pouch, large satchel, chest, grand coffer. Bundles repeat the canonical Crystal Shard and never redesign its shape.

### 8.1 Pack icons and Battle Type emblems

#### Core Mighty Pack Icon

Reference: `[EC] Card - Background 4.png`

```text
Subject: Create a square 1:1 fantasy vending-machine pack icon for the Core Mighty Pack: one sealed collectible card pack with deep sapphire-blue faceted wrapper panels, warm ivory-gold trim, and a large ruby-red crystal fist emblem mounted at the center. The pack should feel like a premium physical booster pack for Mighty cards, compact and readable as a shop icon.

Style: Render it as polished stylized low-poly fantasy art matching the reference image, with clean polygonal forms, crisp planar shading, faceted gemstone surfaces, luminous cyan inner light, rich sapphire shadows, warm gold bevel highlights, and premium trading-card-game pack presentation.

Composition: Compose for a circular crop: place the sealed pack upright at the exact center and contain the complete pack silhouette within an imaginary central circle. Keep the corners and outer edges quiet. Use the ruby fist emblem as the brightest focal point, with small red crystal accents and no visible circular crop.

Output: Transparent background, family-friendly, no photorealism, no text, no numbers, no logo, no border, no card frame, no UI, no characters, no hands, no background scene.
```

#### Core Swift Pack Icon

Reference: `[EC] Card - Background 4.png`

```text
Subject: Create a square 1:1 fantasy vending-machine pack icon for the Core Swift Pack: one sealed collectible card pack with deep sapphire-blue faceted wrapper panels, warm ivory-gold trim, and a large emerald-green crystal wing-feather emblem mounted at the center. The pack should feel like a premium physical booster pack for Swift cards, compact and readable as a shop icon.

Style: Render it as polished stylized low-poly fantasy art matching the reference image, with clean polygonal forms, crisp planar shading, faceted gemstone surfaces, luminous cyan inner light, rich sapphire shadows, warm gold bevel highlights, and premium trading-card-game pack presentation. Use emerald highlights and speed-like angular wrapper folds without turning the icon into a weapon.

Composition: Compose for a circular crop: place the sealed pack upright at the exact center and contain the complete pack silhouette within an imaginary central circle. Keep the corners and outer edges quiet. Use the emerald wing-feather emblem as the brightest focal point, with small green crystal accents and no visible circular crop.

Output: Transparent background, family-friendly, no photorealism, no text, no numbers, no logo, no border, no card frame, no UI, no characters, no hands, no background scene, no sword, no dagger, no weapon.
```

#### Core Vital Pack Icon

Reference: `[EC] Card - Background 4.png`

```text
Subject: Create a square 1:1 fantasy vending-machine pack icon for the Core Vital Pack: one sealed collectible card pack with deep sapphire-blue faceted wrapper panels, warm ivory-gold trim, and a large sapphire-blue crystal droplet emblem mounted at the center. The pack should feel like a premium physical booster pack for Vital cards, compact and readable as a shop icon.

Style: Render it as polished stylized low-poly fantasy art matching the reference image, with clean polygonal forms, crisp planar shading, faceted gemstone surfaces, luminous cyan inner light, rich sapphire shadows, warm gold bevel highlights, and premium trading-card-game pack presentation. Use cool blue healing glow and protective crystal highlights.

Composition: Compose for a circular crop: place the sealed pack upright at the exact center and contain the complete pack silhouette within an imaginary central circle. Keep the corners and outer edges quiet. Use the sapphire droplet emblem as the brightest focal point, with small blue crystal accents and no visible circular crop.

Output: Transparent background, family-friendly, no photorealism, no text, no numbers, no logo, no border, no card frame, no UI, no characters, no hands, no background scene.
```

#### Standard Pack Icon

Reference: `[EC] Card - Background 4.png`

```text
Subject: Create a square 1:1 fantasy vending-machine pack icon for the Standard Pack: one sealed collectible card pack inspired by the provided Elemental TCG card-back reference, with deep sapphire-blue faceted wrapper panels, angular royal-blue beveled armor, warm ivory-gold trim, four small purple corner crystals, and one large glowing cyan diamond crystal at the center. The pack should feel broad and all-purpose rather than tied to one battle type.

Style: Render it as polished stylized low-poly fantasy art matching the reference image, with clean polygonal forms, crisp planar shading, faceted gemstone surfaces, luminous cyan inner light, rich sapphire shadows, warm gold bevel highlights, subtle violet crystal accents, and premium trading-card-game pack presentation.

Composition: Compose for a circular crop: place the sealed pack upright at the exact center and contain the complete pack silhouette within an imaginary central circle. Keep the corners and outer edges quiet. Use the central cyan diamond as the brightest focal point, with balanced red, green, and blue micro-reflections suggesting all battle types without adding separate symbols. Do not draw a visible circle.

Output: Transparent background, family-friendly, no photorealism, no text, no numbers, no logo, no border, no card frame, no UI, no characters, no hands, no background scene.
```

#### Mighty Emblem

Reference: `[EC] Emblem - Mighty.png`

```text
Subject: Create a square 1:1 fantasy Battle Type emblem for Mighty: a compact clenched fist made entirely of faceted ruby crystal, with chunky knuckles, a broad palm, and a short wrist cuff. The fist should resemble the current Mighty emblem: powerful, centered, sticker-like, and clearly readable at small UI size.

Style: Render it as stylized low-poly fantasy icon art with clean polygonal forms, crisp planar shading, saturated ruby-red crystal, bright white facet highlights, deep red internal shadows, and a glowing near-white light source at the center of the palm. Match the premium crystal-sticker look of the existing Mighty and Vital emblems.

Composition: Compose for a circular crop: place the complete fist at the exact center and contain every important shape within an imaginary central circle. Use a thick white outer cutline and a black inner rim/drop shadow around the silhouette. Keep the corners and outer edges quiet. Do not draw a visible circle.

Output: Transparent background, family-friendly, no photorealism, no text, no letters, no numbers, no logo, no border, no card frame, no UI, no weapon, no character.
```

#### Swift Emblem

Reference: `[EC] Emblem - Mighty.png`, `[EC] Emblem - Vital.png`

```text
Subject: Create a square 1:1 fantasy Battle Type emblem for Swift: a compact emerald crystal wing shaped like a sharp curved feather, with layered faceted feather segments sweeping upward and inward around a bright central star. It should communicate speed, agility, wind, and precision without using a sword. The silhouette must be compact like the Mighty fist and Vital droplet emblems, not long or diagonal.

Style: Render it as stylized low-poly fantasy icon art with clean polygonal forms, crisp planar shading, saturated emerald-green crystal, lime-green inner glow, bright white facet highlights, and deep green internal shadows. Match the same premium crystal-sticker look, outline thickness, lighting intensity, and small-icon readability as the existing Mighty and Vital emblems.

Composition: Compose for a circular crop: place the complete wing-feather emblem at the exact center and contain every important shape within an imaginary central circle. Use a thick white outer cutline and a black inner rim/drop shadow around the silhouette. Keep the corners and outer edges quiet. Do not draw a visible circle.

Output: Transparent background, family-friendly, no photorealism, no text, no letters, no numbers, no logo, no border, no card frame, no UI, no sword, no dagger, no weapon, no character.
```

#### Vital Emblem

Reference: `[EC] Emblem - Vital.png`

```text
Subject: Create a square 1:1 fantasy Battle Type emblem for Vital: a single large sapphire-blue crystal water droplet, rounded at the base and pointed at the top, with a bright healing light glowing from its center. The droplet should resemble the current Vital emblem: calm, protective, centered, sticker-like, and clearly readable at small UI size.

Style: Render it as stylized low-poly fantasy icon art with clean polygonal forms, crisp planar shading, saturated sapphire and cyan crystal, bright white facet highlights, deep blue internal shadows, and a radiant near-white healing core. Match the premium crystal-sticker look of the existing Mighty and Vital emblems.

Composition: Compose for a circular crop: place the complete droplet at the exact center and contain every important shape within an imaginary central circle. Use a thick white outer cutline and a black inner rim/drop shadow around the silhouette. Keep the corners and outer edges quiet. Do not draw a visible circle.

Output: Transparent background, family-friendly, no photorealism, no text, no letters, no numbers, no logo, no border, no card frame, no UI, no weapon, no character.
```

### 8.2 Currency and Shard bundle icons

#### Crystal Shard

```text
Subject: Create a square 1:1 fantasy currency icon of one Crystal Shard: a single elongated spear-shaped crystal with a pointed top, a short asymmetrical broken base, luminous cyan front facets, and deep sapphire-blue side facets. Show exactly one continuous crystal with no secondary shards.

Style: Render it as polished stylized low-poly fantasy art matching the Elemental TCG card back, with clean polygonal forms, crisp planar shading, bold faceted geometry, cyan inner light, subtle violet refraction, bright edge highlights, and strong small-icon readability.

Composition: Compose for a circular crop: place the complete shard upright at the exact center and contain its full silhouette within an imaginary central circle. Let it occupy roughly 70% of the canvas. Keep the corners and outer edges empty. Do not draw a visible circle.

Output: Transparent background, family-friendly, no photorealism, no text, no number, no symbol, no logo, no border, no frame, no UI, no pedestal, no ground, no floating particles, no crystal cluster, and no additional shards.
```

#### Card Fragment

```text
Subject: Create a square 1:1 fantasy currency icon of one Card Fragment: a single broad irregular pentagonal piece broken from an enchanted card back. Give it visible thickness, a deep navy and royal-blue faceted face, one partial warm ivory-gold beveled border along two edges, and a cyan crystalline reflection within the surface. Show exactly one solid fragment, not a complete card.

Style: Render it as polished stylized low-poly fantasy art matching the Elemental TCG card back, with clean polygonal forms, crisp planar shading, angular sapphire geometry, warm gold bevels, controlled cyan illumination, and strong small-icon readability. Its broad silhouette must be clearly different from the tall Crystal Shard.

Composition: Compose for a circular crop: tilt the fragment slightly in a three-quarter view and place its complete silhouette at the exact center within an imaginary central circle. Let it occupy roughly 70% of the canvas. Keep the corners and outer edges empty. Do not draw a visible circle.

Output: Transparent background, family-friendly, no photorealism, no text, no number, no symbol, no logo, no border, no card frame, no UI, no complete card, no additional fragments, no fragment pile, no floating chips, and no detached particles.
```

#### 100 Shards Bundle

```text
Subject: Create a square 1:1 fantasy shop icon representing the smallest Crystal Shard bundle: a tidy compact stack of three identical spear-shaped cyan Crystal Shards resting together in one controlled arrangement. Use the exact same canonical shard shape as the single Crystal Shard currency icon. The bundle should feel modest and affordable.

Style: Render it as polished stylized low-poly fantasy art matching the Elemental TCG card back, with clean polygonal forms, crisp planar shading, luminous cyan facets, deep sapphire side planes, subtle violet refraction, and focused magical lighting.

Composition: Compose for a circular crop: place the complete compact stack at the exact center and contain every shard within an imaginary central circle. Keep the silhouette simple and readable, with no shard extending toward the corners. Do not draw a visible circle.

Output: Transparent background, family-friendly, no photorealism, no text, no number, no currency symbol, no logo, no border, no frame, no UI, no bag, no chest, no floating shards, no detached particles, and no excessive crystal cluster.
```

#### 320 Shards Bundle

```text
Subject: Create a square 1:1 fantasy shop icon of a small Crystal Shard pouch: one compact deep-sapphire drawstring pouch with warm gold trim, opened slightly at the top, with two canonical cyan Crystal Shards visibly emerging from the opening. The pouch is the main silhouette and should communicate a practical medium-small purchase.

Style: Render it as polished stylized low-poly fantasy art matching the Elemental TCG card back, with clean polygonal forms, crisp planar shading, angular folded cloth, faceted cyan crystals, deep navy-blue material, warm ivory-gold trim, and focused magical lighting.

Composition: Compose for a circular crop: place the complete pouch upright at the exact center and contain the pouch and visible shards within an imaginary central circle. Keep the opening clearly visible while leaving the corners quiet. Do not draw a visible circle.

Output: Transparent background, family-friendly, no photorealism, no text, no number, no currency symbol, no logo, no border, no frame, no UI, no coins, no loose pile, no floating shards, no detached particles, and no spilled contents.
```

#### 700 Shards Bundle

```text
Subject: Create a square 1:1 fantasy shop icon of a large Crystal Shard satchel: one substantial royal-blue merchant bag with reinforced warm-gold corners, a folded open top, and several canonical cyan Crystal Shards packed visibly inside. The bag should look fuller, heavier, and more valuable than the small pouch without becoming an overflowing pile.

Style: Render it as polished stylized low-poly fantasy art matching the Elemental TCG card back, with clean polygonal forms, crisp planar shading, chunky angular construction, faceted cyan crystals, sapphire-blue material, polished gold reinforcement, and controlled magical glow.

Composition: Compose for a circular crop: place the complete satchel at the exact center in a slight three-quarter view and contain every important shape within an imaginary central circle. Keep the contents compact and the outer edges quiet. Do not draw a visible circle.

Output: Transparent background, family-friendly, no photorealism, no text, no number, no currency symbol, no logo, no border, no frame, no UI, no coins, no chest, no loose shard pile, no floating shards, and no detached particles.
```

#### 1,300 Shards Bundle

```text
Subject: Create a square 1:1 fantasy shop icon of an open Crystal Shard treasure chest: one compact deep-sapphire chest with thick warm ivory-gold bands, angular low-poly construction, and a raised lid revealing many canonical cyan Crystal Shards neatly packed inside. The chest should feel premium and clearly more valuable than either pouch.

Style: Render it as polished stylized low-poly fantasy art matching the Elemental TCG card back, with clean polygonal forms, crisp planar shading, faceted sapphire panels, polished gold bevels, luminous cyan crystal contents, subtle violet refraction, and focused magical lighting.

Composition: Compose for a circular crop: place the complete open chest at the exact center in a slight three-quarter view and contain the lid, body, and contents within an imaginary central circle. Keep the chest compact and avoid shapes reaching into the corners. Do not draw a visible circle.

Output: Transparent background, family-friendly, no photorealism, no text, no number, no currency symbol, no logo, no border, no frame, no UI, no coins, no loose external pile, no floating shards, no detached particles, and no scenery.
```

#### 3,000 Shards Bundle

```text
Subject: Create a square 1:1 fantasy shop icon of a grand Crystal Shard coffer: one large prestigious royal-blue vault chest with broad warm-gold reinforcement, a central cyan crystal clasp, and an open lid revealing an abundant treasury of canonical cyan Crystal Shards. Make it feel like the highest-value bundle through its larger construction, richer trim, brighter internal glow, and densely filled interior.

Style: Render it as polished stylized low-poly fantasy art matching the Elemental TCG card back, with bold polygonal forms, crisp planar shading, elaborate sapphire geometry, thick polished ivory-gold bevels, intensely luminous cyan crystals, restrained violet refraction, and dramatic but controlled magical lighting.

Composition: Compose for a circular crop: place the complete grand coffer at the exact center in a heroic three-quarter view and contain its entire silhouette and crystal contents within an imaginary central circle. Keep the corners quiet and preserve a strong readable silhouette. Do not draw a visible circle.

Output: Transparent background, family-friendly, no photorealism, no text, no number, no currency symbol, no logo, no border, no frame, no UI, no coins, no separate containers, no floating shards, no detached particles, no scenery, and no external crystal pile.
```
