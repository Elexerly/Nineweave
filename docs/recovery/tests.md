# Recovery validation

18 November 2026, Godot 4.7.2 stable `ed1daf0bf`, Mac headless.

- Headless import: completed without script/parse errors.
- Pack-only Web export: completed, payload comparison in `pack-comparison.json`.
- Existing sequential runner: 37/37 suites PASS, exit 0.
- Additional suites: Nick 12 checks, unlocks 11, unlock contract 101, intro duration 42; all PASS, exit 0.
- Total: **41/41 suites passed**, no SCRIPT ERROR, Parse Error, ERROR, WARNING or suite failure markers in the 41 logs.
- Rules: 3,121,037 checks, 2,400 fuzz games.
- AI: 2,566 checks; Medium 29/30 wins, Hard 30/30 against Easy; timing max 209.79 ms against 450 ms ceiling.
- All 66 video sidecars match preserved live host snapshot.
- `git diff --cached --check`: passed.

Runner updated to include all four additional suites in future runs. Gameplay files were unchanged after verification. Generated UID files and build logs are local artifacts, not committed. No production API writes, migrations, publish, or native installation occurred. Browser/physical-device interaction was not tested in this recovery pass; source equivalence is established by all 52 compiled GDScript payloads matching the released pack exactly.
