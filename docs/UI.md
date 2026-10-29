# Elemental TCG — UI and Presentation

**Status:** UI/UX direction of record, merged 2026-10-28 from the former `DESIGN_UI` and `IDEA_CARD_BATTLE` (the battle UX and animation spec).

**Owns:** the UI visual standard, every screen's layout and behaviour, card display, input, and battle animation timing.
**Does not own:** rules ([GAME_DESIGN.md](GAME_DESIGN.md)); labels and amounts for currencies and rewards, which always come from the server and [MONETIZATION.md](MONETIZATION.md); art direction ([ART.md](ART.md)).

Every UI element is authored as a real instance in Studio (editor-first, [ARCHITECTURE.md](ARCHITECTURE.md) §1). **Not built:** most of today's UI is still built in code; it moves to authored kit templates screen by screen, battle last (§10).

---

## 1. Presentation model

- **The 3D world** is the card shop: tables, NPCs, the Vending Machine, the Card Vendor.
- **A 2D ScreenGui overlay** carries everything in a battle, visible only to the two players. It is the gameplay surface.
- **Table visualisation (Not built):** a Part/SurfaceGui mirror of board, HP and turn on the table for spectators, with no interaction.

## 2. UI visual standard

Non-battle panels use a **hybrid game UI**: playful and chunky like a Roblox game panel, while belonging to the crystal-fantasy card world. Quality comes from hierarchy, contrast, touch targets and designed empty states, not from decoration everywhere.

### 2.1 Panel frame

- Thick near-black navy outer stroke, large rounded corners, a coloured title bar, and a solid navy divider between title bar and body. The header must read as its own coloured layer.
- Title bars use individual `UICorner` radii: rounded top, square bottom. Use 9-slice art only for a silhouette native geometry cannot make.
- A restrained native `UIShadow` separates modals from the world, secondary to the stroke.
- Default shell: deep navy body, darker inner surfaces, saturated accent header. Light bodies only for dense inventory grids.
- Every modal has a title bar, a large title, a close button, consistent padding, an optional back button and an optional scrim. Root pages show the panel's product icon in the back-button slot; deeper pages show Back there.
- An invisible input blocker sits under the content: clicking the header or empty interior never closes the modal; only the close button or a click outside does.
- **Entrance:** start slightly below rest, overshoot upward, settle down, in one eased tween under 0.5 s. Play only on open, never on internal page navigation.
- Sections inside a modal use framed surfaces, not nested modal cards.

### 2.2 Colour

- Near-black navy outline; dark blue-navy panel; darker slate-navy inner panels; white primary text, soft blue-grey secondary.
- Accents: Card Fragments warm gold, Crystal Shards cyan, MIGHTY ruby, SWIFT green, VITAL sapphire, NEUTRAL quartz (hex values in §4.3).
- Never let background, panel, section and empty state share one value. Gradients may polish title bars, badges and primary buttons, but hierarchy must work without them.

### 2.3 Typography

- A rounded display font (Fredoka One) for titles, labels, item names and important numbers; a cleaner font for body text.
- Titles are clearly larger than body labels. Text on saturated headers may use a dark stroke.
- Text stays inside its container for long card names, large currency values and localised prices. Test with `1000 Shards`, `1599 Robux`, `10.2K`, `999.9K` and long card names.

### 2.4 Buttons and HUD icons

- Primary buttons are chunky, high-contrast and full-width in purchase rows. Economy actions show item, amount and price at a glance.
- Disabled and loading states visibly dim and stop hover feedback.
- Close and back are large icon buttons, never small text.
- HUD icons that already include a dark silhouette or border render once with `ScaleType = Fit`. Never add a duplicate-image outline or `UIStroke` to pre-bordered art. Unframed art gets its outline from a layered dark copy of the image, not `UIStroke`.
- Desktop world-menu icons are 72 px with a short white label overlapping their lower edge (display font, dark `UIStroke`), never a second row under the icon.

### 2.5 Texture

- Subtle crystal, faceted or diamond patterns in panel bodies and empty states, as a low-opacity overlay above the base fill. It never replaces the fill or carries information.
- Shared navy panel texture `rbxassetid://115366182634060` covers the whole non-header interior edge to edge and never intercepts input. Content padding belongs to the page, not the texture.
- No noisy full-background images in functional panels.

