#!/usr/bin/python3
"""The keybinds registered in the running Hyprland, ready to list.

    keybinds.py                                    ask the running Hyprland
    keybinds.py --binds FILE [--globals FILE]      read saved hyprctl -j output

Prints one JSON object: {"binds": [...]} or {"error": "..."}. Each bind is
{"keys": [labels], "description", "source", "group", "detail", "flags",
"submap", "count", "search"}, sorted into a stable order.

Runtime state is the only source: what `hyprctl -j binds` reports is what is
bound, so a bind a config skipped never appears. A bind's description is
Hyprland's own when it has one. 0xIde's binds are marked "[0xIde] ...", and
0xide-binds.lua names a Caelestia shell shortcut as "global <name>", worded
here from `hyprctl -j globalshortcuts`, which the shell itself registers.
Without a description, a few common dispatchers are put into words and the
rest are shown as they are. Nothing is ever dropped for being unknown.
Standard library only; nothing is written anywhere.
"""

import json
import re
import subprocess
import sys

# Hyprland's modifier mask, in the order they are shown.
MODIFIERS = [(64, "Super"), (4, "Ctrl"), (8, "Alt"), (1, "Shift"),
             (2, "Caps Lock"), (16, "Mod2"), (32, "Mod3"), (128, "Mod5")]

KEYS = {
    "return": "Enter", "space": "Space", "tab": "Tab", "escape": "Esc",
    "backspace": "Backspace", "delete": "Delete", "insert": "Insert",
    "print": "Print Screen", "home": "Home", "end": "End",
    "page_up": "Page Up", "prior": "Page Up", "page_down": "Page Down", "next": "Page Down",
    "left": "←", "right": "→", "up": "↑", "down": "↓",
    "slash": "/", "backslash": "\\", "comma": ",", "period": ".", "minus": "-",
    "equal": "=", "semicolon": ";", "apostrophe": "'", "grave": "`",
    "bracketleft": "[", "bracketright": "]",
    "caps_lock": "Caps Lock", "num_lock": "Num Lock", "scroll_lock": "Scroll Lock",
    "super_l": "Left Super", "super_r": "Right Super",
    "control_l": "Left Ctrl", "control_r": "Right Ctrl",
    "alt_l": "Left Alt", "alt_r": "Right Alt",
    "shift_l": "Left Shift", "shift_r": "Right Shift",
    "mouse:272": "Left Click", "mouse:273": "Right Click", "mouse:274": "Middle Click",
    "mouse:275": "Back Button", "mouse:276": "Forward Button",
    "mouse_up": "Scroll Up", "mouse_down": "Scroll Down",
    "mouse_left": "Scroll Left", "mouse_right": "Scroll Right",
    "xf86audioraisevolume": "Volume Up", "xf86audiolowervolume": "Volume Down",
    "xf86audiomute": "Mute", "xf86audiomicmute": "Mic Mute",
    "xf86audioplay": "Play", "xf86audiopause": "Pause", "xf86audiostop": "Stop",
    "xf86audionext": "Next Track", "xf86audioprev": "Previous Track",
    "xf86monbrightnessup": "Brightness Up", "xf86monbrightnessdown": "Brightness Down",
}

# Dispatchers of a configuration written without Lua, where hyprctl still
# reports what a bind does. Kept to the common few; the rest are shown raw.
DISPATCHERS = {
    "killactive": "Close window",
    "togglefloating": "Toggle floating",
    "fullscreen": "Toggle fullscreen",
    "pin": "Toggle pinned",
    "centerwindow": "Centre window",
    "togglegroup": "Toggle window group",
    "cyclenext": "Focus next window",
    "exit": "Exit Hyprland",
}

FLAGS = [("release", "on release"), ("repeat", "repeats"), ("locked", "works when locked"),
         ("longPress", "long press"), ("non_consuming", "passes the key on"),
         ("catch_all", "catches all keys")]

GROUPS = ["0xIde", "Shell", "Applications", "Windows", "Workspaces", "Screenshots and recording",
          "Media and hardware keys", "Mouse", "Other"]


def key_label(key: str) -> str:
    lower = key.lower()
    if lower in KEYS:
        return KEYS[lower]
    if lower.startswith("mouse:"):
        return "Mouse " + key[6:]
    if lower.startswith("xf86"):
        return re.sub(r"(?<=[a-z])(?=[A-Z])", " ", key[4:]) or key
    if len(key) == 1:
        return key.upper()
    return key.replace("_", " ")


def key_labels(modmask: int, key: str) -> list[str]:
    labels = [name for bit, name in MODIFIERS if modmask & bit]
    return labels + [key_label(key)] if key else labels


def is_mouse(bind: dict) -> bool:
    return bool(bind.get("mouse")) or str(bind.get("key", "")).lower().startswith("mouse")


