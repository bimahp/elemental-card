# Scripts

Tooling for keeping `src/` and the Studio place in step ([ARCHITECTURE §1](../docs/ARCHITECTURE.md)). UI export and checks are in [studio/README.md](studio/README.md).

Every `.luau` file under `studio/` runs in Studio **Edit mode** through the MCP's `execute_luau`: send `local ARGS = { … }` (when the script takes arguments) as the first line, then the file's text unchanged. Confirm first that `list_roblox_studios` shows "Crystal Element Battle Cards" (placeId 73986817887222).

| File | Runs in | What it does |
|---|---|---|
| `studio/pull-sources.luau` | Studio | returns one chunk of every owned script's source |
| `pull-sources.ps1` | PowerShell | writes the saved chunks into `src/` |
| `studio/studio-checksums.luau` | Studio | one checksum line per owned script |
| `checksums.ps1` | PowerShell | the same lines for `src/`; with `-StudioFile`, the comparison |

**Owned scripts** are every `LuaSourceContainer` under ReplicatedFirst, ReplicatedStorage, ServerScriptService, ServerStorage, StarterGui, StarterPlayer and TestService. Workspace holds only free-model leftovers and is not mirrored.

**Line format:** `<Studio path> <class> <enabled> <bytes> <fnv1a32>`, the same on both sides.

## Before changing code

Check that Studio still matches the repo:

1. Run `studio/studio-checksums.luau`. Its result is padded, so the MCP saves it to a file.
2. Run:

   ```bash
   powershell -NoProfile -ExecutionPolicy Bypass -File scripts/checksums.ps1 -StudioFile "<saved result file>"
   ```

3. `differences: 0` means Studio matches the repo. Any `DIFF` or `Studio only` line is an edit made in Studio. Pull it back first, then commit it before making your own change.

## Changing code

1. Edit the file in `src/`.
2. Apply the same change in Studio. Use `multi_edit` for an edit, or set `Source` to the whole file through `execute_luau` (a `[==[ … ]==]` string) for a new script or a full replacement. A new script is created at the matching path with its class and enabled state.
3. Run the checksum comparison again; it must say `differences: 0`.
4. Remind the owner to save the place.

`multi_edit` with `replace_all` can silently apply only some of its replacements ([ARCHITECTURE §10](../docs/ARCHITECTURE.md)). The checksum is the check that catches this.

## Pulling from Studio

1. Run `studio/pull-sources.luau` with `ARGS = { chunk = 1 }`. The first line of the result reads `#chunk <from> <to> <total> scripts=<n> chunks=<k>`.
2. Pull chunks 2 to k. Each chunk works out its own boundaries, so the calls can run in parallel.
3. Write the chunks into `src/`, passing the saved files in chunk order:

   ```bash
   powershell -NoProfile -ExecutionPolicy Bypass -File scripts/pull-sources.ps1 <chunk 1 file> <chunk 2 file> ...
   ```

   It checks every chunk's byte count, writes the scripts with exact bytes, and lists any `src/` file that Studio no longer has. It never deletes one.
4. Run the checksum comparison.

On 2026-10-29 the first pull wrote 86 scripts (812,451 bytes in 10 chunks), and the comparison said `differences: 0`.
