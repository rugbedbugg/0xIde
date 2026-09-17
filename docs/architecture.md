# Architecture

Two independent pipelines. They share a repository and nothing else.

## 1. Theme: Caelestia state reaches applications

```
wallpaper / caelestia scheme set
            |
            v
  ~/.local/state/caelestia/scheme.json        <- the only palette in the system
            |
            +--> caelestia-cli apply_*  ->  GTK, Qt/qtengine, terminals (OSC),
            |                               hypr, fuzzel, btop, htop, nvtop,
            |                               cava, zed, Discord, spicetify colours,
            |                               Chromium policy, Firefox
            |
            +--> theme.postHook
                      |
                      v
            orchestration/hooks/post-theme    <- no application logic lives here
                      |
                      +--> adapters/kde/apply       -> kdeglobals -> Dolphin, Ark
                      |                             -> gtk settings, dconf -> Thunar
                      +--> adapters/spotify/apply   -> spicetify apply -> Spotify
                      +--> adapters/papirus/apply   -> papirus-folders -> icons
                      +--> adapters/edge/apply      -> /etc policy -> Edge
```

Two applications are missing from that list on purpose:

```
  terminals (already themed by caelestia, via OSC escapes)
            |
            +--> yazi      these name ANSI slots, not colours.
            +--> rmpc      No adapter runs. Nothing regenerates.
```

That is the preferred shape. A terminal program that names ANSI slots follows
the scheme with zero moving parts. Reach for a generated theme file only when an
application cannot read the terminal palette.

### The rule this enforces

```
  scheme.json  ->  adapter  ->  application            yes
  scheme.json  ->  our palette  ->  adapter  ->  app   no
```

There is no project-level palette, no intermediate colour file, and no second
transformation. `adapters/kde` is the one adapter that reads another adapter's
output rather than `scheme.json` directly: it derives `kdeglobals` from the
qtengine colours Caelestia already generated, because that is a format
translation rather than a second derivation. It is documented as such in
`adapters/kde/README.md`.

`adapters/papirus` goes further and calls Caelestia's own `sync_papirus_colors`
rather than reimplementing the hue mapping, so it cannot drift.

## 2. Shell: extensions reach Caelestia Shell

```
  upstream caelestia-dots/shell @ shell/upstream.pin
            |
            +-- shell/patches/*.patch          3 patches, 5 upstream files
            +-- shell/plugin/src/*             AiConfig, AiRequest
            +-- shell/plugin/patches/*.patch   4 lines registering them
            +-- shell/extensions/<name>/tree/  files upstream does not have
            |
            v
     shell/build.sh
            |
            +--> cmake build  ->  $XDG_DATA_HOME/caelestia-mod/qml   (plugin)
            +--> QML tree     ->  $XDG_CONFIG_HOME/quickshell/caelestia
```

`$XDG_CONFIG_HOME/quickshell/caelestia` is **build output**. Upstream sanctions
placing a shell copy there, and quickshell prefers it over `/etc/xdg`. Nothing
is edited there; edit the patch or the extension and rebuild.

The plugin is resolved through `QML_IMPORT_PATH`, substituted into `shell.qml`
at build time. No path in this repository names a machine.

## Where a change belongs

| If it is | It goes in |
| --- | --- |
| a value Caelestia has a setting for | `overrides/` |
| behaviour Caelestia Shell does not have | `shell/extensions/` |
| a shape upstream QML has to change for | `shell/patches/` (justify it) |
| translating the scheme for one app | `adapters/<app>/` |
| deciding which adapters run | `orchestration/` |
| needing root, or writing outside `$HOME` | `system/` |
| produced by running any of the above | nowhere; see `docs/generated.md` |
