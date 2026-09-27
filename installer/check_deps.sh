#!/usr/bin/env bash
# Reports which dependency each component needs and whether it is present.
# Never installs anything.
set -uo pipefail
. "$(dirname -- "${BASH_SOURCE[0]}")/../orchestration/lib/common.sh"

missing=0
report() {
    local kind="$1" name="$2" owner="$3"
    if ox_have "$name"; then
        printf '  %-9s %-18s %s\n' "ok" "$name" "$owner"
    elif [ "$kind" = required ]; then
        printf '  %-9s %-18s %s\n' "MISSING" "$name" "$owner"; missing=$((missing+1))
    else
        printf '  %-9s %-18s %s\n' "absent" "$name" "$owner (optional)"
    fi
}

report required jq          "adapters/edge, adapters/papirus"
report required python3     "adapters/kde, installer"
report optional caelestia   "everything (caelestia-cli)"
report optional qs          "shell (quickshell)"
report optional hyprctl     "overrides/caelestia"
report optional cmake       "shell (build only)"
report optional ninja       "shell (build only)"
report optional git         "shell (build only)"
report optional tesseract   "shell/extensions/ocr, shell/extensions/search (text extraction)"
report optional wl-copy     "shell/extensions/ocr (the extracted text goes here)"
report optional curl        "shell/extensions/search (mode=host-upload only)"
report optional rsvg-convert "adapters/cursor (renders the recoloured Sweet cursors)"
report optional xcursorgen  "adapters/cursor (packs the XCursor theme)"
report optional hyprcursor-util "adapters/cursor (the scalable hyprcursor theme)"
report optional fuzzel      "shell/extensions/search (asks before any upload)"
report optional spicetify   "adapters/spotify"
report optional papirus-folders "adapters/papirus"
report optional dconf       "adapters/kde (GNOME font keys)"
report optional notify-send "shell extensions (error reporting)"

[ "$missing" -eq 0 ]
