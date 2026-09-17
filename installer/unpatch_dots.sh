#!/usr/bin/env bash
# Restores dots-managed files that used to carry direct edits, now that those
# edits live in supported override points.
#
# Only files whose current content differs from the dots source are touched, and
# only after the override that replaces the edit is in place. Every replaced
# file is kept under $CM_STATE/replaced first.
#
#   installer/unpatch_dots.sh [--check]
set -euo pipefail
. "$(dirname -- "${BASH_SOURCE[0]}")/../orchestration/lib/common.sh"

CHECK=0; [ "${1:-}" = "--check" ] && CHECK=1
DOTS="${CM_DOTS:-$XDG_STATE_HOME/caelestia/dots}"
[ -d "$DOTS" ] || cm_die "the caelestia dots checkout is not at $DOTS"

# dots source path -> deployed path
restore() {
    local src="$DOTS/$1" dest="$XDG_CONFIG_HOME/$2"
    [ -f "$src" ] || { cm_warn "$1 is not in the dots checkout; leaving $2 alone"; return 0; }
    [ -f "$dest" ] || return 0
    if cmp -s "$src" "$dest"; then cm_log "$2 already matches the dots"; return 0; fi
    if [ "$CHECK" = 1 ]; then
        cm_log "would restore $2 to the dots version:"
        diff -u "$src" "$dest" | sed -n '4,$p' | sed 's/^/      /'
        return 0
    fi
    cm_backup "$dest"
    cp -a "$src" "$dest"
    cm_log "restored $2"
}

drop() {
    local dest="$XDG_CONFIG_HOME/$1"
    [ -e "$dest" ] || return 0
    if [ "$CHECK" = 1 ]; then cm_log "would remove $1 ($2)"; return 0; fi
    cm_backup "$dest"
    rm -f "$dest"
    cm_log "removed $1 ($2)"
}

# Refuse to strip an edit before its replacement exists.
for f in hypr-vars.lua hypr-user.lua; do
    [ -f "$CM_CAELCONF/$f" ] ||
        cm_die "$CM_CAELCONF/$f is missing; run ./install before this"
done
grep -q "user-config.fish" "$XDG_CONFIG_HOME/fish/config.fish" ||
    cm_die "config.fish does not source user-config.fish; not safe to restore it"

cm_step "Restoring dots-managed files"
restore hypr/variables.lua          hypr/variables.lua
restore hypr/hyprland.lua           hypr/hyprland.lua
restore hypr/hyprland/keybinds.lua  hypr/hyprland/keybinds.lua
restore fish/config.fish            fish/config.fish

cm_step "Removing superseded files"
drop hypr/hyprland/cursor.lua "now overrides/caelestia/hypr-user.lua"
drop hypr/hypr-user.lua       "inert: upstream discards its return value"
