# system/spotify

There is nothing to install here. This directory exists to document a
system-level change this project deliberately does **not** make.

`spicetify` rewrites files inside the Spotify installation. Where Spotify is
installed from a distribution package into `/opt/spotify`, that directory is
root-owned, and the common workaround is:

    sudo chmod -R a+wr /opt/spotify

That leaves an executable directory world-writable for the lifetime of the
install: any local process can replace the Spotify binary or its JavaScript
bundle. This machine currently has that change applied. It did not come from
this repository and this repository will not reproduce it.

## Better options, in order

1. **Install Spotify per-user.** A Flatpak or a `~/.local` install puts the
   files under your own ownership and needs no permission change at all.
   `spicetify config spotify_path` points spicetify at it.
2. **Group ownership instead of world-writable.** `chown -R root:$(id -gn)
   /opt/spotify && chmod -R g+w /opt/spotify` narrows the exposure from every
   local process to your own login group.
3. **Re-apply under sudo on demand.** Keep the directory root-owned and run
   `sudo spicetify apply` manually after a theme change. The `spotify` adapter's
   automatic re-apply stops working; everything else still does.

To undo the world-writable change on this machine:

    sudo chown -R root:root /opt/spotify
    sudo chmod -R go-w /opt/spotify

after which option 1 or 3 applies. See `docs/security.md`.
