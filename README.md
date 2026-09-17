# caelestia-mod

A modular extension and theme-synchronisation layer around
[Caelestia](https://github.com/caelestia-dots). It adds capabilities to the
Caelestia Shell, and it pushes Caelestia's colour scheme into applications
Caelestia does not theme itself.

Caelestia remains the source of truth for colours. Nothing here holds a second
palette; every integration reads what Caelestia already produced and translates
it for one application.

## What it provides

- **Shell extensions** built on Caelestia Shell:
  - **OCR** of a selected screen region, including table reconstruction
  - **Region search** and **circle search** - draw around something and search
    for it. By default the region is read locally and the *text* is searched, so
    no image is sent anywhere
  - **Local AI**: a BitNet runtime on `127.0.0.1`, plus a client for any
    OpenAI-compatible endpoint you point it at
- **Theme adapters** for applications Caelestia does not theme itself:
  - **KDE** - Dolphin and Ark, via `kdeglobals`, plus Qt and GTK fonts
  - **Spotify** - re-applies the spicetify theme after a scheme change
  - **Papirus** - folder icons follow the scheme
  - **Microsoft Edge** - browser theme colour via managed policy
  - **Yazi** and **rmpc** - no adapter runs at all; their themes name terminal
    ANSI slots, so they follow the scheme with nothing to regenerate
- **Supported overrides** only. Settings go through the extension points
  Caelestia provides, never into the files it deploys.
- **Optional system integrations**, including **SDDM** login-screen theming and
  the narrow `sudoers` rules two adapters need. Every one is opt-in, prints the
  exact change first, and asks.

## What it is not

- Not a desktop environment. Caelestia, Hyprland and Quickshell do that; this
  sits on top of a working Caelestia install.
- Not a fork that replaces Caelestia. The shell is a **three-patch series over a
  pinned upstream revision**, not a vendored copy, and the CLI and dots are
  untouched upstream packages.
- Not a dotfiles dump. Every file here belongs to a named component you can
  install or skip.
- Not a second theme engine. There is no palette in this repository.

## Documentation

| | |
| --- | --- |
| [docs/architecture.md](docs/architecture.md) | the two pipelines, and where a change belongs |
| [docs/components.md](docs/components.md) | every override, extension, adapter and system module |
| [docs/upstream.md](docs/upstream.md) | **taking a Caelestia update**, with exact commands |
| [docs/security.md](docs/security.md) | search egress, the AI destination, every root operation |
| [docs/generated.md](docs/generated.md) | what is runtime state and is never committed |
| [docs/portability.md](docs/portability.md) | remaining machine-specific assumptions |
| [docs/licensing.md](docs/licensing.md) | why GPL-3.0 and not something permissive |
| [docs/migration.md](docs/migration.md) | how an existing hand-edited setup was moved onto this |

## Prerequisites

A working Caelestia desktop: `caelestia-shell`, `caelestia-cli`, `quickshell`,
Hyprland, and the Caelestia dots deployed. Then:

```sh
./installer/check_deps.sh     # what each component needs, and what is missing
```

Building the shell additionally needs `cmake`, `ninja`, `git` and the Qt 6
development packages.

## Install

```sh
./install --list        # every component, its kind, and whether it is on by default
./install --dry-run     # exactly what would change, grouped by kind. Changes nothing
./install               # the default set. No component in it needs root
./install --status      # what is installed, and whether it works
```

Selective:

```sh
./install --only shell            # just the shell
./install --enable edge           # add a component that is off by default
./install --disable spotify       # skip one that is on
./install --enable sudoers        # privileged; prints the rules and asks
```

Re-running `./install` is a no-op. An adapter whose application is not installed
is skipped rather than failing.

## Components

`./install --list` is authoritative. [docs/components.md](docs/components.md)
describes each one and what mechanism it uses.

| Kind | Default | Needs root |
| --- | --- | --- |
| `overrides`, `foot`, `starship` | on | no |
| `kde`, `yazi`, `rmpc`, `spotify`, `papirus` | on | no |
| `shell` | off (builds from source) | no |
| `edge` | off | yes, to take effect |
| `sudoers`, `sddm` | off | yes |

## Optional and privileged modules

Everything under `system/` is opt-in, prints the exact change first, and asks.
`system/sudoers` validates with `visudo -c` before installing anything.

Two things this project deliberately does **not** do, both documented with
safer alternatives: it never makes `/opt/spotify` writable
([system/spotify](system/spotify/README.md)) and it never chowns the SDDM theme
directory ([system/sddm](system/sddm/README.md)).

One local dependency is documented but **not shipped**: an unpackaged KDE
Connect portal binary whose source is lost. Everything here works without it.
See [system/portals](system/portals/README.md).

## Disabling and uninstalling

Adapters are driven by `$XDG_CONFIG_HOME/caelestia-mod/adapters.enabled`;
removing a line stops that adapter running. `system/sudoers/remove` reverses the
sudo rules. The first version of every file this project replaced is kept under
`$XDG_STATE_HOME/caelestia-mod/replaced/`, and `$XDG_STATE_HOME/caelestia-mod/owned.list`
records what it created. Nothing here deletes either.

## Generated data

This repository holds the mechanisms, never their output. The built plugin, the
upstream checkout, the AI model (~1.4 GB) and all Caelestia runtime state are
excluded, and `tests/run` fails if any of it becomes tracked.
See [docs/generated.md](docs/generated.md).

## Updating the shell against upstream

The shell is patches over a pin, so an update is a patch rebase, not a merge.
`shell/build.sh` refuses to continue if a patch no longer applies, rather than
producing a half-patched tree. Exact commands:
[docs/upstream.md](docs/upstream.md).

## Privacy

Region search runs this by default:

```text
screen region  ->  local OCR  ->  text web search
```

No image is transmitted in that mode. An image-upload mode exists for searching
pictures rather than text; it is **off by default**, and when enabled it asks
before every single upload, naming the host the image would go to. Declining, a
prompt that fails, and a prompt that is dismissed all refuse the upload. It can
also be disabled outright.

The AI backend defaults to a local model on `127.0.0.1`. Pointing it at a remote
endpoint is a configuration choice, and the OCR popup shows the destination
above the submit button at all times. Full detail, including the sudo rules and the two standing
system weaknesses this project refuses to recreate:
[docs/security.md](docs/security.md).

## Licence

GPL-3.0-or-later. Caelestia Shell is GPL-3.0 and this contains patches against
it, so a permissive licence is not available to the repository as a whole.
See [docs/licensing.md](docs/licensing.md).
