# PLAN_UI_FOUNDATIONS — UI groundwork and the first panel

**Status:** Steps 1–7 done on 2026-10-29; steps 8–9 not started.

Builds the foundations of [UI §10](../UI.md) and [ARCHITECTURE §12](../ARCHITECTURE.md), then converts the Matchmaking panel end to end to prove the method. The design is in those docs; this plan records only how it is built and checked.

---

## 1. Scope

**In:**

- The repo pipeline: migration scripts, the UI export, and the UI checks.
- The kit folder and the `UIKit` runtime, with only the templates this plan uses.
- The Panels, backdrop and Popups layers.
- `UIScaleController` and the `UXMode` input fix.
- `PanelCoordinator`, with thin adapters for the panels that are not converted yet.
- `MovementLock`.
- `UIFeedback` with the toast.
- The Matchmaking panel.

**Out**, each in its own later plan:

- **Settings:** the panel, `SetSetting`, and schema v6.0 with the wipe.
- **Dialogue config:** speakers, ids, the queue and `PlayDialogue`.
- **The HUD layer:** the HUD stays as it is here and does not get scaled.
- **Every other panel, then the battle.**

This plan writes nothing to saves, so nobody's profile is wiped by it.

## 2. Facts checked in Studio

Checked on 2026-10-29 in "Crystal Element Battle Cards" (placeId 73986817887222). Edit mode, read only.

| Fact | Effect on this plan |
|---|---|
| `MatchmakingUI` holds `Scrim`, `Dialog`, `Dialog.TitleBar`, `TitleBar.Title`, `TitleBar.CloseButton` and `Dialog.Body`. `MatchmakingController` is 189 lines and builds 2 labels in code: the level label and the elapsed time on the HUD icon. | This is the smallest panel. Only the two labels and the buttons need authoring. |
| Matchmaking refusals come only through `Notify`, as free text. The forfeit cooldown is one example. `MatchmakingUpdate` sends only `queued`, `cancelled` and `matched`. | `UIFeedback` needs reason codes on `Notify` (§4 step 7). |
| `BattleUIController` owns the `Notify` toast (`showNotify`), and `TableManager` also sends `Notify`. | The world toast lives inside the battle script today. It moves to `UIFeedback`. |
| `ChairInteraction` and `NpcSit` are disabled. The live movement locks are `DialogueController`, which saves and restores, `BattleUIController`, which uses `ControlModule` and restores 16/50, and the server `TableManager`, which sets 0 and restores 16 / 50 / 7.2. | `MovementLock` replaces the two client locks. `TableManager` restores the `StarterPlayer` defaults instead of fixed numbers. |
| Only `TargetingSystem` handles Escape. | Escape for panels is new. Battle panels are closed during a battle, so the two do not overlap. |
| `ReplicatedStorage.Kit` does not exist. | Created by `kit-v1`. |
| **The game has no audio.** There are no `SoundGroup`s and nothing in `SoundService`. The only `Sound`s are two in a free-model coffee building. No script creates or plays a sound. | The Music and SFX volume settings would control nothing ([UI §11](../UI.md)). This does not block this plan. |
| Battle animation timing is spread over 39 `TweenInfo.new` calls: 22 in `PhaseRegistry`, 15 in `BattleUIController`, 1 in `CardVisuals` and 1 in `PostBattleController`. There is no shared time scale. | "Faster battle animations" first needs one timing table. That belongs to the Settings plan or the battle plan, not here. |

## 3. Repo layout

```text
.gitattributes             LF for ui/*.json and scripts/studio/*.luau
scripts/studio/
  README.md                how to run scripts, export and check
  ui-json.luau             export / verify / import UI roots as JSON
  split-export.ps1         splits a saved export into ui/<Root>.json
  check-ui.luau            touch-target and phone-frame checks
  kit-v1.luau              Kit folder, tokens, first templates (step 2)
  layers-v1.luau           Panels, PanelBackdrop, Popups ScreenGuis (step 3)
  matchmaking-ui-v1.luau   Matchmaking panel in Panels; HUD elapsed label (step 8)
ui/
  one baseline JSON per StarterGui ScreenGui (12), then Kit, Panels, PanelBackdrop, Popups
```

