# orchestration

The glue between Caelestia's theme pipeline and this project's adapters.

```
caelestia scheme set / wallpaper change
        |
        v
  scheme.json                      <- the only palette source
        |
        +-- caelestia's own apply_* steps (GTK, Qt, terminals, hypr, ...)
        |
        v
  theme.postHook  ->  orchestration/hooks/post-theme
                            |
                            +-- adapters/<name>/apply   for each enabled adapter
```

`hooks/post-theme` holds no application knowledge. It reads
`$XDG_CONFIG_HOME/0xide/adapters.enabled`, runs each listed adapter's
`apply`, and records the outcome. Adding an application means adding an adapter
directory, never editing this file.

It always exits 0. A theme change must not appear to fail because one
integration did; failures go to `$XDG_STATE_HOME/0xide/post-theme.log`
and surface through `./install --status`.

`lib/common.sh` derives every path this project uses from XDG variables, so no
script needs to know a username or where the repository is checked out.
