#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
GODOT=${GODOT:-/workspace/tools/godot/Godot_v4.7.2-stable_linux.x86_64}
export XDG_DATA_HOME=${XDG_DATA_HOME:-/tmp/nineweave-tests/data}
export XDG_CONFIG_HOME=${XDG_CONFIG_HOME:-/tmp/nineweave-tests/config}
export XDG_CACHE_HOME=${XDG_CACHE_HOME:-/tmp/nineweave-tests/cache}
LOGS=${LOGS:-/tmp/nineweave-test-logs}
mkdir -p "$XDG_DATA_HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" "$LOGS"
failed=0
for suite in rules ai layout ui round3 round3b; do
  status=0
  "$GODOT" --headless --path "$ROOT" --script "res://tests/run_${suite}_tests.gd" >"$LOGS/$suite.log" 2>&1 || status=$?
  cat "$LOGS/$suite.log"
  if [ "$status" -ne 0 ] || rg -q 'SCRIPT ERROR|Parse Error|^ERROR:|^WARNING:|NINEWEAVE_.* FAIL' "$LOGS/$suite.log"; then failed=$((failed+1)); fi
done
if [ "$failed" -eq 0 ]; then
  printf 'NINEWEAVE ROUND3B TEST SUMMARY: PASS (6/6 suites; rules, AI, layout, UI, Round 3, Round 3b)\n'
else
  printf 'NINEWEAVE ROUND3B TEST SUMMARY: FAIL (%s of 6 suites failed)\n' "$failed"
fi
exit "$failed"
