#!/bin/sh
# Round 5a captures. Run under a real display, e.g. xvfb-run -a sh godot/tools/capture_r5a.sh.
# Deliberately does not start Xvfb or install anything itself. No network: HTTP is faked.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
GODOT=${GODOT:-/workspace/tools/godot/Godot_v4.7.2-stable_linux.x86_64}
OUT=${1:-/workspace/nineweave-r5a-shots}
export XDG_DATA_HOME=${XDG_DATA_HOME:-/tmp/nineweave-capture/data}
export XDG_CONFIG_HOME=${XDG_CONFIG_HOME:-/tmp/nineweave-capture/config}
export XDG_CACHE_HOME=${XDG_CACHE_HOME:-/tmp/nineweave-capture/cache}
mkdir -p "$OUT" "$XDG_DATA_HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME"
shot() { # size scenario
  "$GODOT" --path "$ROOT" --rendering-method gl_compatibility --resolution "$1" --script res://tools/capture_r5a.gd -- --scenario "$2" --out "$OUT/$1-$2.png"
}
for scenario in waiting opponent_joined timer_ring still_there chat_open report_dialog leave_confirm end_no_show old_server_chat_hidden; do
  shot 390x844 "$scenario"
done
for scenario in waiting chat_open; do
  shot 1366x768 "$scenario"
done
printf 'NINEWEAVE R5A CAPTURES PASS -> %s\n' "$OUT"
