# Elemental TCG

A Roblox digital card battle game set inside a 3D TCG card shop. Players collect creature cards of three crystal affinities (Ruby Bears, Emerald Cats, Sapphire Frogs), build 30-card decks, and duel NPCs and other players at the shop's tables, using Energy and a two-slot Battle Charge built by the creatures they keep alive. Random packs are earned through play only; Robux buys exact items, never randomness.

**Engine:** Roblox Studio (no Rojo; `src/` is pushed through the Studio MCP) | **Language:** Luau | **Phase:** alpha

## Documentation

Start with [docs/HANDOFF.md](docs/HANDOFF.md) for the current status.

| Doc | What it covers |
|---|---|
| [docs/GAME_DESIGN.md](docs/GAME_DESIGN.md) | Battle rules, decks, battle modes, progression, onboarding |
| [docs/CARDS.md](docs/CARDS.md) | Card sets, archetypes and tribes, card data format |
| [docs/MONETIZATION.md](docs/MONETIZATION.md) | Currencies, rewards, packs, Card Vendor, Recycle, Robux shop |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | Code layout, battle engine, networking, persistence |
| [docs/UI.md](docs/UI.md) | UI standard, screens, card display, animation |
| [docs/ART.md](docs/ART.md) | Art direction and prompt library |
| [CLAUDE.md](CLAUDE.md), [AGENTS.md](AGENTS.md) | Instructions and owner decisions for AI agents |

## Repository layout

```text
data/       card sets (pack_*.json) and starter decks; the human-readable catalog
docs/       HANDOFF and the docs of record; plans/ (build records), research/, archive/ (superseded)
src/        every game script, mirroring the Studio DataModel (source of truth)
scripts/    Studio tooling: pull, checksums, UI export and checks
ui/         JSON exports of the authored UI trees
assets/     card images and other art (gitignored)
```
