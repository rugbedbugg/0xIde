# spotify adapter

Two separate things, deliberately split:

- `install` places `user.css`, the Caelestia theme's **layout and shape** rules,
  taken from the Caelestia dots. It is the file the dots deploy when their
  `spicetify` component is enabled; this places it without enabling that.
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

`spicetify apply` rewrites files inside the Spotify installation. Where Spotify
comes from a distribution package in `/opt/spotify`, that directory is
root-owned, and the widely repeated workaround is `sudo chmod -R a+wr
/opt/spotify`. That leaves an executable directory world-writable for the
lifetime of the install: any local process can replace the Spotify binary or its
JavaScript bundle.

**This repository will not make that change, and does not need it made.** Better
options, in order:

1. **Install Spotify per-user.** A Flatpak or a `~/.local` install is already
   owned by you and needs no permission change. Point spicetify at it with
   `spicetify config spotify_path`.
2. **Group ownership instead of world-writable.**
   `sudo chown -R root:$(id -gn) /opt/spotify && sudo chmod -R g+w /opt/spotify`
   narrows the exposure from every local process to your own login group.
3. **Re-apply under sudo on demand.** Keep the directory root-owned and run
   `sudo spicetify apply` after a theme change. This adapter's automatic
   re-apply stops working; nothing else does.

To undo the world-writable change if it has already been applied:

    sudo chown -R root:root /opt/spotify
    sudo chmod -R go-w /opt/spotify