### 2.6 Responsive rules

- **Mobile is landscape-only:** `StarterGui.ScreenOrientation = LandscapeSensor`.
- Panels respect device safe areas. The world HUD uses `DeviceSafeInsets`: currency aligns with the Roblox top-bar row and the menu buttons sit directly beneath it.
- **Modals use two ScreenGuis:** a full-viewport backdrop button (`ScreenInsets = None`, `InputSink = All`, closes on click, renders the only dim) and the panel plus a transparent click-to-close scrim (`CoreUISafeInsets`). Never stack two dims. Headers must not overlap Roblox CoreGui. The backdrop becomes an authored ScreenGui under the Panels layer (§10.1); **Not built:** code creates it today.
- Do not rely on `FullscreenExtension`; set insets explicitly on every loading, modal and battle overlay.
- Dense panels: two columns on desktop, stacked below the mobile threshold.
- Nothing overlaps during hover, selection, loading, price lookup or balance updates.

## 3. World screens

### 3.1 HUD

The top-right anchor holds the world icons: **Profile** (left), **Card Library** (centre), **Matchmaking** (right), plus Item Mall, with the currency bar (Shards, Card Fragments) above. The whole group hides during battle states and returns after.

### 3.2 Card Library

One reusable `InventoryUI` panel with a page stack: `Home → My Cards / Deck Builder / Recycle → Deck List → Deck Editor`.

- **My Cards:** the owned-card grid with filters and preview. Tiles show art, name, quantity, rarity and type colour and ownership; full rules text belongs in the detail panel. Empty detail states use a faint card silhouette or crystal motif, never a blank rectangle.
- **Deck Builder:** saved decks with validity, count and active marker. Create Deck makes a deck with a default name; rename lives in the editor.
- **Deck Editor:** all owned cards; enforces the copy limits; shows validation messages; Set Active only for a valid 30-card deck. A Charge-type indicator (`N Charge Type(s) in deck`) turns into a non-blocking warning (`N Charge Types - Hero Slots: 2` plus a one-time toast) above two producing types. Below it, an informational summary: per-type generators (`+N`) and spenders (`-N`) and pure-Charge count (`PC:N`).
- **Recycle:** owned cards left, queued cards right, `Recycle Selected`, `Clear`, selected count and total Shards. Click a card to queue one copy; click a queued row to remove one. Badges show owned and queued counts. A deck-breaking recycle opens a blocking popup, "Cant add card, used on deck", with Confirm.
- One header back button goes back a page; Back from the root closes the panel.

### 3.3 Card Vending Machine

- **Pack selection** is one vertical scrolling browser of named sections, each a responsive tile grid, so new collections append without a new page. Tiles are about 220×270 on desktop and 160×190 on mobile; art uses `Fit` and is clipped by the scrolling body.
- **Pack Contents:** two columns on both desktop and mobile: a scrolling odds list (about 68%) and a fixed text surface (about 32%) explaining duplicate protection and odds rounding.
- **Odds rows** are stable 58–66 px touch targets with a battle-type outer stroke. The unframed battle-type emblem fills the left icon space (never in a circle); the race overlays the top of the emblem, or `SPELL`. Card names are white display text with a thick rarity stroke (Common quartz, Rare cyan, Epic violet, Legendary gold). A dark right-aligned pill shows the server's percentage with up to four decimals, trailing zeroes removed. Order: rarity, then battle type, then name.
- Hover 0.5 s (desktop) or hold 0.5 s (mobile, cancelled by moving more than 12 px) opens a full card preview; rows tint and strengthen their stroke on hover or touch-down. A normal tap does nothing. Previews are non-interactive, stay in safe bounds and close on scroll, navigation, close, odds refresh, purchase and reveal.
- **Reveal:** a gameplay-modal 3D reveal with movement and prompts locked, a crystal burst, a rigid 3D card stack, five-card results and Claim.

### 3.4 Card Vendor

