# system/portals

## hypr-kdeconnect-portal: an unresolved dependency

This desktop runs a D-Bus service that **is not in this repository and should
not be installed from it**. It is documented here because it is running, it is
enabled, and nothing else on the system explains it.

| | |
| --- | --- |
| Binary | `~/.local/bin/hypr-kdeconnect-portal`, 171 KB, stripped |
| Build ID | `2ecb7f940f9a909be5dd991a978f243e6d50ba86` |
| Built | 2026-09-13, GCC 16.2.1, Qt (`qt_version_tag` present) |
| Package | none; `pacman -Qo` finds no owner |
| Source | not on this machine, and no source path is embedded in the binary |
| Unit | `~/.local/share/systemd/user/hypr-kdeconnect-portal.service`, enabled and active |

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

### What to do

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
