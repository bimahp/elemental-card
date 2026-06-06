# DESIGN_ROADMAP — Elemental TCG

## Phase Overview

| Phase | Goal | Status |
|-------|------|--------|
| v0.1 | Core battle loop — one NPC, one player, full game from start to rewards | ✅ Functionally complete |
| v0.2 | Multiple NPCs + second element deck + basic card collection UI | 📋 Planned |
| v0.3 | Player vs Player + deck building UI | 📋 Planned |
| v0.4 | Card packs, shop, trading | 📋 Planned |
| v1.0 | Full social TCG store — tournaments, mastery, cosmetics | 📋 Planned |

---

## v0.1 — Core Battle Loop ✅

### Goal
Prove the battle system works end-to-end. One NPC, one player, real game from seating to rewards.

### Feature Checklist

| Feature | Status | Notes |
|---------|--------|-------|
| Card data module (Fire Deck) | ✅ Done | 14 unique cards, 24-card deck in Lua |
| Battle state module | ✅ Done | Full board/hand/deck/resource state |
| Battle logic module | ✅ Done | Draw, generate, play, attack, win check |
| NPC AI (rule-based) | ✅ Done | Priority-based: summon → skill → support → attack |
| Server battle controller | ✅ Done | Server-authoritative, RemoteEvents, DataStore |
| Player chair interaction | ✅ Done | ProximityPrompt on DuelTable → Challenge/Leave GUI |
| NPC sit behavior | ✅ Done | Direct CFrame seat, Heartbeat-maintained R6 pose |
| Battle UI | ✅ Done | Full ScreenGui — board, hand, log, camera |
| Rewards + DataStore | ✅ Done | +50 EXP, +25 Gold, 1 random Fire card drop |
| Post-battle screen | ✅ Done | WIN/LOSE overlay, rewards shown, Continue to unseat |

### UI Refinements (completed during v0.1)
- Two-section board layout (EnemySection anchored top, PlayerSection anchored bottom)
- Uniform board card sizes — all 8 slots same dimensions
- Enemy hand backs = player hand card size (visual consistency)
- Character hidden during camera lock (except arms)
- Battle log (240px tall, auto-scrolls)
- Forfeit button below End Turn
- Passive descriptions shown on all applicable cards
- Movement locked until Continue is clicked after battle ends

### Known Issues Still Open

| Issue | Notes |
|-------|-------|
| NPC foot orientation | Testing Z-axis rotation; may need further tuning |
| Avatar thumbnails in info widgets | Placeholder box; can add `GetUserThumbnailAsync` later |
| Turn order (who goes first) | Always player for now; design TBD |
| Deck-out loss rule | No rule currently |
| Max hand size | No cap currently |

---

## v0.2 — More Opponents + Card Collection

### Goal
Give players a reason to keep playing after beating the first NPC. Introduce a second element, show the player their card collection.

### Planned Features

#### Second NPC Deck
- Nature Deck added to CardData module (cards already designed in DESIGN_CARDS.md)
- Second NPC model placed at another table in the world
- NPC AI reused — same logic, different deck

#### Card Collection UI
- Simple inventory screen showing all cards the player owns
- Accessed from a menu or dedicated button in the world
- Cards sorted by: element, type, level
- No deck building yet — read-only display

#### Win Streak / Rematch
- Track wins against each NPC
- Show win count on NPC info widget
- Simple rematch option without leaving seat

#### TBD Decisions to Resolve Before v0.2
- Who goes first? (coin flip at battle start)
- Deck-out rule (lose when you can't draw, or skip draw?)
- Max hand size (7? 10?)
- Max Equipment per monster
- Max Field Supports in play

---

## v0.3 — Player vs Player + Deck Building

### Goal
Enable human-vs-human duels and let players customize their decks.

### Planned Features

#### Player vs Player
- Two players sit at opposing chairs and challenge each other
- Same server-authoritative battle loop — only difference is two human clients
- Matchmaking: proximity-based (challenge whoever is sitting across)

#### Deck Building UI
- Open from card collection screen
- Drag cards into a 24-card slot layout
- Validation: 2-copy limit, type composition
- Save deck to DataStore per player

#### UI Overhaul
- Replace placeholder art with DALL-E generated card images
- Card hover/expand to show full text
- Attack flow: click Active → highlight target → confirm button

---

## v0.4 — Economy + Social

### Goal
Add long-term card acquisition and player-to-player interaction.

### Planned Features
- Card pack opening (Gold → random cards with rarity tiers)
- In-game shop (NPC shopkeeper)
- Player-to-player card trading
- Rarity system: Common / Uncommon / Rare / Legendary

---

## v1.0 — Full Release

### Planned Features
- Tournaments (bracket system, entry fee, prize pool)
- Monster mastery tracking and unlocks
- Cosmetic card borders and art variants
- Spectator view for active duels
- Seasonal ranked ladder
- All 4 element NPC decks (Fire, Nature, Lightning, Water)

---

## Technical Architecture Notes

### Server Authority Model
All game state lives on the server. Clients send actions, server validates, broadcasts sanitized state.

```
Client → fires RemoteEvent (PlayCard, DeclareAttack, EndTurn...)
  ↓
Server → validates → applies to state → checks win → broadcasts state
  ↓
Client → receives UpdateBattleState → re-renders UI
```

### State Sanitization
State sent to client hides opponent's hand — only `handCount` is sent.

### DataStore Schema
```
Key: "ElementalTCG_v1"  (per player by UserId)
{
  exp   = number,
  gold  = number,
  cards = { cardId, cardId, ... }   -- all owned cards (may include duplicates)
}
```

### RemoteEvents
All in `ReplicatedStorage.Remotes/`:

| Event | Direction | Payload |
|-------|-----------|---------|
| `StartDuel` | Client → Server | — |
| `PlayCard` | Client → Server | cardId, targetWho, targetSlot |
| `DeclareAttack` | Client → Server | — |
| `EndTurn` | Client → Server | — |
| `Forfeit` | Client → Server | — |
| `UpdateBattleState` | Server → Client | sanitized state snapshot |
| `BattleOver` | Server → Client | { winner, rewards } |

### Implementation Order Reference (original v0.1)
1. Card data module
2. Battle state module
3. Battle logic module
4. NPC AI module
5. Server battle controller + RemoteEvents
6. Player chair interaction
7. NPC sit behavior
8. Battle UI (ScreenGui)
9. Rewards + DataStore
10. Post-battle screen
