# caelestia-mod

Personal extensions to a [Caelestia](https://github.com/caelestia-dots) desktop,
arranged so that upstream can keep updating underneath them.

Caelestia stays the source of truth for the colour scheme. Nothing here holds a
second palette; every integration reads what Caelestia already produced and
translates it for one application.

## What is in here

| Directory | Owns |
| --- | --- |
| `shell/` | The forked Caelestia Shell: a 3-patch series on a pinned upstream revision, the QML that OCR / AI / search add, and the C++ plugin source those need |
| `overrides/` | Configuration that goes through a supported Caelestia extension point |
| `adapters/` | One directory per application whose theme has to be translated from Caelestia's |
| `orchestration/` | The `postHook` that runs enabled adapters, and shared path helpers |
| `system/` | Everything needing root or writing outside `$HOME`. All opt-in, all print what they will do first |
| `assets/` | Fonts this project installs |
| `manifests/` | Pinned revisions and hashes for things fetched at runtime, never the things themselves |
| `installer/` | Component registry, dependency check, the config-overlay applier |
| `tests/` | Static validation of everything above |
| `docs/` | Architecture, security, upstream compatibility |

## Install

```sh
./install --list        # what exists
./install --dry-run     # what would change
./install               # everything in the default set, none of it privileged
./install --status      # what is installed and whether it works
```

Selective:

```sh
./install --only shell
./install --enable edge --enable sudoers
./install --disable spotify
```

Nothing that needs root is in the default set. `sudoers` and `sddm` print the
exact change and ask before doing anything. Re-running `./install` is a no-op.

## The shell fork

`shell/` does not vendor a copy of Caelestia Shell. It holds a pinned upstream
revision, three patches against it, and the files this project adds. The tree is
materialised at build time:

```sh
./shell/build.sh
```

which clones upstream at the pin, applies the patches, overlays the extensions,
builds the plugin, and installs both. Taking an upstream update is a normal
merge of the patch series, not a re-derivation. See `docs/upstream.md`.

**The upstream patch surface is three patches over five files.** Keeping it that
small is the point; `docs/upstream.md` lists each one and why it cannot be
configuration instead.

## Before you enable the search extension

`shell/extensions/search` can transmit a captured region of your screen off this
machine. It defaults to a mode that does not, and asks before any mode that
does. Read `docs/security.md` before changing that.

## Licence

GPL-3.0-or-later, because Caelestia Shell is GPL-3.0 and this contains patches
against it. See `docs/licensing.md`.
