#!/bin/sh
# Under an existing real display, e.g. xvfb-run -a sh godot/tools/capture_sequence.sh.
# One launch, exact i/FPS times, inclusive final frame. No network or installs.
set -eu
if [ "$#" -ne 5 ]; then
  printf 'Usage: capture_sequence.sh SIZE SCENARIO FPS DURATION OUTDIR\n' >&2; exit 2
fi
ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
GODOT=${GODOT:-/workspace/tools/godot/Godot_v4.7.2-stable_linux.x86_64}
export XDG_DATA_HOME=${XDG_DATA_HOME:-/tmp/nineweave-capture/data}
export XDG_CONFIG_HOME=${XDG_CONFIG_HOME:-/tmp/nineweave-capture/config}
export XDG_CACHE_HOME=${XDG_CACHE_HOME:-/tmp/nineweave-capture/cache}
mkdir -p "$5" "$XDG_DATA_HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME"
"$GODOT" --path "$ROOT" --rendering-method gl_compatibility --resolution "$1" --script res://tools/capture_shots.gd -- --scenario "$2" --fps "$3" --duration "$4" --sequence "$5" --time 0
