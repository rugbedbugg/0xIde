# system/sudoers

One adapter needs root. Rather than run the whole theme hook under sudo, or
leave a system directory writable, this installs a rule scoped to exactly that
command.

| Rule | Needed by | Writes |
| --- | --- | --- |
| `papirus-folders -C *` | `adapters/papirus` | `/usr/share/icons/Papirus*` |

`install` prints the exact rules, validates them with `visudo -c` **before**
installing, and asks. It is never run by a plain `./install`.

## What this does not cover

Caelestia installs its own equivalent Chrome rules. Those come from
caelestia-cli, not from here, and this project neither installs nor removes them.

## Why the rule is needed at all

`papirus-folders` writes under `/usr/share/icons`. It is called with `sudo -n`
and a failure is discarded, so without a rule the folder icons simply stop
following the scheme with no error anywhere. That silence is what makes the
rule worth having rather than just living without the feature.