def describe(bind: dict, globals_: dict) -> tuple[str, str, str]:
    """(description, source, detail): source is description, global or generic."""
    text = str(bind.get("description") or "").strip()
    dispatcher = str(bind.get("dispatcher") or "")
    arg = str(bind.get("arg") or "").strip()

    if text:
        match = re.fullmatch(r"global (\S+)", text)
        if match:
            name = match.group(1)
            if globals_.get(name):
                return globals_[name], "global", name
            return f"Shell shortcut {name}", "generic", name
        if text.startswith("[0xIde]"):
            text = text[len("[0xIde]"):].strip() or text
        return text, "description", "" if dispatcher == "__lua" else f"{dispatcher} {arg}".strip()

    if dispatcher == "__lua":
        return "Lua action", "generic", "a Lua function, which Hyprland cannot describe"
    detail = f"{dispatcher} {arg}".strip()
    if dispatcher == "global" and globals_.get(arg):
        return globals_[arg], "global", arg
    if dispatcher == "exec" and arg:
        return f"Run {arg}", "description", detail
    if dispatcher == "workspace" and arg:
        return f"Focus workspace {arg}", "description", detail
    if dispatcher in ("movetoworkspace", "movetoworkspacesilent") and arg:
        return f"Move window to workspace {arg}", "description", detail
    if dispatcher in DISPATCHERS and not arg:
        return DISPATCHERS[dispatcher], "description", detail
    return detail or "Unknown action", "generic", detail


def group_of(bind: dict, description: str, source: str, detail: str) -> str:
    raw = str(bind.get("description") or "")
    if raw.startswith("[0xIde]"):
        return "0xIde"
    text = f"{description} {detail}".lower()
    key = str(bind.get("key", "")).lower()
    if is_mouse(bind):
        return "Mouse"
    if key.startswith("xf86") or re.search(r"\b(media|track|playback|volume|brightness|wpctl)\b", text):
        return "Media and hardware keys"
    if re.search(r"screenshot|\brecord\b|hyprpicker", text):
        return "Screenshots and recording"
    if "workspace" in text:
        return "Workspaces"
    if re.search(r"\b(window|group|floating|fullscreen|maximised|pinned)\b", text):
        return "Windows"
    if source == "global":
        return "Shell"
    if description.startswith("Run "):
        return "Applications"
    return "Other"


def normalise(binds, globals_list=None) -> dict:
    if not isinstance(binds, list):
        return {"error": "Hyprland's keybind list was not in the expected form"}
    globals_ = {}
    for item in globals_list if isinstance(globals_list, list) else []:
        if isinstance(item, dict) and isinstance(item.get("name"), str):
            globals_[item["name"]] = str(item.get("description") or "").strip()

    merged: dict[tuple, dict] = {}
    for bind in binds:
        if not isinstance(bind, dict):
            continue
        try:
            modmask = int(bind.get("modmask") or 0)
        except (TypeError, ValueError):
            modmask = 0
        key = str(bind.get("key") or "")
        if not key and not bind.get("keycode"):
            continue
        if not key:
            key = f"code:{bind.get('keycode')}"
        description, source, detail = describe(bind, globals_)
        flags = [label for name, label in FLAGS if bind.get(name)]
        submap = str(bind.get("submap") or "")
        group = f"Submap {submap}" if submap else group_of(bind, description, source, detail)
        if is_mouse(bind) and "mouse" not in flags and bind.get("mouse"):
            flags.append("mouse")

        # The same combination doing the same thing, the same way, is listed
        # once with a count; anything that differs stays a row of its own.
        identity = (modmask, key.lower(), submap, description, detail, tuple(flags))
        if identity in merged:
            merged[identity]["count"] += 1
            continue
        keys = key_labels(modmask, key)
        merged[identity] = {
            "keys": keys,
            "description": description,
            "source": source,
            "group": group,
            "detail": detail,
            "flags": flags,
            "submap": submap,
            "count": 1,
            "search": " ".join([" ".join(keys), key, description, detail, group, submap, " ".join(flags)]).lower(),
            "_order": (GROUPS.index(group) if group in GROUPS else len(GROUPS), group,
                       description.lower(), modmask, key.lower(), tuple(flags)),
        }

    rows = sorted(merged.values(), key=lambda row: row["_order"])
    for row in rows:
        del row["_order"]
    # Lua binds carry what they do only in the description 0xide-binds.lua
    # gives them as they are registered. Lua binds with none at all mean that
    # module was not loaded in this session, which the overlay has to say
    # rather than list every one as "Lua action".
    lua = [b for b in binds if isinstance(b, dict) and b.get("dispatcher") == "__lua"]
    annotated = not lua or any(str(b.get("description") or "").strip() for b in lua)
    return {"binds": rows, "annotated": annotated}


def hyprctl(*args: str):
    try:
        proc = subprocess.run(["hyprctl", "-j", *args], capture_output=True, text=True, timeout=5)
    except FileNotFoundError:
        raise RuntimeError("hyprctl is not installed")
    except subprocess.TimeoutExpired:
        raise RuntimeError("Hyprland did not answer")
    if proc.returncode != 0:
        raise RuntimeError("Hyprland did not answer: " + (proc.stderr or proc.stdout).strip()[:200])
    try:
        return json.loads(proc.stdout)
    except json.JSONDecodeError:
        raise RuntimeError("Hyprland's keybind list could not be read")


def read(path: str):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def main(argv: list[str]) -> dict:
    try:
        if "--binds" in argv:
            binds = read(argv[argv.index("--binds") + 1])
            globals_ = read(argv[argv.index("--globals") + 1]) if "--globals" in argv else []
        else:
            binds = hyprctl("binds")
            try:
                globals_ = hyprctl("globalshortcuts")
            except RuntimeError:
                globals_ = []  # descriptions fall back to the shortcut's name
    except RuntimeError as e:
        return {"error": str(e)}
    except (OSError, IndexError, json.JSONDecodeError):
        return {"error": "Hyprland's keybind list could not be read"}
    return normalise(binds, globals_)


if __name__ == "__main__":
    print(json.dumps(main(sys.argv[1:]), ensure_ascii=False))
