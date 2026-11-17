# Tutorial + idle fairness: review/transfer only

**DO NOT merge, reset to, deploy or publish this branch as an app.** Its tree contains transfer artifacts only, not application source. No action in this packet has been applied to production.

Client source: `48beb0f625bc6be188d1afbe61c26b6d0b8b8f78` (changes after tested online-usability source `fdef757`). Server changes: `6b2571d` then `28f7403`, based on historical `1e22629`. The current live project has at least a newer Sitebloc CORS change; NEVER overwrite it with the historical backend branch.

## Read-only findings (2026-11-17)

Both public hosts serve the prior online-usability pack `d4007395e6c4903c6af90dd3a6e22f798d381f11c4db38c3fddc9dc7c92681ad` byte-for-byte, source `fdef757`. Both API preflights return204 with exact Sitebloc origin, and capabilities do not yet advertise tutorial completion. The candidate Neon database has migrations0002–0007;0008/0009 are pending. Its configured restore retention is6hours, but actual restorable window has not been independently proven. The hosting environment's redacted database hostname+database name must still be compared against the connected Neon endpoint before any migration.

## Exact sequence before a coordinated release

1. **Verify target/recovery.** In the current publishing project, report only the database hostname and database name, never a URL/password/token. Compare with the connected Neon project/branch. Verify a usable pre-migration restore point/backup and rollback owner. Do not assume six-hour configured retention proves recoverability. Stop if target/recovery cannot be confirmed.
2. **Preserve current work.** Record current publishing commit/tree and current three client files; ensure local edits are saved. Compare touched backend paths against `manifest.json`. A mismatch is a review item, not permission to replace a file. `cors.ts`, environment, database connection, admin settings, privacy policy, runtime JS/WASM, audio/videos and all other files must remain untouched.
3. **Review/stage backend patch only.** Fetch this branch into a separate checkout. In an isolated copy of the current application use `git apply --check backend-changes.patch` before applying the reviewed diff. Resolve any conflicts against current live work, never by resetting branches. Patch includes runtime API/players/rooms changes, additive migrations0008/0009, matching tests and API docs. It contains no CORS change. Run isolated server tests/typecheck before staging deployment. **Do not run `npm run build` before the verified target and usable backup/restore gates: its build script automatically runs `db:migrate`.** Preview preparation must not invoke live migrations.
4. **Verify/stage client.** From this release folder run `python3 verify_transfer.py /tmp/nineweave-tutorial-index.pck`. It only verifies hashes and assembles a temporary pack. Copy ONLY this assembled PCK, `index.html`, and `BUILD_INFO.txt` into the preserved publishing project's `public/` folder. The64 video sidecars and all other export files are unchanged. Verify preview source48beb0f and mainPack against manifest.
5. **Controlled migration, then coordinated deployment.** Only once target, recovery, reviewed diff and owner authorization are established: apply0008 then0009 with the normal migration ledger. Verify new columns and recorded migrations. Then deploy the matching server and staged client together. Avoid a backend-only public interval with old clients missing the strike warning. Ask testers to refresh/restart.
6. **Post-publish checks.** Both hosts: health/capabilities including `tutorial_completion:true`, exact Sitebloc CORS, BUILD_INFO and pack hash. Two distinct real-device accounts: first tutorial before lobby, completion persists after relogin/device switch, manual How to Play, timely-move reset, separate-player streaks, one10-second acknowledgment per turn, third prompt loss at25seconds, reconnect/no timer reset, rematch reset. Do not delete/create unrelated player records while checking.
7. **Rollback if needed.** Restore the preserved application/client version, keeping additive database columns in place. Do not drop columns or restore the entire database blindly, which could discard tester activity. Use the verified backup/restore procedure only if data repair is actually needed and authorized.

## iOS integration

`client-source.patch` is for source review/integration only, based on fdef757. Native work has later Retina/scaling changes: apply only these source changes into an isolated native worktree; preserve project/export/signing settings. Current review found clean source tests; do not overwrite native workspace wholesale. No simulator downgrade, phone installation, signing change or app submission is included here.

## Verified QA / outstanding QA

- Clean37/37 Godot suites; tutorial24, idle29; independent final review passed.
- Server166/166 tests + typecheck; targeted61/61 race/tournament checks.
- Export smoke19/19; pack16,727,388bytes; only3 export files changed;64 video sidecars unchanged.
- Existing Mac captures at320x568/390x844 show readable ring/warning and tutorial. Final expired-highlight correction was code/test verified, not visually recaptured; wide/opponent captures and real two-player testing remain pending. GUI checks stopped at owner's request.
- Broader historical script suite has15 pre-existing missing-fixture/skill failures reproduced on untouched baseline; not represented as fully passing.

**Nothing in this packet authorizes immediate publication. Report verification results and blockers before the owner publishes.**
