<h1 align=center>0xIde</h1>

<div align=center>

![GitHub last commit](https://img.shields.io/github/last-commit/rugbedbugg/0xIde?style=for-the-badge&labelColor=000000)
![GitHub repo size](https://img.shields.io/github/repo-size/rugbedbugg/0xIde?style=for-the-badge&labelColor=000000)
![Stars](https://img.shields.io/github/stars/rugbedbugg/0xIde?style=for-the-badge&labelColor=000000)
![License](https://img.shields.io/github/license/rugbedbugg/0xIde?style=for-the-badge&labelColor=000000)
[![CI](https://img.shields.io/github/actions/workflow/status/rugbedbugg/0xIde/ci.yml?branch=main&style=for-the-badge&labelColor=000000)](https://github.com/rugbedbugg/0xIde/actions/workflows/ci.yml)

</div>

A modular extension and synchronisation layer around [Caelestia][caelestia]. It adds
capabilities to the Caelestia Shell, and it carries Caelestia's colour scheme into
applications Caelestia does not theme itself.

> [!NOTE]
> This is not a fork, a replacement theme engine or a `$HOME` dump. Caelestia stays the
> source of truth for colours: there is no palette here, and every integration translates
> what Caelestia already generated for one application. The shell is a three-patch series
> over a pinned upstream revision, and every file belongs to a component you can install
> or skip.

## Components

-   Shell extensions, built as patches and overlays on the upstream [Caelestia Shell][shell]:
    -   **Text extraction.** The screen freezes, you drag over some text, and on release
        it is on your clipboard. Nothing opens. [Tesseract][tesseract] runs locally and the
        capture is deleted straight away.
    -   **Web search.** A dragged rectangle is read with local OCR and only the recognised
        text is searched, so no image leaves the machine. A freehand circle searches the
        picture itself with Google Lens, asking first, every time.
    -   **Local AI.** A BitNet runtime bound to `127.0.0.1`, or any OpenAI-compatible
        chat-completions endpoint you point it at. It explains, summarises, translates or
        tabulates captured text, and nothing is sent anywhere unless you press Ask AI.
    -   **OCR & AI settings** in the shell's own settings app.
-   Theme adapters, for applications Caelestia does not reach:
    -   **KDE**: Dolphin and Ark colours via `kdeglobals`, and one font across Qt, GTK and GNOME
    -   **Spotify**: re-applies the spicetify theme after a scheme change
    -   **Microsoft Edge**: browser theme colour through a managed policy
    -   **Papirus**: folder icons follow the scheme
    -   **Yazi** and **rmpc**: nothing to run, their themes name terminal ANSI slots
-   **Login screen** (optional): an SDDM theme that follows the Caelestia scheme,
    wallpaper and profile picture. See [`system/sddm`](system/sddm/README.md).

## Installation

> [!NOTE]
> This extends a working Caelestia desktop. Install the [Caelestia dotfiles][dots] first:
> `caelestia-shell`, `caelestia-cli`, `quickshell` and Hyprland.

### Dependencies

-   [`caelestia-shell`][shell] and [`caelestia-cli`](https://github.com/caelestia-dots/cli)
-   [`quickshell-git`](https://git.outfoxxed.me/quickshell/quickshell)
-   `git`, `rsync`, `python`, `jq`
-   For text extraction: [`tesseract`][tesseract] with the language data you want, and `wl-clipboard`
-   For web search: `curl`, and [`fuzzel`](https://codeberg.org/dnkl/fuzzel) to ask before a circle sends anything
-   For building the shell: `cmake`, `ninja`, `libqalculate` and the Qt 6 development
    packages, the same set upstream needs

Each adapter needs only its own application. To see what each component needs and what
is missing:

```sh
./installer/check_deps.sh
```

### Install

```sh
git clone https://github.com/rugbedbugg/0xIde.git
cd 0xIde
./install --dry-run     # exactly what would change, grouped by kind; changes nothing
./install               # the default set; nothing in it needs root
```

To work with individual components:

```sh
./install --list                  # every component, its kind, and its default
./install --status                # what is installed, and whether it works
./install --only shell            # just the shell
./install --enable sddm           # add a component that is off by default
./install --disable spotify       # skip one that is on
```

> [!WARNING]
> Components under `system/` need root. None is on by default: each prints the exact
> change and asks first, and each has a `remove` that reverses it.

Re-running `./install` is a no-op. An adapter whose application is missing is skipped
rather than failing. The first version of every file this project replaces is kept under
`$XDG_STATE_HOME/0xide/replaced/`, and nothing here deletes it.

## Usage

### Keybinds

| Key                 | Action                          | Result                   |
| ------------------- | ------------------------------- | ------------------------ |
| `SUPER + SHIFT + T` | Extract text from a region      | clipboard, nothing opens |
| `SUPER + SHIFT + A` | Web search, rectangle or circle | browser                  |

They are set in `overrides/caelestia/hypr-vars.lua` and bound in
`overrides/caelestia/hypr-user.lua`, both extension points Caelestia supports. A binding
that collides with one upstream already made is skipped, with a message, rather than
shadowing it.

Web search has one key. Rectangle or circle is picked from a toolbar at the bottom of
the selector, which opens on rectangle, the one that uploads nothing.

### Asking AI

The AI capture ships without a key. It is the same selector, but it opens the recognised
text in a panel instead of stopping at the clipboard:

```sh
qs -c caelestia ipc call picker openAskAi              # capture, then ask
qs -c caelestia ipc call picker showText "$(wl-paste)"  # ask about text you already have
```

Bind `caelestia:askAi` to give it a key. The backend is chosen under **OCR & AI** in the
shell's settings, or under `ai` in `shell.json`.

## Updating

```sh
cd 0xIde
git pull
./install
```

To move the shell to a newer upstream revision:

```sh
$EDITOR shell/upstream.pin    # 1. point the pin at the new revision
./shell/build.sh              # 2. rebuild; this stops if a patch no longer applies
./tests/run                   # 3. re-apply every patch to a clean checkout
```

A patch that no longer applies must fail. Nothing here resolves a conflict
automatically, because a silently mis-rebased patch is worse than a refused build. Rebase
it by hand in `build/shell-src` with `git apply --3way`, then write it back as a
`git format-patch` series.

## Configuring

| File                                                             | What it sets                                                          |
| ---------------------------------------------------------------- | --------------------------------------------------------------------- |
| `overrides/caelestia/hypr-vars.lua`                              | Hyprland variables: browser, editor, cursor theme, the keybinds above |
| `overrides/caelestia/hypr-user.lua`                              | Hyprland settings and binds that are not plain variables              |
| `overrides/caelestia/shell.json`                                 | Caelestia Shell settings, including the AI backend under `ai`         |
| `overrides/caelestia/cli.json`                                   | caelestia-cli settings                                                |
| `overrides/fish/user-config.fish`                                | fish additions                                                        |
| `overrides/foot/overlay.conf`, `overrides/starship/overlay.toml` | keys merged into two files that have no include mechanism             |
| `$XDG_CONFIG_HOME/0xide/region-search.conf`                      | region search mode and confirmation                                   |
| `$XDG_CONFIG_HOME/0xide/adapters.enabled`                        | which adapters the theme hook runs                                    |

`ai.ocrLanguages` in `shell.json` picks the Tesseract languages; empty, the default, uses
every installed one. `config.local` at the repository root, never committed, overrides
paths and binary names for a machine that puts things somewhere unusual.

### Privacy and privileges

-   **Text extraction is local.** The recognised text goes to the clipboard and nowhere
    else, and the capture is deleted whether it succeeded or not.
-   **Region search stays local.** Only the recognised text is searched.
-   **Circle search goes to Google Lens, and asks first.** The capture is sent to Google
    Lens itself and its results open in your browser: only Google receives it, and no
    public link is made. Every send asks first, and a declined, failed or dismissed
    prompt refuses. `mode="host-upload"` in `region-search.conf` routes it through a
    public file host instead, `mode="text"` keeps both gestures local, and `mode="off"`
    disables region search.
-   **The AI backend defaults to a local model** on `127.0.0.1`. A remote endpoint is your
    choice, and the destination is shown above the submit button.
-   **The AI model is not in this repository.** `manifests/ai.toml` pins its revision and
    SHA-256, and the runtime fetches and verifies it only when you ask.
-   **Nothing that needs root is on by default**, and sudo rules are checked with
    `visudo -c` before they are installed.

## Architecture

```text
Caelestia
├── supported overrides      hypr-vars.lua, hypr-user.lua, shell.json, cli.json
├── shell patches/overlays   over a pinned upstream revision
└── theme state              scheme.json, written by Caelestia
      └── orchestration      theme.postHook runs hooks/post-theme
            └── adapters     one directory per application
```

`orchestration/hooks/post-theme` holds no application knowledge: it reads the enabled
list and runs each adapter's `apply`. Adding an application means adding a directory
under `adapters/`, never editing the hook.

| Where                           | What goes there                                                        |
| ------------------------------- | ---------------------------------------------------------------------- |
| `shell/patches/`                | changes to files upstream owns, as a `git format-patch` series         |
| `shell/plugin/`                 | C++ types the packaged plugin lacks, with their registration patch     |
| `shell/extensions/<name>/tree/` | new files, overlaid onto the upstream tree                             |
| `adapters/<name>/`              | one application: `adapter.conf`, `apply`, optional `install`, `status` |
| `system/<name>/`                | anything privileged; it prints the change and asks                     |

Prefer an overlay to a patch: a patch is only for a line that must change inside a file
upstream maintains, and each one costs something at the next update.

## Development

```sh
./tests/run
```

The suite checks syntax and metadata across the tree, re-applies every patch to a clean
checkout of the pin, and drives the installers, adapters and privileged helpers with
their side effects stubbed. It fails if generated state (the built plugin, the upstream
checkout, the AI model, Caelestia runtime state) ever becomes tracked. [CI][ci] runs it
on Arch Linux, with `shellcheck`, on every push and pull request.

## FAQ

### Where did the Arch dotfiles go?

This repository used to hold my acrylic Waybar, Rofi and Kitty dotfiles. They were
retired when the desktop moved to Caelestia, and they are still in the history: every
commit up to `[Repo]: Retire the Arch dotfiles for the Caelestia setup` has them.

### I want to change something Caelestia manages!

Use the overrides in `overrides/`, which are the extension points Caelestia supports.
Nothing here edits a file the Caelestia dots deploy.

### KDE Connect can't drive my pointer or keyboard!

That needs a RemoteDesktop portal, which `xdg-desktop-portal-hyprland` does not provide.
One local portal that did is documented but deliberately not distributed; see
[`system/portals`](system/portals/README.md).

### I want to turn an adapter off without uninstalling it!

Remove its line from `$XDG_CONFIG_HOME/0xide/adapters.enabled`.

## Credits

Built on [Caelestia][caelestia] by [@soramanew](https://github.com/soramanew), and on
[Quickshell](https://quickshell.outfoxxed.me) by [@outfoxxed](https://github.com/outfoxxed).
The rectangle-or-circle region search follows the one in
[end-4's dots](https://github.com/end-4/dots-hyprland).

## License

GPL-3.0-or-later. Caelestia Shell is GPL-3.0 and this repository contains patches against
it, so a permissive licence is not available for the whole. See [`LICENSE`](LICENSE).

## Stonks 📈

<a href="https://www.star-history.com/#rugbedbugg/0xIde&Date">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/svg?repos=rugbedbugg/0xIde&type=Date&theme=dark" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/svg?repos=rugbedbugg/0xIde&type=Date" />
   <img alt="Star History Chart" src="https://api.star-history.com/svg?repos=rugbedbugg/0xIde&type=Date" />
 </picture>
</a>

[caelestia]: https://github.com/caelestia-dots
[shell]: https://github.com/caelestia-dots/shell
[dots]: https://github.com/caelestia-dots/caelestia
[tesseract]: https://github.com/tesseract-ocr/tesseract
[ci]: https://github.com/rugbedbugg/0xIde/actions/workflows/ci.yml
