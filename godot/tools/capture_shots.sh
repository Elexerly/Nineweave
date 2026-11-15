#!/bin/sh
# Run this script under a real display, e.g. xvfb-run -a sh godot/tools/capture_shots.sh.
# Deliberately does not start Xvfb or install anything itself.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
GODOT=${GODOT:-/workspace/tools/godot/Godot_v4.7.2-stable_linux.x86_64}
OUT=${1:-/workspace/nineweave-r1-shots}
export XDG_DATA_HOME=${XDG_DATA_HOME:-/tmp/nineweave-capture/data}
export XDG_CONFIG_HOME=${XDG_CONFIG_HOME:-/tmp/nineweave-capture/config}
export XDG_CACHE_HOME=${XDG_CACHE_HOME:-/tmp/nineweave-capture/cache}
mkdir -p "$OUT" "$XDG_DATA_HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME"
for size in 390x844 844x390 867x553 2601x1659 669x787 1366x1024 1280x720; do
  for scenario in title midgame claim win; do
    progress=0.45
    [ "$scenario" != claim ] || progress=0.62
    "$GODOT" --path "$ROOT" --rendering-method gl_compatibility --resolution "$size" --script res://tools/capture_shots.gd -- --scenario "$scenario" --progress "$progress" --out "$OUT/$size-$scenario.png"
  done
done
for size in 867x553 2601x1659; do
  "$GODOT" --path "$ROOT" --resolution "$size" --script res://tools/capture_shots.gd -- --scenario duo_hinge --out "$OUT/$size-hinge.png"
done
for scenario in settings online; do
  "$GODOT" --path "$ROOT" --resolution 390x844 --script res://tools/capture_shots.gd -- --scenario "$scenario" --out "$OUT/390x844-$scenario.png"
done
printf 'NINEWEAVE CAPTURES PASS -> %s\n' "$OUT"
