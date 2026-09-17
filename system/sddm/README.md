# system/sddm

Regenerates the `corners` SDDM theme's colours and background from the current
Caelestia scheme, so the login screen matches the desktop.

**This writes into `/usr/share/sddm/themes/corners`, which the theme's package
owns.** Two consequences worth stating plainly:

- A package update to the theme overwrites what this wrote. Re-run the sync.
- Something has to be allowed to write there. On this machine that was arranged
  by chowning the directory to the login user's group, which leaves a system
  directory group-writable permanently. This installer will not do that. It
  prints the command so the decision, and the responsibility, stays with you.

`sync` falls back to `sudo -n tee` when it cannot write directly, so with a
root-owned directory and no sudoers rule it simply does nothing rather than
blocking a wallpaper change on a password prompt.

The font name written into `theme.conf` is the Caelestia sans face; see
`assets/fonts`.
