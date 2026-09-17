# Migrating an existing setup

This project grew out of a Caelestia install that had been customised by hand:
values edited directly into the files the Caelestia dots deploy, helper scripts
dropped into `~/.local/bin`, and a shell fork that was not under version
control. This is the record of moving that onto supported mechanisms.

It is worth reading if you are in the same position, because the interesting
part is not *what* moved but *why each edit did not need to be an edit*. If you
are starting from a clean Caelestia install, you can skip it.

## Rollback

`cm_backup` keeps the first version of anything this project replaces, once,
under `~/.local/state/caelestia-mod/replaced/`, mirroring the original path.
`~/.local/state/caelestia-mod/owned.list` records what was created. Nothing in
this repository deletes either.

Before a migration of this kind, take a full snapshot as well - every file the
change could touch, with a manifest recording each original path, its hash,
owner and mode. That is a one-off step, not something `./install` does.

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

## Helper scripts became adapters

The pre-existing setup drove its theming from five loose scripts in
`~/.local/bin`. Each one corresponds to a component here, which is a reasonable
map of where that kind of logic belongs:

| Was a loose script | Is now |
| --- | --- |
| a monolithic `postHook` | `orchestration/hooks/post-theme`, which only dispatches |
| KDE / Qt / GTK colour and font sync | `adapters/kde/apply` |
| Edge policy writer | `adapters/edge/apply` |
| SDDM theme sync | `system/sddm/sync`, because it writes outside `$HOME` |
| an OCR screenshot wrapper | nothing; the in-shell picker path superseded it |

Before deleting any of them, every plausible caller was checked: the repository,
the Caelestia, Hyprland, fish and quickshell configs, user systemd units, the
rest of `~/.local/bin`, and running process command lines. A theme change was
run afterwards and all five adapters still reported `ok`.

## Validation

Every affected subsystem was checked before and after the switch. In summary:
Hyprland reported the same effective values through the override points that it
had previously got from direct edits, `hyprctl configerrors` stayed empty, the
keybind count was unchanged apart from the bindings deliberately added below,
with no duplicates across repeated reloads, and a scheme change propagated
through every adapter.

## Three customizations that turned out to do nothing

Each was verified to have no effect before it was touched. Two were deleted; the
third turned out to be a missing feature rather than dead weight.

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
  actions; no key reached any of them.

That third one was a **gap, not dead weight**: region search and circle search
worked but were unreachable. So rather than being dropped, two of those three
were adopted. `kbRegionSearch` and `kbCircleSearch` now live in
`overrides/caelestia/hypr-vars.lua` and are bound in `hypr-user.lua`;
`kbOcrClipboard` was the only one left unbound: it would have driven a one-step
"OCR straight to the clipboard" capture, and the OCR popup's Copy button already
covers that in two steps. The mode itself still exists - `caelestia shell picker
openOcrClipboard` - so binding it is one line in `hypr-user.lua` if you want it.

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
