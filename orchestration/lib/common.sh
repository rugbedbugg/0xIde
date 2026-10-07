# Shared helpers for 0xIde scripts. Source, do not execute.
# Every path this project touches is derived here, so nothing downstream
# needs to know a username or a checkout location.

: "${XDG_CONFIG_HOME:=$HOME/.config}"
: "${XDG_DATA_HOME:=$HOME/.local/share}"
: "${XDG_STATE_HOME:=$HOME/.local/state}"
: "${XDG_CACHE_HOME:=$HOME/.cache}"
export XDG_CONFIG_HOME XDG_DATA_HOME XDG_STATE_HOME XDG_CACHE_HOME

# Repository root, resolved from this file rather than from $0, so helpers
# work whether they are sourced by ./install, by a hook, or by a test.
OX_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
OX_BUILD="$OX_ROOT/build"
OX_STATE="$XDG_STATE_HOME/0xide"
OX_CONFIG="$XDG_CONFIG_HOME/0xide"
OX_QMLDIR="$XDG_DATA_HOME/0xide/qml"
OX_SHELLDIR="$XDG_CONFIG_HOME/quickshell/caelestia"
OX_CAELCONF="$XDG_CONFIG_HOME/caelestia"
OX_SCHEME="$XDG_STATE_HOME/caelestia/scheme.json"
export OX_ROOT OX_BUILD OX_STATE OX_CONFIG OX_QMLDIR OX_SHELLDIR OX_CAELCONF OX_SCHEME

# 0xIde was called caelestia-mod. Its settings and state move to the new names
# the first time anything here runs, and never over a directory already there.
for _old in "$XDG_CONFIG_HOME/caelestia-mod:$OX_CONFIG" "$XDG_STATE_HOME/caelestia-mod:$OX_STATE"; do
    if [ -d "${_old%%:*}" ] && [ ! -L "${_old%%:*}" ] && [ ! -e "${_old#*:}" ]; then
        mv -- "${_old%%:*}" "${_old#*:}"
    fi
done
unset _old

# Optional machine-local overrides; git-ignored on purpose.
# shellcheck disable=SC1091
[ -r "$OX_ROOT/config.local" ] && . "$OX_ROOT/config.local"

ox_log()  { printf '  %s\n' "$*"; }
ox_step() { printf '\n\033[1m%s\033[0m\n' "$*"; }
ox_warn() { printf '  warning: %s\n' "$*" >&2; }
ox_die()  { printf '  error: %s\n' "$*" >&2; exit 1; }

ox_have() { command -v "$1" >/dev/null 2>&1; }

# Prefer the distribution interpreter: a `python3` on PATH is often a version
# manager shim pinned to a different release than the system packages expect.
ox_python() {
    if [ -x /usr/bin/python3 ]; then echo /usr/bin/python3
    else command -v python3; fi
}

# Reads a "key = value" pin/conf file without sourcing it.
ox_pin() { sed -n "s/^[[:space:]]*$2[[:space:]]*=[[:space:]]*//p" "$1" | head -1; }