Talking to the Vendor opens the shared dialogue, then a Stock → Detail shop with Craft and Buy buttons, maxed and error states. Stock is re-fetched after every purchase so buttons never use a stale snapshot.

### 3.5 Profile

`PlayerStatusUI`: an input-sinking modal with desktop bounds, landscape-mobile sizing, loading, error and retry states, and Overview and Titles tabs. Titles explain locked requirements and allow equipping only owned titles.

### 3.6 Matchmaking

A panel with the player's level, Find Opponent / Cancel Matchmaking and a ticking elapsed-time label on the HUD icon while queued.

### 3.7 Dialogue and quest guidance

The shared dialogue: typewriter text, a camera tween, movement lock and option buttons. Speakers, conversation ids and the queue are in §10.6. Quest guidance: `!` marks on NPC nameplates (three rows: `!`, title, name; the `!` row is 36% of the plate with a 48 px mark) and a screen-space arrow.

## 4. Before the battle

### 4.1 Table flow

- **NPC:** the Noob's `[E] Talk` prompt asks the server for a table; it seats the player, seats a cloned NPC opposite and starts at once (no Challenge button). An input-blocking **"Finding Table..."** overlay shows while seating (also optimistically on the prompt) and clears on battle state, unseat or abort, battle over, timeout or respawn.
- **Local PvP:** `[E] Sit` on the table. A bottom **SeatedOverlay**: "Seated (chair N) — waiting for opponent…" with **Ready** and **Leave Seat**. The battle starts when both are ready.
- While loading, seated or in battle, the client disables the ControlModule and hides that table's prompts; everything is restored afterwards.

### 4.2 Mulligan ("First Draw")

- `OfferMulligan` first puts the player in the seated battle camera; after a short settle beat the **First Draw** dialog opens and clears "Finding Table...".
- It shows the five dealt cards, each with its own **Re-draw** button parented to the card, a countdown matching the server timeout, and a **Battle** button.
- Tapping a Re-draw swaps that card immediately through the server and removes every Re-draw button. Battle finalises. In PvP the first to finish sees "waiting for opponent".
- The dialog closes on the battle's first `UpdateBattleState`, not a separate signal.

### 4.3 Turn banner

At the start of every turn, a full-width **YOUR TURN** / **ENEMY TURN** banner fades and scales in, holds, fades out, and locks input, before that turn's draw animation.

## 5. Battle screen

### 5.1 ScreenGui

`IgnoreGuiInset = true`, `ScreenInsets = DeviceSafeInsets`, `ZIndexBehavior = Sibling`. `ClipToDeviceSafeArea` stays **off**: Roblox does not clip rotated objects, so clipping would crop only the unrotated centre card of an odd hand fan. `AbsoluteSize` may be 1 px short because of Windows display scaling; that is engine behaviour.

### 5.2 Desktop layout

```text
┌──────────────────────────────────────────────┐
│ Enemy hand (card backs, count visible)       │
│ [Slot 1] [Slot 2] [Slot 3]  [Enemy hero]     │
│                                              │
│          Turn 02  0:42  [End Turn]           │
│                                              │
│ [Slot 1] [Slot 2] [Slot 3]  [Your hero]      │
│                              Energy  Grave   │
│ Your hand (fanned)                   Deck    │
└──────────────────────────────────────────────┘
```

- **Hero card** (the fourth cell of each board row): the player's avatar portrait, HP bottom-left, Armor bottom-right (hidden at 0), and **two Battle Charge sockets** on the right edge.
- **Charge sockets** are always two; empty ones stay faintly visible. An occupied socket shows its Battle Type emblem with the amount and a type-coloured rim; the current slot has a bright yellow ring. Sockets are as prominent as the board ATK/HP emblems, never tiny dots, and overlap the portrait edge rather than widening the row. Gains and replacements pop the socket, spends dim it; the state is painted first, so a skipped pop never misleads.
- **Energy:** the Energy icon (`rbxassetid://114305689596215`) is the badge itself, above the Grave pile, sized to the End Turn + Forfeit buttons; "current/cap" in gold display text at a fixed size.
- **Deck and Grave** piles bottom-right with counts. Clicking the Grave opens the graveyard history.
- **Turn timer:** a compact countdown beside the turn indicator and End Turn (desktop) or in the bottom-right cluster (mobile), with a warning colour in the last seconds and an optional pulse in the last 5. It resyncs on each state; if `turnEndsAt` has not changed, a re-render keeps the live countdown.

