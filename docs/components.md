# Components

## Overrides

Configuration going through a mechanism Caelestia or the application supports.

| Component | Target | Mechanism |
| --- | --- | --- |
| `overrides/caelestia/hypr-vars.lua` | Hyprland | upstream merges this table over `hypr/variables.lua` |
| `overrides/caelestia/hypr-user.lua` | Hyprland | upstream requires it for side effects; calls `hl.config` and `hl.bind` |
| `overrides/caelestia/shell.json` | Caelestia Shell | the shell's own settings file, including the `ai` node this project's plugin adds |
| `overrides/caelestia/cli.json` | caelestia-cli | sets `theme.postHook` to this repository's hook; rendered with the checkout path at install time |
| `overrides/fish/user-config.fish` | fish | `config.fish` already sources it |
| `overrides/foot/overlay.conf` | foot | no include mechanism; named keys rewritten in place |
| `overrides/starship/overlay.toml` | starship | no include mechanism; one key rewritten in place |

`hypr-user.lua` deserves a note. Upstream calls `require("hypr-user")` purely for
side effects and discards the return value, and loads it *after* the keybind
module. A version of this file that returned a table (which is what previously
existed at `~/.config/hypr/hypr-user.lua`) therefore did nothing at all. This one
calls `hl` directly, which works, and binds after upstream's binds, which is
what lets it add a keybind without touching `keybinds.lua`.

## Shell extensions

| Extension | Adds | Needs |
| --- | --- | --- |
| `ocr` | region capture to text, a result popup with table reconstruction, a language setting | `grim`, `slurp`, `tesseract` |
| `ai` | an OCR & AI settings page, a local BitNet runtime, streaming chat completions against any OpenAI-compatible endpoint | `python3`; the model is fetched on request |
| `search` | region to web search; circle-to-search gesture | `tesseract` for the default mode, `jq`, `fuzzel` for confirmation |

Each is a `tree/` mirroring the shell layout, overlaid by `shell/build.sh`.
`--extensions ocr` builds a shell with only that one.

`ai` and `ocr` both require the plugin, which provides `GlobalConfig.ai.*` and
`AiRequest`. `search`'s default mode uses `tesseract` directly and does not.

## Plugin

`shell/plugin/src/` provides two types the packaged Caelestia plugin does not:

| Type | Module | Surface |
| --- | --- | --- |
| `AiConfig` | `Caelestia.Config` | `backend`, `backendUrl`, `model`, `systemPrompt`, `ocrLanguages`, `translateLanguage`, `tableMode`, all persisted to `shell.json` |
| `AiRequest` | `Caelestia` | `send(url, payload[, timeoutMs])`, `cancel()`, readonly `running`/`text`/`error`/`status`, signals `changed`/`finished` |

See `shell/plugin/README.md` for how it was recovered and what is inferred.

## Adapters

| Adapter | Application | Mechanism | Root |
| --- | --- | --- | --- |
| `kde` | Dolphin, Ark, Qt apps, Thunar | writes `kdeglobals`, qtengine fonts, GTK settings, dconf | no |
| `spotify` | Spotify | runs `spicetify apply`; installs `user.css` once | no |
| `papirus` | folder icons | calls Caelestia's own `sync_papirus_colors` | yes |
| `edge` | Microsoft Edge | writes a managed policy file | yes |
| `yazi` | yazi | none: theme names ANSI slots | no |
| `rmpc` | rmpc | none: theme names ANSI slots | no |

Each has `adapter.conf` (metadata), `README.md`, and at least one of `apply`
(runs on every theme change), `install` (one-time), `status` (reports health).

## System

| Module | Does | Default |
| --- | --- | --- |
| `system/sudoers` | installs two scoped `NOPASSWD` rules after `visudo -c` and a prompt | off |
| `system/sddm` | enables login-screen sync | off |
| `system/spotify` | nothing; documents a change this project refuses to make | n/a |
| `system/portals` | nothing; documents an unexplained binary | n/a |
