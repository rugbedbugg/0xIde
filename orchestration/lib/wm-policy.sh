# Window-management policies: how a desktop profile wants Hyprland to treat
# windows, and the layout snapshots that let a profile be returned to as it was
# left. Source, do not execute.
#
# A policy is orchestration/wm-policies/<name>.sh defining:
#
#   <name>_describe      what it does to windows, one line per rule
#   <name>_floats <class> <tags>
#                        succeeds when a window of that class and those tags
#                        floats under this policy; the profile being entered is
#                        $DP_PROFILE, so a policy can read its settings with
#                        dp_value "$DP_PROFILE" <key>
#   <name>_rules         optional: lines added to the policy file for new
#                        windows (see below)
#
# What happens to windows is the same for every policy, and lives here:
#
#   snapshot  the layout of the profile being left is recorded per window:
#             address, workspace, monitor, floating, fullscreen, pinned,
#             position, size, stable id, class. A window is only restored when
#             its address, stable id and class all match: Hyprland reuses the
#             address of a closed window, but never a stable id within a
#             session, and a snapshot from an earlier session matches nothing.
#   leave     new windows stop getting the policy's treatment.
#   enter     every ordinary window the policy floats and that is tiled is
#             floated where it already is, and recorded in the ledger; every
#             ledger window the policy does not float is tiled again. Windows
#             on special workspaces, fullscreen and pinned windows are never
#             touched. New windows get the same treatment as they open, from
#             the handler in hypr-user.lua, which reads the policy file and
#             adds what it floats to the ledger.
#   restore   windows in the entered profile's snapshot are put back: floating
#             or tiled, workspace, and for floating windows position and size.
#             Tiled windows are placed by Hyprland's layout; their order within
#             a workspace is not restored.
#   verify    the policy file names the policy, and every window whose state
#             enter or restore set still has it.
#
# So a window that existed when a profile was left comes back as it was, and a
# window created while another profile was active loses only what that profile
# did to it (it is tiled again if the policy floated it) and is otherwise left
# as Hyprland and Caelestia's rules made it.

# shellcheck source=orchestration/lib/hyprland.sh
. "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/hyprland.sh"

OX_WM_POLICY_FILE="$OX_STATE/wm-policy"
OX_WM_LEDGER="$OX_STATE/wm-floated"
OX_WM_LAYOUTS="$OX_STATE/desktop-profile/layout"
OX_WM_EXPECTED="$OX_STATE/desktop-profile/expected"

_wm_loaded=" "
wm_load() {
    local policy="$1"
    dp_valid_policy "$policy" || return 1
    case "$_wm_loaded" in *" $policy "*) return 0 ;; esac
    # shellcheck disable=SC1090
    . "$OX_WM_POLICIES_DIR/$policy.sh" || return 1
    _wm_loaded="$_wm_loaded$policy "
}

wm_call() {
    local policy="$1" hook="$2"
    shift 2
    wm_load "$policy" || { echo "fail: no WM policy $policy"; return 1; }
    declare -F "${policy}_$hook" >/dev/null || return 127
    "${policy}_$hook" "$@"
}

wm_layout_file() { printf '%s/%s.tsv\n' "$OX_WM_LAYOUTS" "$1"; }

# Windows the profile code may change: on a normal workspace, not fullscreen,
# not pinned. Reads client lines on stdin.
_wm_ordinary() { awk -F'\t' '$2 > 0 && $5 == 0 && $6 == 0'; }

# Every policy needs a Hyprland that answers.
wm_check() {
    local policy
    policy="$(dp_get_policy "$1")" || { echo "fail: $1 has no WM policy"; return 1; }
    wm_load "$policy" || { echo "fail: no WM policy $policy"; return 1; }
    dp_have hyprctl || { echo "fail: hyprctl is not installed"; return 1; }
    hypr_clients >/dev/null || { echo "fail: Hyprland is not answering hyprctl"; return 1; }
    echo ok
}

wm_describe_enter() {
    local policy
    policy="$(dp_get_policy "$1")" || return 1
    DP_PROFILE="$1" wm_call "$policy" describe
    [ -s "$(wm_layout_file "$1")" ] && echo "restore windows as they were when $1 was left"
    return 0
}

# Records the layout of <profile>, the one being left, readable by this user only.
wm_snapshot() {
    local clients
    clients="$(hypr_clients)" || { echo "fail: could not list windows" >&2; return 1; }
    mkdir -p "$OX_WM_LAYOUTS" && chmod 700 "$(dirname "$OX_WM_LAYOUTS")" "$OX_WM_LAYOUTS" || return 1
    printf '%s\n' "$clients" | sed '/^$/d' | dp_write_atomic "$(wm_layout_file "$1")"
}

# The policy file the hypr-user.lua handler reads for new windows.
_wm_write_policy() {
    local policy="$1" profile="$2"
    {
        printf 'policy %s\n' "$policy"
        [ -n "$profile" ] && DP_PROFILE="$profile" wm_call "$policy" rules 2>/dev/null
        true
    } | dp_write_atomic "$OX_WM_POLICY_FILE"
}

# New windows are left alone until the next policy is entered.
wm_leave() { _wm_write_policy tiling ""; }

# The ledger holds "address<TAB>stable-id" per window a policy floated. A
# window without a known stable id is never matched, so a reused address can
# never pass for a window that was floated before.
_wm_in_ledger() { [ "$2" != - ] && grep -qxF -- "$1"$'\t'"$2" "$OX_WM_LEDGER" 2>/dev/null; }