- **Running a script:** send `local ARGS = {…}` and then the file's text through `execute_luau` in Edit mode ([scripts/studio/README.md](../../scripts/studio/README.md)). Each migration stamps a `Migration` attribute (`"kit-v1"`) on the root it builds and returns early if the stamp is already there. A rebuild deletes and recreates only its own root.
- **Export:** Luau cannot list an instance's properties, so `ui-json.luau` keeps a property list per class and writes only values that differ from a fresh instance. A class missing from the list fails the export loudly, so nothing is dropped without notice.
- Controllers and modules are written in `src/` and pushed into Studio, with checksums before and after ([ARCHITECTURE §1](../ARCHITECTURE.md)). New modules in steps 2–8 are new files in `src/`.

## 4. Steps

Each step ends with its own check. Steps run in this order because each one uses the step before it.

### Step 1 — Pipeline (done 2026-10-29)

Write `scripts/studio/README.md`, `ui-json.luau`, `split-export.ps1` and `check-ui.luau`. The plan first named separate export, touch and phone-frame scripts; they share one codec and one device harness, so they became one file each.

- **Touch-target check:** lists every visible `GuiButton` under 80 px at the reference size, which is 44 pt on a phone.
- **Phone-frame check:** clones the chosen layers into a temporary ScreenGui at each device size, applies that device's scale and insets, and reports any element that overlaps another or sits off screen.

| Device | Size (landscape) |
|---|---|
| Small phone | 640 × 360 |
| iPhone SE | 667 × 375 |
| iPhone 12/13 | 844 × 390 |
| iPhone Pro Max | 932 × 430 |
| Android mid | 800 × 360 |
| Tablet | 1024 × 768 |
| Desktop | 1280 × 720 and 1920 × 1080 |

**Check:** an export of today's `MatchmakingUI` round-trips. Rebuilding it from the JSON in a scratch folder gives the same tree. The scratch folder is deleted afterwards.

**Result:**
- **Round trip:** `verify` passed for all 12 StarterGui ScreenGuis (264 instances counting the roots, 14 of them scripts and skipped). Their baselines are in `ui/`; each file's size matches the size `verify` reported, and all 12 parse as JSON.
- **Edit mode:** layout, `UIScale`, `AbsoluteSize` and `TextFits` all compute, so `check-ui` reads real layout without Play.
- **Tool limits:** `execute_luau` truncates results near 100,000 characters, which found the need for chunked export. A large result is saved to a file, either as plain text or JSON-wrapped; `split-export.ps1` takes both.
- **Baseline check** over the six world panels and the HUD: 9 touch, 4 text, 2 overlap, 0 offscreen.
  - Four close buttons are 42 pt.
  - The three Card Library filter buttons are 28 pt tall.
  - Everything else comes from the Matchmaking and Profile shells, which code sizes at runtime ([README](../../scripts/studio/README.md)).
- **Not covered:** scripts up to about 16 KB of code were sent without trouble, but `execute_luau`'s limit on input size is still unknown.

### Step 2 — Kit (`kit-v1`, done 2026-10-29)

- Create `ReplicatedStorage.Kit` with the tokens copied from `UITheme` as attributes: colours, stroke widths, corner radius, fonts, `PressLockSeconds = 0.4` and `BackdropTransparency`.
- Templates, all hidden:
  - `PanelFrame` has a title bar, title, close button and body, plus the input blocker, texture and divider that `UIComponents.applyModalShell` adds in code today ([UI §2.1](../UI.md)).
  - `Button` and `ButtonSecondary`.
  - `Toast` has an icon and a label.
  - `Backdrop`.
- Write `ReplicatedStorage.Modules.UIKit` with:
  - `clone(name)`;
  - `setVariant(button, variant)`, which repaints from the tokens;
  - `setEnabled(button, on)`, where a disabled button still fires a "why" callback;
  - `bindPress(button, fn)`, with the 0.4 s lock.
- Other templates are added by the plan that first needs them.
- `UITheme` stays until its last user is converted.

**Check:**
- A headless spec in `TestService`, `UIKitSpec`, covers three things:
  - the press lock drops a second tap within 0.4 s;
  - a disabled button calls its why callback, not its action;
  - `setVariant` sets the token colours.
- Export `Kit`.

