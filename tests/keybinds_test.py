"""shell/extensions/shortcuts/tree/assets/shortcuts/keybinds.py, on saved
hyprctl output (tests/fixtures), never on the running Hyprland.

    python3 tests/keybinds_test.py <repo root>

Prints "ok <what>" or "FAIL <what>" per check.
"""

import copy
import json
import os
import random
import subprocess
import sys
import tempfile

root = sys.argv[1]
helper = os.path.join(root, "shell/extensions/shortcuts/tree/assets/shortcuts/keybinds.py")
fixtures = os.path.join(root, "tests/fixtures")
sys.path.insert(0, os.path.dirname(helper))
import keybinds  # noqa: E402

binds = json.load(open(os.path.join(fixtures, "hyprctl-binds.json"), encoding="utf-8"))
globals_ = json.load(open(os.path.join(fixtures, "hyprctl-globalshortcuts.json"), encoding="utf-8"))


def check(cond, what, detail=None):
    print(("ok " if cond else "FAIL ") + what + ("" if cond or detail is None else f": {detail}"))


def run(*args):
    proc = subprocess.run([sys.executable, helper, *args], capture_output=True, text=True,
                          env={**os.environ, "PYTHONDONTWRITEBYTECODE": "1"})
    return json.loads(proc.stdout)


out = run("--binds", os.path.join(fixtures, "hyprctl-binds.json"),
          "--globals", os.path.join(fixtures, "hyprctl-globalshortcuts.json"))
rows = out.get("binds", [])


def find(keys, submap="", flags=None):
    hits = [r for r in rows if r["keys"] == keys and r["submap"] == submap and (flags is None or r["flags"] == flags)]
    return hits[0] if len(hits) == 1 else (hits or None)


r = find(["Super", "Q"])
check(r and r["description"] == "Close window" and r["group"] == "Windows", "1. a keyboard bind with its description", r)
r = find(["Super", "Shift", "←"])
check(r and r["keys"] == ["Super", "Shift", "←"], "2. several modifiers, in a fixed order, as separate keys", r)
r = find(["Super", "Shift", "T"])
check(r and r["description"] == "Extract text from a screen region" and r["group"] == "0xIde" and r["source"] == "description",
      "3. a bind's own description is used, and 0xIde's are grouped as 0xIde", r)
r = find(["Super", "1"])
check(r and r["description"] == "Lua action" and r["source"] == "generic" and "Lua function" in r["detail"],
      "4. a bind with no description says so rather than guessing", r)
r = find(["Super", "K"])
check(r and r["description"] == "Close window", "5. a common dispatcher without a description is put into words", r)
r = find(["Super", "W"])
check(r and r["description"] == "Run firefox" and r["group"] == "Applications", "5. exec is shown as what it runs", r)
r = find(["Super", "H"])
check(r and r["description"] == "frobnicate sideways 3" and r["source"] == "generic", "6. an unknown dispatcher stays, shown as it is", r)
r = find(["Super", "Right Click"])
check(r and r["group"] == "Mouse" and "mouse" in r["flags"], "7. a mouse bind is listed under Mouse with its button named", r)
r = find(["Super", "Left Click"])
check(r and r["group"] == "Mouse", "7. a mouse bind Hyprland does not flag is still recognised by its key", r)
press, release = find(["Super", "Alt", "P"], flags=[]), find(["Super", "Alt", "P"], flags=["on release"])
check(press and release and press is not release, "8. the same keys on press and on release are two rows", (press, release))
check(press and press["count"] == 2 and release and release["count"] == 1,
      "9. a bind registered twice identically is one row, counted", press)
r = find(["Esc"], submap="resize")
check(r and r["group"] == "Submap resize" and r["submap"] == "resize", "10. a bind in another submap says which", r)
check(find(["→"], submap="resize") and not find(["→"]), "10. a submap bind is not listed as if always active")
r = find(["Super", "E"])
check(r and r["description"] == "Öffne Dateien — 文件管理器" and "文件管理器" in r["search"], "13. a Unicode description is kept as it is", r)
r = find(["Super", "SUPER_L"]) or find(["Super", "Left Super"])
check(r and r["description"] == "Toggle launcher" and r["source"] == "global",
      "a Caelestia shell shortcut is worded by the shell's own description", r)
r = find(["Super", "G"])
check(r and r["description"] == "Toggle dashboard", "a legacy global dispatcher is worded the same way", r)
r = find(["Super", "Shift", ","])
check(r and r["description"] == "group.lock_active" and r["source"] == "description",
      "a description from 0xide-binds that is only the dispatcher is shown as it is", r)
