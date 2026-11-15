#!/bin/sh
# Run this script under a real display, e.g. xvfb-run -a sh godot/tools/capture_shots.sh.
# Deliberately does not start Xvfb or install anything itself.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
GODOT=${GODOT:-/workspace/tools/godot/Godot_v4.7.2-stable_linux.x86_64}
OUT=${1:-/workspace/nineweave-r3-shots}
export XDG_DATA_HOME=${XDG_DATA_HOME:-/tmp/nineweave-capture/data}
export XDG_CONFIG_HOME=${XDG_CONFIG_HOME:-/tmp/nineweave-capture/config}
export XDG_CACHE_HOME=${XDG_CACHE_HOME:-/tmp/nineweave-capture/cache}
mkdir -p "$OUT" "$XDG_DATA_HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME"
shot() { # size scenario progress name
  "$GODOT" --path "$ROOT" --rendering-method gl_compatibility --resolution "$1" --script res://tools/capture_shots.gd -- --scenario "$2" --progress "$3" --out "$OUT/$1-$4.png"
}
for size in 390x844 844x390 867x553 2601x1659 669x787 1366x1024 1024x768 1280x720; do
  for scenario in title midgame claim win; do
    shot "$size" "$scenario" 0.45 "$scenario"
  done
done
# Settled emblem / victory panel, an early claim frame and the AI thinking state.
for size in 390x844 867x553; do
  shot "$size" claim_end 1.0 claim_end
  shot "$size" win_end 0.95 win_end
  shot "$size" claim 0.2 claim-early
  shot "$size" thinking 0.45 thinking
done
for size in 867x553 2601x1659 669x787; do
  shot "$size" duo_hinge 0.45 hinge
done
for size in 430x932 375x667 360x640 932x430 667x375 568x320 1920x1080; do
  shot "$size" midgame 0.45 midgame
done
# Round 3e: Safari-short portrait viewports (toolbars visible).
for size in 390x664 390x620; do
  shot "$size" midgame 0.45 midgame
done
for scenario in settings online; do
  shot 390x844 "$scenario" 0.45 "$scenario"
done

# Round 3: deterministic character presentations at the five review sizes.
for size in 390x844 844x390 867x553 669x787 1366x1024; do
  for scenario in character_select lock_in claim_pop win_spotlight duo_panel last_move reaction; do
    shot "$size" "$scenario" 0.5 "$scenario"
  done
done

printf 'NINEWEAVE CAPTURES PASS -> %s\n' "$OUT"
