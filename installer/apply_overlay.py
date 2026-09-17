#!/usr/bin/python3
"""Rewrite named keys in a config file this project does not own.

Used only where upstream offers no include or drop-in mechanism, which is
currently foot and starship. Everything else goes through a supported override
point instead.

The overlay names sections and keys; every other line of the target is left
exactly as it is, so an upstream change to an untouched setting survives. A key
already at the wanted value is not rewritten, so repeated runs are no-ops.

    apply_overlay.py <overlay> <target> [--ini|--toml] [--check]
"""

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


def main() -> int:
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    flags = {a for a in sys.argv[1:] if a.startswith("--")}
    overlay, target = Path(args[0]), Path(args[1])
    style = "toml" if "--toml" in flags else "ini"

    if not target.exists():
        print(f"{target}: does not exist, skipping", file=sys.stderr)
        return 0

    original = target.read_text()
    updated, changes = apply(original, parse_overlay(overlay.read_text()), style)

    if not changes:
        print(f"{target.name}: already current")
        return 0
    if "--check" in flags:
        for change in changes:
            print(f"{target.name}: would set {change}")
        return 1

    target.write_text(updated)
    for change in changes:
        print(f"{target.name}: set {change}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
