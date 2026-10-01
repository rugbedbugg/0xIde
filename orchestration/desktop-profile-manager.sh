# Desktop profile manager: moves the session from the active profile to
# another. Source, do not execute; ./0xide is the command line.
#
# Every profile runs on Hyprland with the Caelestia shell, and differs in its
# presentation (the provider's part) and its window-management policy
# (lib/wm-policy.sh). A switch runs in this order and stops at the first step
# that fails:
#
#   PREFLIGHT  the target's provider and WM policy can run (checked while planning)
#   SNAPSHOT   the current profile's window layout is recorded
#   LEAVE      the current profile's presentation is taken down
#   WM_LEAVE   new windows stop getting the current policy's treatment
#   WM_ENTER   the target's policy is applied to existing and new windows
#   RESTORE    windows the target's own snapshot knows are put back as they were
#   ENTER      the target's presentation is shown and the shell checked
#   VERIFY     the shell runs and owns notifications, and the windows conform
#   COMMIT     the target is recorded as the active profile
#
# COMMIT is last, so the recorded profile only ever names a profile that was
# verified. A failure after SNAPSHOT rolls back: the current profile's policy
# and presentation are entered again and its windows restored from the
# snapshot this switch took, and nothing is committed.

# shellcheck source=orchestration/lib/wm-policy.sh
. "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lib/wm-policy.sh"

DPM_LOG="$OX_STATE/desktop-profile.log"
DPM_LOCK="$OX_STATE/desktop-profile.lock"

# Calls a provider hook for a profile.
dpm_call() {
    local profile="$1" hook="$2" provider
    shift 2
    provider="$(dp_get_provider "$profile")" || return 1
    ox_provider_call "$provider" "$hook" "$profile" "$@"
}

# ok, or the first reason <profile> is not fully in effect.
dpm_verify() {
    local result
    result="$(dpm_call "$1" verify 2>&1)"
    [ "$result" = ok ] || { echo "$result"; return 1; }
    wm_verify "$1"
}

dpm_say() {
    mkdir -p "$OX_STATE" 2>/dev/null
    printf '%s %s\n' "$(date '+%F %T')" "$*" >> "$DPM_LOG" 2>/dev/null
    printf '  %s\n' "$*" >&2
}

# One line per stage: STAGE<TAB>profile it acts on<TAB>what it does. Empty
# when the target is already active. Fails when the target is unknown or
# cannot run here.
dpm_build_plan() {
    local target="$1" current check cpol tpol
    dp_validate_profile "$target" || { echo "fail: no profile named '$target'" >&2; return 1; }
    current="$(dp_get_active_profile)"
    [ "$current" = "$target" ] && return 0
    check="$(dpm_call "$target" check 2>/dev/null)"
    [ "$check" = ok ] || { echo "fail: $target cannot run here: ${check#fail: }" >&2; return 1; }
    check="$(wm_check "$target" 2>/dev/null)"
    [ "$check" = ok ] || { echo "fail: $target cannot run here: ${check#fail: }" >&2; return 1; }
    cpol="$(dp_get_policy "$current")"
    tpol="$(dp_get_policy "$target")"

    printf 'PREFLIGHT\t%s\t%s\n' "$target" "$target can run: shell and $tpol policy"
    printf 'SNAPSHOT\t%s\t%s\n' "$current" "record the window layout of $current"
    printf 'LEAVE\t%s\t%s\n' "$current" "take down the $current presentation"
    printf 'WM_LEAVE\t%s\t%s\n' "$current" "stop applying the $cpol policy to new windows"
    printf 'WM_ENTER\t%s\t%s\n' "$target" "apply the $tpol policy"
    printf 'RESTORE\t%s\t%s\n' "$target" "restore windows $target last saw"
    printf 'ENTER\t%s\t%s\n' "$target" "show the $target presentation"
    printf 'VERIFY\t%s\t%s\n' "$target" "$target is in effect"
    printf 'COMMIT\t-\t%s\n' "record $target as the active profile"
}

# The plan, with each step's details underneath.
dpm_show_plan() {
    local plan stage profile desc
    plan="$(dpm_build_plan "$1")" || return 1
    if [ -z "$plan" ]; then
        echo "$1 is already the active profile; nothing to do"
        return 0
    fi
    while IFS=$'\t' read -r stage profile desc; do
        printf '%-10s %s\n' "$stage" "$desc"
        case "$stage" in
            LEAVE)    dpm_call "$profile" describe_leave ;;
            WM_ENTER) wm_describe_enter "$profile" ;;
            ENTER)    dpm_call "$profile" describe_enter ;;
        esac | sed 's/^/             - /'
    done <<<"$plan"
}

_dpm_notify() {
    ox_cmd_runner notify-send -a 0xide -i preferences-desktop-theme "$@" >/dev/null 2>&1 || true
}

