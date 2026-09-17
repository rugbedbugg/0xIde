# Security and privacy

Everything in this project that leaves `$HOME`, needs root, or sends data
anywhere. Nothing here happens during a plain `./install`.

## Screenshot uploads

`shell/extensions/search` turns a selected screen region into a web search.
There is no way to do image search without sending the image to someone, so the
mode that does is not the default and never runs silently.

| Mode | What leaves the machine | Default |
| --- | --- | --- |
| `text` | nothing. The region is OCR'd locally and the **text** is searched | yes |
| `host-upload` | the image, to a public file host, then its URL to Google Lens | no |
| `off` | nothing | no |

Configured in `$XDG_CONFIG_HOME/caelestia-mod/region-search.conf`.

`host-upload` is worth understanding before enabling. The image is uploaded to a
public file host and Google Lens is handed the resulting URL. That URL is
public and unauthenticated for as long as the host keeps the file - by default
one hour with litterbox, indefinitely with some alternatives. Anyone who
circles a password manager, a private document, or a message thread publishes
it. The adapter asks for confirmation naming the host every time, unless you set
`confirm="never"`.

**This replaces the original behaviour, which uploaded unconditionally with no
prompt.** If you are migrating from that, the default is now `text` and you will
notice the difference.

### On avoiding the upload entirely

Google Lens has an undocumented direct-upload endpoint that would send the image
to Google and to nobody else, which is strictly better than an intermediate
public host. It is not implemented here: it is undocumented, unversioned, and
shipping an unverified network path as a selectable option is worse than not
offering it. `text` mode is the actually-upload-free option and is the default.

## The AI backend

Local by default. `backend = "managed"` runs BitNet on `127.0.0.1` and no
request leaves the machine. `backend = "external"` sends the selected text to
whatever URL you configure, which may be remote; the OCR popup shows the
destination above the submit button at all times.

The model is not in this repository. `manifests/ai.toml` pins its revision and
SHA-256; `runtime.py` fetches and verifies it, only when you ask.

## Root

| What | Why | Where |
| --- | --- | --- |
| `NOPASSWD` for `papirus-folders -C *` | it writes under `/usr/share/icons`; Caelestia calls it on every theme change and fails silently without this | `system/sudoers` |
| `NOPASSWD` for one `mkdir` and one `tee` under `/etc/opt/edge/policies/managed` | Edge reads its theme colour from a managed policy file | `system/sudoers` |
| writes under `/usr/share/sddm/themes/corners` | login screen colours | `system/sddm` |

`system/sudoers/install` prints the exact rules, validates them with
`visudo -c` before installing, and asks. Both rules are scoped to a single
command with a fixed target path.

Caelestia installs its own equivalent Chrome rules. Those are not from here and
this project neither installs nor removes them.

## Standing weaknesses on this machine that this project will not reproduce

Two changes exist on the machine this repository was extracted from. Neither
came from this repository, and `./install` will not recreate either.

### `/opt/spotify` is world-writable

`spicetify` needs write access to the Spotify installation, and the usual
workaround is `chmod -R a+wr /opt/spotify`. That leaves an executable directory
writable by every local process for the lifetime of the install. `system/spotify`
documents three better options and the commands to undo it.

### The SDDM theme directory is group-owned by the login user

`/usr/share/sddm/themes/corners` was chowned so the sync could write to it
without prompting. That leaves a system directory group-writable permanently.
`system/sddm/install` prints the command but will not run it; by default the
sync escalates per write instead, and simply does nothing if it cannot.

## An unexplained binary

`~/.local/bin/hypr-kdeconnect-portal` is a stripped, unpackaged ELF running as an
enabled user D-Bus service. It implements the RemoteDesktop portal that
`xdg-desktop-portal-hyprland` does not, so KDE Connect can drive this machine's
input. Its source is not on this machine.

It is **not** in this repository and must not be published from it. See
`system/portals/README.md` for the full record.

## What was checked and found clean

No API key, token, bearer credential, or private key appears in any file this
repository tracks. The AI is local, so there is no inference credential to leak.
`tests/run` fails the build if a username, hostname, or absolute home path
appears in a tracked file outside `docs/`.
