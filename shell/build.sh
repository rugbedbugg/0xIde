#!/usr/bin/env bash
# Materialises the forked Caelestia shell from upstream + patches + extensions,
# builds the plugin, and (unless --no-install) installs both.
#
#   ./shell/build.sh [--extensions ai,ocr,search,desktop-profile,wallpaper-info,unnova,shortcuts] [--no-install] [--no-plugin]
#
# Nothing here writes outside $OX_BUILD, $OX_QMLDIR and $OX_SHELLDIR.
set -euo pipefail
. "$(dirname -- "${BASH_SOURCE[0]}")/../orchestration/lib/common.sh"

EXTENSIONS="ai,ocr,search,desktop-profile,wallpaper-info,unnova,shortcuts"
DO_INSTALL=1
DO_PLUGIN=1
while [ $# -gt 0 ]; do
    case "$1" in
        --extensions) EXTENSIONS="$2"; shift 2 ;;
        --no-install) DO_INSTALL=0; shift ;;
        --no-plugin)  DO_PLUGIN=0; shift ;;
        *) ox_die "unknown option $1" ;;
    esac
done

SRC="$OX_BUILD/shell-src"
PIN="$OX_ROOT/shell/upstream.pin"
URL="$(ox_pin "$PIN" url)"
REV="$(ox_pin "$PIN" rev)"
[ -n "$URL" ] && [ -n "$REV" ] || ox_die "shell/upstream.pin is incomplete"

# Every tool is checked before anything is cloned or compiled, so a missing
# one fails in a second rather than after the build, with nothing half-written.
missing=""
for tool in git cmake ninja; do ox_have "$tool" || missing="$missing $tool"; done
[ -n "$(ox_python)" ] || missing="$missing python3"
[ "$DO_INSTALL" = 1 ] && { ox_have rsync || missing="$missing rsync"; }
[ -z "$missing" ] || ox_die "missing${missing}, required to build and install the shell (see ./installer/check_deps.sh shell)"

ox_step "Upstream source @ ${REV:0:9}"
mkdir -p "$OX_BUILD"
if [ ! -d "$SRC/.git" ]; then
    ox_log "cloning $URL"
    git clone --quiet "$URL" "$SRC"
fi
if ! git -C "$SRC" cat-file -e "$REV^{commit}" 2>/dev/null; then
    ox_log "fetching the pinned revision"
    git -C "$SRC" fetch --quiet origin
fi
# A clean checkout every time: the tree is build output, never a place to edit.
git -C "$SRC" checkout --quiet --detach "$REV"
git -C "$SRC" clean -qfdx
git -C "$SRC" reset --quiet --hard

