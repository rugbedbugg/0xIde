# Desktop profiles: the registry of profiles and the one piece of state, which
# profile is active. Source, do not execute.
#
# Every profile is a personality of the one runtime, Hyprland with the
# Caelestia shell. A profile is profiles/<id>/profile.conf (or the same under
# $XDG_CONFIG_HOME/0xide/profiles, which wins):
#
#   id               = windows-xp        must match the directory name
#   name             = Windows XP        what the launcher and settings show
#   provider         = native-caelestia  providers/<provider>/provider.sh runs it
#   wm_policy        = stacking          orchestration/wm-policies/<policy>.sh
#   description      = ...               one line, optional
#   presentation     = windows-xp        the shell look it asks for, optional
#   wm_float_classes = a, b              hybrid only: window classes that float
#   wm_float_tags    = c, d              hybrid only: window tags that float
#
# The active profile is written only by the profile manager, and only after the
# profile it names has been entered and verified. A missing, empty or unknown
# value means Caelestia, so a damaged state file can never leave a session
# without a desktop.

_dp_lib="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=orchestration/lib/common.sh
. "$_dp_lib/common.sh"

OX_PROFILES_DIR="$OX_ROOT/profiles"
OX_PROFILES_USER_DIR="$OX_CONFIG/profiles"
OX_WM_POLICIES_DIR="$OX_ROOT/orchestration/wm-policies"
OX_ACTIVE_PROFILE_FILE="$OX_STATE/active-profile"
DP_DEFAULT_PROFILE=caelestia

dp_valid_id() {
    case "$1" in
        ''|-*|*[!a-z0-9-]*) return 1 ;;
    esac
}

# A comma-separated list of window classes or tags: each one a plain name.
dp_valid_names() {
    local item
    local IFS=,
    for item in $1; do
        item="${item// /}"
        case "$item" in
            ''|*[!A-Za-z0-9._-]*) return 1 ;;
        esac
    done
}

dp_valid_policy() { dp_valid_id "$1" && [ -r "$OX_WM_POLICIES_DIR/$1.sh" ]; }

# id|name|provider|wm_policy|description for one profile.conf, or non-zero if
# it is not a usable profile.
dp_parse_profile() {
    local file="$1" id name provider policy description
    [ -r "$file" ] || return 1
    id="$(ox_pin "$file" id)"
    name="$(ox_pin "$file" name)"
    provider="$(ox_pin "$file" provider)"
    policy="$(ox_pin "$file" wm_policy)"
    description="$(ox_pin "$file" description)"
    dp_valid_id "$id" && dp_valid_id "$provider" && dp_valid_policy "$policy" || return 1
    [ "$id" = "$(basename "$(dirname "$file")")" ] || return 1
    [ -n "$name" ] || return 1
    dp_valid_names "$(ox_pin "$file" wm_float_classes)" && dp_valid_names "$(ox_pin "$file" wm_float_tags)" || return 1
    # The fields travel as |- and tab-separated lines.
    case "$name$description" in *'|'*|*$'\t'*) return 1 ;; esac
    printf '%s|%s|%s|%s|%s\n' "$id" "$name" "$provider" "$policy" "$description"
}

# Every usable profile, once each, by id; a user profile shadows a shipped one.
dp_list_profiles() {
    local file id
    for file in "$OX_PROFILES_USER_DIR"/*/profile.conf "$OX_PROFILES_DIR"/*/profile.conf; do
        id="$(dp_parse_profile "$file" 2>/dev/null)" || continue
        printf '%s\n' "${id%%|*}"
    done | sort -u
}

# The profile.conf that defines <id>: the user's if it parses, else the shipped one.
dp_profile_file() {
    local id="$1" file
    dp_valid_id "$id" || return 1
    for file in "$OX_PROFILES_USER_DIR/$id/profile.conf" "$OX_PROFILES_DIR/$id/profile.conf"; do
        dp_parse_profile "$file" >/dev/null 2>&1 && { printf '%s\n' "$file"; return 0; }
    done
    return 1
}

dp_resolve_profile() {
    local file
    file="$(dp_profile_file "$1")" || return 1
    dp_parse_profile "$file"
}

dp_field() {
    local parsed
    parsed="$(dp_resolve_profile "$1")" || return 1
    printf '%s\n' "$parsed" | cut -d'|' -f"$2"
}
dp_get_display_name() { dp_field "$1" 2; }
dp_get_provider()     { dp_field "$1" 3; }
dp_get_policy()       { dp_field "$1" 4; }
dp_get_description()  { dp_field "$1" 5; }
dp_validate_profile() { dp_resolve_profile "$1" >/dev/null; }

# Any other setting of a profile, such as its presentation. Empty when unset.
dp_value() {
    local file
    file="$(dp_profile_file "$1")" || return 0
    ox_pin "$file" "$2"
}

dp_get_active_profile() {
    local active=""
    [ -r "$OX_ACTIVE_PROFILE_FILE" ] && active="$(tr -d '[:space:]' < "$OX_ACTIVE_PROFILE_FILE")"
    if [ -n "$active" ] && dp_validate_profile "$active"; then
        printf '%s\n' "$active"
    else
        printf '%s\n' "$DP_DEFAULT_PROFILE"
    fi
}

# Writes stdin to <file> atomically: readers see the old content or the new.
dp_write_atomic() {
    local file="$1" tmp
    mkdir -p "$(dirname "$file")" || return 1
    tmp="$(mktemp "$file.XXXXXX")" || return 1
    cat > "$tmp" && mv -f "$tmp" "$file" || { rm -f "$tmp"; return 1; }
}

# The commit.
dp_set_active_profile() {
    dp_validate_profile "$1" || return 1
    printf '%s\n' "$1" | dp_write_atomic "$OX_ACTIVE_PROFILE_FILE"
}

dp_is_active() { [ "$(dp_get_active_profile)" = "$1" ]; }
