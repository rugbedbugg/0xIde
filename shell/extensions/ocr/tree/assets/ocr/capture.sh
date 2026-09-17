#!/usr/bin/env bash
# Shared OCR helper for an existing grim/slurp keyboard shortcut.
set -euo pipefail
helper_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
fail() { notify-send -a caelestia-ocr -u critical 'OCR failed' "$1"; exit 1; }
geometry=$(slurp) || exit 0
capture=$(mktemp --suffix=.png)
trap 'rm -f -- "$capture"' EXIT
grim -g "$geometry" "$capture" || fail 'Could not capture the selected region'
if ! result=$(uv run --no-project --python 3.13 "$helper_dir/recognize.py" "$capture" --language "${1:-eng}"); then
    fail "$result"
fi
qs -c caelestia ipc call picker showOcr "$result" || fail 'Could not reach caelestia-shell'