# Puts <current> back after a failed switch to <target>: its policy, its
# windows as this switch's snapshot recorded them, and its presentation.
# Succeeds when <current> verifies again.
dpm_rollback() {
    local current="$1" target="$2" entered="$3" why
    dpm_say "rolling back to $current"
    if [ "$entered" = 1 ]; then
        dpm_call "$target" leave "$current" >&2 || dpm_say "taking down $target again failed"
    fi
    wm_leave || dpm_say "resetting the policy file failed"
    wm_enter "$current" >&2 || dpm_say "applying the $(dp_get_policy "$current") policy again failed"
    wm_restore "$current" >&2 || dpm_say "restoring the $current windows failed"
    dpm_call "$current" enter "$target" >&2 || dpm_say "showing $current again failed"
    why="$(dpm_verify "$current")" || { dpm_say "$current does not verify: $why"; return 1; }
}

# Switches to <target>. With --dry-run, prints the plan and changes nothing.
# Exit status: 0 switched (or already there), 1 failed and rolled back or
# nothing changed, 2 failed and the rollback did not verify either.
dpm_execute_plan() {
    local target="$1" dry_run="${2:-0}" current plan stage profile desc
    local entered=0 failed=""

    if [ "$dry_run" = 1 ]; then
        dpm_show_plan "$target"
        return
    fi

    mkdir -p "$OX_STATE" || return 1
    exec 9>"$DPM_LOCK"
    if ! flock -n 9; then
        exec 9>&-
        echo "fail: another profile switch is running" >&2
        return 1
    fi

    # Planned under the lock, so it starts from the profile that is really active.
    current="$(dp_get_active_profile)"
    if ! plan="$(dpm_build_plan "$target")"; then
        exec 9>&-
        return 1
    fi
    if [ -z "$plan" ]; then
        exec 9>&-
        echo "$target is already the active profile"
        return 0
    fi

    dpm_say "switching $current -> $target"
    # The plan is read on its own descriptor so that nothing a step runs can
    # consume it from stdin.
    while IFS=$'\t' read -r -u 3 stage profile desc; do
        dpm_say "$stage: $desc"
        case "$stage" in
            PREFLIGHT) ;;
            SNAPSHOT) wm_snapshot "$profile" >&2 || { failed="$stage"; break; } ;;
            LEAVE)    dpm_call "$profile" leave "$target" >&2 || { failed="$stage"; break; } ;;
            WM_LEAVE) wm_leave >&2 || { failed="$stage"; break; } ;;
            WM_ENTER) wm_enter "$profile" >&2 || { failed="$stage"; break; } ;;
            RESTORE)  wm_restore "$profile" >&2 || { failed="$stage"; break; } ;;
            ENTER)    entered=1
                      dpm_call "$profile" enter "$current" >&2 || { failed="$stage"; break; } ;;
            VERIFY)   desc="$(dpm_verify "$profile")" || { dpm_say "$desc"; failed="$stage"; break; } ;;
            COMMIT)   dp_set_active_profile "$target" || { failed="$stage"; break; } ;;
            *)        failed="unknown stage $stage"; break ;;
        esac
    done 3<<<"$plan"

    if [ -z "$failed" ]; then
        exec 9>&-
        dpm_say "$target is now the active profile"
        return 0
    fi

    dpm_say "switch to $target failed at $failed"
    # Nothing has changed before the snapshot is taken.
    if [ "$failed" = SNAPSHOT ]; then
        exec 9>&-
        _dpm_notify -u critical "Desktop not switched" "Could not record the window layout, so nothing was changed. Details: $DPM_LOG"
        return 1
    fi
    if dpm_rollback "$current" "$target" "$entered"; then
        exec 9>&-
        dpm_say "back on $current"
        _dpm_notify -u critical "Desktop not switched" "Could not switch to $(dp_get_display_name "$target") (failed at $failed), so $(dp_get_display_name "$current") was restored. Details: $DPM_LOG"
        return 1
    fi
    exec 9>&-
    dpm_say "rollback to $current did not verify; $current is still recorded as active"
    _dpm_notify -u critical "Desktop switch failed" "Switching to $(dp_get_display_name "$target") failed at $failed, and $(dp_get_display_name "$current") could not be fully restored. Details: $DPM_LOG"
    return 2
}

# At login: new windows get the committed profile's policy, whatever the
# policy file said before. Existing windows are not touched; the Caelestia
# shell is started by Hyprland itself.
dpm_resume() {
    local active
    active="$(dp_get_active_profile)"
    _wm_write_policy "$(dp_get_policy "$active")" "$active"
}

# The active profile, and whether it is really in effect.
dpm_status() {
    local active why
    active="$(dp_get_active_profile)"
    if why="$(dpm_verify "$active")"; then
        echo "$active: in effect"
    else
        echo "$active: recorded as active, but not in effect (${why#fail: })"
        return 1
    fi
}

dpm_get() { dp_get_active_profile; }

# id, name, whether it is active, description; tab-separated with --tsv.
dpm_list() {
    local id active name mark
    active="$(dp_get_active_profile)"
    while IFS= read -r id; do
        name="$(dp_get_display_name "$id")"
        if [ "${1:-}" = --tsv ]; then
            printf '%s\t%s\t%s\t%s\n' "$id" "$name" "$([ "$id" = "$active" ] && echo 1 || echo 0)" "$(dp_get_description "$id")"
        else
            mark=" "; [ "$id" = "$active" ] && mark="*"
            printf '%s %-14s %s\n' "$mark" "$id" "$name"
        fi
    done < <(dp_list_profiles)
}
