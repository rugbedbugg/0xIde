# Generated state

This project commits the mechanism, never the output. Roughly 1.45 GB of what
exists on a running machine is regenerable and none of it is tracked.

## Never committed

| Path | What | Size |
| --- | --- | --- |
| `~/.local/share/caelestia/ai/` | BitNet runtime and the GGUF model | ~1.4 GB |
| `build/` | upstream checkout, cmake output, the materialised shell tree | ~600 MB |
| `~/.local/share/caelestia-mod/qml/` | the built plugin | ~29 MB |
| `~/.local/state/caelestia/` | `scheme.json`, `sequences.txt`, wallpaper state, `apps.sqlite`, `notifs.json`, the dots clone | ~2 MB |
| `~/.cache/caelestia*` | caches | |
| `~/.config/kdeglobals` | output of `adapters/kde` | |
| `~/.config/gtk-{3,4}.0/`, `qtengine/caelestia.colors` | Caelestia's own output | |
| `spicetify/Themes/caelestia/color.ini` | Caelestia's output; `user.css` **is** tracked | |
| `assets/ai/manifest.json` | rendered from `manifests/ai.toml` at build time | |
| `__pycache__/`, `*.so`, `*.qmltypes`, `*.o` | compiled output | |

## The distinction that is easy to get wrong

`kdeglobals` and `qtengine/config.json` are written by `adapters/kde/apply`,
which lives in this repository. The **script** is source. Its **output** is not,
and committing it would make the repository a second palette.

The same applies to `manifests/ai.toml` and `assets/ai/manifest.json`: the TOML
is source, the JSON is build output rendered from it.

## Checked automatically

`tests/run` fails if any of `build/`, `scheme.json`, `sequences.txt`,
`apps.sqlite`, `notifs.json`, `kdeglobals`, `color.ini`, `*.gguf`, `*.so`, or
`__pycache__` is tracked.
