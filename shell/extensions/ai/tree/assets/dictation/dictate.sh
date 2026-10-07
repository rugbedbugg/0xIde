#!/usr/bin/env bash
# Voice dictation, as a toggle. On, it listens and types each phrase into the
# focused window as soon as you pause; off, it stops. The listening and typing
# are speech.py's; this only starts it, stops it, and says which it did.
#
# Nothing leaves the machine: audio goes from the microphone to a
# whisper-server bound to 127.0.0.1, and no recording is kept.
set -euo pipefail

here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
state="${XDG_RUNTIME_DIR:-/tmp}/0xide-dictation"
model="${XDG_DATA_HOME:-$HOME/.local/share}/0xide/speech/ggml-base.bin"
config="${XDG_CONFIG_HOME:-$HOME/.config}/caelestia/shell.json"
pidfile="$state/listener.pid"
idfile="$state/notification"
python=/usr/bin/python3
[ -x "$python" ] || python="$(command -v python3)"

# As the shell's own notifications read: a symbolic icon the notification view
# tints with the scheme, and urgency for the colour.
note() { notify-send -a 0xide-dictation -i audio-input-microphone-symbolic "$@"; }
fail() {
    note -u critical "Dictation failed" "$1"
    exit 1
}
replace_id() { [ -s "$idfile" ] && printf -- '-r\n%s\n' "$(cat "$idfile")"; }
# The listener's last error, if it logged one.
last_error() { grep -o '"error": "[^"]*"' "$state/listener.log" 2>/dev/null | tail -1 | cut -d'"' -f4 || true; }

# The listener can also end long after it started: whisper-server failing to
# load the model, or the microphone going away. Without this, "Dictation on"
# stayed up with nothing listening. Turning it off with the key takes the PID
# file away first, so that is not reported as a failure.
watch_listener() {
    local listener="$1" reason
    while kill -0 "$listener" 2>/dev/null; do sleep 1; done
    [ "$(cat "$pidfile" 2>/dev/null)" = "$listener" ] || return 0
    reason="$(last_error)"
    mapfile -t replace < <(replace_id)
    rm -f -- "$pidfile" "$idfile"
    note "${replace[@]}" -u critical "Dictation stopped" "${reason:-The listener stopped; see $state/listener.log}"
}

mkdir -p "$state"
chmod 700 "$state"

# Off: the listener finishes the phrase in progress, types it, and exits.
if [ -f "$pidfile" ] && kill -0 "$(cat "$pidfile")" 2>/dev/null; then
    listener="$(cat "$pidfile")"
    rm -f -- "$pidfile"
    kill -TERM "$listener" 2>/dev/null || true
    for _ in $(seq 100); do
        kill -0 "$listener" 2>/dev/null || break
        sleep 0.1
    done
    mapfile -t replace < <(replace_id)
    rm -f -- "$idfile"
    note "${replace[@]}" -u low "Dictation off" "Stopped listening."
    exit 0
fi

# On.
for tool in whisper-server pw-record wtype; do
    command -v "$tool" >/dev/null 2>&1 || fail "$tool is not installed. Dictation needs the whisper-cpp and wtype packages."
done
[ -f "$model" ] || fail "The speech model is not installed. Install it under OCR & AI in the shell's settings."
# A muted microphone records silence, which Whisper fills with invented words.
if command -v pactl >/dev/null 2>&1 && pactl get-source-mute @DEFAULT_SOURCE@ 2>/dev/null | grep -q 'yes'; then
    fail "Your microphone is muted. Unmute it, then turn dictation on again."
fi

language="$(jq -r '.ai.dictationLanguage // "en"' "$config" 2>/dev/null || echo en)"
[ -n "$language" ] || language=en
setsid "$python" "$here/speech.py" listen --language "$language" > "$state/listener.log" 2>&1 &
echo $! > "$pidfile"
note -p -t 0 "Dictation on" "Speak; each phrase is typed as you pause. Press the dictation key again to stop." > "$idfile" || true

# Say so if it could not start, rather than leaving "on" showing.
sleep 3
# Pressed again meanwhile: that press turned it off, and said so.
[ -f "$pidfile" ] || exit 0
if ! kill -0 "$(cat "$pidfile")" 2>/dev/null; then
    reason="$(last_error)"
    mapfile -t replace < <(replace_id)
    rm -f -- "$pidfile" "$idfile"
    note "${replace[@]}" -u critical "Dictation failed" "${reason:-The listener stopped; see $state/listener.log}"
    exit 1
fi
watch_listener "$(cat "$pidfile")" </dev/null >/dev/null 2>&1 &
