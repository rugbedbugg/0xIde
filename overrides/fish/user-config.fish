# Caelestia's supported fish extension point. config.fish sources this at the
# end of its interactive block, so nothing in the dots-managed config.fish
# needs editing.

# Toolchains managed by mise (Node, Java, Go). A no-op where mise is absent.
if test -x $HOME/.local/bin/mise
    $HOME/.local/bin/mise activate fish | source
end

# Keep ~/.local/bin ahead of system paths for locally installed tools.
if not contains $HOME/.local/bin $PATH
    set -gx PATH $HOME/.local/bin $PATH
end