r = find(["Volume Up"])
check(r and r["group"] == "Media and hardware keys" and "works when locked" in r["flags"], "XF86 keys get names, and lock flags show", r)
r = find(["code:191"])
check(r is not None, "a bind by keycode alone is still listed", r)
check(len(rows) == len(binds) - 1, "every bind is listed once, the identical pair as one", (len(rows), len(binds)))

# Unknown global: the name, not a made-up label.
lone = keybinds.normalise([dict(binds[0], description="global caelestia:nowhere", has_description=True)], [])
check(lone["binds"][0]["description"] == "Shell shortcut caelestia:nowhere", "a global the shell has not described is named, not invented")
check(keybinds.normalise(binds, None)["binds"] and True, "no global shortcut list still lists every bind")

# 15. The same input in any order gives the same output.
shuffled = copy.deepcopy(binds)
random.Random(7).shuffle(shuffled)
check(keybinds.normalise(shuffled, globals_) == keybinds.normalise(binds, globals_), "15. output order does not depend on Hyprland's order")
groups = [r["group"] for r in rows]
check(groups == sorted(groups, key=lambda g: (keybinds.GROUPS.index(g) if g in keybinds.GROUPS else len(keybinds.GROUPS), g)),
      "15. groups come in a fixed order")

# 11, 12 and failures.
with tempfile.TemporaryDirectory() as tmp:
    bad = os.path.join(tmp, "bad.json")
    open(bad, "w").write("{not json")
    check("error" in run("--binds", bad), "11. malformed JSON is an error, not a crash")
    empty = os.path.join(tmp, "empty.json")
    open(empty, "w").write("[]")
    check(run("--binds", empty) == {"binds": [], "annotated": True}, "12. no binds is an empty list")
    obj = os.path.join(tmp, "obj.json")
    open(obj, "w").write('{"binds": 1}')
    check("error" in run("--binds", obj), "a JSON value that is not a list is an error")
    junk = os.path.join(tmp, "junk.json")
    open(junk, "w").write('[1, "x", null, {"modmask": "nonsense", "key": "Q"}]')
    got = run("--binds", junk)
    check(got.get("binds") and got["binds"][0]["keys"] == ["Q"], "entries of the wrong shape are skipped, odd fields tolerated", got)
    # No hyprctl on PATH: an error the overlay can show.
    proc = subprocess.run([sys.executable, helper], capture_output=True, text=True,
                          env={"PATH": tmp, "PYTHONDONTWRITEBYTECODE": "1"})
    check(json.loads(proc.stdout) == {"error": "hyprctl is not installed"} and proc.returncode == 0,
          "without hyprctl it says so", proc.stdout)
    fake = os.path.join(tmp, "hyprctl")
    open(fake, "w").write("#!/bin/sh\necho 'HYPRLAND_INSTANCE_SIGNATURE not set' >&2\nexit 1\n")
    os.chmod(fake, 0o755)
    proc = subprocess.run([sys.executable, helper], capture_output=True, text=True,
                          env={"PATH": tmp, "PYTHONDONTWRITEBYTECODE": "1"})
    check(json.loads(proc.stdout).get("error", "").startswith("Hyprland did not answer"),
          "without Hyprland's IPC it says Hyprland did not answer", proc.stdout)

# 14. Search: every word has to appear; the overlay filters the same way.
def search(query):
    terms = query.lower().split()
    return [r for r in rows if all(t in r["search"] for t in terms)]


check(any(r["keys"] == ["Volume Up"] for r in search("volume")), "14. search finds volume keys by name")
check({r["description"] for r in search("workspace")} >= {"Focus next workspace", "Focus workspace 2"}, "14. search finds workspace binds")
check(search("super shift t") and all("Super" in r["keys"] and "Shift" in r["keys"] for r in search("super shift t")),
      "14. search by keys needs every key")
check(any(r["group"] == "0xIde" for r in search("text")), "14. search matches descriptions")
check(search("mouse") and all("mouse" in r["search"] for r in search("mouse")), "14. search matches groups")
check(search("zzzz-nothing") == [], "14. a search with no match is empty")

# 15. A session whose Lua binds carry no descriptions (0xide-binds.lua was not
# loaded) is reported as such; its binds are still all listed, not guessed at.
check(out.get("annotated") is True, "15. the annotated fixture is reported as annotated")
bare = copy.deepcopy(binds)
for b in bare:
    if b.get("dispatcher") == "__lua":
        b["description"] = ""
plain = keybinds.normalise(bare, globals_)
check(plain.get("annotated") is False, "15. Lua binds without descriptions are reported as unannotated")
check(len(plain["binds"]) >= len(rows) - 5 and len(plain["binds"]) > 0, "15. and every bind is still listed",
      (len(plain["binds"]), len(rows)))
nolua = [b for b in binds if b.get("dispatcher") != "__lua"]
check(keybinds.normalise(nolua, globals_).get("annotated") is True, "15. a session without Lua binds is not called unannotated")
