#!/usr/bin/python3 -I
"""
What closing the lid does, through systemd-logind, for Nexus's Power page.

Unprivileged it only reads:

    logind_lid.py status

Installed by system/lid as /usr/local/libexec/0xide-logind-lid (root:root
0755) and run through sudo, it also writes, and only this:

    sudo -n /usr/local/libexec/0xide-logind-lid set <undocked> <docked>
    sudo -n /usr/local/libexec/0xide-logind-lid reset

<undocked> and <docked> are each suspend, ignore, lock or hibernate, and
hibernate only where logind says it can. `set` writes one drop-in of its own,
/etc/systemd/logind.conf.d/80-0xide-lid.conf, with HandleLidSwitch and
HandleLidSwitchExternalPower (both <undocked>, so charger and battery behave
alike) and HandleLidSwitchDocked. It reloads logind in place, which keeps every
session running, then reads the three values back from logind; if any of that
fails, the previous file is put back. `reset` removes the drop-in. No other
logind setting or file is written. Every answer is one JSON line on stdout.
"""

import json
import os
import pwd
import subprocess
import sys
import time
from pathlib import Path

DROPIN_NAME = "80-0xide-lid.conf"
DROPIN_DIR = "/etc/systemd/logind.conf.d"
# Where logind reads drop-ins, highest priority first: a file of the same name
# in an earlier directory hides the later one.
CONF_DIRS = (DROPIN_DIR, "/run/systemd/logind.conf.d", "/usr/local/lib/systemd/logind.conf.d",
             "/usr/lib/systemd/logind.conf.d")
HELPER = "/usr/local/libexec/0xide-logind-lid"
SYSTEMCTL = "/usr/bin/systemctl"
BUSCTL = "/usr/bin/busctl"
SUDO = "/usr/bin/sudo"
ACTIONS = ("suspend", "ignore", "lock", "hibernate")
KEYS = ("HandleLidSwitch", "HandleLidSwitchExternalPower", "HandleLidSwitchDocked")
ENV = {"PATH": "/usr/bin:/bin", "LANG": "C.UTF-8"}
LOGIN1 = ("org.freedesktop.login1", "/org/freedesktop/login1", "org.freedesktop.login1.Manager")

# The tests run this unprivileged over a private root with stand-ins for
# systemctl, busctl and sudo. Never as root: sudo drops the variable anyway,
# and a root run ignores it.
TEST_ROOT = os.environ.get("OX_LID_TEST_ROOT") if os.geteuid() != 0 else None


def path(p: str) -> Path:
    return Path(TEST_ROOT + p) if TEST_ROOT else Path(p)


def answer(**data) -> None:
    print(json.dumps(data), flush=True)


def refuse(error: str, code: int, **data) -> int:
    answer(ok=False, error=error, **data)
    return code


def run(argv: list[str]) -> subprocess.CompletedProcess:
    argv = [str(path(argv[0])), *argv[1:]]
    return subprocess.run(argv, env=ENV, stdin=subprocess.DEVNULL, capture_output=True, text=True, check=False,
                          timeout=30)


def busctl(*args: str):
    """The data of busctl --json=short, or None when logind did not answer."""
    out = run([BUSCTL, "--system", "--json=short", *args])
    if out.returncode != 0:
        return None
    try:
        return json.loads(out.stdout)["data"]
    except (ValueError, KeyError, TypeError):
        return None


def effective() -> dict | None:
    """The lid settings logind is acting on now, whatever file set them."""
    values = {}
    for key in KEYS:
        value = busctl("get-property", *LOGIN1, key)
        if not isinstance(value, str):
            return None
        values[key] = value
    return values


def can(method: str) -> str:
    value = busctl("call", *LOGIN1, method)
    return value[0] if isinstance(value, list) and value and isinstance(value[0], str) else "unknown"


def lid_inhibitors() -> list[dict]:
    """Low-level handle-lid-switch locks, which stop logind acting on the lid
    whatever it is set to; sleep and shutdown locks do not."""
    rows = busctl("call", *LOGIN1, "ListInhibitors")
    found = []
    for row in (rows[0] if isinstance(rows, list) and rows else []):
        if isinstance(row, list) and len(row) >= 4 and "handle-lid-switch" in str(row[0]).split(":"):
            found.append({"who": row[1], "why": row[2], "mode": row[3]})
    return found


def lid_keys(file: Path) -> dict:
    """The lid keys a logind configuration file sets in its [Login] section."""
    found, section = {}, None
    try:
        text = file.read_text()
    except OSError:
        return found
    for raw in text.splitlines():
        line = raw.strip()
        if not line or line[0] in "#;":
            continue
        if line.startswith("["):
            section = line
            continue
        key, sep, value = line.partition("=")
        if sep and section == "[Login]" and key.strip() in KEYS:
            found[key.strip()] = value.strip()
    return found


def dropins() -> list[tuple[str, Path]]:
    """Every drop-in logind reads, in the order it applies them."""
    chosen = {}
    for d in CONF_DIRS:
        try:
            names = sorted(e.name for e in path(d).iterdir() if e.name.endswith(".conf"))
        except OSError:
            continue
        for name in names:
            chosen.setdefault(name, path(d) / name)
    return sorted(chosen.items())


def others() -> tuple[list[dict], list[dict]]:
    """Other drop-ins that set lid keys: those applied after this one, which
    override it, and those before, which it overrides."""
    later, earlier = [], []
    for name, file in dropins():
        if name == DROPIN_NAME:
            continue
        keys = lid_keys(file)
        if keys:
            entry = {"file": str(file).removeprefix(TEST_ROOT or ""), "keys": keys}
            (later if name > DROPIN_NAME else earlier).append(entry)
    return later, earlier


