# caelestia-mod

A modular extension and synchronisation layer around
[Caelestia](https://github.com/caelestia-dots).

It does two things. It adds capabilities to the Caelestia Shell, and it pushes
Caelestia's colour scheme into applications Caelestia does not theme itself.

It is **not** a `$HOME` dump, a fork, or a replacement theme engine. Caelestia
stays the source of truth for colours: there is no palette in this repository,
and every integration reads what Caelestia already generated and translates it
for one application. The shell is a three-patch series over a pinned upstream
revision, not a vendored copy. Every file belongs to a named component you can
install or skip.

## Features

**Caelestia Shell extensions**, built as patches and overlays on the upstream
shell:

- **Text extraction.** The screen freezes, you drag a rectangle over some text,
  and on release the text is on your clipboard. Tesseract runs locally, there is
  no result window to dismiss, and the capture is deleted straight away.
- **Region search.** Draw a rectangle and search the web for what is in it.
- **Circle search.** Draw freehand around something and search for that.
- **Local AI.** A BitNet runtime bound to `127.0.0.1`, plus a client for any
  OpenAI-compatible chat-completions endpoint you point it at. It reads a
  captured region into a result window that can explain, summarise, translate or
  rebuild it as a table. This is a separate action from text extraction, and
  text extraction never touches it.

**Theme synchronisation** for applications Caelestia does not reach:

- **KDE.** Dolphin and Ark colours via `kdeglobals`, plus one font across Qt,
  GTK and GNOME.
- **Spotify.** Re-applies the spicetify theme after a scheme change.
- **Microsoft Edge.** Browser theme colour through a managed policy file.
- **Papirus.** Folder icons follow the scheme.
- **Yazi** and **rmpc.** No adapter runs at all: their themes name terminal ANSI
  slots, so they follow Caelestia's palette with nothing to regenerate.
- **SDDM** (optional). Login screen colours and wallpaper.

## Installation

```sh
./install --help        # every mode and flag
./install --dry-run     # exactly what would change, grouped by kind. Changes nothing
./install               # the default set. No component in it needs root
```

Then, to work with individual components:

```sh
./install --list                  # every component, its kind, and its default
./install --status                # what is installed, and whether it works
./install --only shell            # just the shell
./install --enable edge           # add a component that is off by default
./install --disable spotify       # skip one that is on
./install --enable sudoers        # privileged; prints the rules and asks first
```

Re-running `./install` is a no-op. An adapter whose application is not installed
is skipped rather than failing. The first version of every file this project
replaces is kept under `$XDG_STATE_HOME/caelestia-mod/replaced/`, and nothing
here ever deletes it.

To stop an adapter without uninstalling it, remove its line from
`$XDG_CONFIG_HOME/caelestia-mod/adapters.enabled`. `system/sudoers/remove`
reverses the sudo rules.

## Requirements

A working Caelestia desktop: `caelestia-shell`, `caelestia-cli`, `quickshell`,
Hyprland, and the Caelestia dots deployed.

```sh
./installer/check_deps.sh     # what each component needs, and what is missing
```

Building the shell additionally needs `cmake`, `ninja`, `git`, `libqalculate`
and the Qt 6 development packages, which is the same set upstream needs.

Text extraction needs exactly two things: `tesseract`, with the language data
you want, and `wl-clipboard`. Region search additionally uses `jq`, and its
optional image-upload mode uses `curl` and `fuzzel`. Each adapter needs only its
own application present.

## Default keybindings

| Key | Action |
| --- | --- |
| `SUPER + SHIFT + T` | Extract text from a region of the screen |
| `SUPER + SHIFT + A` | Region search |
| `SUPER + SHIFT + O` | Circle search |

One more action ships unbound: `kbAskAi` opens the same selector but sends the
text to the AI result window instead of the clipboard. Give it a key in
`hypr-vars.lua` to use it.

These are defined in `overrides/caelestia/hypr-vars.lua` and bound in
`overrides/caelestia/hypr-user.lua`, both of which are extension points
Caelestia supports. No file that the Caelestia dots deploy is edited. A binding
that collides with one upstream already made is skipped, with a message, rather
than shadowing it.

`SUPER + SHIFT + O` is used for circle search because upstream already binds
`SUPER + SHIFT + C` to the colour picker.

## Configuration

Everything user-editable lives in one of these:

| File | What it sets |
| --- | --- |
| `overrides/caelestia/hypr-vars.lua` | Hyprland variables: browser, editor, cursor theme, the keybindings above |
| `overrides/caelestia/hypr-user.lua` | Hyprland settings and binds that are not plain variables |
| `overrides/caelestia/shell.json` | Caelestia Shell settings, including the AI backend under `ai` |
| `overrides/caelestia/cli.json` | caelestia-cli settings |
| `overrides/fish/user-config.fish` | fish shell additions |
| `overrides/foot/overlay.conf`, `overrides/starship/overlay.toml` | keys merged into two files that have no include mechanism |
| `$XDG_CONFIG_HOME/caelestia-mod/region-search.conf` | region search mode and confirmation |
| `shell.json`, `ai.ocrLanguages` | Tesseract languages. Empty, the default, uses every installed one |
| `$XDG_CONFIG_HOME/caelestia-mod/adapters.enabled` | which adapters the theme hook runs |

`config.local` at the repository root, which is never committed, overrides
paths and binary names for a machine that puts things somewhere unusual.

The AI backend is configured in `shell.json` under `ai`, or from the AI page in
the shell's settings.

## Privacy and privileges

- **Text extraction is local.** Tesseract runs on this machine, the recognised
  text goes to the clipboard and nowhere else, and the captured image is deleted
  whether it succeeded or not. It never reaches the AI backend.
- **Region search is local first.** By default the region is read with local OCR
  and only the recognised *text* is sent to a web search. No image leaves the
  machine.
- **Image upload is opt-in.** A mode that uploads the captured pixels to a file
  host for reverse image search exists, is off by default, and when enabled asks
  before every single upload, naming the host. A declined prompt, a failed
  prompt and a dismissed prompt all refuse. Region search can also be turned off
  entirely.
- **The AI backend defaults to a local model** on `127.0.0.1`. Pointing it at a
  remote endpoint is a configuration choice, and the destination is shown above
  the submit button at all times.
- **Nothing that needs root is enabled by default.** Everything under `system/`
  is opt-in, prints the exact change first, and asks. `system/sudoers` validates
  its rules with `visudo -c` before installing them. This project never chowns a
  system directory and never makes one world-writable; where a common workaround
  does that, the component's own README gives the safer alternative instead.
- **The AI model is not in this repository and is not downloaded by
  `./install`.** `manifests/ai.toml` pins its revision and SHA-256; the runtime
  fetches and verifies it only when you ask for it. Cloning this repository
  downloads no model.

One local dependency is documented but deliberately not distributed: an
unpackaged portal binary, its source lost, that provided the RemoteDesktop
portal `xdg-desktop-portal-hyprland` does not. Nothing here requires it, and the
only thing its absence costs is KDE Connect driving your pointer and keyboard
from a phone. See [system/portals](system/portals/README.md).

## Architecture

```text
Caelestia
├── supported overrides      hypr-vars.lua, hypr-user.lua, shell.json, cli.json
├── Shell extensions/patches patches over a pinned upstream revision
└── theme state              scheme.json, written by Caelestia
      └── orchestration      theme.postHook runs hooks/post-theme
            └── adapters     one directory per application
```

Caelestia writes the palette. `orchestration/hooks/post-theme` is a dispatcher
with no application knowledge: it reads the enabled list and runs each adapter's
`apply`. Adding an application means adding a directory under `adapters/`, never
editing the hook.

## Contributing

| Where | What goes there |
| --- | --- |
| `shell/patches/` | changes to files upstream owns, as `git format-patch` series |
| `shell/plugin/` | C++ types the packaged plugin does not provide, plus their registration patch |
| `shell/extensions/<name>/tree/` | new files, overlaid onto the upstream tree; no patch needed |
| `adapters/<name>/` | one application: `adapter.conf`, `apply`, optional `install` and `status` |
| `system/<name>/` | anything privileged. Must print the change and ask |
| `orchestration/lib/common.sh` | shared path derivation and safe file installation |

Prefer an extension overlay to a patch. A patch is only for a line that has to
change inside a file upstream maintains, and every patch is a cost at the next
update.

Run the tests:

```sh
./tests/run
```

Take an upstream update:

```sh
# 1. Point the pin at the new revision
$EDITOR shell/upstream.pin

# 2. Rebuild. This refuses to continue if a patch no longer applies
./shell/build.sh

# 3. If a patch failed, rebase it by hand against the new tree
cd build/shell-src
git apply --3way ../../shell/patches/0002-*.patch    # resolve conflicts
git diff > /tmp/rebased.patch                        # then reformat as a series

# 4. Re-run the tests, which re-apply every patch to a clean checkout
./tests/run
```

Two rules that are not negotiable:

- **A patch that no longer applies must fail.** Nothing here tries to resolve a
  conflict automatically. `shell/build.sh` stops rather than producing a
  half-patched tree, because a silently mis-rebased patch is worse than a
  refused build. Resolving a conflict is a maintainer decision.
- **Generated state is never committed.** The built plugin, the upstream
  checkout, the AI model and all Caelestia runtime state are excluded, and
  `tests/run` fails if any of it becomes tracked.

## Licence

GPL-3.0-or-later. Caelestia Shell is GPL-3.0 and this repository contains
patches against it, so a permissive licence is not available for the whole. The
`LICENSE` file is byte-identical to the one upstream ships.
