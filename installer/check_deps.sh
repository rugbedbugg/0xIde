#!/usr/bin/env bash
# Reports which dependency each component needs and whether it is present.
# Never installs anything.
#
#   ./installer/check_deps.sh          everything a default install needs
#   ./installer/check_deps.sh shell    also count the shell's build tools as required
set -uo pipefail
. "$(dirname -- "${BASH_SOURCE[0]}")/../orchestration/lib/common.sh"

# The shell is off by default, so its build tools are required only when it is
# being installed; otherwise a missing one is reported against the shell alone.
WITH_SHELL=0
for arg in "$@"; do
    case "$arg" in
        shell) WITH_SHELL=1 ;;
        *) ox_die "unknown component $arg (only shell has its own requirements)" ;;
    esac
done

missing=0
report() {
    local kind="$1" name="$2" owner="$3"
    [ "$kind" = shell ] && [ "$WITH_SHELL" = 1 ] && kind=required
    if ox_have "$name"; then
        printf '  %-9s %-18s %s\n' "ok" "$name" "$owner"
    elif [ "$kind" = required ]; then
        printf '  %-9s %-18s %s\n' "MISSING" "$name" "$owner"; missing=$((missing+1))
    elif [ "$kind" = shell ]; then
        printf '  %-9s %-18s %s\n' "absent" "$name" "$owner (required to install the shell)"
    else
        printf '  %-9s %-18s %s\n' "absent" "$name" "$owner (optional)"
    fi
}

report required jq          "adapters/papirus"
report required python3     "adapters/kde, installer"
report optional caelestia   "everything (caelestia-cli)"
report optional qs          "shell (quickshell)"
report optional hyprctl     "overrides/caelestia"
report shell    git         "shell (fetches upstream)"
report shell    cmake       "shell (builds the plugin)"
report shell    ninja       "shell (builds the plugin)"
report shell    rsync       "shell (deploys the build)"
report optional tesseract   "shell/extensions/ocr, shell/extensions/search (text extraction)"
report optional wl-copy     "shell/extensions/ocr (the extracted text goes here)"
report optional curl        "shell/extensions/search (mode=host-upload only)"
report optional whisper-server "voice dictation (whisper-cpp)"
report optional wtype       "voice dictation (types the text)"
report optional pw-record   "voice dictation (records the microphone)"
report optional rsvg-convert "adapters/cursor (renders the recoloured Sweet cursors)"
report optional xcursorgen  "adapters/cursor (packs the XCursor theme)"
report optional hyprcursor-util "adapters/cursor (the scalable hyprcursor theme)"
report optional fuzzel      "shell/extensions/search (asks before any upload)"
report optional spicetify   "adapters/spotify"
report optional papirus-folders "adapters/papirus"
report optional dconf       "adapters/kde (GNOME font keys)"
report optional notify-send "shell extensions (error reporting)"

[ "$missing" -eq 0 ]
