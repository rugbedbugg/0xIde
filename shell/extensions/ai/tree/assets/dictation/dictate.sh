#!/usr/bin/env bash
# Voice dictation, as a toggle: the first press starts recording, the second
# stops it, transcribes it on this computer with whisper.cpp, and types the
# text into the focused window. The text is also left on the clipboard, for a
# window that does not accept typed input.
#
# Nothing leaves the machine. The recording lives in the private runtime
# directory and is deleted as soon as it has been transcribed.
set -euo pipefail

state="${XDG_RUNTIME_DIR:-/tmp}/0xide-dictation"
model="${XDG_DATA_HOME:-$HOME/.local/share}/0xide/speech/ggml-base.bin"
config="${XDG_CONFIG_HOME:-$HOME/.config}/caelestia/shell.json"
audio="$state/recording.wav"
pidfile="$state/recorder.pid"
idfile="$state/notification"
# Recording stops by itself after this long, in case the second press never comes.
limit=120

# As the shell's own notifications read: a symbolic icon the notification view
# tints with the scheme, and urgency for the colour.
note() { notify-send -a 0xide-dictation -i audio-input-microphone-symbolic "$@"; }
fail() {
    note -u critical "Dictation failed" "$1"
    rm -f -- "$audio" "$pidfile"
    exit 1
}

mkdir -p "$state"
chmod 700 "$state"

recording() { [ -f "$pidfile" ] && kill -0 "$(cat "$pidfile")" 2>/dev/null; }

if ! recording; then
    command -v whisper-cli >/dev/null 2>&1 || fail "whisper-cli is not installed. Install the whisper-cpp package."
    command -v pw-record >/dev/null 2>&1 || fail "pw-record is not installed. It comes with PipeWire."
    [ -f "$model" ] || fail "The speech model is not installed. Install it under OCR & AI in the shell's settings."
    rm -f -- "$audio"
    timeout "$limit" pw-record --rate 16000 --channels 1 --format s16 "$audio" >/dev/null 2>&1 &
    echo $! > "$pidfile"
    note -p -t 0 "Listening" "Speak, then press the dictation key again to stop." > "$idfile" || true
    exit 0
fi

# Second press: pw-record finishes the file on SIGINT.
recorder="$(cat "$pidfile")"
kill -INT "$recorder" 2>/dev/null || true
for _ in $(seq 50); do
    kill -0 "$recorder" 2>/dev/null || break
    sleep 0.1
done
rm -f -- "$pidfile"
replace=()
[ -s "$idfile" ] && replace=(-r "$(cat "$idfile")")
rm -f -- "$idfile"

[ -s "$audio" ] || fail "Nothing was recorded. Check the microphone."

language="$(jq -r '.ai.dictationLanguage // "auto"' "$config" 2>/dev/null || echo auto)"
[ -n "$language" ] || language=auto
text="$(whisper-cli -m "$model" -f "$audio" -l "$language" -nt -np 2>/dev/null | tr '\n' ' ' | tr -s ' ')" ||
    fail "whisper-cli could not transcribe the recording."
rm -f -- "$audio"
text="${text#"${text%%[![:space:]]*}"}"
text="${text%"${text##*[![:space:]]}"}"

if [ -z "$text" ] || [ "$text" = "[BLANK_AUDIO]" ]; then
    note "${replace[@]}" -u low "Nothing heard" "No speech was recognised."
    exit 0
fi

printf '%s' "$text" | wl-copy 2>/dev/null || true
if command -v wtype >/dev/null 2>&1 && wtype -- "$text" 2>/dev/null; then
    note "${replace[@]}" "Dictated" "$text"
else
    note "${replace[@]}" "Dictated to the clipboard" "$text"
fi
