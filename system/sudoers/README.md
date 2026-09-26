# system/sudoers

Two adapters need root for one path each. Rather than run the whole theme hook
under sudo, or leave a system directory writable, this installs a rule scoped to
exactly those commands.

| Rule | Needed by | Writes |
| --- | --- | --- |
| `papirus-folders -C *` | `adapters/papirus` (and Caelestia's own call) | `/usr/share/icons/Papirus*` |
| `mkdir -p`, `tee` on one path | `adapters/edge` | `/etc/opt/edge/policies/managed/0xide.json` |

`install` prints the exact rules, validates them with `visudo -c` **before**
installing, and asks. It is never run by a plain `./install`.

## What this does not cover

Caelestia installs its own equivalent Chrome rules. Those come from
caelestia-cli, not from here, and this project neither installs nor removes them.

## Why the rule is needed at all

`papirus-folders` writes under `/usr/share/icons`. Caelestia calls it with
`sudo -n` and discards the failure, so without a rule the folder icons simply
stop following the scheme with no error anywhere. That silence is what makes the
rule worth having rather than just living without the feature.
