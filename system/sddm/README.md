# system/sddm

The Caelestia lockscreen as the SDDM login screen, kept in step with the
desktop: the same scheme, wallpaper and profile picture, updated on every
theme change.

`theme/` is a port of the shell's `modules/lock` at the pinned revision: the
lock tile that spins in over the blurred wallpaper and opens into the panel,
the condensed two-colour clock, the ClamShell profile picture, and the
password field whose characters arrive as Material 3 shapes and settle into
circles. The side columns hold what a greeter needs instead of what a
lockscreen shows: the machine and the session to start on the left, the power
actions and the accounts on the right. Only the primary screen has a password
field; the others show the wallpaper and the lock tile.

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
              theme.conf.user              palette, mode, clock format, OS name
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
sddm-greeter-qt6 --test-mode --theme /usr/share/sddm/themes/caelestia
```
