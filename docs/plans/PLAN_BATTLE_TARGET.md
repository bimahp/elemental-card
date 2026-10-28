# Targeting Revamp Plan

## Summary
Current targeting has four hand-card classes from `CardText.targetClass(card)`: `slot`, `friendly`, `enemy`, and fallback `hero`. The fallback is the problem: every AOE, random, draw, armor, hand-tax, and other self-resolving spell currently becomes “drop on your hero.”

Revamp targeting by adding an explicit spell-level `playTarget` field to card data. The UI will use `playTarget` to highlight intuitive surfaces, while existing effects still decide actual rules resolution. Chosen single targets still win over automatic side effects.

## Public Data / Remote Changes
- Add required `playTarget` to every spell in pack JSON and runtime `Cards.lua`.
- Creatures do not need `playTarget`; they remain implicit empty-slot cards.
- Valid `playTarget` values:
  - `friendly_creature`, `enemy_creature`, `friendly_character`, `enemy_character`, `any_creature`
  - `own_hero`, `enemy_hero`
  - `own_board`, `enemy_board`, `battle_board`
  - `own_side`, `enemy_side`
- Add optional remote field for zone drops:
  - Client sends `opts.zone = "own_board" | "enemy_board" | "battle_board" | "own_side" | "enemy_side"`.
  - Server remaps it to canonical `{ scope = "board"|"side"|"battle", side? = "player"|"npc" }`.
  - Current effects may ignore `chosenZone`; this is future-ready for board/environment mechanics.
- Keep existing object payloads unchanged:
  - Creature summon: `{ slot = N }`
  - Card/hero target: `{ target = { side = "player"|"npc", slot = 0..3 } }`

## Key Implementation Changes
- Replace `CardText.targetClass(card)` with a new helper such as `CardText.playTarget(card)` that returns explicit `playTarget` for spells and `empty_slot` for creatures.
- Extend `CardSchema`:
  - Require valid `playTarget` on every spell.
  - Reject `playTarget` on creatures or ignore it consistently.
  - Validate compatibility: single chosen-target effects must use matching target surfaces.
- Update desktop and mobile targeting together:
  - `enemy_board`: highlight enemy creature-slot region only, not enemy hero.
  - `own_board`: highlight own creature-slot region only.
  - `battle_board`: highlight both creature-slot regions.
  - `own_side` / `enemy_side`: highlight board region plus hero.
  - `own_hero` / `enemy_hero`: highlight only hero card.
  - Character targets highlight valid creature cards plus hero where allowed.
- Fix server-side targeted Stealth validation while touching targeting:
  - Enemy targeted spells must reject stealthed enemy creatures, matching current UX and rules.
- Add `chosenZone` through `BattleLogic.playCard` context for future actions.
- Existing card assignment defaults:
  - AOE enemy damage/split: `enemy_board`
  - Friendly-wide buffs/heals: `own_board`
  - Whole-board future cards: `battle_board`
  - Draw-only/self utility: `own_side`
  - Enemy hand-tax/random enemy utility: `enemy_side`
  - Crystal Vent and hero-resource effects: `own_hero`
  - Armor plus draw/heal hero effects: `own_hero`
  - Mixed cards with a required chosen target, like Leech Life or Spirit Crush: chosen target surface wins.

## Test Plan
- Schema validation fails any spell missing `playTarget`.
- Desktop drag highlights correct zones for:
  - summon, friendly creature, enemy creature, enemy character, own hero, enemy board AOE, own board buff, own side utility, enemy side utility, battle board future fixture.
- Mobile drag matches desktop behavior using mobile board/hero frames.
- Server accepts zone drops for AOE/self-resolving spells and rejects incompatible zones.
- Server still accepts existing chosen target payloads.
- Stealthed enemy creatures cannot be targeted by spells from client or malicious remote.
- Regression smoke:
  - Play AOE by dropping on enemy board, not hero.
  - Play draw/armor utility on intended own-side or own-hero surface.
  - Play Crystal Vent on own hero.
  - Play single-target spells on card/hero targets.
  - Attack targeting remains unchanged.

## Assumptions
- `playTarget` is required for spells only.
- Chosen single-target effects take priority over extra automatic effects.
- Zone drops are added now as a future-facing remote/interface, but current card effects continue resolving from existing effect schema unless a future action consumes `chosenZone`.