# A path substituted for a placeholder lands inside double-quoted QML, Lua and
# JSON strings and a single-quoted shell word, so one with a quote, backslash
# or newline is refused rather than escaped for each language. Spaces are fine.
ox_path_substitutable() {
    case "$1" in
        *[\"\'\\]*|*$'\n'*) return 1 ;;
    esac
}

# Replaces every <placeholder> in stdin with <path>, whatever sed would make of
# the path's &, | or \. Check the path with ox_path_substitutable first.
ox_render_path() {
    local repl
    repl="$(printf '%s' "$2" | sed 's/[\\&|]/\\&/g')"
    sed "s|$1|$repl|g"
}

# Writes stdin to $1 only if the content differs, so repeated installs are
# no-ops and nothing downstream sees a spurious mtime change.
ox_install_file() {
    local dest="$1" mode="${2:-644}" tmp
    mkdir -p "$(dirname "$dest")"
    tmp="$(mktemp "${dest}.cm.XXXXXX")"
    cat > "$tmp"
    chmod "$mode" "$tmp"
    if [ -e "$dest" ] && cmp -s "$tmp" "$dest"; then
        rm -f "$tmp"
        return 1
    fi
    ox_backup "$dest"
    mv -f "$tmp" "$dest"
    return 0
}

# Keeps the first version of any file this project replaces, once, forever.
ox_backup() {
    local src="$1" dest
    [ -e "$src" ] || return 0
    dest="$OX_STATE/replaced/${src#/}"
    [ -e "$dest" ] && return 0
    mkdir -p "$(dirname "$dest")"
    cp -a "$src" "$dest"
    ox_log "kept the previous $src in $dest"
}

# Records a path as owned by this project so uninstall knows what it may remove.
ox_own() {
    mkdir -p "$OX_STATE"
    printf '%s\n' "$1" >> "$OX_STATE/owned.list"
    sort -u -o "$OX_STATE/owned.list" "$OX_STATE/owned.list"
}


# Quickshell's CLI, run under a non-UTF-8 locale (an SSH session, cron, a bare
# systemd unit), prints Qt's locale warning on stdout ahead of its JSON:
#
#     \e[33m  WARN\e[0m: Detected locale "C" with character encoding "ANSI_X3.4-1968", which is not UTF-8.
#     Qt depends on a UTF-8 locale, and has switched to "C.UTF-8" instead.
#     If this causes problems, reconfigure your locale. See the locale(1) manual
#     for more information.
#
# This removes exactly that block, and only at the start. Anything else, an
# unknown warning or malformed JSON included, passes through to the parser
# and fails there.
ox_strip_qt_locale_warning() {
    awk '
        NR == 1 { if ($0 ~ /WARN.*: Detected locale ".*" with character encoding ".*", which is not UTF-8\.$/) { held = $0; next } }
        NR == 2 && held != "" { if ($0 ~ /^Qt depends on a UTF-8 locale, and has switched to ".*" instead\.$/) { held = held "\n" $0; next } }
        NR == 3 && held ~ /\n/ { if ($0 == "If this causes problems, reconfigure your locale. See the locale(1) manual") { held = held "\n" $0; next } }
        NR == 4 && held ~ /\n.*\n/ { if ($0 == "for more information.") { held = ""; done = 1; next } }
        { if (held != "" && !done) { print held; held = "" } done = 1; print }
        END { if (held != "" && !done) print held }
    '
}

# Whether an adapter is enabled: ./install lists it once it has set it up.
ox_adapter_enabled() { grep -qx "$1" "$OX_CONFIG/adapters.enabled" 2>/dev/null; }

# The commands an adapter's adapter.conf requires that are not installed,
# space separated; "" when it has them all.
ox_adapter_missing() {
    local conf="$OX_ROOT/adapters/$1/adapter.conf" cmd missing=""
    [ -f "$conf" ] || return 0
    for cmd in $(ox_pin "$conf" requires | tr ',' ' '); do
        ox_have "$cmd" || missing="$missing $cmd"
    done
    printf '%s' "${missing# }"
}

# What the last theme change did for one adapter, from the theme hook's log:
# "ok", "not applied", "FAILED (exit N)", or "" when it has not run since.
ox_theme_result() {
    sed -n -e "s/^$1 \(ok\) ([0-9]*s)\$/\1/p" -e "s/^$1 \(not applied\) (see above)\$/\1/p" \
        -e "s/^$1 \(FAILED (exit [0-9]*)\)\$/\1/p" "$OX_STATE/post-theme.log" 2>/dev/null | tail -n1
}

# The sudoers files that grant papirus-folders itself, with any option, rather
# than through 0xIde's fixed helper; one per line, empty when none does.
# sudo -ll names each entry's file, which /etc/sudoers.d cannot be read for.
ox_wide_papirus_rules() {
    sudo -n -ll 2>/dev/null | awk '/^Sudoers entry: /{f=$3} /^[[:space:]]+\/usr\/bin\/papirus-folders -C/{print f}' | sort -u
}

# True when a passwordless sudo rule exists for a command. Greps the rule list
# rather than running the command, and matches NOPASSWD explicitly so a cached
# sudo credential cannot make an absent rule look present.
ox_has_sudo_rule() {
    sudo -n -l 2>/dev/null | grep -q "NOPASSWD:.*$1"
}