wm_enter() {
    local profile="$1" policy clients address floating x y w h sid class tags
    local ledger="" expected=""
    policy="$(dp_get_policy "$profile")" || return 1
    wm_load "$policy" || return 1
    clients="$(hypr_clients)" || { echo "fail: could not list windows" >&2; return 1; }
    # The policy file first, so windows opening meanwhile get the new treatment.
    _wm_write_policy "$policy" "$profile" || return 1
    while IFS=$'\t' read -r -u 3 address _ _ floating _ _ x y w h sid class tags; do
        [ -n "$address" ] || continue
        if DP_PROFILE="$profile" wm_call "$policy" floats "$class" "$tags"; then
            if [ "$floating" = 0 ]; then
                hypr_action "$address" "$sid" "$class" float on &&
                    hypr_action "$address" "$sid" "$class" move "$x" "$y" &&
                    hypr_action "$address" "$sid" "$class" resize "$w" "$h" || return 1
                ledger="$ledger$address"$'\t'"$sid"$'\n'
            elif _wm_in_ledger "$address" "$sid"; then
                ledger="$ledger$address"$'\t'"$sid"$'\n'
            fi
            expected="$expected$address"$'\t1\t-\n'
        elif [ "$floating" = 1 ] && _wm_in_ledger "$address" "$sid"; then
            hypr_action "$address" "$sid" "$class" float off || return 1
            expected="$expected$address"$'\t0\t-\n'
        fi
    done 3<<<"$(printf '%s\n' "$clients" | _wm_ordinary)"
    printf '%s' "$ledger" | dp_write_atomic "$OX_WM_LEDGER" &&
        printf '%s' "$expected" | dp_write_atomic "$OX_WM_EXPECTED"
}

# Puts back the windows <profile>'s snapshot knows and that still exist: the
# same address, stable id and class. Anything else is a different window, or
# one that cannot be told apart from a different one, and is left alone.
wm_restore() {
    local profile="$1" snapshot clients now address ws floating x y w h sid class
    local c_ws c_floating c_x c_y c_w c_h c_sid c_class expected=""
    snapshot="$(wm_layout_file "$profile")"
    [ -s "$snapshot" ] || return 0
    clients="$(hypr_clients)" || { echo "fail: could not list windows" >&2; return 1; }
    while IFS=$'\t' read -r -u 3 address ws _ floating _ _ x y w h sid class _; do
        [ -n "$address" ] || continue
        now="$(printf '%s\n' "$clients" | _wm_ordinary | awk -F'\t' -v a="$address" '$1 == a')"
        [ -n "$now" ] || continue
        IFS=$'\t' read -r _ c_ws _ c_floating _ _ c_x c_y c_w c_h c_sid c_class _ <<<"$now"
        hypr_same_window "$address" "$sid" "$class" "$address" "$c_sid" "$c_class" || continue
        if [ "$c_floating" != "$floating" ]; then
            hypr_action "$address" "$sid" "$class" float "$([ "$floating" = 1 ] && echo on || echo off)" || return 1
        fi
        if [ "$c_ws" != "$ws" ]; then
            hypr_action "$address" "$sid" "$class" workspace "$ws" || return 1
        fi
        if [ "$floating" = 1 ]; then
            [ "$c_x $c_y" = "$x $y" ] || hypr_action "$address" "$sid" "$class" move "$x" "$y" || return 1
            [ "$c_w $c_h" = "$w $h" ] || hypr_action "$address" "$sid" "$class" resize "$w" "$h" || return 1
        fi
        expected="$expected$address"$'\t'"$floating"$'\t'"$ws"$'\n'
    done 3<<<"$(_wm_ordinary < "$snapshot")"
    # Later lines win in verify, so restored windows override what enter expected.
    { cat "$OX_WM_EXPECTED" 2>/dev/null; printf '%s' "$expected"; } | dp_write_atomic "$OX_WM_EXPECTED.new" &&
        mv -f "$OX_WM_EXPECTED.new" "$OX_WM_EXPECTED"
}

wm_verify() {
    local profile="$1" policy in_effect clients address floating ws line c_ws c_floating
    policy="$(dp_get_policy "$profile")" || { echo "fail: $profile has no WM policy"; return 1; }
    # No policy file is tiling, as it is to the hypr-user.lua handler.
    in_effect="$(head -1 "$OX_WM_POLICY_FILE" 2>/dev/null)"
    [ "${in_effect:-policy tiling}" = "policy $policy" ] ||
        { echo "fail: the $policy policy is not in effect"; return 1; }
    clients="$(hypr_clients)" || { echo "fail: could not list windows"; return 1; }
    # The last expectation for each window is the one that counts.
    while IFS=$'\t' read -r address floating ws; do
        [ -n "$address" ] || continue
        line="$(printf '%s\n' "$clients" | awk -F'\t' -v a="$address" '$1 == a')"
        [ -n "$line" ] || continue
        IFS=$'\t' read -r _ c_ws _ c_floating _ <<<"$line"
        [ "$c_floating" = "$floating" ] || { echo "fail: window $address floating=$c_floating, wanted $floating"; return 1; }
        [ "$ws" = - ] || [ "$c_ws" = "$ws" ] || { echo "fail: window $address on workspace $c_ws, wanted $ws"; return 1; }
    done < <(tac "$OX_WM_EXPECTED" 2>/dev/null | awk -F'\t' '!seen[$1]++' | tac)
    echo ok
}
