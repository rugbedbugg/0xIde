# Desktop profile providers, and the one door every desktop command goes
# through. Source, do not execute.
#
# A provider is providers/<name>/provider.sh defining, with "-" in the name
# spelled "_":
#
#   <name>_check                 ok, or "fail: why"; must not change anything
#   <name>_describe_enter <id>   what entering profile <id> does, one line per step
#   <name>_describe_leave <id>   the same for leaving it
#   <name>_enter <id> <from>     show profile <id>; non-zero if it did not
#   <name>_leave <id> <to>       stop showing profile <id>; non-zero if it did not
#   <name>_verify <id>           ok, or "fail: why"; must not change anything
#
# Every command that touches the running desktop (the shell, Hyprland, D-Bus,
# notifications) is run through ox_cmd_runner. Setting OX_DP_RUNNER to an
# executable makes that executable receive the command instead, which is how
# the tests run everything without reaching the real session.

_dpp_lib="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=orchestration/lib/desktop-profile.sh
. "$_dpp_lib/desktop-profile.sh"

OX_PROVIDERS_DIR="$OX_ROOT/providers"

ox_cmd_runner() {
    if [ -n "${OX_DP_RUNNER:-}" ]; then
        "$OX_DP_RUNNER" "$@"
    else
        "$@"
    fi
}

# Waits between polls; the tests turn them off.
dp_sleep() { [ "${OX_DP_NO_SLEEP:-0}" = 1 ] || sleep "$1"; }

dp_have() { ox_cmd_runner command -v "$1" >/dev/null 2>&1; }

# Polls "$@" until it succeeds, up to $DP_WAIT_TRIES times.
dp_wait_for() {
    local tries=0
    until "$@"; do
        tries=$((tries + 1))
        [ "$tries" -ge "${DP_WAIT_TRIES:-20}" ] && return 1
        dp_sleep 0.5
    done
}

# PID and executable of whoever owns org.freedesktop.Notifications, as
# "pid exe", or nothing when nobody does.
dp_notification_owner() {
    ox_cmd_runner busctl --user --no-pager status org.freedesktop.Notifications 2>/dev/null |
        awk -F= '$1 == "PID" { pid = $2 } $1 == "Exe" { exe = $2 } END { if (pid) print pid, exe }'
}

_dp_loaded=" "
ox_provider_load() {
    local provider="$1" impl
    dp_valid_id "$provider" || return 1
    case "$_dp_loaded" in *" $provider "*) return 0 ;; esac
    impl="$OX_PROVIDERS_DIR/$provider/provider.sh"
    [ -r "$impl" ] || return 1
    # shellcheck disable=SC1090
    . "$impl" || return 1
    _dp_loaded="$_dp_loaded$provider "
}

# Calls <provider>_<hook> with the remaining arguments. Returns 127 when the
# provider does not define that hook.
ox_provider_call() {
    local provider="$1" hook="$2" fn
    shift 2
    ox_provider_load "$provider" || { printf 'fail: no provider %s\n' "$provider"; return 1; }
    fn="${provider//-/_}_$hook"
    declare -F "$fn" >/dev/null || return 127
    "$fn" "$@"
}
