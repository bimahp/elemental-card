# Ant-Verse UI infrastructure: what elemental-card can reuse

**Status:** research, 2026-10-29. Fact-checked against the ant-verse repo (commit `54961ce`, tag `beta-1.1`) and the elemental-card Studio place (read only, plus one Play session). The owner answered §7 the same day; nothing is planned or built yet.

**Owns:** how ant-verse builds its UI (authoring, kit, layers, scaling, panels, dialogue, settings, feedback, checks), how elemental-card builds its UI today, and the comparison between them.
**Does not own:** elemental-card's UI design ([UI.md](../UI.md)) or its architecture ([ARCHITECTURE.md](../ARCHITECTURE.md)). Nothing here is a rule until the owner decides it and it moves into a doc of record.

---

## 1. Method

| Source | What was read |
|---|---|
| ant-verse docs | `docs/UI_UX_DIRECTION.md`, `docs/UI_REVAMP_PLAN.md`, `docs/MOBILE_UI_CHECK_2026-10-25.md`, `docs/MOBILE_UI_REFINE_PLAN.md` (outline) |
| ant-verse built contracts | `ant-verse/tools/ui/KIT.md`, `HUD.md`, `DIALOGUE.md` |
| ant-verse code | `UIKit`, `UIRefs`, `UIFeedback`, `PanelCoordinator`, `UIScaleController`, `Config/UIScale`, `Rules/UIScaleRules`, `Config/Settings`, `Rules/SettingsRules`, `SettingsService`, `SettingsController`, `DialogueController`, `Config/Dialogue`, `Rules/DialogueRules`, `MovementLockController`, the headers of `LayoutController`, `PromptController`, `HudController` and `Client.client.luau` |
| elemental-card Studio (Edit) | every ScreenGui's properties and descendant counts; a scan of every script for `Instance.new` of GUI classes; `UIComponents`, `UITheme`, `UXMode`, `DialogueController`, `HudController`; greps for panel, input, settings and movement-lock code |
| elemental-card Studio (Play) | the PlayerModule's location and API, `PreferredInput`, the startup console |

Where ant-verse's direction doc and its built contracts disagree, the built contract (`tools/ui/*.md` and the code) wins. §2.12 lists the disagreements that were found.

## 2. How ant-verse builds UI

### 2.1 Authoring pipeline

- Code lives in the repo (`ant-verse/src`) and is pushed to Studio with MCP `multi_edit`. Repo and Studio are compared by checksum (`tools/checksums.ps1`, `compare-checksums.ps1`).
- Every UI tree is made by an **idempotent migration script** in `tools/studio/*.luau` (302 files), run once in Studio. Examples: `ui-kit-v1`, `hud-revamp-v1`, `dialogue-v1`, `barracks-ui-v1` to `-v9`.
- After a migration, `tools/studio/export-ui.luau` exports the tree to `tools/ui/blueprint.json` (2.78 MB, one entry per root). This is how UI trees are versioned in git.
- Each UI area has a short **contract** doc in `tools/ui/` (`KIT.md`, `HUD.md`, `DIALOGUE.md` and 30 more): which instances exist, which controller fills them, and how it was verified.
- Controllers find authored instances with `UIRefs` (`layer`, `template`, `clone`) and `UIKit.clone`. They never build visual trees.

### 2.2 The kit

All shared templates live in one folder, `ReplicatedStorage.Assets.UI.Kit`.

- **Tokens** are attributes on the folder: colours (`Ink`, `Cream`, `Rust`, `Green`, `Red`, `Blue`, `Gold`, `Grey`, `Ivory`), numbers (`LipHeight 6`, `PressSink 4`, `SwapLockSeconds .4`, stroke widths, `BackdropTransparency .4`) and icon-button motion (`IconHoverScale 1.15`, `IconHoverRotation -8`).
- **Templates** are hidden children: `Button` and `ButtonSecondary` (a face over a darker lip), `IconButton`, `CurrencyPill`, `Card`, `StatRow`, `CostChip`, `CostLine`, `Toggle`, `Stepper`, `Segmented`, `Tab`, `PanelFrame`, `Popup`, `Toast`, `Backdrop`, `ScrollBar`, `BarRow`, `SliderRow`, plus game-specific cards.
- **`UIKit`** (378 lines) is the runtime half. It only switches states:

| Function | What it does |
|---|---|
| `setVariant` | primary, danger, toggle, premium, secondary or disabled colours |
| `setEnabled` | greys a button, but **a disabled button still takes taps**, so the caller can say why ("never a silent dead button") |
| `bindPress` | press feel (face sinks onto its lip) plus a **swap lock**: taps within 0.4 s of a state change are ignored, so a double-tap cannot undo the order it just gave |
| `bindBackdrop` | a tap on the dim closes the topmost overlay only; it asks `GetGuiObjectsAtPosition` what is on top instead of using a button |
| `closeOnTapOutside` | a card's pop-up buttons close on any tap elsewhere |
| `setIcon` | icon by art id through `Config.UIIcons`; a missing upload shows a placeholder colour, never an empty hole |
| `setIconButton`, `setIconOutline` | the naked icon button: eight Ink-tinted copies of the icon nudged outward make the outline (the same idea as elemental-card's layered-copy rule) |
| `setShare` | bar fills keep their full rounded shape and a `UIGradient` hides the part past the share, so a nearly empty bar never squashes into a blob |
| `compact` | `1240 → 1.2K` for tight spaces |

### 2.3 Layers

One ScreenGui per job, not one per panel:

| Layer | Insets | DisplayOrder | Holds |
|---|---|---|---|
| `AntVerseHUD` | `DeviceSafeInsets` | 5 | currencies, menu, thumb buttons, toast |
| `AntVersePanels` | `CoreUISafeInsets` | 20 | every full panel (Colony, Shop, Settings, Upgrade…) |
| `AntVersePopups` | `CoreUISafeInsets` | 30 | popups, dialogue box, toast over panels |
| `AntVersePrompts` | whole screen | 4 | custom proximity-prompt cards, above Roblox's TouchGui so the thumbstick does not steal their taps |

A legacy layer, `AntVerseUI`, was never fully migrated (§2.12).

### 2.4 Scaling and input

- Layouts are authored on a **1280 × 720 reference canvas**. A layer opts in with the attribute `AutoScale = true` and a `Root` frame holding a `UIScale`.
- `UIScaleController` sets `scale = clamp(shortSide / ref, 0.55, 1.5) × UISize`, where `ref` is 720 for touch and 1000 for a pointer. It sets `Root.Size = 1/scale`, so children always see about 1280 × 720.
- Two **authoring rules** make this hold on an iPhone 12 (short side 390, scale 0.55): every tap target is at least 80 px and body text at least 26 px at the reference. Those come out at 44 pt and 14 pt.
- A fixed-height panel gets a second `UIScale` (`PanelFit`) that shrinks it to fit under the Roblox top bar.
- Input comes from `UserInputService.PreferredInput` (touch first, then pointer), with a `TouchEnabled`/`MouseEnabled` fallback. Each layer publishes `AppliedScale` and `AppliedInput` attributes for other code.
- The rules are pure (`UIScaleRules`) and covered by `UIScaleRulesSpec`.

### 2.5 Panels

- **`PanelCoordinator`** (31 lines) owns which panel has focus. A panel registers `close` and `back` functions. `claim(id)` closes whatever was open, so only one panel is ever open. Escape or gamepad B calls `back`. 14 panels register with it.
- **Standard frame** (`Kit.PanelFrame`): a header with icon, title, resource chips and close; a left tab rail (landscape has width to spare, not height); content in the middle; a detail column on the right with the **primary action at the bottom right**, under the right thumb.
- **Rules from the direction doc:** one screen per topic, opened from many doors; at most panel → sub-sheet deep; sub-sheets slide in inside the same frame; the panel header shows the resources spent there; locked items name their requirement and offer "Show me".
- **Content patterns** are built once: cost chip (red when short, tapping says where to get it), toggle with ON/OFF words, slider plus steppers, segmented choice, empty state with one action, badge dot only for actionable states, confirm popup only for irreversible or costly actions.

### 2.6 Dialogue

Content, rules and display are three separate pieces:

| Piece | File | Job |
|---|---|---|
| Content | `Config/Dialogue` | `Speakers` (name and portrait), `Lines` (conversations by id), `Pools` (random NPC flavour lines) |
| Rules | `Rules/DialogueRules` | pure: turns an id (`"<id>"`, `"quest:<id>"`, `"cue:<id>"`, `"idle:<n>"`, `"pool:<pool>:<n>"`) into a speaker and texts; fills `{placeholders}` from game state |
| Display | `DialogueController` | fills the authored box (`AntVersePopups.Root.Dialogue`): portrait, name tag, line, "Tap to continue", one dot per line |

- **The server answers with ids, not text.** The same rules resolve them on both sides.
- Conversations **queue**: a second `play` waits its turn, and `waitClosed()` lets a quest wait for the box to close.
- While a dialogue shows, the screen is locked: a dim takes every tap (a tap advances), movement is held (§2.7), the camera holds, prompts turn off through a `DialogueLock` attribute, the keyboard is sunk (Space, Enter, E advance), and the server shields the player from enemies.
- Every text is at most 96 characters so it fits the box.
- A Studio-only `DebugDialogue` attribute plays, advances or closes a dialogue for testing; `debugInfo()` returns what the box shows.
- `DialogueSpec` tests the rules.

### 2.7 Movement lock

`MovementLockController` (67 lines) is the **only** code that stops the player. Callers hold or release a named reason (`"Dialogue"`, `"Work"`, `"Login"`). While any reason is held, a render step writes a zero move and no jump. No caller saves or restores `WalkSpeed`, so two locks can never restore each other's values.

### 2.8 Settings

Four small pieces:

| Piece | Job |
|---|---|
| `Config/Settings` | `Order`, and per key: `Kind` (`Step` or `Toggle`), `Default`, `Min`/`Max`/`Step`, `Label`, and the `LocalPlayer` attribute it is published on |
| `Rules/SettingsRules` | pure `coerce` (snap and clamp, or nil for a bad key or type), `step`, `sanitize`; `SettingsRulesSpec` |
| `SettingsService` | validates and saves into the profile; remote rate-limited 10 per 2 s; returns `BadArgs` or `NotLoaded` |
| `SettingsController` | binds one authored row per key; changes apply **at once** and are reverted if the server refuses; values are published as `LocalPlayer` attributes that other controllers watch (`UIScaleController` watches `UISize`) |

- Settings today: Ambient sound, Combat sound, UI size (80–130 %), Reduced effects, Damage numbers, Quest arrows, Camera shake. "Only options that do something today are offered."
- Saved as an additive profile field. ProfileStore's `Reconcile` fills it on old saves, so ant-verse needed no version bump.
- Roblox's own menu already covers graphics and master volume, so they are not repeated.

### 2.9 Feedback

- The server returns a **code** (`TooFar`, `CannotAfford`, `MaxLevel`…). `UIFeedback` maps every code to one sentence, in one table, and shows it in the kit toast.
- Every toast has an icon chosen by what it is about. The toast moves above the dialogue box while one shows.
- Announcements (world events) use the same toast through one `Announce` event.

### 2.10 HUD and buttons

- Top right: currency pills in the Roblox top-bar strip, then the menu as two rows of three icon buttons, with a show/hide arrow on phones.
- Icon buttons have a fixed invisible `Hit` area and a label overlapping the icon's bottom; hover tilts and grows the art, touch plays the same pop briefly.
- Proximity prompts use a custom card (`PromptController`) in their own layer.
- Right-thumb buttons are placed relative to Roblox's jump button, read at runtime.

### 2.11 Checks and tooling

| Tool | What it does |
|---|---|
| `touch-target-audit.luau` | lists every visible interactive element under 44 pt at phone scale |
| Phone-frame harness | a temporary Edit-mode ScreenGui clones the live layers into nine simulated devices (640 × 360 to iPad), applies the real scale and insets, and reads `AbsolutePosition`/`AbsoluteSize` to find overlaps and off-screen elements |
| Device table | the nine landscape devices most Roblox players use, with safe area, scale and virtual canvas (`MOBILE_UI_CHECK_2026-10-25.md`) |
| `debugInfo()` | every controller returns its state for MCP inspection |
| Studio debug attributes | `DebugDialogue`, `DebugQuests`…, only when `RunService:IsStudio()` |
| Specs | `UIScaleRulesSpec`, `SettingsRulesSpec`, `DialogueSpec`, `UIKitBarsSpec`, `FeedbackRulesSpec` |

### 2.12 What did not go well in ant-verse

These are mistakes to avoid copying.

- **A half-finished migration.** The legacy `AntVerseUI` layer still exists next to the kit layers. It is not scaled, so it needed `LayoutController` presets (`LayoutWide`/`Compact`/`Narrow`/`Stacked` as JSON attributes) plus a `legacyFit` correction just for the Forage block. Two layout systems now run side by side.
- **Baked tokens.** Tokens are attributes, but templates copy the colours when they are authored ("Templates authored before the change keep their baked colours"). Changing white text to ivory needed a script that recoloured 190 labels and a second script to patch the blueprint.
- **Many re-tunes.** `barracks-ui-v1` to `-v9`, `colony-panel-v1` to `-v5`, `icon-button-v2`, `-v3`. Each is a new migration and a new export.
- **Input traps found late, on phones:** a full-width transparent ScrollingFrame above the prompt layer ate the TAP key's touches; Roblox hides its jump button when jumping is off, which moved every thumb button while riding.
- **The direction doc drifted from the build.** It says backdrop taps close small popups only; the built kit closes every panel on a backdrop tap (owner, 2026-10-20). It says to hide touch controls while a panel is open (`GuiService.TouchControlsEnabled`); no code does this. It says verbs keep fixed radial slots; the owner replaced that with layout by count (2026-10-14).
- **The HANDOFF grew to 274 KB.** elemental-card's documentation rules already answer this.

## 3. How elemental-card builds UI today

Checked in Studio on 2026-10-29 ("Crystal Element Battle Cards", placeId 73986817887222).

### 3.1 ScreenGuis

`StarterGui.ScreenOrientation` is `LandscapeSensor`. There are 12 ScreenGuis, one per screen, holding **252 authored instances** in total:

| ScreenGui | Insets | DisplayOrder | Authored instances |
|---|---|---|---|
| `BattleUI` | Device | 0 | 60 |
| `Hud` | Device | 0 | 32 |
| `InventoryUI` | CoreUI | 10 | 61 |
| `DialogueUI` | Device | 0 | 9 |
| `QuestHUD` | Device | 0 | 4 |
| `PackOpenUI` | Device | 100 | 20 |
| `ItemMallUI` | CoreUI | 11 | 13 |
| `VendingMachineUI` | CoreUI | 12 | 13 |
| `MulliganUI` | Device | 60 | 15 |
| `MatchmakingUI` | CoreUI | 12 | 6 |
| `VendorUI` | CoreUI | 11 | 13 |
| `PlayerStatusUI` | CoreUI | 13 | 6 |

No ScreenGui has a `UIScale`, `UISizeConstraint`, `UIAspectRatioConstraint` or `UITextSizeConstraint`.

### 3.2 Most UI is built in code

Client scripts call `Instance.new` on GUI classes at about **364 places** (many inside loops). The largest:

| Script | GUI `Instance.new` | Lines |
|---|---|---|
| `BattleUI.BattleUIController` | 70 | 2,415 |
| `InventoryUI.InventoryController` | 58 | 520 |
| `BattleUI.Modules.CardVisuals` | 48 | 649 |
| `VendingMachineController` | 39 | 705 |
| `SharedUI.UIComponents` | 28 | 515 |
| `VendorUIController` | 17 | 318 |
| `PlayerStatusUIController` | 16 | 569 |

Authored ScreenGuis hold only shells (a `Scrim` and a `Dialog`). Cards, slots, rows, buttons, the modal chrome (corner, stroke, shadow, input blocker, texture, divider) and the full-screen backdrop ScreenGui are made at runtime.

**This contradicts the owner rule** in [CLAUDE.md](../../CLAUDE.md), [ARCHITECTURE §1](../ARCHITECTURE.md) and [UI.md](../UI.md) ("All UI is authored as real instances in Studio"). The docs describe the rule as if it is met.

### 3.3 Shared pieces that exist

- **`ReplicatedStorage.Modules.UITheme`**: colours, sizes, fonts and accents as a Lua table. Applied by code, so a change applies everywhere at once.
- **`StarterGui.SharedUI.UIComponents`**: `applyModalShell` (styles an authored dialog and adds the input blocker and texture), `createModalShell`, `createPrimaryButton`, `createCurrencyPill`, `createEmptyState`, `createProgressBar`, `bindFullscreenBackdrop` (the two-ScreenGui backdrop from [UI §2.6](../UI.md)), and the 0.44 s entrance tween.
- `createProgressBar` **resizes** its rounded fill, the shape ant-verse found squashes into a blob near empty (§2.2 `setShare`).

### 3.4 Mobile and input

- **`UXMode`** (battle only) says `Mobile` when the viewport is under 800 px wide **or the last input was not a mouse**.
- So on a PC, pressing any key, typing in chat or using a gamepad switches the battle to the mobile layout, and moving the mouse switches it back. Seen in Play: on a 2171 × 922 keyboard-and-mouse window the console printed `[UXMode] initial mode: Mobile`. [UI §5.3](../UI.md) describes the rule as "narrower than 800 px or input is Touch", which is not what the code does.
- `PreferredInput` exists in this Studio (`KeyboardAndMouse` in Play) and is not used.
- Other panels size by raw pixels and scale fractions; only `PlayerStatusUI`, `QuestHUD`, the pack reveal and the battle read `ViewportSize`.
- `TextScaled` is used in the battle, cards, targeting and the chair prompt.

### 3.5 Panels

- No coordinator. Each controller enables and disables its own ScreenGui.
- Escape is handled only by `TargetingSystem` (cancel a drag). No panel closes on Escape and nothing handles gamepad B or `SelectedObject`.

### 3.6 Dialogue

- **`DialogueController`** (300 lines) has features ant-verse lacks: a typewriter, a camera tween to the NPC, a focus mode (depth of field, colour grade, highlight on the NPC, other humanoids hidden, every prompt and the quest HUD off), and option buttons that return an action.
- **Content is not separated.** Lines are written inline in `TrainerInteraction`, `QuestHUDController` and `VendorUIController` as `{Segments = …, Options = …}`. There are no speaker names or portraits, no queue and no line-length limit.
- Option buttons are built in code in an older brown-and-gold Gotham style that does not match [UI §2](../UI.md).

### 3.7 Movement lock

Three places stop the player, each its own way:

| Script | Lock | Release |
|---|---|---|
| `DialogueController` | saves `WalkSpeed`, `JumpPower`, `JumpHeight`, jump state; sets them to 0 | restores the saved values |
| `ChairInteraction` | `WalkSpeed = 0`, `JumpPower = 0` | hard-codes `16` and `50` |
| `BattleUIController` | `ControlModule:Disable()` | `16` and `50` again, plus `Enable()` |

A hard-coded restore overwrites whatever another lock saved. **Correction (2026-10-29):** `ChairInteraction` is disabled; the live third lock is the server's `TableManager` (0 while seated, restores 16 / 50 / 7.2). A fourth, `PackRevealController` (ControlModule, `ContextActionService` sink, jump), was found while building PLAN_UI_FOUNDATIONS step 6. `ControlModule:Disable` does exist in this place's PlayerModule (checked in Play; ant-verse's note that Roblox removed it does not apply here).

### 3.8 Settings and feedback

- **No settings** of any kind: no panel, no saved preferences, no volume or UI-size control.
- **No shared feedback.** `BattleUIController` has its own `showWarningToast`; `InventoryController` has one toast. There is no code-to-message table.
- The HUD (`TopRightAnchor`) has four authored image buttons (Inventory, Item Mall, Matchmaking, Profile) with a floating label each, and turns off Roblox's player list.

## 4. Comparison and what to bring

**Adopt** = take the pattern as it is. **Adapt** = take the idea, change the shape. **Skip** = does not fit or is not worth it now.

| # | Ant-verse piece | elemental-card today | Verdict | Why |
|---|---|---|---|---|
| 1 | One kit folder of authored templates + a `UIKit` that only switches states | `UIComponents` builds widgets in code | **Adopt** | It is the only way to meet the editor-first rule. Highest value: **a card template** replacing `CardVisuals`' 48 constructors, since the same card shows in hand, board, deck, previews, Library, Vendor, packs and Mulligan |
| 2 | Migration scripts + `blueprint.json` export + checksums | Code only in Studio; no UI history | **Adapt** | elemental-card has no repo code, so a 2.8 MB UI blueprint would be the only exported tree. Keep migration scripts in the repo (`scripts/studio/`) and export only the kit and changed roots. Needs an owner decision |
| 3 | Four layers by job (HUD, Panels, Popups, Prompts) | 12 ScreenGuis, one per screen | **Adapt** | One Panels layer makes the coordinator and scaling simple. `BattleUI` stays its own layer: its rotated hand fan and `ClipToDeviceSafeArea` off ([UI §5.1](../UI.md)) are special |
| 4 | 1280 × 720 canvas + one `UIScale` per layer + 80 px / 26 px authoring floors | Raw pixels, no `UIScale`, `TextScaled` | **Adopt, per layer, completely** | Do not repeat ant-verse's half-migration (§2.12): a layer is either on the scale rule or not |
| 5 | `PreferredInput` input detection | `UXMode` keys on last input | **Adopt** | Fixes the PC-flips-to-mobile fault in §3.4 |
| 6 | `PanelCoordinator` (one panel, Escape/B = back) | none | **Adopt** | 31 lines, no visual change |
| 7 | `bindBackdrop` via `GetGuiObjectsAtPosition` | two-ScreenGui backdrop, built in code | **Adapt** | elemental-card's two-gui rule works; author the backdrop instead of creating it. Switch to hit-testing only if a click-through bug appears |
| 8 | Swap lock + disabled buttons still explain | none | **Adopt** | End Turn, Forfeit, Buy, Craft and Recycle are all double-tap risks |
| 9 | Dialogue split: `Config/Dialogue` + pure `DialogueRules` + server sends ids; speakers with portrait; queue | inline lines in three controllers | **Adopt the split, keep elemental's display** | Keep the typewriter, camera and focus mode. Add speakers, ids, a queue and a template for option buttons |
| 10 | `MovementLockController` by reasons | three conflicting locks | **Adopt** | Removes the hard-coded 16/50 restores |
| 11 | Settings: config + pure rules + service + optimistic controller, published as attributes | none | **Adopt the stack** | Which settings is a design call (§6). The plumbing is small and tested |
| 12 | `UIFeedback` code-to-message table + one toast template | ad-hoc toasts | **Adopt** | One table keeps every refusal worded the same way; how each server path reports its reasons today was not checked |
| 13 | `setShare` gradient bars | resized fill | **Adopt** when the EXP or loading bar is next touched | Small |
| 14 | Touch audit, phone-frame harness, device table | spot checks only ([HANDOFF §3](../HANDOFF.md)) | **Adopt** | Read-only, cheap, and the only way to check layout numbers in [UI.md](../UI.md) |
| 15 | `debugInfo()` + Studio debug attributes | console prints | **Adopt** | Fits the MCP VM limit (execute_luau cannot read live client module state) |
| 16 | Standard frame: left rail, content, detail, primary bottom-right | Card Library page stack | **Adapt** | The rail suits the Card Library (My Cards, Decks, Recycle); the page stack can stay inside it. Design decision |
| 17 | Naked icon button (eight outline copies, fixed hit area, pop) | image buttons + floating label | **Adapt** | The outline method matches elemental's own rule; the fixed `Hit` area and pop are worth taking |
| 18 | Custom prompt cards in their own layer | Roblox prompts | **Skip for now** | Only worth it if prompts get missed on phones |
| 19 | Thumb arc, HUD collapse arrow, two-row menu | battle has no thumbstick; four HUD icons | **Skip** | Solves ant-verse problems elemental-card does not have yet |
| 20 | Cream/ink/rust palette, ant-trail pattern, ivory text | crystal navy direction ([UI §2](../UI.md)) | **Skip** | Visual identity stays elemental-card's own; only the token mechanism is reused |

## 5. Critique

- **The real gap is not a missing feature.** elemental-card already breaks its own editor-first rule in most of its UI, and its docs say otherwise. Before porting anything, decide whether the rule is real. If it is, the migration is large: the battle alone is 2,415 + 649 lines that construct UI.
- **Do it by layer, not by widget.** Ant-verse's worst UI debt came from adding a new system beside an old one (§2.12). Converting one screen fully (kit, scale, coordinator, feedback) beats converting one widget everywhere.
- **Templates lose live theming.** `UITheme` applied by code updates every panel at once. Authored templates bake colours. Either keep `UIKit.setVariant`-style code that repaints from tokens on every state change, or accept recolour migrations like ant-verse's ivory pass.
- **Battle is the hardest and the most valuable.** Cards are cloned dozens of times per match and their layout rules are already precise ([UI §6](../UI.md)), which makes them ideal for a template. But the hand fan, lunges and `UIScale` punches in `BattleUIController` depend on the current runtime structure. Converting it needs its own plan and a full battle replay test.
- **Ant-verse's direction doc is not a reliable source on its own.** Use the `tools/ui/*.md` contracts and the code (§2.12).

## 6. Not verified

- Ant-verse on a real phone (its own docs say the same).
- How many instances elemental-card's code creates at runtime. §3.2 counts call sites, not instances.
- Whether elemental-card's panels block world input while open (proximity prompts, movement). Not tested.
- Whether a mid-battle `UXMode` flip on PC actually breaks the layout. The flip itself is shown by the code and the startup log; its effect was not played through.

## 7. Owner decisions

All seven questions were answered on 2026-10-29. The decisions are recorded in [AGENTS.md](../../AGENTS.md) ("UI/UX infrastructure from ant-verse"). In short: migrate everything to authored templates (battle last); scale for size, mode for layout; HUD, Panels and Popups layers with one coordinator; migration scripts plus a UI export in this repo; Music and SFX volume, UI size and faster battle animations as settings, shipped with a profile wipe; speakers and dialogue ids, keeping elemental-card's display; foundations first, then one small panel end to end.

The design of record is now [UI §10](../UI.md) and [ARCHITECTURE §12](../ARCHITECTURE.md), marked **Not built**. This doc stays outside reference.