### 5.3 Mobile layout

Mobile mode starts when the viewport is narrower than 800 px or `UserInputService.PreferredInput` is Touch (`UXMode`, §10.2). It never follows the last input, so a key press or chat on a PC never flips the layout. The desktop frame hides and `mobileRoot` shows a four-row grid:

| Row | Height | Contents |
|---|---|---|
| Enemy hand | 20% | Face-down backs fanned like the player hand, 46 px of each visible |
| Enemy board | 30% | 3 slots + hero, scaled to the row |
| Player board | 30% | Same |
| Player hand | 20% collapsed / 35% expanded | The playable hand |

- The board pair sits at vertical centre; the 46 px enemy peek matches the collapsed player peek.
- A Grave button (bottom-left, 44×44, count badge) and a HUD cluster (Energy, Deck, End Turn, Forfeit, stacked) docked bottom-right.
- **Collapsed hand:** a slight fan (16° / (n−1) per card), 46 px visible. **Tapping a card** tweens the row to 35% height over 0.18 s with a tighter 8° / (n−1) fan and a scrim behind.
- **Drag to play:** dragging at least 25 px lifts the card to the top layer, collapses the hand and highlights valid zones. Card z-order is `25 + i`, left lowest. A drag flag stops the hand from expanding mid-drag.

## 6. Cards on screen

### 6.1 One silhouette

Hand, board, deck and graveyard share one artwork-forward card shape (about 14:19). Art fills the frame edge to edge; name and stats overlay it.

```text
┌──────────────┐
│(E)           │ ← stat cluster on the upper-left edge:
│(A)   [ART]   │   Energy / Attack / Health emblems
│(H)           │
│              │
│──Name bar────│ ← straddles art and description 50/50
│ Description  │ ← ability name + text (full mode)
└────[RACE]────┘ ← type badge, bottom-centre (full mode)
```

- **Full mode** (hand, deck, graveyard, previews): art fills the top 62%, the light description panel the next ~34%. Ability text is always visible.
- **Compact mode** (board): art fills the whole card; no name bar, description or type badge; Attack and Health only.
- **Name bar:** bold white text on a dark outline, centred.
- **Type badge:** a pill at the bottom centre, slightly past the edge, in the archetype colour with a white border, showing the race (BEAR, CAT, FROG, TREANT, GOLEM) or `SPELL`.
- **Spell circle:** spells show their art inside an archetype-ringed circle in the upper centre, over the archetype background, so creature and spell read differently at a glance (spells have no ATK/HP).
- **Border:** 4 px in the archetype colour, contextual stroke so the size never changes.

### 6.2 Stat cluster

- Energy, Attack and Health emblems stacked on the left edge as one group, each an icon with its value centred in Fredoka One. ATK and HP values are white with a dark outline; the Energy value is gold `RGB(255,224,70)`.
- Full mode: all three, each 0.15 of the card size at `x = −0.05` (overlapping the edge). Compact mode: ATK and HP only, 0.2 of the card at `x = 0.03`. Both use a 0.03 top inset and 0.03 gap.
- **Cost colours on hand cards:** Energy turns green below base cost and red above, like ATK/HP buffs and debuffs.
- **Charge cost badge:** the Battle Type emblem with the amount. Hybrid cards place it right of the Energy badge; pure-Charge cards put it in the Energy position and hide the Energy badge (never a "0"). A hand-taxed Charge cost shows in the debuff colour.
- A legacy CORRUPTED card prefixes its name with ☠; nothing else changes.
- Icons: Energy `rbxassetid://114305689596215`, Attack `rbxassetid://139799158026059`, Health `rbxassetid://113514992851320`.

### 6.3 Type colours

One main colour per archetype, used for the card border, type badge, board borders and target highlights. The badge fill is a vertical gradient from about 15% lighter to 15% darker.

