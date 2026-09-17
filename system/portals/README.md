# system/portals

## hypr-kdeconnect-portal: a local dependency that is not part of this project

**If you have cloned this repository, there is nothing for you to do here.**

- It is **not distributed**. No binary, no source, nothing to install.
- It is **not required**. Nothing in this repository imports it, calls it,
  depends on it, or checks for it.
- Everything here **works without it** - every shell extension, adapter,
  override and system module behaves identically on a machine that has never
  heard of it.
- The only thing its absence costs is **KDE Connect remote input**: driving this
  machine's pointer and keyboard from a phone. Screen sharing, screenshots and
  global shortcuts are unaffected, because those come from
  `xdg-desktop-portal-hyprland`, a normal package.
- If its source is ever recovered, it **belongs in its own repository**, not
  this one. It is a standalone portal backend and has nothing to do with
  theming or with Caelestia Shell.

The rest of this file is the record of what it is and why it could not be
included, kept so the gap is documented rather than silently ignored.

### Why it is written down at all

The machine this project was extracted from runs a D-Bus service that no package
owns and whose source no longer exists. Publishing a repository while quietly
omitting a running, enabled component of the setup would misrepresent it, so it
is described here instead.

| | |
| --- | --- |
| Binary | `~/.local/bin/hypr-kdeconnect-portal`, 171 KB, stripped |
| Build ID | `2ecb7f940f9a909be5dd991a978f243e6d50ba86` |
| Built | 2026-09-13, GCC 16.2.1, Qt (`qt_version_tag` present) |
| Package | none; `pacman -Qo` finds no owner |
| Source | not recoverable; no source path is embedded in the binary |
| Unit | a user systemd unit, enabled, of which a copy is kept beside this file |

### What it does

It implements `org.freedesktop.impl.portal.RemoteDesktop` under the bus name
`org.freedesktop.impl.portal.desktop.hypr_kdeconnect`, creating virtual pointer
and keyboard devices through the Wayland virtual-input protocols. That is what
lets KDE Connect drive this machine's cursor and keyboard from a phone.

### Why it exists

`xdg-desktop-portal-hyprland` 1.4.1 exposes:

    Screenshot, ScreenCast, GlobalShortcuts, InputCapture

and **not** `RemoteDesktop`. The only installed portal that does expose
RemoteDesktop is `kde.portal`, the Plasma backend, which is not usable here.
So the gap this fills is real and upstream has not closed it.

### Status

The binary appears to be locally written: the mangled symbols use an `hkcf::`
namespace, its log strings are first-person about this exact integration, and it
carries a self-test CLI (`--self-test-motion`, `--self-test-scroll-discrete`,
`--self-test-absolute`). It is the same situation as the shell plugin: a locally
built artefact whose source tree is gone.

Unlike the plugin, it cannot responsibly be reconstructed. The plugin's entire
API surface was recorded in machine-readable `.qmltypes` next to it, so
rebuilding it was recovering a known shape. There is no equivalent record here,
and recreating a stripped Wayland/D-Bus program from its binary is a different
activity altogether.

### What to do, if you are the person who lost the source

1. **Check for the source elsewhere** - another machine, a backup, or an
   unpushed branch. If it turns up, it belongs in its own repository, not this
   one.
2. **Until then, treat this as an undocumented binary.** Do not publish it. A
   public repository must not ship a stripped executable no one can rebuild or
   audit.
3. **If it is lost for good**, either keep running the existing binary as a
   known local exception, or drop KDE Connect remote input until
   `xdg-desktop-portal-hyprland` implements RemoteDesktop upstream.

The unit file is kept here, with `%h` in place of the absolute home path, so the
service can be recreated if the binary is ever rebuilt. Installing it is
deliberately not wired into `./install`.
