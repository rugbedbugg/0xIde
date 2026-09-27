# cursor adapter

Upstream Caelestia sets `cursorTheme = "sweet-cursors"`, but the Sweet package
(`sweet-cursors-git` on the AUR) installs its theme as `Sweet-cursors`, and
XCursor and hyprcursor look theme names up case sensitively. Nothing in
Caelestia's install pulls Sweet in either. So every install gets the default
cursor, and this is an upstream bug, not something specific to one system.

This adapter keeps Sweet's shapes and swaps its colours for the scheme's.

- It reads Sweet's scalable sources (`cursors_scalable`: one SVG per frame, with
  hotspots and frame delays in `metadata.json`).
- It maps Sweet's fixed palette to scheme roles: the body is `surface`, the rim
  is `onSurface`, the error red is `error`, and the gradients run from the
  primary palette to the tertiary one.
- Accents are taken at tone 40 under a light rim and tone 70 under a dark one,
  from the scheme's key colour palettes, because Sweet draws its badge glyphs
  (`?`, `+`, the link arrow) in the rim colour on top of them.
- It renders an XCursor theme at 24, 36, 48 and 72 px. With `hyprcursor-util`
  present it also writes a hyprcursor theme into the same directory, which
  Hyprland draws from the SVGs at any scale.

The result is `$XDG_DATA_HOME/icons/0xide-sweet`, swapped in whole so nothing
reads a half-built theme. It is rebuilt only when the palette or the Sweet
source changes; an unchanged theme change costs about a tenth of a second.

`overrides/caelestia/hypr-vars.lua` points Hyprland at `0xide-sweet` once it
exists, and at `Sweet-cursors` before that. This adapter also sets GTK's
`settings.ini`, gsettings, and `~/.icons/default` when that one inherited
Sweet, then asks Hyprland to reload the cursor. X applications that are already
running keep the cursor they loaded until they restart.

Sweet is GPL-3.0, the same as this project; the recoloured theme is a
derivative built on your machine, and no Sweet files are stored here.
