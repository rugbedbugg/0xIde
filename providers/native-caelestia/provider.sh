# The Caelestia shell under Hyprland: the provider every desktop profile uses.
# Sourced by the profile manager; see orchestration/lib/desktop-provider.sh
# for the interface. Every desktop command goes through ox_cmd_runner.
#
# The shell keeps running from one profile to the next. What changes between
# profiles is their presentation (the profile's `presentation` setting, which
# the shell will read to change its look) and their WM policy, which the
# manager applies. Only Caelestia's own presentation exists so far; any other
# is reported as not built yet, and the shell looks as it always does.

# shellcheck source=orchestration/lib/desktop-provider.sh
. "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../orchestration/lib" && pwd)/desktop-provider.sh"

_nc_presentation() {
    local presentation
    presentation="$(dp_value "$1" presentation)"
    printf '%s\n' "${presentation:-caelestia}"
}

native_caelestia_check() {
    local tool
    for tool in caelestia qs; do
        dp_have "$tool" || { echo "fail: $tool is not installed"; return 1; }
    done
    echo ok
}

native_caelestia_describe_enter() {
    local presentation
    presentation="$(_nc_presentation "$1")"
    if [ "$presentation" = caelestia ]; then
        echo "show the Caelestia presentation"
    else
        echo "show the $presentation presentation (not built yet: the Caelestia look stays)"
    fi
    echo "make sure the Caelestia shell runs and owns org.freedesktop.Notifications"
}

native_caelestia_describe_leave() {
    echo "keep the Caelestia shell running for the next profile"
}

# PIDs of running Caelestia shell instances. `qs list` prints a plain notice
# rather than JSON when there are none, which jq rejects: that is also none.
_nc_pids() {
    ox_cmd_runner qs -c caelestia list -j 2>/dev/null | jq -r '.[]?.pid' 2>/dev/null
}
_nc_running() { [ -n "$(_nc_pids)" ]; }

_nc_owns_notifications() {
    local owner pid
    owner="$(dp_notification_owner)"
    [ -n "$owner" ] || return 1
    for pid in $(_nc_pids); do
        [ "${owner%% *}" = "$pid" ] && return 0
    done
    return 1
}

native_caelestia_enter() {
    if ! _nc_running; then
        ox_cmd_runner caelestia shell -d >/dev/null 2>&1 ||
            { echo "fail: caelestia shell -d did not start the shell" >&2; return 1; }
    fi
    dp_wait_for _nc_owns_notifications ||
        { echo "fail: the Caelestia shell does not own notifications" >&2; return 1; }
}

# Nothing to undo until presentations exist.
native_caelestia_leave() { return 0; }

native_caelestia_verify() {
    _nc_running || { echo "fail: the Caelestia shell is not running"; return 1; }
    _nc_owns_notifications || { echo "fail: the Caelestia shell does not own notifications"; return 1; }
    echo ok
}
