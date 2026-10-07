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
# As the shell's own notifications read: a symbolic icon the notification view
# tints with the scheme, and urgency for the colour (failure critical, a
# cancelled or disabled search low, a search that went ahead normal).
note() { notify-send -a 0xide-search -i system-search-symbolic "$@"; }
if [[ -z "$image" || ! -s "$image" ]]; then
    note -u critical "Search failed" "The selected image was not captured"
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
# Lens's own upload form. The browser posts to it, then follows it to the results.
lens_upload="https://lens.google.com/v3/upload"
# host|field=value|...|filefield=@   The reply is either the URL itself or
# JSON containing it. Listed in order; the first that answers with a link wins.
upload_endpoints=(
    "https://uguu.se/upload|files[]=@"
)

conf="${XDG_CONFIG_HOME:-$HOME/.config}/0xide/region-search.conf"
# shellcheck disable=SC1090
[[ -r "$conf" ]] && source "$conf"

if [[ "$mode" == "off" ]]; then
    note -u low "Region search is disabled" "Enable it in ${conf}"
    exit 0
fi

# --- helpers -----------------------------------------------------------------
die() { note -u critical "Search failed" "$1"; exit 1; }

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
    command -v tesseract >/dev/null 2>&1 || die "OCR requires Tesseract. Install tesseract first."
    # The languages the shell's OCR uses (OCR & AI settings), so both read the
    # same; empty there means every installed one.
    installed="$(tesseract --list-langs 2>/dev/null | tail -n +2 | grep -vx osd || true)"
    [[ -n "$installed" ]] || die "Tesseract has no language data. Install one, e.g. tesseract-data-eng."
    ocr_languages="$(jq -r '.ai.ocrLanguages // ""' "${XDG_CONFIG_HOME:-$HOME/.config}/caelestia/shell.json" 2>/dev/null || true)"
    ocr_languages="${ocr_languages//[[:space:]]/}"
    [[ -n "$ocr_languages" ]] || ocr_languages="$(paste -sd+ <<<"$installed")"
    missing=()
    IFS=+ read -ra wanted <<<"$ocr_languages"
    for code in "${wanted[@]}"; do
        grep -qxF -- "$code" <<<"$installed" || missing+=("$code")
    done
    [[ ${#missing[@]} -eq 0 ]] ||
        die "Tesseract has no data for $(IFS=,; echo "${missing[*]}" | sed 's/,/, /g'). Install it (e.g. tesseract-data-${missing[0]}) or change the OCR languages."
    # Tesseract's own reason for anything else, such as an unreadable image.
    # Under set -e a failure here otherwise ended the search with no message.
    errors="$(mktemp)"
    trap 'rm -f -- "$image" "$errors"' EXIT
    raw="$(tesseract "$image" - -l "$ocr_languages" 2>"$errors")" ||
        die "Tesseract could not read the region: $(tail -n1 "$errors")"
    text="$(printf '%s' "$raw" | tr '\n' ' ' | tr -s ' ')"
    text="${text#"${text%%[![:space:]]*}"}"
    text="${text%"${text##*[![:space:]]}"}"
    [[ -n "$text" ]] || die "No text was found in the selected region. Draw a circle instead to search the image itself."
    open_search "${search_url}$(printf '%s' "$text" | jq -sRr @uri)"
fi

# --- mode: lens (image goes to Google Lens only) ------------------------------
if [[ "$mode" == "lens" ]]; then
    ask "Send this region to lens.google.com?" ||
        { note -u low "Search cancelled" "Nothing was sent."; exit 0; }
    # Lens ties its results to the session cookie set by the upload itself, so
    # a results link from an upload made here opens empty in the browser. The
    # browser has to post the image: this page carries it inline and submits
    # Lens's own upload form as soon as it loads. It lives in the private
    # runtime directory and is removed once the browser has had time to read it.
    handoff_dir="${XDG_RUNTIME_DIR:-/tmp}/0xide-search"
    mkdir -p "$handoff_dir"
    chmod 700 "$handoff_dir"
    rm -f -- "$handoff_dir"/lens-*.html
    page="$(mktemp "$handoff_dir/lens-XXXXXX.html")"
    {
        printf '<!doctype html><meta charset="utf-8"><title>Google Lens</title>\n'
        printf '<form id="f" method="post" enctype="multipart/form-data" action="%s">' "$lens_upload"
        printf '<input id="i" type="file" name="encoded_image"></form>\n<script>\n'
        printf 'const b64 = "%s";\n' "$(base64 -w0 "$image")"
        cat <<'JS'
const bytes = Uint8Array.from(atob(b64), c => c.charCodeAt(0));
const files = new DataTransfer();
files.items.add(new File([bytes], "region.png", { type: "image/png" }));
document.getElementById("i").files = files.files;
document.getElementById("f").submit();
</script>
JS
    } > "$page"
    ( sleep 60; rm -f -- "$page" ) >/dev/null 2>&1 &
    note "Google Lens" "Region sent to Google Lens; results opened in your browser."
    open_search "file://$page"
fi

# --- mode: host-upload (image leaves this machine) ---------------------------
[[ "$mode" == "host-upload" ]] || die "Unknown mode '${mode}' in ${conf}"

# Name the host alone in the prompt: the full endpoint path is noise, and the
# host is the fact the person is being asked to agree to.
host="${upload_endpoints[0]%%|*}"
host="${host#*://}"
host="${host%%/*}"
ask "Upload this region to ${host} and open Google Lens?" ||
    { note -u low "Search cancelled" "Nothing was uploaded."; exit 0; }

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

note "Google Lens" "Region uploaded to ${host}; search opened in your browser."
open_search "https://lens.google.com/uploadbyurl?url=$(printf '%s' "$image_url" | jq -sRr @uri)"