| MIGHTY | SWIFT | VITAL | NEUTRAL |
|---|---|---|---|
| `#A50E0E` | `#0D652D` | `#174EA6` | `#9AA0A6` |

### 6.4 Sizes

| | Desktop | Mobile |
|---|---|---|
| Hand | 132×178 | 112×152 |
| Board | 96×130 | scales to 30% of viewport height |
| Deck / Graveyard | 86×116 | 70×95 |

### 6.5 Card back

Used for the enemy hand and the deck: a rounded rect `RGB(92,62,38)` with a 1.5 px `RGB(58,38,22)` stroke; art `rbxassetid://139116126302379` full-bleed (a brown crystal sunburst with an energy gem); an inset panel at 84% with a 2.5 px black stroke; a white 115° diagonal gloss.

### 6.6 Board status

- **Taunt:** a large semi-transparent shield icon over the art.
- **Stealth:** a light cloud/fog icon; the card stays readable and is never darkened.
- **Summoning sickness:** looping "Z" particles from the top right (never on Charge creatures).
- **Disabled Shatter:** a compact red X badge.
- **Exhausted this turn:** the whole card dims. This is the only full-card dark overlay.
- Statuses use icons, never text.

### 6.7 Previews

- **Board:** hover 0.5 s (desktop) or hold 0.5 s without dragging (mobile) shows the full card at 1.7× to the **left** of the slot, flipping right near the left screen edge. It hides on leave or release and never shows during a drag.
- **Hand:** hovering scales a card 1× → 1.22×, lifted, with neighbours opening space; description text scales with it; rotation stays.

### 6.8 Hand fan

- Fanning starts beyond 3 cards and ramps to full strength over 3 more; at most 4° per card and 28° total.
- Spacing is the smaller of card width × factor (player 0.8, enemy 0.5) or what fits the row.
- The player hand sits 20 px past the bottom edge, the enemy hand 30 px past the top; arc height scales with spacing.
- Unplayable cards (not enough Energy or Charge, no valid target) are greyed when the client has the hint.

## 7. Input

There is no "selected" state and no Play / Attack / Info buttons. Both playing and attacking are **press and drag**:

```text
Idle → press + drag past threshold → Dragging (arrow, valid zones lit, hint banner)
  → release on a lit zone → action sent
  → release elsewhere, ESC or right-click → cancelled, back to Idle
```

- **Playing:** creatures drop on a lit empty slot; single-target spells on the matching card or hero; board and side spells on the lit board segment or side (an enemy area spell drops on the enemy board). Zones come from `CardData.playTarget(card)`. Valid zones highlight green; the banner names the target ("Drop on an empty slot").
- **Attacking:** drag a creature that can attack (not sick, not yet attacked, ATK > 0). Enemy creatures (not Stealthed) and the enemy hero highlight red; a non-Stealthed Taunt creature is the only valid target. A creature that cannot attack does not start a drag. On mobile a short stationary hold opens the preview instead.
- The arrow, hint and toasts render on the always-on-top `TargetingOverlay`, so they work in both layouts.
- **Rejected actions:** when the server refuses (not enough Energy or Charge, Taunt, Stealth, sickness, an unmet spell condition such as *No Wounded Ally*), a red toast appears near the centre and fades; the card stays in hand.

## 8. Animation

The server never waits for animation (§1). The client plays the event log in order through the `BattleDirector` ([ARCHITECTURE.md](ARCHITECTURE.md) §6).

### 8.1 Card movement

Every card move is visible: draw (deck glows, card flies to hand), play (lift, travel, land in slot), destroy (shake, fade, fly to graveyard), discard (hand to graveyard), mill (deck to graveyard).

### 8.2 Cast reveal

Playing a card locks input; the card zooms to about 1.8× centre screen, then a single-target damage spell sends a Battle-Type-tinted bolt from the caster's hero to the target before the impact. Other cards play the normal animation. More archetypes (AOE swipe, heal bloom, buff pulse, shield pulse, summon puff, shatter, rebirth) are **Not built**.

### 8.3 Attacks

Cards themselves lunge; there are no creature models.

