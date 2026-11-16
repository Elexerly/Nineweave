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
# Godot resolves export paths from the staged project, so anchor caller-relative output.
OUT=$(CDPATH= cd -- "$OUT" && pwd)
# XDG stays under /tmp. Read existing templates via a symlink; never installs.
TEMPLATES=${TEMPLATES:-/home/box/.local/share/godot/export_templates/4.7.2.stable}
if [ -d "$TEMPLATES" ] && [ ! -e "$XDG_DATA_HOME/godot/export_templates/4.7.2.stable" ]; then
  ln -s "$TEMPLATES" "$XDG_DATA_HOME/godot/export_templates/4.7.2.stable"
fi
if [ ! -f "$XDG_DATA_HOME/godot/export_templates/4.7.2.stable/web_nothreads_release.zip" ]; then
  printf 'WEB EXPORT: FAIL (4.7.2.stable web_nothreads_release.zip template is missing)\n'; exit 2
fi
(cd "$ROOT" && tar cf - --exclude=./.godot --exclude='*.log' --exclude='*.import' --exclude=./assets/hero_video_src .) | (cd "$STAGE/project" && tar xf -)
# Hero-specific lossy import settings must survive the isolated re-import.
(cd "$ROOT" && find assets/heroes -name '*.import' -print | tar cf - -T -) | (cd "$STAGE/project" && tar xf -)
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
SHA=unqueried
BRANCH=unqueried
TREE=unqueried
TAG=
REPO=$(CDPATH= cd -- "$ROOT/.." && pwd)
if git -C "$REPO" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  SHA=$(git -C "$REPO" rev-parse HEAD)
  BRANCH=$(git -C "$REPO" rev-parse --abbrev-ref HEAD)
  TREE=$(git -C "$REPO" status --porcelain | awk '{print $2}' | tr '\n' ' ')
  TAG=$(git -C "$REPO" describe --tags --exact-match 2>/dev/null || true)
fi
cat > "$OUT/BUILD_INFO.txt" <<INFO
Nineweave Round 5p (trimmed Kellen intro)
engine: $("$GODOT" --headless --version)
preset: Web / Compatibility / variant/thread_support=false
mode: $MODE
built: $(date -u +%Y-%m-%dT%H:%M:%SZ)
source SHA: $SHA
branch: $BRANCH
tag: ${TAG:-pending}
tree: $TREE
staging: $STAGE/project
notices: THIRD_PARTY_NOTICES.md and LICENSES/*OFL.txt
INFO
if rg -q 'SCRIPT ERROR|Parse Error|ERROR:.*(export|Export|template|Template|resource|Resource|script|Script)' "$STAGE/export.log"; then status=1; fi
for file in index.html index.js index.wasm index.pck; do
  [ -s "$OUT/$file" ] || { printf 'missing %s\n' "$OUT/$file"; status=1; }
done
# Streamed Theora sidecars live beside index.html, never in the web PCK.
find "$ROOT/assets/hero_video" -type f -name '*.ogv' | while IFS= read -r clip; do
  rel=${clip#"$ROOT/assets/hero_video/"}
  mkdir -p "$OUT/hero_video/$(dirname "$rel")"
  cp "$clip" "$OUT/hero_video/$rel"
done
python3 "$ROOT/tools/check_hero_video_pack.py" "$ROOT" "$OUT" || status=1
# Round 3b: every owner recording must be packed as an imported stream.
oggs=0
for ogg in "$ROOT"/assets/audio/*/*.ogg; do
  name=$(basename "$ogg"); oggs=$((oggs+1))
  rg -a -q "${name%.ogg}\\.ogg-[0-9a-f]{32}\\.oggvorbisstr" "$OUT/index.pck" || { printf 'audio not packed: %s\n' "$name"; status=1; }
done
printf 'packed audio checked: %s ogg\n' "$oggs"
PCK_BYTES=$(wc -c < "$OUT/index.pck" | tr -d ' ')
printf 'packed bytes: %s (limit < 20000000; target <= 18000000)\n' "$PCK_BYTES"
[ "$PCK_BYTES" -lt 20000000 ] || { printf 'WEB EXPORT: PCK size budget exceeded\n'; status=1; }
printf 'staging: %s\n' "$STAGE"
if [ "$status" -eq 0 ]; then printf 'WEB EXPORT: PASS -> %s/index.html\n' "$OUT"; else cat "$STAGE/export.log"; printf 'WEB EXPORT: FAIL\n'; fi
exit "$status"
