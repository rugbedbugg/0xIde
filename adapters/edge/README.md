# edge adapter

Caelestia themes Chromium through a managed policy file. Edge reads the same
kind of file from its own directory, so this does the same thing one path over.

**This adapter needs root.** It writes `/etc/opt/edge/policies/managed/0xide.json`.
`system/sudoers` installs a rule scoped to that one file and nothing else; without
it the adapter exits quietly rather than prompting for a password during a theme
change. See `system/sudoers/README.md`.

Set `OX_EDGE_BINARY` in `config.local` for a different Edge channel
(`microsoft-edge-stable`, `microsoft-edge-beta`).
