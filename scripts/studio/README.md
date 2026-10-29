# Studio UI scripts

Repo tooling for the editor-first UI pipeline ([ARCHITECTURE §12.1](../../docs/ARCHITECTURE.md)). These scripts author, export and check UI in Studio. Game code lives in `src/`; pulling it and comparing checksums is in [../README.md](../README.md). They run in **Edit mode** only, through the Roblox Studio MCP.

Authoring scripts here may call `Instance.new` for GUI: they are the editor that builds the authored instances. Game code never does ([ARCHITECTURE §1](../../docs/ARCHITECTURE.md)).

## Running a script

1. Confirm the right place is connected: `list_roblox_studios` must show "Crystal Element Battle Cards" (placeId 73986817887222).
2. Send `local ARGS = { … }` as the first line, then the file's text unchanged, through `execute_luau` with `datamodel_type = "Edit"`.
3. Remind the owner to save the place after any script that changes it.

`execute_luau` cuts a result off near 100,000 characters. A result too large to show inline is saved to a file under the session's `tool-results/` folder, either as plain text or as a JSON array of `{type, text}` blocks.

## Files

| File | What it does | Changes the place |
|---|---|---|
| `ui-json.luau` | `export`, `verify` and `import` of UI roots as deterministic JSON | `import` only |
| `split-export.ps1` | splits a saved export into `ui/<Root>.json` | no |
| `check-ui.luau` | touch-target and phone-frame checks | no |
| `kit-v1.luau` | builds `ReplicatedStorage.Kit` (tokens and templates); `rebuild = true` replaces a kit-v1 Kit | yes |
| `layers-v1.luau` | builds the `PanelBackdrop`, `Panels` and `Popups` ScreenGuis (needs kit-v1) | yes |
| `matchmaking-ui-v1.luau` | builds `Panels.Root.Matchmaking` from the kit and deletes `StarterGui.MatchmakingUI` | yes |
| `<area>-v<n>.luau` | migrations, one per UI change | yes |

## ui-json.luau

```lua
local ARGS = { mode = "verify", roots = { "StarterGui.MatchmakingUI" } }
local ARGS = { mode = "export", roots = { "StarterGui.MatchmakingUI", "StarterGui.Hud" } }
local ARGS = { mode = "import", json = [==[ …one export… ]==], parent = "ServerStorage", name = "Restored" }
```

- **export** writes each root as `=== <root path>` followed by its JSON. Only properties that differ from a fresh `Instance.new(class)` are written; keys are sorted, so the same tree always gives the same file. Scripts inside a root are listed as `"skipped": "code"`, never exported.
- **verify** exports a root, rebuilds it in `ServerStorage._UIJsonVerify`, exports the rebuild and compares the two. `OK` means the export holds everything the rebuild needs. It cannot see a property that is missing from the class lists: such a property is lost on both sides. Add it to `PROPS` when a root uses it.
- **import** rebuilds one exported root under `parent`. It does not restore scripts.
- **A class missing from `PROPS` fails the export** and names the instance, so nothing is dropped without notice.
- An export over 90,000 bytes comes back in chunks: the first line is `#chunk <from> <to> <total>`. Rerun with `offset = <to> + 1` until `<to>` equals `<total>`, and join the chunks without their `#chunk` lines.

Saving an export into `ui/`:

```bash
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/studio/split-export.ps1 "<saved result file>"
```

Add `-Only VendorUI,Hud` to write some roots only. An export ends with an `#end` line and padding, so even a small one is saved to a file. The splitter refuses a file without `#end` (truncated) or a single chunk.

**When to export:** after every migration, export each root it changed and commit the JSON with the script.

## check-ui.luau

```lua
local ARGS = {
	roots = { "StarterGui.MatchmakingUI" },
	show = { "StarterGui.MatchmakingUI.Dialog" }, -- force closed panels visible in the copy
	checks = { "touch", "frames" },               -- default: both
	devices = { "iPhone 12/13" },                  -- default: all eight
}
```

It copies each root into a temporary ScreenGui per device, applies the device's safe insets (and the layer's `UIScale` when the root has `AutoScale`), lets layout run, and reports:

| Finding | Meaning |
|---|---|
| `touch` | a button under 44 pt on a touch device (80 px at the 1280 × 720 reference) |
| `offscreen` | an element outside its layer's safe area (not checked inside scrolling frames or rotated elements) |
| `text` | non-scaled text that does not fit its box (`TextFits = false`) |
| `overlap` | two drawn things cross: text by where its glyphs sit, others by their box. A textless element that fully contains the other counts as its background |

- An element meant to overlap or leave the screen opts out with the attribute `CheckOverlapOK` or `CheckOffscreenOK`.
- The check reads the **authored** layout. Sizes that code sets at runtime show as `0x0`.
- Device sizes are in points. The safe insets and the 58 pt top bar are approximate.

Baseline on 2026-10-29, before any migration, over the six world panels and the HUD: 9 touch, 4 text, 2 overlap, 0 offscreen.
- **touch:**
  - the Card Library, Vending Machine, Card Vendor and Item Mall close buttons are 42 × 42;
  - the three Card Library filter buttons are 28 tall;
  - the Matchmaking and Profile close buttons are 0 × 0, because code sizes them.
- **text and overlap:** all six come from the Matchmaking and Profile title bars, also sized by code.
