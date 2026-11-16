#!/bin/sh
# Run under xvfb-run. Optional output argument for restricted workspaces.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
GODOT=${GODOT:-/workspace/tools/godot/Godot_v4.7.2-stable_linux.x86_64}
OUT=${1:-/workspace/nineweave-r5b-shots}
export XDG_DATA_HOME=${XDG_DATA_HOME:-/tmp/nineweave-r5b-capture/data}
export XDG_CONFIG_HOME=${XDG_CONFIG_HOME:-/tmp/nineweave-r5b-capture/config}
export XDG_CACHE_HOME=${XDG_CACHE_HOME:-/tmp/nineweave-r5b-capture/cache}
mkdir -p "$OUT" "$XDG_DATA_HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME"
for scenario in bracket_start bracket_semis bracket_final_rival eliminated champion animation_advance; do
  "$GODOT" --path "$ROOT" --rendering-method gl_compatibility --resolution 390x844 --script res://tools/capture_r5b.gd -- --scenario "$scenario" --out "$OUT/390x844-$scenario.png"
done
for scenario in bracket_start champion; do
  "$GODOT" --path "$ROOT" --rendering-method gl_compatibility --resolution 1366x768 --script res://tools/capture_r5b.gd -- --scenario "$scenario" --out "$OUT/1366x768-$scenario.png"
done
printf 'NINEWEAVE ROUND5B CAPTURES PASS (8/8) -> %s\n' "$OUT"
