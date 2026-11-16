#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
GODOT=${GODOT:-/workspace/tools/godot/Godot_v4.7.2-stable_linux.x86_64}
OUT=${1:-$ROOT/.godot/r5c/shots}
export XDG_DATA_HOME=${XDG_DATA_HOME:-/tmp/nineweave-r5c-capture/data}
export XDG_CONFIG_HOME=${XDG_CONFIG_HOME:-/tmp/nineweave-r5c-capture/config}
export XDG_CACHE_HOME=${XDG_CACHE_HOME:-/tmp/nineweave-r5c-capture/cache}
mkdir -p "$OUT" "$XDG_DATA_HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME"
for dims in 390x844 1366x768; do
  for scenario in versus victory defeat victory_still chooser tournament_lobby tournament_private coming_soon bracket countdown registered online_lobby; do
    "$GODOT" --path "$ROOT" --rendering-method gl_compatibility --resolution "$dims" --script res://tools/capture_r5c.gd -- --scenario "$scenario" --out "$OUT/$dims-$scenario.png"
  done
done
for scenario in victory chooser bracket; do
  "$GODOT" --path "$ROOT" --rendering-method gl_compatibility --resolution 844x390 --script res://tools/capture_r5c.gd -- --scenario "$scenario" --out "$OUT/844x390-$scenario.png"
done
printf 'NINEWEAVE ROUND5C CAPTURES PASS (27/27) -> %s\n' "$OUT"
