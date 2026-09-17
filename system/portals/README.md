# system/portals

## hypr-kdeconnect-portal: a local dependency that is not distributed

**If you have cloned this repository, there is nothing for you to do here.**

- It is **not distributed**. No binary, no source, nothing to install.
- It is **not required**. Nothing in this repository imports it, calls it,
  depends on it, or checks for it.
- Everything here **works without it**. Every shell extension, adapter, override
  and system module behaves identically on a machine that has never heard of it.
- The only thing its absence costs is **KDE Connect remote input**: driving this
  machine's pointer and keyboard from a phone. Screen sharing, screenshots and
  global shortcuts are unaffected, because those come from
  `xdg-desktop-portal-hyprland`, a normal package.

This file exists so that a component of the setup this project was extracted
from is disclosed rather than quietly omitted.

### What it is

A user D-Bus service implementing `org.freedesktop.impl.portal.RemoteDesktop`
under the bus name `org.freedesktop.impl.portal.desktop.hypr_kdeconnect`, which
creates virtual pointer and keyboard devices through the Wayland virtual-input
protocols.

It exists because `xdg-desktop-portal-hyprland` 1.4.1 exposes `Screenshot`,
`ScreenCast`, `GlobalShortcuts` and `InputCapture`, and **not** `RemoteDesktop`.
The only installed portal that does expose RemoteDesktop is the Plasma backend,
which is not usable here. The gap is real and upstream has not closed it.

### Why it is not included

It exists only as a locally built, stripped binary that no package owns and
whose source tree is gone. It appears to have been written locally: its mangled
symbols use an `hkcf::` namespace, its log strings are first-person about this
exact integration, and it carries a self-test CLI.

It cannot responsibly be reconstructed the way `shell/plugin` was. That
reconstruction worked because Qt had recorded the plugin's entire public
interface in `.qmltypes` next to the binary. There is no equivalent record here,
and recreating a stripped Wayland/D-Bus program from its binary is a different
activity altogether.

A public repository must not ship a stripped executable nobody can rebuild or
audit, so it is not shipped. If the source is ever recovered it belongs in its
own repository: it is a standalone portal backend with nothing to do with
theming or with Caelestia Shell.

The systemd user unit is kept beside this file, with `%h` in place of the home
path, so the service can be recreated if the binary is ever rebuilt. Installing
it is deliberately not wired into `./install`.
