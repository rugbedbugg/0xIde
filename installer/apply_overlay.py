#!/usr/bin/python3
"""Rewrite named keys in a config file this project does not own.

Used only where upstream offers no include or drop-in mechanism, which is
currently foot, starship and Zed. Everything else goes through a supported
override point instead.

The overlay names sections and keys; every other line of the target is left
exactly as it is, so an upstream change to an untouched setting survives. A key
already at the wanted value is not rewritten, so repeated runs are no-ops.

    apply_overlay.py <overlay> <target> [--ini|--toml|--jsonc|--json] [--check]

For JSONC (JSON with comments and trailing commas, as Zed writes it) only
top-level keys are supported, and each overlay value is a JSON value.

For JSON (--json) the overlay is itself a JSON object, merged recursively into
the target: objects are merged key by key, and any other value the overlay
names (a string, number, list...) replaces the target's. Keys only the target
has, at any depth, are kept, since the target is also written by the
application's own settings UI. An invalid target is never rewritten, and a
missing one is created from the overlay.
"""

import json
import re
import sys
from pathlib import Path

SECTION = re.compile(r"^\s*\[(?P<name>[^\]]+)\]\s*$")
COMMENT = re.compile(r"^\s*[#;]")


def parse_overlay(text: str) -> dict[str | None, dict[str, str]]:
    wanted: dict[str | None, dict[str, str]] = {None: {}}
    section: str | None = None
    for line in text.splitlines():
        if COMMENT.match(line) or not line.strip():
            continue
        if match := SECTION.match(line):
            # "[main]" names the unnamed leading section, which foot.ini has and
            # TOML calls the top level. There is no literal [main] in either.
            name = match.group("name")
            section = None if name == "main" else name
            wanted.setdefault(section, {})
            continue
        key, _, value = line.partition("=")
        wanted[section][key.strip()] = value.strip()
    return wanted


def key_line(key: str, value: str, style: str) -> str:
    return f"{key}={value}" if style == "ini" else f"{key} = {value}"


def apply(target: str, wanted: dict, style: str) -> tuple[str, list[str]]:
    lines = target.splitlines()
    out: list[str] = []
    changes: list[str] = []
    section: str | None = None
    seen: dict[str | None, set[str]] = {}
    # Where each section ends, so a missing key can be appended inside it.
    tail: dict[str | None, int] = {}
    in_multiline = False

    for line in lines:
        # A TOML multi-line string can contain lines that look exactly like a
        # table header; starship's prompt format is full of them.
        if line.count('"""') % 2:
            in_multiline = not in_multiline
        if not in_multiline and (match := SECTION.match(line)):
            tail[section] = len(out)
            section = match.group("name")
            seen.setdefault(section, set())
            out.append(line)
            continue

        stripped = line.lstrip("#; ").rstrip()
        key = stripped.partition("=")[0].strip()
        targets = wanted.get(section, {})
        if key and key in targets and key not in seen.setdefault(section, set()):
            replacement = key_line(key, targets[key], style)
            seen[section].add(key)
            if line != replacement:
                changes.append(f"[{section or 'main'}] {key} = {targets[key]}")
            out.append(replacement)
            continue
        out.append(line)
    tail[section] = len(out)

    # Append anything the target never had, inside its own section.
    for name, keys in wanted.items():
        missing = [k for k in keys if k not in seen.get(name, set())]
        if not missing:
            continue
        if name is None:
            # Top-level keys must go before the first table, not at the end of
            # the file, where TOML would read them as part of the last table.
            at = 0
            while at < len(out) and (COMMENT.match(out[at]) or not out[at].strip()):
                at += 1
        else:
            at = tail.get(name)
        if at is None:
            out.append("")
            out.append(f"[{name}]")
            at = len(out)
        block = [key_line(k, keys[k], style) for k in missing]
        changes.extend(f"[{name or 'main'}] {k} = {keys[k]} (added)" for k in missing)
        out[at:at] = block
        tail = {n: (i + len(block) if i >= at else i) for n, i in tail.items()}

    return "\n".join(out) + "\n", changes


def top_level_values(text: str) -> dict[str, tuple[int, int]]:
    """Top-level key -> (start, end) of its value in a JSONC document.

    A scanner, not a parser: it only tracks depth, strings and comments, which
    is all it takes to find where each top-level value begins and ends.
    """
    spans: dict[str, tuple[int, int]] = {}
    i, depth, n = 0, 0, len(text)
    key, value_start, last_string = None, None, None

    def skip_string(j: int) -> int:
        j += 1
        while text[j] != '"':
            j += 2 if text[j] == "\\" else 1
        return j + 1

    while i < n:
        c = text[i]
        if text.startswith("//", i):
            i = text.find("\n", i)
            i = n if i < 0 else i
            continue
        if text.startswith("/*", i):
            i = text.index("*/", i) + 2
            continue
        if c == '"':
            end = skip_string(i)
            if depth == 1 and value_start is None:
                last_string = json.loads(text[i:end])
            i = end
            continue
        if c in "{[":
            depth += 1
        elif c in "}]":
            if depth == 1 and value_start is not None:
                spans[key] = (value_start, len(text[:i].rstrip()))
                value_start = None
            depth -= 1
        elif depth == 1 and c == ":" and value_start is None:
            key = last_string
            value_start = i + 1
            while text[value_start] in " \t":
                value_start += 1
        elif depth == 1 and c == "," and value_start is not None:
            spans[key] = (value_start, len(text[:i].rstrip()))
            value_start = None
        i += 1
    return spans


