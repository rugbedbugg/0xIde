# system/lid

What closing the lid does is systemd-logind's to decide, so Nexus's Power page
sets it there: it holds while the shell is stopped or restarting. Changing
logind's configuration needs root, so this installs a fixed helper and a rule
for that helper alone. It is never run by a plain `./install`.

| Rule | Needed by | Writes |
| --- | --- | --- |
| `/usr/local/libexec/0xide-logind-lid` | Nexus → Power → Lid | `/etc/systemd/logind.conf.d/80-0xide-lid.conf` |

The helper is `shell/extensions/power/tree/assets/power/logind_lid.py`, the same
file the shell reads the lid setting with, installed root:root 0755. Run through
sudo it takes `set <undocked> <docked>` or `reset`, and refuses anything else
before it reads the system:

- `<undocked>` and `<docked>` are each `suspend`, `ignore`, `lock` or
  `hibernate`; `hibernate` only when logind's `CanHibernate` says `yes`.
- `set` writes `HandleLidSwitch` and `HandleLidSwitchExternalPower` (both
  `<undocked>`, so a charger changes nothing) and `HandleLidSwitchDocked`, and
  nothing else, to its own drop-in. `/etc/systemd/logind.conf` and every other
  drop-in are left as they are.
- It refuses when a drop-in applied after its own (by name, across
  `/etc`, `/run`, `/usr/local/lib` and `/usr/lib`) sets a lid key, since that
  one would win; it names the file. One applied before is overridden, and kept.
- It reloads logind with `systemctl reload systemd-logind`. The unit is
  `notify-reload`: logind reads its configuration again on SIGHUP and the
  sessions keep running. It is never restarted, which would end the graphical
  session.
- It then reads the three settings back from logind over D-Bus. A failed
  reload, or a logind not acting on the new values, puts the previous file back
  (or removes the new one) and reloads again; the answer says what happened.
- It runs only with sudo's metadata agreeing that an ordinary user called it,
  under `python3 -I` and a fixed `PATH`, and calls only `/usr/bin/systemctl`
  and `/usr/bin/busctl`.

Unprivileged, `logind_lid.py status` reports what logind acts on now, the
drop-in, other drop-ins that override it or that it overrides, `handle-lid-switch`
inhibitors, hibernate support, and whether the helper is installed, current and
allowed. `./install --status` reports the same.

Lock screen locks through logind: it asks every session to lock, and the
Caelestia shell locks when its session is asked (its `SessionManager` listens for
logind's `Lock`). Running `loginctl lock-session` shows the same.

`install` prints the exact changes, validates the rule with `visudo -c`
**before** installing anything, and asks; installing changes no lid setting.
`remove` resets the lid first, while the helper is there to do it, then takes
back the rule and the helper.

The tests run the real helper on a private root where
`tests/fixtures/fake-logind` stands in for systemctl, busctl and sudo, so no lid
event, suspend, hibernate or reload of the real logind can happen.
