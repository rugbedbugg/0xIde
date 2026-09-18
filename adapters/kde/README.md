# kde adapter

KDE applications read their palette from `kdeglobals` through `KColorScheme`,
not from the Qt platform theme. Caelestia writes a qtengine colour file and a
GTK stylesheet but never writes `kdeglobals`, so Dolphin and Ark keep the last
palette a KDE settings module left behind.

This adapter derives `kdeglobals` from what Caelestia already generated for
qtengine rather than re-deriving it from `scheme.json`. Caelestia stays the one
place the palette comes from; this only translates a format.

It also unifies fonts across the three toolkits, because Caelestia themes
colours but leaves fonts to each toolkit's own default:

| Target | File | Key |
| --- | --- | --- |
| Qt / KDE | `kdeglobals` | `[General] font`, `fixed`, `smallestReadableFont`, `toolBarFont`, `menuFont` |
| Qt (qtengine) | `qtengine/config.json` | `fixed_font`, `general_font` |
| GTK 3 and 4 | `gtk-{3,4}.0/settings.ini` | `gtk-font-name` |
| GNOME schema | dconf | `font-name`, `document-font-name`, `monospace-font-name` |

Fonts fall back to whatever `fc-match` resolves when the configured family is
not installed, so a machine without the Caelestia fonts still gets a coherent
result instead of a broken one.

## Widget style

Caelestia generates colours on every theme change, but the GTK theme and the Qt
widget style are set once when the dots are installed and never revisited. A
light scheme therefore ended up drawn inside dark chrome. This adapter picks
them from the scheme's `mode` instead:

| `mode` | Qt style | GTK theme | libadwaita |
| --- | --- | --- | --- |
| `light` | `Breeze` | `adw-gtk3` | `prefer-light` |
| `dark` | `Darkly` | `adw-gtk3-dark` | `prefer-dark` |

Darkly is a Breeze fork, so the pair looks like one desktop rather than two. A
name that is not installed is skipped rather than written, because a style Qt
cannot resolve drops applications onto their fallback, which looks worse than
the mismatch this fixes.

The theme name goes into `gtk-3.0/settings.ini` and into dconf. The dconf half
is what makes GTK applications that are **already open** change without being
restarted. GTK4 and libadwaita ignore the theme name and follow `color-scheme`,
so they get that instead.

## Notes

- Group headers in `kdeglobals` are preserved verbatim, including compound
  headers such as `[Colors:Header][Inactive]`, so settings this adapter does not
  own survive untouched.
- Writes are atomic and content-compared, so re-running changes nothing.
- This is the one adapter that reads another adapter's output. If Caelestia
  changes its qtengine template, this needs adjusting; nothing else here does.
