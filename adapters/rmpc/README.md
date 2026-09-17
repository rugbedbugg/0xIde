# rmpc adapter

Same approach as the `yazi` adapter: the theme names ANSI slots, so it follows
Caelestia's terminal palette with nothing to regenerate.

Two things worth knowing about rmpc specifically:

- It uses **ratatui** colour names, not terminal-conventional ones.
  `dark_gray` is valid; `bright_black` is not. rmpc rejects an unknown name with
  `Invalid color format` and then falls back to its own defaults *silently*, so a
  typo looks like "the theme did not load" rather than an error.
- Testing it in a fresh terminal needs the palette replayed first. `foot rmpc`
  runs rmpc instead of the shell, so `config.fish` never replays
  `sequences.txt` and rmpc renders against stock terminal colours. Use
  Caelestia's own pattern instead:

      foot fish -C "exec rmpc"
