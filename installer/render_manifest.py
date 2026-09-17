#!/usr/bin/python3
"""Render manifests/ai.toml into the flat JSON the AI runtime reads.

The TOML file is the source of truth. The JSON is build output: it exists only
inside a materialised shell tree and is never committed.
"""

import json
import sys
import tomllib
from pathlib import Path

KEYS = [
    ("runtimeRepo", "runtime", "repo"),
    ("runtimeRevision", "runtime", "revision"),
    ("model", "model", "name"),
    ("modelRevision", "model", "revision"),
    ("modelFile", "model", "file"),
    ("modelBytes", "model", "bytes"),
    ("modelSha256", "model", "sha256"),
    ("contextTokens", "limits", "contextTokens"),
    ("responseTokens", "limits", "responseTokens"),
]


def main() -> int:
    source, dest = Path(sys.argv[1]), Path(sys.argv[2])
    data = tomllib.loads(source.read_text())
    try:
        rendered = {name: data[section][key] for name, section, key in KEYS}
    except KeyError as missing:
        print(f"{source}: missing {missing}", file=sys.stderr)
        return 1

    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_text(json.dumps(rendered, indent=2) + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
