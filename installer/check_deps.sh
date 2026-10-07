#!/usr/bin/env bash
# Reports which tools each part of 0xIde uses and whether they are present.
# Never installs anything.
#
#   ./installer/check_deps.sh          everything a default install needs
#   ./installer/check_deps.sh shell    also count the shell's build tools as required
#
# Only the installer's own tools are required. Everything else belongs to one
# feature, which says what it lacks when it is used; an application an adapter
# themes (Spotify, Firefox, Zed...) is not a dependency at all, and the tools
# an adapter needs come from its own adapter.conf rather than a copy here.
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
declare -A seen=()
report() {
    local kind="$1" name="$2" owner="$3"
    seen[$name]=1
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

# The installer itself.
report required jq          "installer, adapters"
report required python3     "installer, adapters"

# Building and running the shell (./install --enable shell).
report shell    git         "shell (fetches upstream)"
report shell    cmake       "shell (builds the plugin)"
report shell    ninja       "shell (builds the plugin)"
report shell    rsync       "shell (deploys the build)"
report optional qs          "shell (quickshell runs it)"
report optional caelestia   "shell, desktop profiles (caelestia-cli)"
report optional hyprctl     "desktop profiles, keyboard shortcuts overlay, overrides/caelestia"
report optional notify-send "shell extensions (how failures are shown)"

# Shell features, each used only when you use it.
report optional tesseract   "OCR and region text search (plus a tesseract-data-<lang> package)"
report optional wl-copy     "OCR (the extracted text goes to the clipboard)"
report optional magick      "OCR (reads small screen text more accurately)"
report optional xdg-open    "region search (opens the results)"
report optional fuzzel      "region search (asks before any upload)"
report optional curl        "region search (mode=host-upload only)"
report optional uv          "local AI, offline translation and the speech model (Python runtimes)"
# The same tools as runtime.py's preflight, which tests/run checks.
report optional clang       "local AI (builds the BitNet runtime)"
report optional clang++     "local AI (builds the BitNet runtime)"
report optional whisper-server "voice dictation (whisper-cpp)"
report optional pw-record   "voice dictation (records the microphone)"
report optional wtype       "voice dictation (types the text)"
report optional pactl       "voice dictation (mute check), the voice override"
report optional gio         "wallpaper delete (moves it to the Trash)"

# Adapters: what each one's adapter.conf requires, besides the above.
for conf in "$OX_ROOT"/adapters/*/adapter.conf; do
    [ -f "$conf" ] || continue
    adapter="$(basename "$(dirname "$conf")")"
    for cmd in $(ox_pin "$conf" requires | tr ',' ' '); do
        [ -n "${seen[$cmd]:-}" ] && continue
        users="$(grep -l "^requires *=.*\b$cmd\b" "$OX_ROOT"/adapters/*/adapter.conf | xargs -n1 dirname | xargs -n1 basename | paste -sd, | sed 's/,/, /g')"
        report optional "$cmd" "adapters: ${users:-$adapter}"
    done
done

# System components (./install --enable sddm / sudoers), which ask first.
report optional visudo      "system/sudoers, system/sddm (checks the rule before installing it)"
report optional sddm-greeter-qt6 "system/sddm (the login screen theme)"

[ "$missing" -eq 0 ]
