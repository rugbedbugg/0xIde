# The one place 0xIde's desktop profiles talk to Hyprland. Source, do not
# execute. Every call goes through ox_cmd_runner, so the tests can answer
# them with tests/desktop-sim instead of the real compositor socket.
#
# Queries use `hyprctl -j clients`. Actions use `hyprctl eval` with the Lua
# dispatchers Caelestia's own Hyprland config uses (hl.dispatch with
# hl.dsp.window.float, .move and .resize, the window looked up with
# hl.get_window), since this Hyprland is configured in Lua. Each action's
# first line names it (local action = "0xide: float 0x1234 on"), which is what
# a log or the simulator reads. Every value put into the Lua is checked
# first, so nothing from a window title or class can reach it.

# shellcheck source=orchestration/lib/desktop-provider.sh
. "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/desktop-provider.sh"

hypr_available() { dp_have hyprctl && hypr_clients >/dev/null; }

# One line per mapped window, tab-separated:
#   address  workspace-id  monitor  floating(0/1)  fullscreen  pinned(0/1)
#   x  y  width  height  stable-id  class  tags(comma-separated)
# An address is a pointer Hyprland may hand to a new window once the old one
# closes; the stable id is a per-session counter that is never reused, in hex
# without leading zeros, as Lua's string.format("%x", w.stable_id) writes it.
# Tabs are IFS whitespace to `read`, which would merge an empty field with the
# next, so an unknown stable id or class is written as "-".
hypr_clients() {
    local json
    json="$(ox_cmd_runner hyprctl -j clients 2>/dev/null)" || return 1
    printf '%s' "$json" | jq -r '
        def known: if . == null or . == "" then "-" else . end;
        .[] | select(.mapped and (.hidden | not)) |
        [.address, (.workspace.id | tostring), (.monitor | tostring),
         (if .floating then 1 else 0 end), (.fullscreen | tostring), (if .pinned then 1 else 0 end),
         (.at[0] | tostring), (.at[1] | tostring), (.size[0] | tostring), (.size[1] | tostring),
         (.stableId | if type == "string" then ascii_downcase | sub("^0+(?=.)"; "") else null end | known),
         (.class | known), ((.tags // []) | join(","))] | @tsv'
}

# A window is the same one only if its address, known stable id and class all match.
hypr_same_window() { [ "$2" != - ] && [ "$1 $2 $3" = "$4 $5 $6" ]; }

_hypr_int() { [[ "$1" =~ ^-?[0-9]+$ ]]; }

# A string as a Lua literal made only of decimal byte escapes, so no byte of a
# window's class can end the string or become Lua.
_hypr_lua_str() {
    local bytes
    bytes="$(printf '%s' "$1" | od -An -v -tu1)"
    printf '"'
    # shellcheck disable=SC2086
    [ -z "${bytes// /}" ] || printf '\\%03d' $bytes
    printf '"'
}

# hypr_action <identity> float on|off
# hypr_action <identity> workspace <workspace-id>
# hypr_action <identity> move <x> <y>
# hypr_action <identity> resize <width> <height>
#
# <identity> is three arguments, a window as hypr_clients lists it: address,
# stable id ("-" when Hyprland gives none) and class. The Lua looks the window
# up by address, checks the stable id (when known) and class are still that
# window's, and only then dispatches, with that window object: a dispatcher
# given no window acts on the focused one, so none is ever sent without one. A
# window that is gone or is now another one is an error, never a no-op.
#
# The script's first line names the action. It must not start with "-": hyprctl
# takes an argument starting with "-" for an option of its own and prints its
# usage instead of evaluating it.
hypr_action() {
    local address="$1" sid="$2" class="$3" op="$4" body lua out want_floating=""
    shift 4
    [[ "$address" =~ ^0x[0-9a-f]+$ ]] || { echo "fail: bad window address '$address'" >&2; return 1; }
    [[ "$sid" =~ ^([0-9a-f]+|-)$ ]] || { echo "fail: bad stable id '$sid'" >&2; return 1; }
    case "$op" in
        float)
            # on/off, never set/unset: Hyprland 0.56 reads any other word as toggle.
            case "${1:-}" in on) want_floating=true ;; off) want_floating=false ;; *) return 1 ;; esac
            body="hl.dsp.window.float({ action = \"$1\", window = w })" ;;
        workspace)
            _hypr_int "${1:-}" && [ "$1" -gt 0 ] || return 1
            body="hl.dsp.window.move({ workspace = $1, window = w, follow = false })" ;;
        move)
            _hypr_int "${1:-}" && _hypr_int "${2:-}" || return 1
            body="hl.dsp.window.move({ x = $1, y = $2, relative = false, window = w })" ;;
        resize)
            _hypr_int "${1:-}" && _hypr_int "${2:-}" || return 1
            body="hl.dsp.window.resize({ x = $1, y = $2, window = w })" ;;
        *)
            echo "fail: unknown Hyprland action $op" >&2; return 1 ;;
    esac
    lua="local action = \"0xide: $op $address $*\"
local w = hl.get_window(\"address:$address\")
if not w or w.address ~= \"$address\" then error(action .. \": no such window\") end
local id = \"$sid\"
if id ~= \"-\" and (type(w.stable_id) ~= \"number\" or string.format(\"%x\", w.stable_id) ~= id) then
    error(action .. \": the address now belongs to another window\")
end
local class = (w.class == nil or w.class == \"\") and \"-\" or w.class
if class ~= $(_hypr_lua_str "$class") then error(action .. \": the address now belongs to another window\") end
hl.dispatch($body)"
    [ -z "$want_floating" ] ||
        lua="$lua
if w.floating ~= $want_floating then error(action .. \": Hyprland did not change it\") end"
    out="$(ox_cmd_runner hyprctl eval "$lua" 2>&1)" || { echo "fail: hyprctl eval ($op $address $*): $out" >&2; return 1; }
    [ "$out" = ok ] || { echo "fail: hyprctl eval ($op $address $*): $out" >&2; return 1; }
}
