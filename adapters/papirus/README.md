# papirus adapter

Caelestia already calls `papirus-folders` from its GTK theming step. It needs
root to write into `/usr/share/icons`, and when that fails it fails silently, so
the folder icons simply stop tracking the scheme.

The fix is a sudoers rule scoped to `papirus-folders` alone, installed by
`system/sudoers`. With it in place Caelestia's own call succeeds and this
adapter is only a manual fallback and a status check.

The colour mapping is Caelestia's `sync_papirus_colors`, called directly rather
than reimplemented, so this can never drift from what Caelestia would have done.

`papirus-folders` hardcodes `sizes=(22x22 24x24 32x32 48x48 64x64)` and
deliberately leaves out `16x16`, so the smallest folder icons keep the stock
colour. That is upstream behaviour, not a bug here.
