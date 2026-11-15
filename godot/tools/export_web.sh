#!/bin/sh
# Staging-copy, single-threaded Compatibility Web release. No installs/network.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
GODOT=${GODOT:-/workspace/tools/godot/Godot_v4.7.2-stable_linux.x86_64}
OUT=${1:-${OUT:-/workspace/nineweave-web-build}}
STAGE=${STAGE:-$(mktemp -d /tmp/nineweave-export.XXXXXX)}
export XDG_DATA_HOME=${XDG_DATA_HOME:-/tmp/nineweave-export-xdg/data}
export XDG_CONFIG_HOME=${XDG_CONFIG_HOME:-/tmp/nineweave-export-xdg/config}
export XDG_CACHE_HOME=${XDG_CACHE_HOME:-/tmp/nineweave-export-xdg/cache}
mkdir -p "$STAGE/project" "$OUT" "$XDG_DATA_HOME/godot/export_templates" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME"
# XDG stays under /tmp. Read existing templates via a symlink; never installs.
TEMPLATES=${TEMPLATES:-/home/box/.local/share/godot/export_templates/4.7.2.stable}
if [ -d "$TEMPLATES" ] && [ ! -e "$XDG_DATA_HOME/godot/export_templates/4.7.2.stable" ]; then
  ln -s "$TEMPLATES" "$XDG_DATA_HOME/godot/export_templates/4.7.2.stable"
fi
if [ ! -f "$XDG_DATA_HOME/godot/export_templates/4.7.2.stable/web_nothreads_release.zip" ]; then
  printf 'WEB EXPORT: FAIL (4.7.2.stable web_nothreads_release.zip template is missing)\n'; exit 2
fi
(cd "$ROOT" && tar cf - --exclude=./.godot --exclude='*.log' --exclude='*.import' .) | (cd "$STAGE/project" && tar xf -)
# Disable editor-only network listeners in the isolated import/export process.
mkdir -p "$XDG_CONFIG_HOME/godot"
cat > "$XDG_CONFIG_HOME/godot/editor_settings-4.7.tres" <<'SETTINGS'
[gd_resource type="EditorSettings" format=3]
[resource]
network/language_server/enable_smart_resolve = false
network/debug_adapter/port = 0
SETTINGS
status=0
"$GODOT" --headless --path "$STAGE/project" --import >"$STAGE/import.log" 2>&1 || status=$?
if rg -q 'SCRIPT ERROR|Parse Error' "$STAGE/import.log"; then cat "$STAGE/import.log"; exit 1; fi
MODE=--export-release
[ "${DEBUG:-0}" = 1 ] && MODE=--export-debug
"$GODOT" --headless --path "$STAGE/project" "$MODE" Web "$OUT/index.html" >"$STAGE/export.log" 2>&1 || status=$?
cp "$ROOT/THIRD_PARTY_NOTICES.md" "$OUT/THIRD_PARTY_NOTICES.md"
mkdir -p "$OUT/LICENSES"
cp "$ROOT/assets/fonts/"*OFL.txt "$OUT/LICENSES/"
SHA=$(cd "$ROOT/.." && git rev-parse HEAD 2>/dev/null || printf unknown)
BRANCH=$(cd "$ROOT/.." && git branch --show-current 2>/dev/null || printf unknown)
TREE='clean committed tree'
[ -z "$(cd "$ROOT/.." && git status --porcelain 2>/dev/null)" ] || TREE='UNCOMMITTED CHANGES PRESENT (not a pure commit build)'
cat > "$OUT/BUILD_INFO.txt" <<INFO
Nineweave Round 2
engine: $("$GODOT" --headless --version)
preset: Web / Compatibility / variant/thread_support=false
mode: $MODE
built: $(date -u +%Y-%m-%dT%H:%M:%SZ)
source SHA: $SHA
branch: $BRANCH
tree: $TREE
staging: $STAGE/project
notices: THIRD_PARTY_NOTICES.md and LICENSES/*OFL.txt
INFO
if rg -q 'SCRIPT ERROR|Parse Error|ERROR:.*(export|Export|template|Template|resource|Resource|script|Script)' "$STAGE/export.log"; then status=1; fi
for file in index.html index.js index.wasm index.pck; do
  [ -s "$OUT/$file" ] || { printf 'missing %s\n' "$OUT/$file"; status=1; }
done
printf 'staging: %s\n' "$STAGE"
if [ "$status" -eq 0 ]; then printf 'WEB EXPORT: PASS -> %s/index.html\n' "$OUT"; else cat "$STAGE/export.log"; printf 'WEB EXPORT: FAIL\n'; fi
exit "$status"
