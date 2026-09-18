# Shared helpers for caelestia-mod scripts. Source, do not execute.
# Every path this project touches is derived here, so nothing downstream
# needs to know a username or a checkout location.

: "${XDG_CONFIG_HOME:=$HOME/.config}"
: "${XDG_DATA_HOME:=$HOME/.local/share}"
: "${XDG_STATE_HOME:=$HOME/.local/state}"
: "${XDG_CACHE_HOME:=$HOME/.cache}"
export XDG_CONFIG_HOME XDG_DATA_HOME XDG_STATE_HOME XDG_CACHE_HOME

# Repository root, resolved from this file rather than from $0, so helpers
# work whether they are sourced by ./install, by a hook, or by a test.
CM_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
CM_BUILD="$CM_ROOT/build"
CM_STATE="$XDG_STATE_HOME/caelestia-mod"
CM_CONFIG="$XDG_CONFIG_HOME/caelestia-mod"
CM_QMLDIR="$XDG_DATA_HOME/caelestia-mod/qml"
CM_SHELLDIR="$XDG_CONFIG_HOME/quickshell/caelestia"
CM_CAELCONF="$XDG_CONFIG_HOME/caelestia"
CM_SCHEME="$XDG_STATE_HOME/caelestia/scheme.json"
export CM_ROOT CM_BUILD CM_STATE CM_CONFIG CM_QMLDIR CM_SHELLDIR CM_CAELCONF CM_SCHEME

# Optional machine-local overrides; git-ignored on purpose.
# shellcheck disable=SC1091
[ -r "$CM_ROOT/config.local" ] && . "$CM_ROOT/config.local"

cm_log()  { printf '  %s\n' "$*"; }
cm_step() { printf '\n\033[1m%s\033[0m\n' "$*"; }
cm_warn() { printf '  warning: %s\n' "$*" >&2; }
cm_die()  { printf '  error: %s\n' "$*" >&2; exit 1; }

cm_have() { command -v "$1" >/dev/null 2>&1; }

# Prefer the distribution interpreter: a `python3` on PATH is often a version
# manager shim pinned to a different release than the system packages expect.
cm_python() {
    if [ -x /usr/bin/python3 ]; then echo /usr/bin/python3
    else command -v python3; fi
}

# Reads a "key = value" pin/conf file without sourcing it.
cm_pin() { sed -n "s/^[[:space:]]*$2[[:space:]]*=[[:space:]]*//p" "$1" | head -1; }

# Writes stdin to $1 only if the content differs, so repeated installs are
# no-ops and nothing downstream sees a spurious mtime change.
cm_install_file() {
    local dest="$1" mode="${2:-644}" tmp
    mkdir -p "$(dirname "$dest")"
    tmp="$(mktemp "${dest}.cm.XXXXXX")"
    cat > "$tmp"
    chmod "$mode" "$tmp"
    if [ -e "$dest" ] && cmp -s "$tmp" "$dest"; then
        rm -f "$tmp"
        return 1
    fi
    cm_backup "$dest"
    mv -f "$tmp" "$dest"
    return 0
}

# Keeps the first version of any file this project replaces, once, forever.
cm_backup() {
    local src="$1" dest
    [ -e "$src" ] || return 0
    dest="$CM_STATE/replaced/${src#/}"
    [ -e "$dest" ] && return 0
    mkdir -p "$(dirname "$dest")"
    cp -a "$src" "$dest"
    cm_log "kept the previous $src in $dest"
}

# Records a path as owned by this project so uninstall knows what it may remove.
cm_own() {
    mkdir -p "$CM_STATE"
    printf '%s\n' "$1" >> "$CM_STATE/owned.list"
    sort -u -o "$CM_STATE/owned.list" "$CM_STATE/owned.list"
}


# True when a passwordless sudo rule exists for a command. Greps the rule list
# rather than running the command, and matches NOPASSWD explicitly so a cached
# sudo credential cannot make an absent rule look present.
cm_has_sudo_rule() {
    sudo -n -l 2>/dev/null | grep -q "NOPASSWD:.*$1"
}
