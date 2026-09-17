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

## Superseded helpers removed from `~/.local/bin`

Five scripts predating this repository were replaced by adapters and the
orchestration hook. Before removing them, every plausible caller was checked:
this repository, `~/.config/caelestia`, `~/.config/hypr`, `~/.config/fish`,
`~/.config/quickshell`, user systemd units, the rest of `~/.local/bin`, and
running process command lines. The only references found were from
`caelestia-post-hook` to its own siblings, and it was removed too.

| Removed | Replaced by |
| --- | --- |
| `caelestia-post-hook` | `orchestration/hooks/post-theme` |
| `caelestia-theme-sync` | `adapters/kde/apply` |
| `caelestia-edge-theme` | `adapters/edge/apply` |
| `caelestia-sddm-sync` | `system/sddm/sync` |
| `caelestia-ocr-screenshot` | nothing; it wrapped `capture.sh`, which the in-shell picker path superseded |

All five remain in the rollback snapshot, byte-identical. A theme change was run
afterwards and all five adapters still reported `ok`.

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

The last one was a **gap, not just dead weight**: circle-to-search and region
search worked but no key reached them. That is now closed. Both are bound in
`overrides/caelestia/hypr-user.lua`, with the keys configurable through
`hypr-vars.lua`:

| Action | Key | Note |
| --- | --- | --- |
| OCR capture | `SUPER + SHIFT + T` | unchanged |
| Region search | `SUPER + SHIFT + A` | the originally intended key, free |
| Circle search | `SUPER + SHIFT + O` | **not** the originally intended `SUPER + SHIFT + C`, which is upstream's `kbColorPicker` |

`hypr-user.lua` checks each key against every `vars.kb*` upstream already binds
and skips its own binding, with a message, rather than shadowing one. Making
these reachable immediately exposed a latent bug in the picker overlay: the
search-mode label used `Tokens` in a file that never imported `Caelestia.Config`,
so it had been throwing `ReferenceError` on every invocation that nobody could
reach. Fixed in `shell/patches/0002`.