ox_step "Patches"
# Our own plugin sources go in before the patch that declares them.
install -Dm644 "$OX_ROOT/shell/plugin/src/aiconfig.hpp"  "$SRC/plugin/src/Caelestia/Config/aiconfig.hpp"
install -Dm644 "$OX_ROOT/shell/plugin/src/airequest.hpp" "$SRC/plugin/src/Caelestia/airequest.hpp"
install -Dm644 "$OX_ROOT/shell/plugin/src/airequest.cpp" "$SRC/plugin/src/Caelestia/airequest.cpp"
install -Dm644 "$OX_ROOT/shell/plugin/src/procfs.hpp" "$SRC/plugin/src/Caelestia/Services/procfs.hpp"
install -Dm644 "$OX_ROOT/shell/plugin/src/procfs.cpp" "$SRC/plugin/src/Caelestia/Services/procfs.cpp"
install -Dm644 "$OX_ROOT/shell/plugin/src/processes.hpp" "$SRC/plugin/src/Caelestia/Services/processes.hpp"
install -Dm644 "$OX_ROOT/shell/plugin/src/processes.cpp" "$SRC/plugin/src/Caelestia/Services/processes.cpp"
for p in "$OX_ROOT"/shell/plugin/patches/*.patch "$OX_ROOT"/shell/patches/*.patch; do
    [ -e "$p" ] || continue
    ox_log "$(basename "$p")"
    git -C "$SRC" apply --whitespace=nowarn "$p" ||
        ox_die "$(basename "$p") does not apply to ${REV:0:9}. Rebase it by hand; see README.md."
done

ox_step "Extensions"
IFS=',' read -ra wanted <<<"$EXTENSIONS"
for ext in "${wanted[@]}"; do
    [ -n "$ext" ] || continue
    tree="$OX_ROOT/shell/extensions/$ext/tree"
    [ -d "$tree" ] || ox_die "no such extension: $ext"
    ox_log "$ext"
    (cd "$tree" && find . -type f -print0) | while IFS= read -r -d '' rel; do
        install -Dm"$( [ -x "$tree/$rel" ] && echo 755 || echo 644 )" "$tree/$rel" "$SRC/$rel"
    done
done

ox_step "AI manifest"
"$(ox_python)" "$OX_ROOT/installer/render_manifest.py" \
    "$OX_ROOT/manifests/ai.toml" "$SRC/assets/ai/manifest.json"
"$(ox_python)" "$OX_ROOT/installer/render_manifest.py" \
    "$OX_ROOT/manifests/translate.toml" "$SRC/assets/ai/translate.json" --whole
"$(ox_python)" "$OX_ROOT/installer/render_manifest.py" \
    "$OX_ROOT/manifests/speech.toml" "$SRC/assets/dictation/speech.json" --whole

if [ "$DO_PLUGIN" = 1 ]; then
    ox_step "Plugin"
    cmake -S "$SRC" -B "$OX_BUILD/plugin" -G Ninja \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="$OX_BUILD/plugin-install" \
        -DINSTALL_QMLDIR=lib/qt6/qml >/dev/null
    cmake --build "$OX_BUILD/plugin" --target caelestia-config caelestia-core
    cmake --build "$OX_BUILD/plugin"
    cmake --install "$OX_BUILD/plugin" >/dev/null
fi

# The import path and this checkout's location are substituted here rather
# than committed, so no machine path ever enters the repository.
for p in "$OX_QMLDIR" "$OX_ROOT"; do
    ox_path_substitutable "$p" || ox_die "a path put into QML must not contain a quote, backslash or newline: $p"
done
while IFS= read -r f; do
    ox_render_path @OXIDE_QML_IMPORT_PATH@ "$OX_QMLDIR" < "$f" | ox_render_path @OXIDE_ROOT@ "$OX_ROOT" > "$f.new" &&
        mv -f "$f.new" "$f"
done < <(grep -rlF --include='*.qml' -e "@OXIDE_QML_IMPORT_PATH@" -e "@OXIDE_ROOT@" "$SRC" || true)
grep -rqF --include='*.qml' -e "@OXIDE_QML_IMPORT_PATH@" -e "@OXIDE_ROOT@" "$SRC" && ox_die "path substitution failed"

if [ "$DO_INSTALL" = 0 ]; then
    ox_step "Built, not installed"
    ox_log "shell tree:  $SRC"
    exit 0
fi

ox_step "Install"
# The plugin lived under caelestia-mod before the rename. It moves as the
# shell.qml that names its new place is deployed, so the two never disagree.
legacy_data="$XDG_DATA_HOME/caelestia-mod"
if [ -d "$legacy_data/qml" ] && [ ! -L "$legacy_data" ] && [ ! -e "$OX_QMLDIR" ]; then
    mkdir -p "$(dirname "$OX_QMLDIR")"
    mv -- "$legacy_data/qml" "$OX_QMLDIR"
fi
if [ -d "$legacy_data" ] && [ ! -L "$legacy_data" ] && [ -e "$OX_QMLDIR" ]; then
    rm -rf --one-file-system -- "$legacy_data"
fi
if [ "$DO_PLUGIN" = 1 ]; then
    plugin_src="$OX_BUILD/plugin-install/lib/qt6/qml"
    [ -d "$plugin_src" ] || ox_die "plugin install produced nothing at $plugin_src"
    mkdir -p "$OX_QMLDIR"
    rsync -a --delete "$plugin_src/" "$OX_QMLDIR/"
    ox_own "$OX_QMLDIR"
    ox_log "plugin -> $OX_QMLDIR"
fi

ox_backup "$OX_SHELLDIR"
mkdir -p "$OX_SHELLDIR"
# Upstream's top-level build and packaging entries are anchored with a leading
# "/". Unanchored, rsync matches a name at any depth, which dropped the
# utils/scripts/ that utils/Searcher.qml imports; --delete then left an older
# copy in place, so only a fresh install showed it. VCS data, build files and
# bytecode are unwanted wherever they appear, so those stay unanchored.
rsync -a --delete \
    --exclude '.git' --exclude '/plugin' --exclude '/nix' --exclude '/scripts' \
    --exclude '/extras' --exclude 'CMakeLists.txt' --exclude '/flake.*' \
    --exclude '__pycache__' \
    "$SRC/" "$OX_SHELLDIR/"
ox_own "$OX_SHELLDIR"
ox_log "shell  -> $OX_SHELLDIR"
# Not `caelestia shell -r`: after a first install it misses the system shell.
ox_log "./install switches the running shell over; after building by hand: ./installer/shell-handoff restart"