**Result:**
- **Kit:** `kit-v1` built `ReplicatedStorage.Kit` with 51 tokens and 5 templates. The tokens are 31 colours (all of `UITheme`'s; `Dust` is renamed `Epic`), 15 numbers, 4 fonts and the panel texture.
- **Spec:** `UIKitSpec` passes. It also asserts the authoring floors over every template: buttons at least 80 px, text at least 26 px.
- **Push:** `UIKit` and `UIKitSpec` are new files in `src/`, pushed with `execute_luau`. Checksums show 88 of 88 matching, the first verified repo-to-Studio push.
- **Export:** `verify` passed for the Kit (36 instances), which needed `UIShadow` and `InputSink` added to `ui-json.luau`. `ui/Kit.json` is written.
- **Scale correction found in the build:** a fit probe of `PanelFrame` on the eight devices showed two faults in the step 4 scale rule.
  - At 1040 × 600 the panel fit no phone. The Panels layer loses the top bar, which leaves only 549–587 px of reference height.
  - Scaling by the short side alone gave a 4:3 tablet only 960 reference px of width.
- **What changed:**
  - The template is now 1040 × 540.
  - The rule became `min(height / refHeight, width / refWidth)` with the reference 1280 × 720 for touch and 1777 × 1000 for pointer ([UI §10.2](../UI.md)).
  - `check-ui.luau` uses the same rule.
- **After the change:** the panel fits all eight devices, and its close button is at least 44 pt on every touch device.
- **Also changed:** `split-export.ps1` and the export now use an `#end` marker and padding, so even a small export is saved to a file.

### Step 3 — Layers (`layers-v1`, done 2026-10-29)

| ScreenGui | Insets | DisplayOrder | `AutoScale` |
|---|---|---|---|
| `PanelBackdrop` | None, `InputSink = All` | 19 | no (full screen) |
| `Panels` | `CoreUISafeInsets` | 20 | yes |
| `Popups` | `CoreUISafeInsets` | 30 | yes |

- Each scaled layer has a `Root` frame holding a `UIScale`.
- Today's panels sit at DisplayOrder 10–13, below `PanelBackdrop`. So they must never be open at the same time as a converted panel. The coordinator adapters in step 5 ensure this.
- `MulliganUI` (60) and `PackOpenUI` (100) stay above all three layers.
- **One toast:** the toast lives only in `Popups`, above everything except the battle, Mulligan and pack reveal. This replaces the earlier HUD/Popups split, and [UI §10.1](../UI.md) is updated to match.

**Check:**
- Export the three layers.
- The phone-frame check passes on the empty layers.

**Result:**
- **Build:** `layers-v1` built the three ScreenGuis as in the table. Reading them back confirmed insets, order, enabled state, `AutoScale` and children.
- **Stronger check than planned:** `check-ui` ran on all three layers with probes placed in them for the run: a `PanelFrame` holding a bottom-right `Button` in Panels, and a `Toast` in Popups. Across all eight devices it found 0 touch, 0 offscreen, 0 text and 0 overlap. This is also the first real use of the check's `AutoScale` path. The probes were removed in the same call.
- **Exports:** `ui/PanelBackdrop.json`, `ui/Panels.json` and `ui/Popups.json` are written.

### Step 4 — Scale and input (done 2026-10-29)

- `ReplicatedStorage.Modules.UIScaleRules` is pure. `scaleFor(width, height, input, uiSize)` returns `clamp(min(height / refHeight, width / refWidth), 0.55, 1.5) × uiSize`, with the reference 1280 × 720 for touch and 1777 × 1000 for pointer (corrected in step 2). The starting values live in `UIScaleConfig`.
- `UIScaleController` is a client script. On every viewport or input change it does four things:
  - it sets each `AutoScale` layer's `UIScale`;
  - it sizes `Root` at `1 / scale`;
  - it publishes the `AppliedScale` and `AppliedInput` attributes;
  - it reads `UISize` from a `LocalPlayer` attribute, which defaults to 1 until Settings ships.
- `UXMode` keeps its API and decides from `PreferredInput` and width < 800 only.

**Check:**
- `UIScaleRulesSpec` covers three cases: a phone at the floor, a desktop at 1, and the clamp at both ends.
- In Play on a PC, `UXMode` starts as Desktop and stays Desktop after key presses and chat.
- With the Studio device emulator set to a touch phone, it says Mobile.

**Result:**
- **New code:** `UIScaleConfig`, `UIScaleRules`, `UIScaleRulesSpec` and `UIScaleController` are new in `src/`, and `UXMode` was replaced whole. Checksums show 92 of 92 matching.
- **Spec:** `UIScaleRulesSpec` passes. It covers phone floor, Pro Max, 4:3 tablet, 720p, 1080p, the 4K ceiling, UI size, input fallbacks and layout.
- **Play, 2171 × 922 keyboard-and-mouse window:**
  - The log reads `[UXMode] initial mode: Desktop`; the research run logged `Mobile` here.
  - After W, Space, A, D and Shift, the last input is Keyboard and `BattleUI.Main` stays visible with `MobileRoot` hidden.
  - Panels and Popups report scale 0.922 (`min(922/1000, 2171/1777)`), `AppliedInput` pointer, and a `Root` of 2171 × 864 points.
  - Setting `UISize = 1.3` rescaled them live to 1.1986, and clearing it restored 0.922.
  - No errors or warnings.
- **Not covered:** the touch case in the Studio device emulator. The MCP cannot switch the emulator. `UIScaleRulesSpec` covers `PreferredInput.Touch → Mobile`, but a real Play run on an emulated phone is still to do.

### Step 5 — PanelCoordinator (done 2026-10-29)

- `PanelCoordinator` is a client module with `register(id, {close, back})`, `claim(id)`, `release(id)`, `back()` and `debugInfo()`.
- **Back input:** Escape and gamepad B go through `UserInputService`. Escape needs a Play test first, because Roblox may use Escape for its own menu and swallow it. If it is swallowed, gamepad B stays, Escape is dropped, and [UI §10.1](../UI.md) is updated.
- **Adapters:** the five panels that are not converted yet are `InventoryUI`, `VendingMachineUI`, `VendorUI`, `ItemMallUI` and `PlayerStatusUI`. Each gets a few lines in its controller: register on start, `claim` on open, `release` on close. So "one panel open" holds from now on, before those panels are converted.
- Battle states release every claim, the same way the HUD hides during battle today.

**Check:**
- A headless `PanelCoordinatorSpec`:
  - claiming B closes A;
  - `back` on a root page closes the panel;
  - a release by a panel that does not own the claim is ignored.
- In Play:
  - opening the Card Library while the Item Mall is open closes the Item Mall;
  - Escape or B closes the top panel.

**Result:**
- **Code:**
  - `PanelCoordinator` and `PanelCoordinatorSpec` are new.
  - All six world panels got adapters, Matchmaking included, so the rule holds before step 8 converts it.
  - The edits were pushed with `multi_edit`, without `replace_all`. Checksums show 94 of 94 matching.
  - The spec passes against a fresh module copy, which avoids the require cache. It covers claim, release by a panel without the claim, back through pages, back on root, refusal, `closeAll` and an unregistered claim.
- **Closing refused while busy:** the Vending Machine refuses to close while purchasing or revealing. Without that, a claim during a reveal would have left two panels open. UI §10.1 now says so.
- **Bug fixed:** Back on the Card Library's root page used to set `gui.Enabled = false` without `close()`. That left `isOpen` true, so the HUD button could not reopen the panel. Back now calls `close()`.
- **Play (real clicks and keys):**
  - Profile opened through its Studio test hook.
  - **Escape opened the Roblox menu, and Profile stayed open.** Escape was dropped as planned. UI §10.1 and AGENTS are updated, and the keyboard Back key is UI §11 item 4.
  - Gamepad B closed Profile.
  - A click on the HUD Card Library button opened it. Opening Profile then closed the Card Library.
  - B on the Card Library's root page closed it, and a click reopened it, which confirms the bug fix.
  - No errors.
- **Not covered:**
  - A real gamepad; B was simulated as a `KeyCode` through the MCP.
  - A world prompt opening one panel over another, for example the Vending Machine prompt while the Card Library is open.
  - While a panel's backdrop is up it catches HUD taps and closes that panel instead. HUD buttons therefore never open a second panel directly.
- **Seen once:** in 1 of 4 Play runs, `UXMode` logged `initial mode: Mobile` on the 2171 × 922 window, then corrected itself. The next three runs logged `Desktop`. `UXMode` now prints the viewport and input behind each decision so the next occurrence shows its cause (HANDOFF §4).

### Step 6 — MovementLock (done 2026-10-29)

- `MovementLock` is a client module with `hold(reason)`, `release(reason)`, `isHeld()` and `debugInfo()`.
- While any reason is held, it disables the `ControlModule` and turns jumping off. When the last reason is released, it turns them back on.
- It never writes `WalkSpeed` or `JumpPower`. `ControlModule:Disable` exists in this place's PlayerModule.
- Changes to callers:
  - `DialogueController` holds `"Dialogue"` and drops its save and restore.
  - `BattleUIController` holds `"Battle"` and drops `Enable()` and the 16/50 restore.
  - `TableManager` on the server keeps its seated lock, but restores the `StarterPlayer` defaults (`CharacterWalkSpeed`, `CharacterJumpPower`, `CharacterJumpHeight`) instead of fixed numbers.

**Check:**
- In Play: talk to the Noob, then leave the dialogue. The character moves at normal speed.
- Then run an NPC battle start and an exit. Movement comes back once and the speed is the default.
- Last, open a dialogue while another hold is active. Closing it does not free the player early.

**Result:**
- **A fourth lock:** `PackRevealController` had its own movement lock, which the research (§3.7) missed. It disabled the ControlModule, sank the movement actions and turned off jumping, and its `Enable()` on release could undo a battle lock. It now holds `"PackReveal"`, and its prompt suppression stays its own.
- **Code:**
  - `MovementLock` and `MovementLockSpec` are new.
  - `DialogueController`, `BattleUIController`, `PackRevealController` and `TableManager` were edited with `multi_edit`.
  - The client `WalkSpeed = 16, JumpPower = 50` after battle is removed. `TableManager.unlockMovement` reads the `StarterPlayer` defaults: 16, 50 and 7.2 in this place.
  - Checksums show 96 of 96 matching.
- **Spec:** `MovementLockSpec` passes. It covers first hold locks, extra and repeated holds, partial release, release of an unheld reason, unlock on the last release, relock, and a blank reason.
- **Play, dialogue:**
  - Talking to the Card Merchant opened the dialogue.
  - Holding W for 1.5 s moved the character **0.00 studs**. Jumping was off and `WalkSpeed` stayed 16, untouched.
  - After "Not right now." jumping came back and S moved the character 9.90 studs.
- **Play, seat:**
  - `[E] Sit` at table 8 seated the player. W and Space left them seated. `WalkSpeed` read 0 from the server lock, jumping was off, and prompts were hidden.
  - After **Leave Seat**, `WalkSpeed` read 16 and `JumpHeight` 7.2, from the `StarterPlayer` defaults. Jumping and prompts were back, and S moved 13.89 studs.
  - No errors.
- **Not covered:**
  - The NPC-battle start and exit. The Noob's `TalkPrompt` did not trigger in this session, either with E or with `InputHoldBegin`, although it was enabled, 5 studs away and prompts were on. That is unexplained and untouched by this step, so a manual Noob talk is worth one check.
  - The battle-end restore therefore goes untested. Seating covered the same `setBattleControlsLocked` calls and the server restore.
  - The overlapping-holds case is covered only by the spec.

### Step 7 — UIFeedback (done 2026-10-29)

- `ReplicatedStorage.Modules.UIFeedback` is one table from reason code to message, with an icon per code. `show(code, values)` clones `Kit.Toast` into `Popups`. A string that is not a code shows as it is, so old `Notify` text keeps working during the migration.
- `Notify` gains a code form: `Notify:FireClient(player, { code = "MatchmakingCooldown", values = { seconds = n } })`. `BattleController`'s cooldown message moves to this code. Other `Notify` senders keep plain text until their screen is converted.
- The `Notify` handler moves out of `BattleUIController` into `UIFeedback`. The battle's own red toast ([UI §7](../UI.md)) stays as it is until the battle plan.

**Check:**
- A headless `UIFeedbackSpec`:
  - every code has a message and an icon;
  - a plain string passes through;
  - missing values never error.
- In Play: queuing while on cooldown shows the coded toast.

**Result:**
- **Code:**
  - `UIFeedback`, `UIFeedbackController` and `UIFeedbackSpec` are new.
  - The plan said "other `Notify` senders keep plain text". There were only three senders, so all three use codes now: `BattleController`'s `MatchmakingCooldown` and `TableManager`'s `TablesBusy` and `SeatFailed`.
  - The `NotifyOverlay` ScreenGui and `showNotify` are gone from `BattleUIController`.
  - Pushed with `multi_edit`; checksums show 99 of 99 matching.
- **Spec:** `UIFeedbackSpec` passes. It covers every code having text and an existing icon with no values, value formatting (125 s reads "2m 5s"), a bad value, plain text, an unknown code and a non-string.
- **Play:** the test fired `Notify` from the server side to the real client.
  - `{ code = "MatchmakingCooldown", values = { seconds = 125 } }` showed the right sentence with `TextFits` true, the Matchmaking icon and the red rim (`CD4248`). The toast was 664 × 89 points at scale 0.922.
  - A plain string showed as it is, with the tinted placeholder icon (`354674`) and the normal rim.
  - Each toast left the screen on its own.
  - No errors.
- **Not covered:**
  - Real cooldown, busy and seat-failure situations; the server lines were only changed, not hit.
  - A delayed second send from the same server test call never arrived. The MCP probably ends the call's VM before its 1.5 s delay. The first send had already shown plain text works.

### Step 8 — Matchmaking panel (`matchmaking-ui-v1`)

- Build `Panels.Root.Matchmaking` from `Kit.PanelFrame`, authored at 1280 × 720:
  - a level label;
  - a status label;
  - `Find Opponent` as the primary `Button`;
  - `Cancel Matchmaking` as `ButtonSecondary`.
- Author the elapsed-time label on the HUD Matchmaking icon in `Hud`. It is not scaled; `Hud` changes only in the HUD plan.
- `MatchmakingController` clones nothing and builds nothing. It fills the labels, switches the buttons with `UIKit`, binds them with `bindPress`, and registers with `PanelCoordinator`. The backdrop shows while it is open.
- Delete the old `StarterGui.MatchmakingUI`. Remove the two `Instance.new` calls.

**Check:**
- In Play, run the whole flow: open from the HUD, Find Opponent, watch the elapsed timer tick, Cancel, close by X, by backdrop and by Escape or B.
- Then queue until an NPC fallback match starts. The panel closes and the battle starts.
- A double tap on Find never sends two joins. The server log shows one `JoinMatchmaking`.
- The touch-target check reports nothing under 80 px in `Panels`.
- The phone-frame check is clean on every device in step 1.
- `script_grep` finds no GUI `Instance.new` left in `MatchmakingController`.
- Export `Panels`, `PanelBackdrop` and `Hud`.

### Step 9 — Record

- [HANDOFF](../HANDOFF.md):
  - move "UI infrastructure" to partly built;
  - drop the `UXMode` and movement-lock known issues;
  - lower the editor-first count.
- In [UI §10](../UI.md) and [ARCHITECTURE §12](../ARCHITECTURE.md), remove **Not built** from the parts that now exist.
- Remind the owner to save the place.

## 5. Risks

- **`execute_luau` size limits** on long migration scripts are unknown. If a script is too long, split it into numbered parts (`kit-v1a`, `kit-v1b`) that each stamp their own step.
- **Baked colours.** Templates copy token colours when they are authored. A later token change needs a recolour migration. `setVariant` covers only state colours ([ARCHITECTURE §12.2](../ARCHITECTURE.md)).
- **Mixed layers during the migration.** Old panels are unscaled and new ones are scaled. The coordinator stops them overlapping, but they will look different sizes on phones until each is converted. This is expected and temporary.
- **Escape** may be taken by Roblox (step 5).

## 6. Following plans

In order:

1. **Settings:** UI size, plus the open audio and animation-speed questions ([UI §11](../UI.md)), shipping schema v6.0 with the wipe.
2. **Dialogue config.**
3. **One plan per screen:** Profile, Item Mall, Card Vendor, Vending Machine, Card Library, then the HUD layer.
4. **The battle**, with the card template, last.
