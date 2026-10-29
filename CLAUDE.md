# Elemental TCG — instructions for Claude

A Roblox digital card battle game set in a 3D TCG card shop (desktop and landscape mobile). **All game code lives in the Roblox Studio place**, reached through the Roblox Studio MCP; there is no Rojo. This repo holds the docs, the card data in `data/`, vendored ProfileStore in `vendor/`, the UI migration scripts and exports ([ARCHITECTURE §12.1](docs/ARCHITECTURE.md)), and gitignored art in `assets/`.

**Start every session with [`docs/HANDOFF.md`](docs/HANDOFF.md):** current status, what is next, what to check, how work is done. Update it when status changes. Owner decisions and project memory are in [`AGENTS.md`](AGENTS.md).

Docs of record (each fact has exactly one home):

| Doc | Owns |
|---|---|
| [`docs/GAME_DESIGN.md`](docs/GAME_DESIGN.md) | Battle rules, decks, modes, forfeits, progression, onboarding |
| [`docs/CARDS.md`](docs/CARDS.md) | Card sets, archetypes and tribes, rarity, card data format |
| [`docs/MONETIZATION.md`](docs/MONETIZATION.md) | Currencies, rewards and caps, packs, Vendor, Recycle, Robux shop |
| [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) | Module layout, engine, networking, persistence, tooling limits |
| [`docs/UI.md`](docs/UI.md) | UI standard, screens, card display, input, animation |
| [`docs/ART.md`](docs/ART.md) | Art direction and prompt library |

`docs/plans/` are build records, `docs/research/` is outside reference, `docs/archive/` is superseded. None of them override a doc of record.

## Owner rules (always)

- **Editor-first UI:** every UI element is a real instance authored in Studio. Code only clones, fills and switches state; no `Instance.new` for GUI. Image-icon outlines use a layered dark copy of the image, not `UIStroke`.
- **Settle design in the docs before building.** Prefer simple, unified mechanics. Large work gets a plan in `docs/plans/` first.
- **When asked "do you understand?",** explain your understanding and plan, and wait for the go-ahead.
- **Critique directly.** Challenge weak ideas and flag flaws, including architecture corrections found mid-build; never quietly route around them.
- **No paid randomness:** Robux never buys a random outcome, directly or through a conversion chain (MONETIZATION §1).
- **Check the right Studio place is connected** before any MCP edit; other projects' places may be open.
- **Saves:** a minor schema bump needs a migration; a major bump wipes profiles and needs the owner's explicit yes.
- **After changes:** test (headless for pure modules, Studio Play with real remotes for player paths), update the doc of record and HANDOFF in the same session, and remind the owner to save the place.

## Documentation rules

Learned from ant-verse, where the docs of record worked and their headers and handoff did not:

1. **One home per fact.** Other docs link to it instead of repeating numbers. When two docs disagree, fix the owner and delete the copy.
2. **Header = status line + Owns / Does not own.** One sentence of status with a date. No revision history in headers or "Last updated" lines; history is git and the plans.
3. **Numbered sections** so references like `GAME_DESIGN §3.11` stay stable. Add sections at the end of their level; do not renumber casually.
4. **Mark what is not built** with **Not built** at the rule. Docs describe the design; HANDOFF says what is built.
5. **Open decisions live in one numbered list per doc**, at the end. Resolve them by editing the rule and deleting the entry.
6. **Plans never become design.** When a build changes a rule, update the doc of record in the same session; the plan only records how it was built.
7. **HANDOFF stays one screen of status.** No narrative of what was found; that belongs in the plan.
8. **Numbers are starting values** and name the config module that holds them.
9. **Plain, short sentences.** Tables for values, prose for rules.
