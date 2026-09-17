# Upstream compatibility

## What this project does to upstream

| | Count | Where |
| --- | --- | --- |
| Supported Caelestia extension points used | 5 | `overrides/` |
| Upstream shell files patched | 5, in 3 patches | `shell/patches/` |
| Upstream plugin files patched | 3, 4 added lines | `shell/plugin/patches/` |
| Upstream dots files rewritten in place | 2 | `overrides/foot`, `overrides/starship` |
| Files added to the shell tree | 10 | `shell/extensions/` |

## The pinned base

`shell/upstream.pin` names the revision the patches are written against:
`750e67d9` (2026-09-02, "fix(services): only list physical ethernet interfaces
(#1864)").

How it was chosen: the previously-live shell tree was compared file-by-file
against candidate upstream commits. 278 of 283 QML files matched exactly across
`24aa15ee..065dac29`, identifying the branch point. Evidence from the lost
plugin build narrowed it further: the built `.qmltypes` carry the namespaced
Blobs types from `06bdb6ad` and the tree carried the Nmcli change merged as
`750e67d9`, so the build tree was at or after that commit.

`750e67d9` is also the merge of the local Nmcli change, so that change is now
upstream and is deliberately **not** carried here.

## The patch surface, and why each one exists

### `shell/patches/0001` - shell.qml, 2 lines

The plugin import path, and `settings.watchFiles`.

The import path cannot be configuration: quickshell reads `QML_IMPORT_PATH` from
a pragma at the top of `shell.qml` before any config is loaded. It is stored as
`@CAELESTIA_MOD_QML_IMPORT_PATH@` and substituted by `shell/build.sh`, so no
machine path is committed.

`settings.watchFiles: false` is carried forward from the pre-migration
configuration. **It is a revert candidate**: it disables live reload of
`shell.json`, which means `./install` changes to that file do not take effect
until the shell restarts. If you do not need it, drop the second hunk.

### `shell/patches/0002` - AreaPicker.qml, Picker.qml

OCR and region/circle search capture modes. Upstream's picker dispatches a
completed selection to exactly one consumer (screenshot); these modes need it to
dispatch to three.

These two files are one patch rather than two because the change does not
separate at file granularity: `Picker` dispatches on `loader.ocr` and
`loader.searchMode`, and `AreaPicker` owns the loaders and the result popup
those modes need. Splitting them yields two patches neither of which applies
alone.

### `shell/patches/0003` - PageRegistry.qml, PageCompRegistry.qml

Appends one settings page to each of two registries. Upstream has no runtime
page-registration hook, so this cannot be configuration. It is the patch most
likely to conflict on an upstream update, and the easiest to fix: re-append.

### `shell/plugin/patches/0001` - 4 lines

One `#include`, one `CONFIG_SUBOBJECT`, two CMake source entries. The actual
implementation is in `shell/plugin/src/`, copied in before the patch is applied,
so it stays readable rather than living inside a diff.

## What was removed from the patch surface during migration

| Was | Now |
| --- | --- |
| `hypr/variables.lua`, 7 values edited | `overrides/caelestia/hypr-vars.lua` |
| `hypr/hyprland.lua`, `require("hyprland.cursor")` | `overrides/caelestia/hypr-user.lua` calls `hl.config` directly |
| `hypr/hyprland/cursor.lua`, a new file in a managed directory | same |
| `hypr/hyprland/keybinds.lua`, one `create_bind` | `hypr-user.lua` calls `hl.bind`, which is what `create_bind` calls |
| `fish/config.fish`, 2 additions | `overrides/fish/user-config.fish`, which `config.fish` already sources |

Four dots-managed files that upstream explicitly warns against editing are no
longer edited at all.

## What could not be moved

`foot.ini` and `starship.toml` have no include, drop-in, or override mechanism,
and both are deployed by the Caelestia dots. They are rewritten in place by
`installer/apply_overlay.py`, which changes only the named keys, leaves every
other line alone, and does nothing when the value is already right. A dots
update that changes an unrelated setting survives; one that changes these keys
is overwritten on the next `./install`.

## Taking an upstream update

```sh
cd build/shell-src
git fetch origin
git log --oneline <pinned>..origin/main -- modules/areapicker modules/nexus shell.qml
```

Then, for each patch that no longer applies, rebase it by hand, update
`shell/upstream.pin`, and run `./tests/run`, which fails if any patch does not
apply to the pin. `shell/build.sh` refuses to continue on a patch failure rather
than producing a half-patched tree.

The shell is not vendored, so there is no upstream history in this repository to
rewrite, and no merge to resolve: only the patch series moves.
