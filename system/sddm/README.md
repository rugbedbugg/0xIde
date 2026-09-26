# system/sddm

A Caelestia login screen for SDDM, kept in step with the desktop: the same
scheme, wallpaper and profile picture, updated on every theme change.

`theme/` builds it from the shell's `modules/lock` at the pinned revision and
Caelestia's own design tokens, colours and motion. One column sits centred over
the wallpaper: the lockscreen's condensed two-colour clock and date, then the
account field, then the lockscreen's password pill, whose characters arrive as
Material 3 shapes and settle into circles. The account field is the shell's filled
text field, holding a user name over an underline with that account's picture
beside it: type any name, or
open the chevron (or press Down) to pick from the accounts SDDM lists. It
starts on the last user, and Tab moves between it and the password. Two
buttons in the bottom-left corner open the power actions and the session to
start, in the shell's menu style; a power action SDDM cannot perform right now
is shown greyed out (in `preview`, with no daemon to ask, that is all of
them). With a menu open, the arrow keys, Tab, Enter and Escape work it. Only the primary screen has the form; the others show the
wallpaper, clock and date.

Surfaces are solid, as the shell draws them with transparency off:
`solidSurfaces=true` in `theme/theme.conf` is the greeter's own choice. Set it
to `false` to follow `appearance.transparency` instead, when the pill, field,
chip and buttons take the desktop panels' translucent colours (from that
setting and the wallpaper's brightness) over the wallpaper blurred as Hyprland
blurs behind them.

It needs SDDM's Qt 6 greeter. Shape morphing comes from `qt6-m3shapes-git`,
which `caelestia-shell` already depends on; without it, rounded squares stand
in and animate their corners. Google Sans Flex, which the Caelestia dots place
in the user's font directory, is copied into the theme at install time; Rubik
stands in without it.

## Installing

```sh
./install --enable sddm     # or: system/sddm/install
system/sddm/remove          # reverses it
```

The installer prints every change and asks once. It installs:

| Path | What |
| --- | --- |
| `/usr/share/sddm/themes/caelestia/` | the theme, root-owned, from `theme/` |
| `/usr/local/libexec/caelestia-sddm-sync` | the fixed helper, from `caelestia-sddm-sync` |
| `/etc/sudoers.d/caelestia-sddm` | `NOPASSWD` for that helper alone, for the user who ran the installer |
| `/etc/sddm.conf.d/zz-caelestia.conf` | `Current=caelestia`; SDDM reads it after other drop-ins |

Removing the drop-in restores whichever theme was chosen before. Re-run the
installer after changing the theme's QML.

## How it stays in step

```text
caelestia scheme/wallpaper change
  -> orchestration/hooks/post-theme
       -> system/sddm/sync                 as you, no privileges
            ~/.local/state/caelestia/sddm/
              theme.conf.user              palette, mode, clock format, transparency
              wallpaper.{png,jpg}          named by its bytes
              avatar.{png,jpg}             from ~/.face
       -> sudo -n caelestia-sddm-sync      no arguments, no environment
            theme.conf.user                re-written from what parses
            backgrounds/caelestia_wallpaper.{png,jpg}
            faces/<you>
```

The greeter runs as `sddm` and cannot read home directories, which is why the
wallpaper and picture are handed over rather than referenced.

The helper takes nothing from its caller but sudo's own `SUDO_USER` and
`SUDO_UID`, checked against each other. It reads fixed file names from a fixed
directory under that user's home, refuses anything that is not a regular file
owned by them, and decides image types from the bytes. It parses
`theme.conf.user` strictly (every key one the theme reads, every value of that
key's shape) and installs its own canonical copy of the result, so nothing the
greeter might read differently gets through. It writes only inside the theme
directory, only into root-owned directories, atomically.

## Testing without logging out

```sh
system/sddm/preview    # this checkout's theme, with the current wallpaper and picture
sddm-greeter-qt6 --test-mode --theme /usr/share/sddm/themes/caelestia    # what is installed
```

`preview` needs nothing installed: `sync` writes its state whether or not the
theme is there, and only hands it over once it is.