| | Total | Windup | Lunge | Impact | Return |
|---|---|---|---|---|---|
| Creature vs creature | 0.45 s | 0.05 | 0.15 | 0.10 | 0.15 |
| Face attack | 0.37 s | 0.05 | 0.12 | 0.08 | 0.12 |

- The card travels only 25–35% of the distance; impact effects complete the illusion. Lunge `Quad Out`, return `Quad In`.
- **Impact:** the target shakes for 0.08 s and punches 1.00 → 1.05 → 1.00. Damage numbers appear at impact, not after the return.
- **Death** starts right after damage and plays while the attacker returns. If the attacker also dies, it shrinks to nothing during its return and its slot empties when the return completes.

## 9. After the battle

The Result panel uses the shared modal shell, tinted for victory or defeat, with an EXP progress bar and one line per non-zero reward (record, Card Fragments, first-clear bonus, EXP). With nothing earned it says "No reward this time." Every value comes from the server's reward plan. Continue closes the Battle UI. The server then moves the character beside the chair.

```text
┌────────────────────────────┐
│         YOU WON!           │
│   Record: 12W / 7L         │
│   +3 Card Fragments        │
│   +45 EXP   [=====---] Lv12│
│        [Continue]          │
└────────────────────────────┘
```

## 10. UI infrastructure

**Not built** as a whole: decided 2026-10-29 from [research/ANTVERSE_UI_INFRASTRUCTURE.md](research/ANTVERSE_UI_INFRASTRUCTURE.md). The code side (kit runtime, controllers, versioning) is in [ARCHITECTURE §12](ARCHITECTURE.md).

### 10.1 Layers

One ScreenGui per job, not one per screen:

| Layer | Insets | Holds |
|---|---|---|
| HUD | `DeviceSafeInsets` | world icons, currency bar, quest arrow and marks |
| Panels | `CoreUISafeInsets` | Card Library, Vending Machine, Card Vendor, Item Mall, Matchmaking, Profile, Settings |
| Popups | `CoreUISafeInsets` | dialogue box, confirm popups, the toast |

- Popups sit above Panels, Panels above HUD. The full-viewport backdrop (§2.6) is its own authored ScreenGui directly under Panels.
- **Built 2026-10-29** by `scripts/studio/layers-v1.luau`:
  - `PanelBackdrop`: DisplayOrder 19, no insets, off until a panel opens, holding `Kit.Backdrop`.
  - `Panels`: DisplayOrder 20.
  - `Popups`: DisplayOrder 30.
  - Panels and Popups each hold an `AutoScale` `Root` frame with a `UIScale`.
- **Not built:** the HUD layer. Today's `Hud` ScreenGui stays until its own plan. Today's panels sit at DisplayOrder 10–13, under the new layers.
- **Only one panel is open at a time.** Opening a panel closes the open one. A panel busy with a purchase or reveal refuses to close, and the new one then does not open. Gamepad B goes back a page, then closes the panel from its root page. Escape cannot do this: Roblox opens its own menu on Escape and the game never sees the key (tested 2026-10-29). A keyboard Back key is open (§11).
- **Built 2026-10-29:** `PanelCoordinator` covers all six world panels: Card Library, Vending Machine, Card Vendor, Item Mall, Profile and Matchmaking.
- **BattleUI, PackOpenUI and MulliganUI stay their own ScreenGuis**, because of the battle's insets and clipping (§5.1) and their DisplayOrder above everything else. They do not join the panel rule.

### 10.2 Size and layout

**Scale decides size; mode decides layout.**

- Every layer is authored on a **1280 × 720 reference canvas** and holds one `UIScale`. The scale is `clamp(min(height / refHeight, width / refWidth), 0.55, 1.5) × UI size`. The reference is 1280 × 720 for touch and 1777 × 1000 for a pointer, so desktop gets more room and smaller UI. The layer's root is sized `1 / scale`, so children see at least the reference canvas, minus insets. The width term keeps a 4:3 tablet at 0.8 instead of overflowing it. Starting values; they live in `UIScaleConfig`.
- **Panel room:** the Panels layer loses the Roblox top bar and the notch. On the smallest phone (640 × 360) that leaves about **1160 × 549** at the reference, so a panel is authored at most **1120 × 540**. `Kit.PanelFrame` starts at 1040 × 540.
- **Authoring floors** at the reference: every tap target is at least 80 px and body text at least 26 px. On a phone these come out at about 44 pt and 14 pt.
- A layer is either fully on the scale rule or not on it. No layer mixes scaled and raw-pixel children.
- **Mode** (desktop or mobile layout) is only for screens whose arrangement changes, today only the battle (§5.3). It comes from `PreferredInput` and screen size, never from the last input.
- Each layer publishes its applied scale and input mode as attributes for other code.
- **Built 2026-10-29:** scaling for Panels and Popups, and the `UXMode` rule. A `UISize` attribute on the player multiplies the scale; the Settings plan will set it.