def ours() -> Path:
    return path(DROPIN_DIR) / DROPIN_NAME


def content(undocked: str, docked: str) -> str:
    return ("# Written by 0xIde from Nexus Settings → Power. Removed by: 0xide-logind-lid reset\n"
            "[Login]\n"
            f"HandleLidSwitch={undocked}\n"
            f"HandleLidSwitchExternalPower={undocked}\n"
            f"HandleLidSwitchDocked={docked}\n")


def put(text: str | None) -> None:
    """The drop-in as text, or gone for None; never half-written."""
    target = ours()
    if text is None:
        target.unlink(missing_ok=True)
        return
    target.parent.mkdir(mode=0o755, parents=True, exist_ok=True)
    tmp = target.with_name(f".{DROPIN_NAME}.{os.getpid()}")
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o644)
    try:
        os.write(fd, text.encode())
        os.fsync(fd)
    finally:
        os.close(fd)
    os.replace(tmp, target)
    dirfd = os.open(target.parent, os.O_RDONLY)
    try:
        os.fsync(dirfd)
    finally:
        os.close(dirfd)


def reload() -> str | None:
    """Reloads logind in place (its unit is notify-reload: SIGHUP, and the
    reload returns once logind has read its configuration again). Never a
    restart, which would end the graphical session. The error, or None."""
    out = run([SYSTEMCTL, "reload", "systemd-logind.service"])
    return None if out.returncode == 0 else (out.stderr.strip() or f"systemctl reload exited {out.returncode}")


def settled(expected: dict) -> bool:
    for _ in range(10):
        if effective() == expected:
            return True
        time.sleep(0.2)
    return False


def caller() -> str | None:
    """The user sudo ran this for, when sudo's own metadata agrees with itself."""
    name, uid = os.environ.get("SUDO_USER"), os.environ.get("SUDO_UID")
    if not name or not uid or not uid.isdigit() or int(uid) == 0:
        return None
    try:
        return name if pwd.getpwnam(name).pw_uid == int(uid) else None
    except KeyError:
        return None


def privileged() -> str | None:
    """Why this may not write, or None."""
    if TEST_ROOT:
        return None
    if os.geteuid() != 0:
        return "must be run through sudo"
    if caller() is None:
        return "not invoked through sudo by an ordinary user"
    return None


def restore(previous: str | None) -> str:
    """Puts the previous drop-in back and reloads; says how that went."""
    try:
        put(previous)
    except OSError as error:
        return f"the previous setting could not be put back: {error}"
    failed = reload()
    return f"the previous setting is back in the file, but logind did not reload: {failed}" if failed else \
        "the previous setting is back"


def apply(text: str | None, expected: dict | None) -> int:
    """Writes the drop-in (or removes it, for None), reloads, and checks what
    logind acts on; any failure restores what was there."""
    target = ours()
    try:
        previous = target.read_text() if target.exists() else None
    except OSError as error:
        return refuse(f"cannot read {DROPIN_DIR}/{DROPIN_NAME}: {error}", 1)
    if previous == text and (expected is None or effective() == expected):
        answer(ok=True, changed=False, **(status_fields()))
        return 0
    try:
        put(text)
    except OSError as error:
        return refuse(f"cannot write {DROPIN_DIR}/{DROPIN_NAME}: {error}", 1)
    failed = reload()
    if failed is None and expected is not None and not settled(expected):
        failed = "logind reloaded but is not acting on the new setting"
    if failed:
        return refuse(f"{failed}; {restore(previous)}", 1)
    answer(ok=True, changed=True, **(status_fields()))
    return 0


def status_fields() -> dict:
    later, earlier = others()
    now = effective()
    mine = lid_keys(ours())
    helper = path(HELPER)
    try:
        current = helper.read_bytes() == Path(__file__).read_bytes()
    except OSError:
        current = False
    allowed = helper.is_file() and run([SUDO, "-n", "-l", HELPER]).returncode == 0
    return {
        "undocked": now["HandleLidSwitch"] if now else None,
        # Empty when unset: logind then uses HandleLidSwitch on a charger too.
        "externalPower": now["HandleLidSwitchExternalPower"] if now else None,
        "docked": now["HandleLidSwitchDocked"] if now else None,
        "dropin": mine or None,
        "overriddenBy": later,
        "overrides": earlier,
        "inhibitors": lid_inhibitors(),
        "hibernate": can("CanHibernate"),
        "helper": {"installed": helper.is_file(), "current": current, "allowed": allowed},
    }


def main(argv: list[str]) -> int:
    if argv == ["status"]:
        if effective() is None:
            return refuse("logind did not answer on the system bus", 1)
        answer(ok=True, **status_fields())
        return 0
    if argv == ["reset"]:
        why = privileged()
        if why:
            return refuse(why, 1)
        return apply(None, None)
    # Arguments first: nothing about the system is read for a bad request.
    if len(argv) != 3 or argv[0] != "set" or argv[1] not in ACTIONS or argv[2] not in ACTIONS:
        return refuse(f"expected: set <undocked> <docked>, each one of {', '.join(ACTIONS)}; or status; or reset", 2)
    undocked, docked = argv[1], argv[2]
    why = privileged()
    if why:
        return refuse(why, 1)
    if "hibernate" in (undocked, docked):
        support = can("CanHibernate")
        if support != "yes":
            return refuse(f"this computer cannot hibernate (logind says {support})", 3)
    later, _ = others()
    if later:
        files = ", ".join(entry["file"] for entry in later)
        return refuse(f"{files} sets the lid too and is applied after 0xIde's setting, so it would win", 4,
                      overriddenBy=later)
    return apply(content(undocked, docked),
                 {"HandleLidSwitch": undocked, "HandleLidSwitchExternalPower": undocked,
                  "HandleLidSwitchDocked": docked})


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
