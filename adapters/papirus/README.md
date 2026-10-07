# papirus adapter

Caelestia calls `papirus-folders` from its GTK theming step, which the gtk
adapter replaces, so the recolouring is done here instead. It needs root to
write into `/usr/share/icons`.

Root comes only through the fixed helper `system/sudoers` installs
(`/usr/local/libexec/0xide-papirus-folders`), which takes a colour name and
nothing else. Without it, `apply` exits 3 with the reason, the theme log says
`papirus not applied`, and `status` says the folders will not follow the scheme.

The colour mapping is Caelestia's `sync_papirus_colors`, run with its subprocess
calls captured rather than reimplemented, so this can never drift from what
Caelestia would have chosen. If Caelestia's call ever changes shape, `apply`
fails and says so instead of guessing.

`apply` records what it did in `$XDG_STATE_HOME/0xide/papirus.result`, which
`status` reads: applied, unavailable (and why), or failed (and why).

`papirus-folders` hardcodes `sizes=(22x22 24x24 32x32 48x48 64x64)` and
deliberately leaves out `16x16`, so the smallest folder icons keep the stock
colour. That is upstream behaviour, not a bug here.