### 10.3 Kit

One folder of authored, hidden templates (`ReplicatedStorage.Kit`) that every screen clones: primary and secondary buttons, icon button, panel frame, popup, toast, backdrop, currency pill, progress bar, tab, toggle, slider row, empty state and the card (§6). Colours, sizes and fonts are attributes on the folder (tokens), taken from today's `UITheme`. **Built 2026-10-29:** the panel frame, both buttons, the toast and the backdrop. The others are added by the plan that first needs them.

- **Panel frame:** title bar 96 px with an 80 px icon or Back slot on the left and an 80 px close button on the right, title text 40 px, body inset 24 px.

- Templates keep the crystal-navy look of §2; only the mechanism comes from ant-verse.
- **Buttons:** a press lock ignores taps within 0.4 s of a state change, so a double tap on End Turn, Forfeit, Buy, Craft or Recycle cannot fire twice. A disabled button still takes taps and says why instead of doing nothing.
- **Icon buttons** have a fixed invisible hit area and a short pop on press. Outlines stay the layered dark copy of §2.4.
- **Progress bars** keep the fill's full rounded shape and hide the empty part with a gradient, so a nearly empty bar never squashes into a blob.
- A missing image upload shows a placeholder colour, never an empty hole.

### 10.4 Feedback

Every refusal and notice uses one toast template with an icon. Each server reason maps to one sentence in one table (`UIFeedback`), so the same refusal always reads the same way. The battle's red toast (§7) becomes this toast.

- **Built 2026-10-29** for the free-roam toast. One toast is on screen at a time, top centre of Popups, for 2.6 s before it fades. A refusal has a red rim. A code without an icon shows a tinted square.
- **Not built:** the battle's red toast (§7) still uses its own code until the battle plan.

### 10.5 Settings

A Settings panel in the Panels layer, opened from a HUD icon:

| Setting | Kind | Range | Default |
|---|---|---|---|
| Music volume | slider | 0–100% | 100% |
| SFX volume | slider | 0–100% | 100% |
| UI size | slider | 80–130%, 10% steps | 100% |
| Faster battle animations | toggle | on / off | off |

- Changes apply at once and revert if the server refuses them. They are saved in the profile.
- Faster battle animations shorten `BattleDirector` phase timings (§8) by one multiplier. It never skips a phase, so every card move stays visible. The multiplier is open (§11).
- Only settings that do something are offered. Graphics and master volume stay in Roblox's own menu.
- Ranges and defaults are starting values in `SettingsConfig`.

### 10.6 Dialogue

- **Speakers** have a name tag and a portrait, shown in the dialogue box beside the line.
- Conversations are written once in `DialogueConfig` by id, not inline in controllers. The server sends ids, never text.
- Conversations **queue**: a second one waits until the first closes.
- Each line is at most 96 characters so it fits the box.
- The typewriter, camera tween and focus mode (§3.7) stay. Option buttons are a kit template.

## 11. Open decisions

1. The faster-animation multiplier, and whether the turn banner and cast reveal shorten with it (§10.5).
2. Where the Settings icon sits among the HUD icons (§3.1, §10.5).
3. Music and SFX volume: the game has no music or sound effects yet (checked 2026-10-29), so under §10.5 these two settings wait until audio exists. Either add audio first, or ship Settings with UI size and faster animations only.
4. A keyboard key for Back. Escape belongs to the Roblox menu (§10.1), so the choice is Backspace or no key at all, since every panel already has Back and X buttons.
