# spotify adapter

Two separate things, deliberately split:

- `install` places `user.css`, the Caelestia theme's **layout and shape** rules,
  taken from the Caelestia dots. This is the file the dots would deploy if the
  `spicetify` component were enabled, which it is not on this machine.
- `apply` runs `spicetify apply` after a theme change. Caelestia rewrites
  `color.ini` itself but never re-applies, so without this Spotify keeps the old
  palette until something else triggers an apply.

`color.ini` is **not** in this repository. caelestia-cli owns it and regenerates
it from `scheme.json`; copying it here would create a second palette source.

## user.css divergence from upstream dots

Two selector chains use descendant combinators where upstream uses `>`.
Spotify's DOM gained wrapper elements that broke the direct-child chains, which
showed up as a 12px scrollbar where the theme intends 4px. Everything else is
byte-identical to the dots.

## Privilege note

`spicetify apply` rewrites files inside the Spotify installation. On this
machine that was made possible by making `/opt/spotify` user-writable, which is
a standing weakening of a system directory. `system/spotify` documents the
safer alternatives and this repo never performs that change itself. See
`docs/security.md`.
