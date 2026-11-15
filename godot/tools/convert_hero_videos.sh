#!/bin/sh
# Convert hero MP4 sources to Ogg Theora for Godot's VideoStreamPlayer.
# Maps:  assets/hero_video_src/<hero_id>/{intro,victory}.mp4
#    ->  assets/hero_video/<hero_id>/{intro,victory}.ogv
# Also writes assets/hero_video/manifest.json listing which clips exist.
# The manifest MUST ship in every export (including web). The .ogv files
# are bundled on iOS/Android and served beside index.html on web.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
SRC="$ROOT/assets/hero_video_src"
DST="$ROOT/assets/hero_video"
Q=${Q:-6}
# Phone-clean 3–5 MB: width 540, Theora q:v 6, Vorbis q:a 3.
SCALE=${SCALE:-540:-2}

if ! command -v ffmpeg >/dev/null 2>&1; then
  printf 'convert_hero_videos: ffmpeg is required\n' >&2
  exit 1
fi

mkdir -p "$DST"
converted=0
skipped=0
failed=0

list=$(find "$SRC" -type f \( -name 'intro.mp4' -o -name 'victory.mp4' \) | sort || true)
if [ -z "$list" ]; then
  printf 'no source mp4 files under %s\n' "$SRC"
fi

old_ifs=$IFS
IFS='
'
for mp4 in $list; do
  IFS=$old_ifs
  [ -n "$mp4" ] || continue
  rel=${mp4#"$SRC"/}
  hero_id=${rel%%/*}
  kind=$(basename "$mp4" .mp4)
  case "$kind" in intro|victory) ;; *) continue ;; esac
  out_dir="$DST/$hero_id"
  out="$out_dir/$kind.ogv"
  mkdir -p "$out_dir"
  if [ -f "$out" ] && [ ! "$mp4" -nt "$out" ]; then
    printf 'up to date: %s/%s.ogv\n' "$hero_id" "$kind"
    skipped=$((skipped+1))
    continue
  fi
  printf 'converting %s/%s.mp4 -> %s/%s.ogv\n' "$hero_id" "$kind" "$hero_id" "$kind"
  # Map only the primary video (and audio if present). Drop attached album-art MJPEG.
  # Keep Vorbis audio when the source has an audio stream so in-game clips can duck music.
  if ffmpeg -hide_banner -y -i "$mp4" -map 0:v:0 -map 0:a:0? \
      -c:v libtheora -q:v "$Q" -r 24 -vf "scale=$SCALE" \
      -c:a libvorbis -q:a 3 -ac 2 -ar 44100 \
      "$out" </dev/null; then
    converted=$((converted+1))
  else
    printf 'FAILED: %s/%s\n' "$hero_id" "$kind" >&2
    rm -f "$out"
    failed=$((failed+1))
  fi
done
IFS=$old_ifs

python3 - "$DST" << 'PY'
import json, os, sys
dst = sys.argv[1]
manifest = {}
for hero_id in sorted(os.listdir(dst)):
    folder = os.path.join(dst, hero_id)
    if not os.path.isdir(folder):
        continue
    kinds = []
    for kind in ("intro", "victory"):
        path = os.path.join(folder, f"{kind}.ogv")
        if os.path.isfile(path) and os.path.getsize(path) > 0:
            kinds.append(kind)
    if kinds:
        manifest[hero_id] = kinds
path = os.path.join(dst, "manifest.json")
with open(path, "w", encoding="utf-8") as f:
    json.dump(manifest, f, indent=2)
    f.write("\n")
print("manifest: %s (%d heroes)" % (path, len(manifest)))
for hero_id, kinds in manifest.items():
    print("  %s: %s" % (hero_id, ", ".join(kinds)))
PY

printf 'converted=%s skipped=%s failed=%s\n' "$converted" "$skipped" "$failed"
if [ "$failed" -gt 0 ]; then
  printf 'convert_hero_videos: FAIL (%s conversions failed)\n' "$failed"
  exit 1
fi
printf 'convert_hero_videos: PASS\n'
