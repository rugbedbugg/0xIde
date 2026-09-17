#!/usr/bin/env bash
# Materialises the forked Caelestia shell from upstream + patches + extensions,
# builds the plugin, and (unless --no-install) installs both.
#
#   ./shell/build.sh [--extensions ai,ocr,search] [--no-install] [--no-plugin]
#
# Nothing here writes outside $CM_BUILD, $CM_QMLDIR and $CM_SHELLDIR.
set -euo pipefail
. "$(dirname -- "${BASH_SOURCE[0]}")/../orchestration/lib/common.sh"

EXTENSIONS="ai,ocr,search"
DO_INSTALL=1
DO_PLUGIN=1
while [ $# -gt 0 ]; do
    case "$1" in
        --extensions) EXTENSIONS="$2"; shift 2 ;;
        --no-install) DO_INSTALL=0; shift ;;
        --no-plugin)  DO_PLUGIN=0; shift ;;
        *) cm_die "unknown option $1" ;;
    esac
done

SRC="$CM_BUILD/shell-src"
PIN="$CM_ROOT/shell/upstream.pin"
URL="$(cm_pin "$PIN" url)"
REV="$(cm_pin "$PIN" rev)"
[ -n "$URL" ] && [ -n "$REV" ] || cm_die "shell/upstream.pin is incomplete"

for tool in git cmake ninja; do cm_have "$tool" || cm_die "$tool is required to build the shell"; done

cm_step "Upstream source @ ${REV:0:9}"
mkdir -p "$CM_BUILD"
if [ ! -d "$SRC/.git" ]; then
    cm_log "cloning $URL"
    git clone --quiet "$URL" "$SRC"
fi
if ! git -C "$SRC" cat-file -e "$REV^{commit}" 2>/dev/null; then
    cm_log "fetching the pinned revision"
    git -C "$SRC" fetch --quiet origin
fi
# A clean checkout every time: the tree is build output, never a place to edit.
git -C "$SRC" checkout --quiet --detach "$REV"
git -C "$SRC" clean -qfdx
git -C "$SRC" reset --quiet --hard

cm_step "Patches"
# Our own plugin sources go in before the patch that declares them.
install -Dm644 "$CM_ROOT/shell/plugin/src/aiconfig.hpp"  "$SRC/plugin/src/Caelestia/Config/aiconfig.hpp"
install -Dm644 "$CM_ROOT/shell/plugin/src/airequest.hpp" "$SRC/plugin/src/Caelestia/airequest.hpp"
install -Dm644 "$CM_ROOT/shell/plugin/src/airequest.cpp" "$SRC/plugin/src/Caelestia/airequest.cpp"
for p in "$CM_ROOT"/shell/plugin/patches/*.patch "$CM_ROOT"/shell/patches/*.patch; do
    [ -e "$p" ] || continue
    cm_log "$(basename "$p")"
    git -C "$SRC" apply --whitespace=nowarn "$p" ||
        cm_die "$(basename "$p") does not apply to ${REV:0:9}. See docs/upstream.md."
done

cm_step "Extensions"
IFS=',' read -ra wanted <<<"$EXTENSIONS"
for ext in "${wanted[@]}"; do
    [ -n "$ext" ] || continue
    tree="$CM_ROOT/shell/extensions/$ext/tree"
    [ -d "$tree" ] || cm_die "no such extension: $ext"
    cm_log "$ext"
    (cd "$tree" && find . -type f -print0) | while IFS= read -r -d '' rel; do
        install -Dm"$( [ -x "$tree/$rel" ] && echo 755 || echo 644 )" "$tree/$rel" "$SRC/$rel"
    done
done

cm_step "AI manifest"
"$(cm_python)" "$CM_ROOT/installer/render_manifest.py" \
    "$CM_ROOT/manifests/ai.toml" "$SRC/assets/ai/manifest.json"

if [ "$DO_PLUGIN" = 1 ]; then
    cm_step "Plugin"
    cmake -S "$SRC" -B "$CM_BUILD/plugin" -G Ninja \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="$CM_BUILD/plugin-install" \
        -DINSTALL_QMLDIR=lib/qt6/qml >/dev/null
    cmake --build "$CM_BUILD/plugin" --target caelestia-config caelestia-core
    cmake --build "$CM_BUILD/plugin"
    cmake --install "$CM_BUILD/plugin" >/dev/null
fi

# The import path is substituted here rather than committed, so no machine
# path ever enters the repository.
sed -i "s|@CAELESTIA_MOD_QML_IMPORT_PATH@|$CM_QMLDIR|" "$SRC/shell.qml"
grep -q "@CAELESTIA_MOD_QML_IMPORT_PATH@" "$SRC/shell.qml" && cm_die "import path substitution failed"

if [ "$DO_INSTALL" = 0 ]; then
    cm_step "Built, not installed"
    cm_log "shell tree:  $SRC"
    exit 0
fi

cm_step "Install"
if [ "$DO_PLUGIN" = 1 ]; then
    plugin_src="$CM_BUILD/plugin-install/lib/qt6/qml"
    [ -d "$plugin_src" ] || cm_die "plugin install produced nothing at $plugin_src"
    mkdir -p "$CM_QMLDIR"
    rsync -a --delete "$plugin_src/" "$CM_QMLDIR/"
    cm_own "$CM_QMLDIR"
    cm_log "plugin -> $CM_QMLDIR"
fi

cm_backup "$CM_SHELLDIR"
mkdir -p "$CM_SHELLDIR"
rsync -a --delete \
    --exclude '.git' --exclude 'plugin' --exclude 'nix' --exclude 'scripts' \
    --exclude 'extras' --exclude 'CMakeLists.txt' --exclude 'flake.*' \
    --exclude '__pycache__' \
    "$SRC/" "$CM_SHELLDIR/"
cm_own "$CM_SHELLDIR"
cm_log "shell  -> $CM_SHELLDIR"
cm_log "restart the shell to pick this up: caelestia shell -d"
