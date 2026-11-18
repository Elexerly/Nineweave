# Web source reconstruction, 18 November 2026

This is a source recovery branch, NOT a deployment branch. Do not deploy its inherited old backend/public directory wholesale. The verified hosting snapshot remains `040c06c58aab754bfbd7eac8f422d49dd6cbb6c8` on `review/live-host-2026-11-18`.

## Provenance

The released web build identifies `fa059ed19a066614b7347dfc7ce3630a8ced40bb`; that commit and its Nick predecessor `51616260115d9718f075c7da4a0b4cfdab954128` were not present on GitHub or the Mac's shared repository. This is a reconstruction, not a claim to recover the original commits/history.

Base `cdff998bdda1890c6da57e9338ddcf1c47802b25` recovered the pure web source through released tutorial, timer and account-unlock patches on `1cccd15`. Applied the preserved native Nick change `7cc4a53`, resolving existing account-unlock overlap and excluding the native ad-report heading and native readiness test. Then applied the exact `release/six-second-intros/client-source.patch` from transfer `e1385bd92aea00f15c4b58c4ddf0a1705bf83cec`.

The existing conflicted recovery worktree was left untouched. No backend, database, installed app or production host was changed. No AdMob/native bridge code was introduced.

## Release comparison

Godot 4.7.2 `ed1daf0bf`, headless import then `--export-pack Web`, produced 843 entries versus 843 in the released pack. No missing or extra entries. All **52 compiled GDScript files match byte-for-byte**, including main game controller and video overlay. 833/843 total entries are byte-identical. All **66 external OGV videos** match the host snapshot byte-for-byte.

Live pack SHA256: `8cf30a10e4a2350def23aca587310a806015e85fb32eab53b32140a061448d62`, 17,144,772 bytes. It was independently downloaded from `https://nineweave.grok.me/index.pck` and matched snapshot Git blob `38fe89c649b42d259874b30fc2f0e3206ef56a37`. Both live domains' BUILD_INFO reported the same six-second source.

The ten remaining differences are generated metadata:
- Seven `assets/art/*.png.import` files differ only in their `uid` value (comparison normalized only that field).
- Global script-class cache contains the same definitions in a different order.
- UID cache is regenerated.
- Packed main scene differs by four bytes: Godot's generated node `unique_id`. Loading/saving each packed scene confirmed identical structure/properties/script path; generated external-resource labels also differ in textual dumps.

Actual texture/audio payloads, project configuration and gameplay scripts match. This establishes compiled client equivalence, not original source-comment or Git-history identity. Full HTML/WASM re-export and interactive browser/device QA have NOT been done as part of this recovery. Only the iOS template is installed on this Mac; pack-only export does not require installing a Web template.

Reproduce payload comparison with `python3 godot/tools/compare_recovery_pack.py LIVE.pck RECOVERED.pck`. Detailed results: `pack-comparison.json`. Local test results will be recorded separately after completion. Tests run headlessly using fixtures, without production writes.
