# Migration record

What the live machine looked like before this repository existed, and what
changed when it was pointed at it.

## Rollback

A snapshot of every file this migration could touch was taken first:

    ~/.local/state/caelestia-mod-backup/20260917-060123/     333 files, 12 MB
        manifest.tsv    original path, backup path, sha256, owner, group, mode, size

Separately, `cm_backup` keeps the first version of anything this project
replaces, once, under `~/.local/state/caelestia-mod/replaced/`, mirroring the
original path. Neither is deleted by any script here.

## What moved out of dots-managed files

`installer/unpatch_dots.sh` restored four files to their dots content and
removed two, but only after checking the replacement was in place first: it
refuses to run if `hypr-vars.lua` or `hypr-user.lua` is missing, or if
`config.fish` does not source `user-config.fish`.

| File | Before | After |
| --- | --- | --- |
| `hypr/variables.lua` | 7 values edited | pristine dots; values in `hypr-vars.lua` |
| `hypr/hyprland.lua` | `require("hyprland.cursor")` added | pristine dots |
| `hypr/hyprland/keybinds.lua` | OCR `create_bind` added | pristine dots |
| `fish/config.fish` | mise + PATH added | pristine dots |
| `hypr/hyprland/cursor.lua` | new file in a managed directory | removed; `hl.config` in `hypr-user.lua` |
| `hypr/hypr-user.lua` | duplicate that upstream discarded | removed |
| `foot/foot.ini` | 2 values edited | still edited, now by `apply_overlay.py` |
| `starship.toml` | 1 value edited | still edited, now by `apply_overlay.py` |

## Validation

Every affected subsystem was checked before and after. See the Phase 2 report
for the full table; the summary is that Hyprland reports the same effective
values through the override points that it previously got from direct edits,
`hyprctl configerrors` is empty, the bind count is unchanged at 143 with the
OCR bind present exactly once, and a scheme change propagates through all five
adapters.

## Three customizations that were dropped

Each was verified to have no effect before removal.

- **`~/.config/hypr/hypr-user.lua`** returned a table. Upstream calls
  `require("hypr-user")` for side effects and discards the return value, and
  loads it after the keybind module. It never did anything; the same two values
  in `hypr-vars.lua`, which upstream does merge, were doing the work.
- **`blurSpecialWs = true`** in `variables.lua` was overridden by
  `blurSpecialWs = false` in `hypr-vars.lua`, which merges after. Confirmed
  live: `hyprctl getoption decoration:blur:special` returned `false` both before
  and after.
- **`kbOcrClipboard`, `kbRegionSearch`, `kbCircleSearch`** were defined in
  `variables.lua` and referenced nowhere. The shell implements all three
  actions; no key reached them. They are not carried into `hypr-vars.lua`.

The last one is a **gap, not just dead weight**: circle-to-search and region
search work but have no keybind. Adding them is three `hl.bind` lines in
`overrides/caelestia/hypr-user.lua` against `picker circleSearch`,
`picker open` with search mode, and `picker openOcrClipboard`. It was left
undone deliberately, because choosing three keybindings is a preference, not a
migration.