def apply_jsonc(target: str, wanted: dict) -> tuple[str, list[str]]:
    keys = wanted.get(None, {})
    changes: list[str] = []
    for key, value in keys.items():
        spans = top_level_values(target)
        rendered = json.dumps(json.loads(value))
        if key in spans:
            start, end = spans[key]
            if json.loads(value) == _loads_loose(target[start:end]):
                continue
            target = target[:start] + rendered + target[end:]
            changes.append(f"{key} = {rendered}")
        else:
            brace = target.index("{")
            target = f'{target[:brace + 1]}\n  "{key}": {rendered},{target[brace + 1:]}'
            changes.append(f"{key} = {rendered} (added)")
    return target, changes


def merge_json(target, overlay, path: str = "") -> list[str]:
    """Merges overlay into target in place; returns the key paths it changed."""
    changes: list[str] = []
    for key, value in overlay.items():
        where = f"{path}.{key}" if path else key
        if isinstance(value, dict) and isinstance(target.get(key), dict):
            changes.extend(merge_json(target[key], value, where))
        elif key not in target:
            target[key] = value
            changes.append(f"{where} = {json.dumps(value)} (added)")
        elif target[key] != value:
            target[key] = value
            changes.append(f"{where} = {json.dumps(value)}")
    return changes


def apply_json(overlay: Path, target: Path, check: bool) -> int:
    try:
        wanted = json.loads(overlay.read_text())
    except (OSError, json.JSONDecodeError) as err:
        print(f"{overlay}: not valid JSON ({err}); nothing changed", file=sys.stderr)
        return 2
    if not isinstance(wanted, dict):
        print(f"{overlay}: the overlay must be a JSON object", file=sys.stderr)
        return 2

    if target.exists():
        try:
            current = json.loads(target.read_text())
        except (OSError, UnicodeDecodeError, json.JSONDecodeError) as err:
            print(f"{target}: not valid JSON ({err}); left untouched", file=sys.stderr)
            return 2
        if not isinstance(current, dict):
            print(f"{target}: not a JSON object; left untouched", file=sys.stderr)
            return 2
        changes = merge_json(current, wanted)
    else:
        current = wanted
        changes = ["(created from the overlay)"]

    if not changes:
        print(f"{target.name}: already current")
        return 0
    if check:
        for change in changes:
            print(f"{target.name}: would set {change}")
        return 1

    # Written beside the target and renamed over it, so a reader never sees
    # half a file, keeping the target's permissions.
    target.parent.mkdir(parents=True, exist_ok=True)
    tmp = target.with_name(f".{target.name}.overlay")
    tmp.write_text(json.dumps(current, indent=4, ensure_ascii=False) + "\n")
    if target.exists():
        tmp.chmod(target.stat().st_mode & 0o7777)
    tmp.replace(target)
    for change in changes:
        print(f"{target.name}: set {change}")
    return 0


def _loads_loose(value: str):
    """A value as JSON, or None when it holds comments or trailing commas."""
    try:
        return json.loads(value)
    except json.JSONDecodeError:
        return None


def main() -> int:
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    flags = {a for a in sys.argv[1:] if a.startswith("--")}
    overlay, target = Path(args[0]), Path(args[1])
    if "--json" in flags:
        return apply_json(overlay, target, "--check" in flags)
    style = "toml" if "--toml" in flags else "jsonc" if "--jsonc" in flags else "ini"

    if not target.exists():
        print(f"{target}: does not exist, skipping", file=sys.stderr)
        return 0

    # As for --json, a target that cannot be read or scanned is left as it is
    # and reported in one line, with exit 2, rather than as a traceback.
    try:
        original = target.read_text()
        wanted = parse_overlay(overlay.read_text())
        updated, changes = apply_jsonc(original, wanted) if style == "jsonc" else apply(original, wanted, style)
    except (OSError, UnicodeDecodeError, ValueError, IndexError) as err:
        print(f"{target}: could not be read as {style} ({err or type(err).__name__}); left untouched", file=sys.stderr)
        return 2

    if not changes:
        print(f"{target.name}: already current")
        return 0
    if "--check" in flags:
        for change in changes:
            print(f"{target.name}: would set {change}")
        return 1

    try:
        target.write_text(updated)
    except OSError as err:
        print(f"{target}: could not be written ({err.strerror or err}); left untouched", file=sys.stderr)
        return 2
    for change in changes:
        print(f"{target.name}: set {change}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
