# system/sudoers

One adapter needs root. Rather than run the whole theme hook under sudo, leave
a system directory writable, or grant a general-purpose tool, this installs a
fixed helper and a rule for that helper alone.

| Rule | Needed by | Writes |
| --- | --- | --- |
| `/usr/local/libexec/0xide-papirus-folders` | `adapters/papirus` | `/usr/share/icons/Papirus/` folder links and icon cache |

The helper (`0xide-papirus-folders`, installed root:root 0755) takes exactly one
argument, a colour name, and refuses anything else before reading sudo's
metadata. It accepts only colours `papirus-folders -l` lists for the system
`Papirus` theme, checks that `SUDO_USER` and `SUDO_UID` agree and are not root,
and runs `papirus-folders -C <colour> --theme Papirus -u` with a fixed
environment. The caller chooses nothing else: no theme, directory or option.

A rule for `papirus-folders` itself, which earlier versions installed, was wider
than that: it also accepts `--theme <directory>` and then makes symlinks and an
icon cache in that directory as root. `install` replaces it in the same file.

`install` prints the exact changes, validates the rule with `visudo -c`
**before** installing anything, and asks. It is never run by a plain `./install`.
`remove` takes back the rule and the helper.

## What this does not cover

Caelestia installs its own equivalent Chrome rules. Those come from
caelestia-cli, not from here, and this project neither installs nor removes them.

## Why the rule is needed at all

`papirus-folders` writes under `/usr/share/icons`. Without the helper the folder
icons do not follow the scheme; `adapters/papirus/status` and the theme log say
so, rather than reporting success.
