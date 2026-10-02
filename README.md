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
    -   **Desktop profiles**: personalities of the same Hyprland and Caelestia session,
        such as tiled Caelestia or floating Windows XP. `>theme` in the launcher, or
        **Theme** in settings, switches through one CLI that verifies each switch and
        rolls back a failed one. See [Desktop profiles](#desktop-profiles).
    -   **Wallpaper info**: right-click a wallpaper in the launcher's `>wallpaper` or the
        **Wallpapers** settings page to see its size in pixels, on disk and in memory once
        shown, and to move it to the Trash (`gio`, after a confirming second click; the
        wallpaper in use cannot be deleted). The size is read from the file's header, so
        checking a huge image costs nothing.
    -   **UnNova**, a system monitor and process manager in the shell's own look: click
        the character in the power panel. See [UnNova](#unnova).
-   Theme adapters, for applications Caelestia does not reach:
    -   **GTK**: open GTK windows recolour on a scheme change instead of on their next
        start, including Edge and Chrome in their GTK appearance. See
        [`adapters/gtk`](adapters/gtk/README.md).
    -   **KDE**: Dolphin and Ark colours via `kdeglobals`, and one font across Qt, GTK and GNOME
    -   **Spotify**: re-applies the spicetify theme after a scheme change
    -   **Papirus**: folder icons follow the scheme
    -   **Cursor**: Caelestia's Sweet cursor, rebuilt in the scheme's colours. Upstream
        names it `sweet-cursors` while the package installs `Sweet-cursors`, so stock
        Caelestia always shows the default cursor. See [`adapters/cursor`](adapters/cursor/README.md).
-   Fixes for Caelestia's own app themes that never take effect:
    -   **Zed**: Caelestia regenerates a Zed theme on every change, but its settings select
        One Light and One Dark. This selects the Caelestia theme, which Zed reloads live.
    -   **Firefox**: the CaelestiaFox extension colours it live, but Caelestia copies its
        layout (`userChrome.css`, `user.js`) only into `~/.mozilla`, while current Firefox
        keeps profiles under `~/.config/mozilla`. This puts them in both.
-   **Noise-suppressed microphone** (optional, `./install --enable voice`): PipeWire's
    WebRTC filter on the default microphone, which removes steady background noise and
    brings quiet speech up. Dictation and every other application record through it.
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
-   For web search: [`fuzzel`](https://codeberg.org/dnkl/fuzzel) to ask before a circle sends anything, and `curl` for the optional file-host mode
-   For voice dictation: `whisper-cpp` and `wtype`
-   For the local AI model: [`uv`](https://docs.astral.sh/uv/), `git`, `clang`, `cmake` and
    `ninja`, to build the runtime on your machine. Not needed for an external endpoint
-   For the cursor: [`sweet-cursors-git`](https://aur.archlinux.org/packages/sweet-cursors-git),
    `librsvg` and `xorg-xcursorgen`, plus `hyprcursor` for a cursor that stays sharp at any scale
-   For building the shell: `cmake`, `ninja`, `libqalculate` and the Qt 6 development
    packages, the same set upstream needs

Each adapter needs only its own application. To see what each component needs and what
is missing:

```sh
./installer/check_deps.sh
./installer/check_deps.sh shell   # also require the shell's build tools
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

Installing the shell replaces the Caelestia shell that is running, whether that is the
stock one or an earlier 0xIde build, with exactly one instance of the new one, and leaves
any other Quickshell configuration running as it was. Run it from the desktop session.

Re-running `./install` is a no-op. An adapter whose application is missing is skipped
rather than failing. The first version of every file this project replaces is kept under
`$XDG_STATE_HOME/0xide/replaced/`, and nothing here deletes it.

## Usage

### Keybinds

| Key                 | Action                              | Result                                    |
| ------------------- | ----------------------------------- | ----------------------------------------- |
| `SUPER + SHIFT + T` | Extract text from a region          | clipboard, nothing opens                  |
| `SUPER + SHIFT + A` | Search a region, or ask AI about it | browser, or the AI panel                  |
| `SUPER + SHIFT + D` | Dictation on or off                 | each phrase typed where you are           |

They are set in `overrides/caelestia/hypr-vars.lua` and bound in
`overrides/caelestia/hypr-user.lua`, both extension points Caelestia supports. A binding
that collides with one upstream already made is skipped, with a message, rather than
shadowing it.

`SUPER + SHIFT + A` has three choices, picked from a card at the bottom of the selector
before you drag: **Text** searches the words read from a rectangle, **Image** sends a
circled region to Google Lens after asking, and **Ask AI** opens a rectangle's text in the
AI panel. It opens on Text, the one that uploads nothing, and the card hides once you
start dragging; press `Esc` to start over.

### Asking AI

1. **Choose a backend, once.** In the shell's settings, open **OCR & AI** and pick
   **Local** to run a small model on this computer (see below), or point it at any
   OpenAI-compatible endpoint.
2. **Capture.** Press `SUPER + SHIFT + A`, choose **Ask AI**, and drag over the text.
3. **Ask.** Pick **Explain**, **Summarize**, **Translate**, **Custom** or **Code** and press
   **Ask AI**. Any text you select in either pane is what gets asked about instead of the
   whole capture.

The answer appears beside the text, formatted, with code in the terminal's font; it can be
scrolled while it is still being written. **Code** asks for the minimal working code for
the problem in the capture.

The first answer takes a few seconds while the local model starts. It is a 2B model on the
CPU, good for short passages rather than long documents. With the local backend nothing
leaves this computer.

**Translate** runs offline, without the model, once two or more languages are installed
under **Translation** in the OCR & AI settings (about 160 MB each). Pick the languages
beside the Translate button; any two installed languages translate into each other through
English. Without them, Translate asks the model instead, which is weak outside English.
The models are [Argos Translate](https://github.com/argosopentech/argos-translate)'s, run
with CTranslate2; [`manifests/translate.toml`](manifests/translate.toml) pins them.

For scripts, or a key of its own, the same panel is reachable over IPC and as the
`caelestia:askAi` shortcut:

```sh
qs -c caelestia ipc call picker openAskAi              # capture, then ask
qs -c caelestia ipc call picker showText "$(wl-paste)"  # ask about text you already have
```

The backend can also be set under `ai` in `shell.json`.

#### Installing the local model

The local backend runs Microsoft's
[BitNet b1.58 2B4T](https://huggingface.co/microsoft/bitnet-b1.58-2B-4T-gguf), a
2-billion-parameter model with ternary weights, on
[BitNet.cpp](https://github.com/microsoft/BitNet). Neither is shipped here:
[`manifests/ai.toml`](manifests/ai.toml) pins both revisions and the model's SHA-256.

Install it from **OCR & AI** in the shell's settings, or say yes when the AI panel offers
it the first time you ask. If Download cannot be pressed, the reason is shown under it:
missing build tools, too little disk, or the check still running. It then:

1. checks for the tools above and about 4.1 GiB of free disk,
2. fetches the pinned BitNet.cpp source,
3. builds it for your CPU, which takes several minutes,
4. downloads `ggml-model-i2_s.gguf`, about 1.1 GiB, and verifies its hash,
5. starts the model once as a health check.

Both places show the current step, the time spent on it, and a progress bar: the
downloaded bytes while downloading, a moving bar for steps that report no amount. It keeps
going if you close the panel, and the AI panel shows it in its banner. A failure shows the
installer's own error, the step, and `install.log`; Cancel stops it and keeps nothing.

Everything goes in `$XDG_DATA_HOME/0xide/ai` (`~/.local/share/0xide/ai`), and **Uninstall**
on the same page deletes it. From a terminal, the same installer is:

```sh
cd ~/.config/quickshell/caelestia/assets/ai
uv run --no-project --python 3.13 runtime.py install
```

The model server listens on `127.0.0.1` only, starts on the first question, and stops
after five idle minutes or when the shell exits.

### Voice dictation

`SUPER + SHIFT + D` turns dictation on; press it again to turn it off. While it is on,
everything you say is typed into the focused window, a phrase at a time, as soon as you
pause. Speech is transcribed on this computer by
[whisper.cpp](https://github.com/ggml-org/whisper.cpp), and no recording is kept. A muted
microphone is refused rather than recorded as silence. It needs the `whisper-cpp` and
`wtype` packages, and the speech model, which **Voice dictation** in the OCR & AI settings
installs (148 MB, pinned in [`manifests/speech.toml`](manifests/speech.toml)). It listens
for English unless you set another language there, or `auto` to detect it.

### Desktop profiles

One Hyprland/Caelestia runtime. Multiple desktop personalities.

Every profile runs on the same Hyprland session with the same Caelestia shell. What a
profile changes is how windows are managed, and later how the shell looks:

| Profile      | Window policy                                | Presentation                    |
| ------------ | -------------------------------------------- | ------------------------------- |
| `caelestia`  | `tiling`: Hyprland's tiling, as always       | Caelestia                       |
| `windows-xp` | `stacking`: every window floats and overlaps | not built yet; Caelestia's look |

A third policy, `hybrid`, tiles windows except the classes and tags a profile lists in
`wm_float_classes` and `wm_float_tags`. Policies are in
[`orchestration/wm-policies/`](orchestration/wm-policies).

Type `>theme` in the launcher and pick a desktop, or use **Theme** in the settings app.
The same switch from a terminal:

```sh
./0xide profile list                  # * marks the active one
./0xide profile plan windows-xp       # what switching would do; changes nothing
./0xide profile set windows-xp        # switch
./0xide profile set caelestia         # and back
./0xide profile status                # is the recorded profile really in effect?
```

A switch records the window layout of the profile it leaves, applies the new policy to
open windows and to windows as they open, puts back the windows the new profile's own
snapshot knows, and checks that the shell runs, owns notifications, and the windows are
as asked. Only then is the profile recorded as active. If any step fails, the previous
profile's policy and window layout are put back and nothing is recorded; the details are
in `$XDG_STATE_HOME/0xide/desktop-profile.log`. `set` exits 0 on success, 1 when it failed
and the previous desktop was restored, 2 when that restore failed too.

Returning to Caelestia tiles again every window a policy floated, puts windows that
existed before the switch back on their workspaces, and leaves windows that were already
floating alone. The order of tiled windows within a workspace is not restored. Windows
on special workspaces, fullscreen and pinned windows are never touched. A window is
matched by its address, Hyprland's stable id and its class together, since Hyprland can
give a closed window's address to a new one; a window that was closed and reopened is
treated as new, and one without a stable id is left as it is.

At login, Hyprland runs `./0xide profile resume`, which gives new windows the recorded
profile's policy. A missing or damaged record means Caelestia.

> [!NOTE]
> The Windows XP profile changes window management only. Its Luna look, Start menu and
> taskbar are not built yet, so the Caelestia shell keeps its own look. XPlasma, which
> restyles a KDE Plasma session, was studied as reference material for that look; it is
> not used at runtime, and 0xIde never starts Plasma.

### UnNova

Click the animated character in the power panel (or run
`qs -c caelestia ipc call unnova open`). There is only ever one UnNova window; opening it
again brings the open one forward. It has two tabs.

**0xIde** shows what 0xIde itself runs, by what it is rather than by process ID:

| Component        | Shown                                                    | Actions                   |
| ---------------- | -------------------------------------------------------- | ------------------------- |
| Local AI         | stopped, starting, ready or stopping; its memory and CPU  | Start, Unload, Restart    |
| Dictation        | the speech model, and whether dictation is listening      | none                      |
| Translation      | installed languages, and whether it is translating        | Cancel active translation |
| Text recognition | languages, and whether it is reading a capture            | none                      |
| Desktop          | the active desktop profile                               | none (Theme does)         |

Only the local AI keeps a server running, so only it has something to unload or restart;
those use the runtime's own stop and start. The others start a helper for each use and
leave nothing behind to manage. You can cancel an active translation. Model and language
setup stays in Settings; dictation and capture keep their existing shortcuts. Opening
UnNova never starts the local AI; **Start** does so explicitly when its model is installed.

**Processes** lists every process you can see, calmer than a task manager's table: name,
CPU and memory, with PID and user underneath. Search matches the name, PID, command line
or user. **List** sorts by memory, CPU, name or PID, and values that barely differ keep
their places instead of reshuffling every second. **Tree** shows each process under its
real parent; clicking a row selects it, and only its chevron folds it. The selected
process fills the left pane: identity, CPU and memory with a minute of history, threads,
how long it has run, state, parent, executable and command line.

**End task** sends SIGTERM, which asks the process to exit and lets it clean up. If it is
still running a few seconds later, UnNova says so and offers **Keep waiting** or **Force
stop** (SIGKILL); it never escalates by itself. **Actions…** also offers Force stop,
Pause (SIGSTOP), Resume (SIGCONT), Hang up (SIGHUP), Interrupt (SIGINT) and any other
signal by name, each explained before it is sent. Processes such as init, Hyprland, the
shell itself, PipeWire and networking say what ending them would break. Nothing is
elevated: a process you are not allowed to signal says so.

A process is identified by its PID together with its start time, because Linux reuses
PIDs. On supported kernels, before any signal UnNova pins the process with a pidfd and
checks the start time again. This prevents a reused PID from redirecting a signal to
another process. Exactly the selected process is signalled, never its children or
others with the same name. An identity mismatch always refuses the action.

UnNova reads `/proc` directly, once a second, and only while its window is open. It starts
no processes to do it.

CPU percentages are a share of total machine capacity. Memory in the list is resident
memory minus shared pages; the details also show full resident memory. These are `/proc`
estimates, not proportional-set-size accounting. Command lines are capped at 64 KiB.
On kernels without pidfds, signalling falls back to rechecking PID and start time before
`kill(2)`; that fallback cannot eliminate the narrow exit/reuse race between those calls.

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
| `overrides/caelestia/cli.json`                                   | caelestia-cli settings, including `enableGtk` for the gtk adapter     |
| `overrides/fish/user-config.fish`                                | fish additions                                                        |
| `overrides/foot/overlay.conf`, `overrides/starship/overlay.toml` | keys merged into two files that have no include mechanism             |
| `overrides/zed/overlay.jsonc`                                    | the theme key merged into Zed's `settings.json`                       |
| `$XDG_CONFIG_HOME/0xide/region-search.conf`                      | region search mode and confirmation                                   |
| `$XDG_CONFIG_HOME/0xide/adapters.enabled`                        | which adapters the theme hook runs                                    |
| `profiles/<id>/profile.conf`, `$XDG_CONFIG_HOME/0xide/profiles/` | desktop profiles: provider, window policy, presentation               |

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
-   **No model is in this repository.** `manifests/ai.toml`, `translate.toml` and
    `speech.toml` pin what is fetched, and each is downloaded only when you ask.
-   **Dictation stays on this computer.** Audio goes from the microphone to a local
    whisper-server on `127.0.0.1` and is not kept.
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
| `shell/plugin/`                 | C++ the packaged plugin lacks, with its registration patches           |
| `shell/extensions/<name>/tree/` | new files, overlaid onto the upstream tree                             |
| `adapters/<name>/`              | one application: `adapter.conf`, `apply`, optional `install`, `status` |
| `system/<name>/`                | anything privileged; it prints the change and asks                     |
| `profiles/`, `providers/`       | desktop profiles, and the provider that shows and verifies each one    |
| `orchestration/wm-policies/`    | window-management policies a profile can name                          |

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

UnNova's process core is compiled on its own with `c++` and signals only children the test
starts. Its service and the local AI lifecycle are driven in a windowless `qs`; those two
parts need `qs` and a plugin built with `./shell/build.sh --no-install`, and are skipped
without them. The runtime-control checks use mock services in an unmapped window
(`./tests/unnova-live --controls`); they need a Wayland connection and never start models
or translation requests.

CI compiles the process core; the full plugin and Quickshell checks require the local
build environment described above. Qt's model-contract test covers repeated row
insertions, removals and moves. For the opt-in rendered check, run `./tests/unnova-live`
in a Wayland session after building. It opens an isolated UnNova with private settings,
signals only its own disposable children,
and records screenshots, logs, sampling times, CPU use and RSS in a temporary directory.
It neither installs the build nor restarts the running shell.

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
