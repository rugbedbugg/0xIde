# yazi adapter

Yazi's theme here names **ANSI slots** (`blue`, `bright_black`, ...) and never a
hex colour. Caelestia already pushes its palette into every terminal as OSC
escape sequences, so a slot-named theme follows the scheme with no template, no
regeneration step, and no hook. Change the wallpaper and Yazi is already right.

This is the pattern to prefer for any terminal program. The alternative - a
generated theme file per app - adds a file Caelestia has to rewrite and this
project has to keep in sync, for the same result.

`y.fish` is upstream Yazi's own cd-on-exit wrapper, using `--cwd-file`.

## Checking it

`./adapters/yazi/status` fails if any hex colour appears in the config, which is
the only way this can silently stop tracking the scheme.
