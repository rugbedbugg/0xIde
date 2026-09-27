#!/usr/bin/env bash
# Search a captured screen region.
#
#   region_search.sh <capture> [gesture]
#
# The gesture the picker used decides what kind of search this is by default:
# a dragged rectangle is a text search, a drawn circle is a visual one.
#
# PRIVACY: modes other than "text" transmit the captured pixels off this
# machine. Nothing is transmitted unless the mode in force says so and the
# confirmation below is accepted. See the Privacy section of README.md.
set -euo pipefail

image="${1:-}"
gesture="${2:-}"
if [[ -z "$image" || ! -s "$image" ]]; then
    notify-send -a 0xide-search -u critical "Search failed" "The selected image was not captured"
    exit 1
fi
trap 'rm -f -- "$image"' EXIT

# --- configuration -----------------------------------------------------------
# mode      text        OCR locally, search the extracted text. No image leaves
#                       this machine. The default for a rectangle.
#           lens        Send the image to Google Lens itself and open its
#                       results. Only Google receives it, and no public link is
#                       made. The default for a circle, and it still asks first.
#           host-upload Upload the image to a public file host, then hand Google
#                       Lens the resulting URL. The URL is public and
#                       unauthenticated for as long as the host retains it.
#           off         Disabled.
# confirm   always      Ask before any transmission (default).
#           never       Never ask. Only meaningful with an explicit mode.
#
# Setting mode in region-search.conf overrides the gesture for both, so one
# line still turns uploading off everywhere.
mode="text"
if [[ "$gesture" == "circle" ]]; then
    mode="lens"
fi
confirm="always"
search_url="https://www.google.com/search?q="
# Lens takes the image itself and answers with a redirect to its results. It
# only answers a browser, so it is asked as one.
lens_upload="https://lens.google.com/v3/upload"
browser_agent="Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0 Safari/537.36"
# host|field=value|...|filefield=@   The reply is either the URL itself or
# JSON containing it. Listed in order; the first that answers with a link wins.
upload_endpoints=(
    "https://uguu.se/upload|files[]=@"
)
ocr_languages="eng"

conf="${XDG_CONFIG_HOME:-$HOME/.config}/0xide/region-search.conf"
# shellcheck disable=SC1090
[[ -r "$conf" ]] && source "$conf"

if [[ "$mode" == "off" ]]; then
    notify-send -a 0xide-search "Region search is disabled" "Enable it in ${conf}"
    exit 0
fi

# --- helpers -----------------------------------------------------------------
die() { notify-send -a 0xide-search -u critical "Search failed" "$1"; exit 1; }

open_search() {
    xdg-open "$1" >/dev/null 2>&1 &
    exit 0
}

# Returns 0 only on an explicit, affirmative choice. A missing prompt program,
# a dismissed prompt, or any error all deny.
ask() {
    [[ "$confirm" == "never" ]] && return 0
    command -v fuzzel >/dev/null 2>&1 || die "fuzzel is needed to confirm sending the image. Install it, or set confirm=never in ${conf} to accept this permanently."
    local answer
    answer="$(printf 'Cancel\nSend the image\n' |
        fuzzel --dmenu --prompt "$1 " --lines 2 2>/dev/null || true)"
    [[ "$answer" == "Send the image" ]]
}

# --- mode: text (no image egress) --------------------------------------------
if [[ "$mode" == "text" ]]; then
    command -v tesseract >/dev/null 2>&1 || die "tesseract is not installed, so the region cannot be read locally."
    text="$(tesseract "$image" - -l "$ocr_languages" 2>/dev/null | tr '\n' ' ' | tr -s ' ')"
    text="${text#"${text%%[![:space:]]*}"}"
    text="${text%"${text##*[![:space:]]}"}"
    [[ -n "$text" ]] || die "No text was found in the selected region. Draw a circle instead to search the image itself."
    open_search "${search_url}$(printf '%s' "$text" | jq -sRr @uri)"
fi

# --- mode: lens (image goes to Google Lens only) ------------------------------
if [[ "$mode" == "lens" ]]; then
    ask "Send this region to lens.google.com?" ||
        { notify-send -a 0xide-search "Search cancelled" "Nothing was sent."; exit 0; }
    # No --location: the redirect is the answer, not something to follow.
    results="$(curl --silent --show-error --max-time 30 --user-agent "$browser_agent" \
        --form "encoded_image=@${image};type=image/png" \
        --output /dev/null --write-out '%{http_code} %{redirect_url}' "$lens_upload" 2>/dev/null || true)"
    status="${results%% *}"
    results="${results#* }"
    [[ "$status" == 30* && "$results" == https://* ]] ||
        die "Google Lens did not accept the image (HTTP ${status:-no reply}). Set mode=host-upload in ${conf} to go through a file host instead."
    notify-send -a 0xide-search "Google Lens" "Region sent to Google Lens; results opened in your browser."
    open_search "$results"
fi

# --- mode: host-upload (image leaves this machine) ---------------------------
[[ "$mode" == "host-upload" ]] || die "Unknown mode '${mode}' in ${conf}"

# Name the host alone in the prompt: the full endpoint path is noise, and the
# host is the fact the person is being asked to agree to.
host="${upload_endpoints[0]%%|*}"
host="${host#*://}"
host="${host%%/*}"
ask "Upload this region to ${host} and open Google Lens?" ||
    { notify-send -a 0xide-search "Search cancelled" "Nothing was uploaded."; exit 0; }

image_url=""
reason=""
for spec in "${upload_endpoints[@]}"; do
    IFS='|' read -r endpoint rest <<<"$spec"
    args=()
    IFS='|' read -ra fields <<<"$rest"
    for field in "${fields[@]}"; do
        [[ "$field" == *@ ]] && field="${field}${image}"
        args+=(-F "$field")
    done
    # No --fail: the status and the body are both wanted, so that a refusal can
    # say which host refused and with what, rather than "could not upload".
    name="${endpoint#*://}"; name="${name%%/*}"
    reply="$(curl --location --silent --show-error --max-time 20 \
        --write-out $'\n%{http_code}' "${args[@]}" "$endpoint" 2>/dev/null || true)"
    status="${reply##*$'\n'}"
    reply="${reply%$'\n'*}"
    if [[ "$status" != 2* ]]; then
        reason="${name} refused it (HTTP ${status:-no reply})"
        continue
    fi
    # Some hosts answer with the URL, others with JSON containing it.
    if [[ "$reply" == \{* || "$reply" == \[* ]]; then
        reply="$(printf '%s' "$reply" |
            jq -r '[.. | strings | select(startswith("http"))] | first // empty' 2>/dev/null)"
    fi
    reply="${reply//$'\n'/}"
    if [[ "$reply" == http* ]]; then
        image_url="$reply"
        host="$name"
        break
    fi
    reason="${name} replied without a link"
done

[[ -n "$image_url" ]] ||
    die "${reason:-No upload host is configured}. Set upload_endpoints in ${conf} to use a different host."

notify-send -a 0xide-search "Google Lens" "Region uploaded to ${host}; search opened in your browser."
open_search "https://lens.google.com/uploadbyurl?url=$(printf '%s' "$image_url" | jq -sRr @uri)"
