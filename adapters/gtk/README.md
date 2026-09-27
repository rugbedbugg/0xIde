# gtk adapter

Caelestia colours GTK by writing its palette into the user stylesheet,
`~/.config/gtk-3.0/gtk.css`. GTK reads that file once, when an application
starts, and never again. Every GTK3 window that is already open keeps the old
colours until it is restarted: Microsoft Edge or Chrome in their GTK appearance,
Thunar, file pickers.

GTK does reload the *theme* when the theme name changes. So this adapter:

- renders Caelestia's own `gtk.css` and `thunar.css` templates with the scheme,
  so the colours are exactly what Caelestia's GTK step would have produced;
- writes them into a theme that imports `adw-gtk3` or `adw-gtk3-dark`, matching
  the scheme's mode, under `$XDG_DATA_HOME/themes`;
- alternates that theme between `0xide-a` and `0xide-b`, so every palette change
  is a real theme switch. dconf carries it through the settings portal to open
  windows, which redraw at once. An unchanged palette switches nothing.

For that to work the user stylesheet must stop defining colours, since a colour
defined there overrides the theme's in every application that read it at
startup. `overrides/caelestia/cli.json` therefore turns Caelestia's GTK step
off (`"enableGtk": false`), and this adapter does the rest of what that step
did: the GTK4 and libadwaita stylesheet, Thunar's, `color-scheme`, and the icon
theme, honouring `iconTheme`, `iconThemeLight` and `iconThemeDark` from
`cli.json`. Papirus folder colours are the papirus adapter's.

GTK4 and libadwaita ignore themes entirely, so those applications still read the
palette from `~/.config/gtk-4.0/gtk.css` and change on their next start, as they
did before.

If you turn this adapter off, remove `"enableGtk": false` from
`$XDG_CONFIG_HOME/caelestia/cli.json` too, or GTK stops following the scheme.
