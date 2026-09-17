# Portability

## How paths are resolved

Every script sources `orchestration/lib/common.sh`, which derives everything
from XDG variables with standards-compliant defaults and resolves the repository
root from `BASH_SOURCE` rather than `$0`. No script knows a username or a
checkout location.

`tests/run` fails if a username, hostname, or `/home/...` path appears in any
tracked file outside `docs/`.

## What is still machine-specific, and where it lives

| Assumption | Where | Notes |
| --- | --- | --- |
| Arch Linux, `pacman`/AUR | throughout | dependency names in `installer/check_deps.sh` are Arch names |
| `microsoft-edge-dev` channel | `adapters/edge` | override with `CM_EDGE_BINARY` in `config.local` |
| the `corners` SDDM theme | `system/sddm` | override with `CM_SDDM_THEME_DIR` |
| `/etc/opt/edge/policies/managed` | `adapters/edge` | override with `CM_EDGE_POLICY_DIR` |
| `Sweet-cursors` cursor theme | `overrides/caelestia/hypr-vars.lua` | a value, easy to change |
| Google Sans Flex, CaskaydiaCove NF | `adapters/kde` | falls back through `fc-match` when absent |
| `mise` at `~/.local/bin/mise` | `overrides/fish` | guarded by `test -x`; a no-op without it |
| `/usr/bin/python3` | `shell/extensions/ocr/tree/services/Ocr.qml`, `common.sh` | deliberate. Where a version manager (mise, asdf, pyenv) puts a shim on `PATH`, `python3` can resolve to a release the distribution packages were not built against; naming the interpreter avoids that. Change `Ocr.qml`'s `python` property on a distribution that puts it elsewhere |

`config.local` at the repository root is sourced by `common.sh` if present and
is git-ignored. Machine-specific values belong there.

## Per-monitor configuration

`~/.config/caelestia/monitors/<name>/shell.json` is keyed by connector name
(`eDP-1` on a laptop, something else on a desktop) and is therefore inherently
machine-specific, so this project does not install one. Create it yourself if
you want per-monitor overrides.

## What is not portable and is not meant to be

`system/portals` documents a portal binary that existed only on the machine this
project came from. It is not distributed, nothing here depends on it, and it is
deliberately not installable from this repository.
