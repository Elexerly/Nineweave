# Seven-tap codes and permanent background unlocks: staged transfer

This branch is an artifact carrier, NOT a deployable site branch. Do not merge it wholesale or reset your hosting project to this branch: its unrelated root/public files are old. Preserve the current hosted backend, Sitebloc CORS, game engine, videos, database connection, admin settings, privacy page and all newer work.

## What this adds

In Options, tap the AI difficulty control seven consecutive times. The first six taps retain the normal difficulty cycling. Another control/navigation breaks the sequence. The seventh opens a code box; Back returns to Options. Appearance replaces Cosmetics.

Five free procedural background prototypes are available: Blizzard, TicTacToe, 010127 (New Year), 0704027 (July Fourth; exact user spelling), Patrick (St Patrick's Day). Codes ignore case and trim whitespace. Ownership is server-authoritative, persists through account recovery, and is removed with account deletion. Duplicate redemption is safe. Offline/error responses do not grant local ownership.

W2026, G2026, J2026, B2026, N2026, E2026, JB2026, T2026, JY2026, GM2026 and D2026 are reserved only. They show not yet available and grant nothing until their real characters and entitlement checks are added.

## Stage into the existing hosted project

1. Fetch this transfer branch into a separate directory. Run `python3 release/account-unlocks/verify_transfer.py /tmp/nineweave-unlocks-index.pck`. It verifies all hashed payloads and assembles only a PCK; it does not deploy or run SQL.
2. In the CURRENT hosted project, run `git apply --check <transfer>/release/account-unlocks/backend-source.patch`. Only apply if this succeeds. If it conflicts, inspect and port the narrow changes; do not reset the project or overwrite newer files. The backend patch does not touch cors.ts. It includes migration 0011 and tests. Migration 0010/version enforcement is a separate feature and must not be pulled in accidentally.
3. Copy the verified assembled PCK to `public/index.pck`, and this packet's `index.html` and `BUILD_INFO.txt` to their corresponding public files. Do not replace index.wasm, index.js, videos or other assets. The export uses Godot 4.7.2 Compatibility, non-threaded, matching the live game's engine family. Verify compatibility with the hosted engine before publication.
4. Do NOT apply client-source.patch or integration-tests.patch into the hosted site. They are source backup for the editable Godot project and must be integrated separately, preserving the iOS-specific changes.
5. Run online tests and typecheck with no production database URL. Inspect the preview on desktop and narrow phone; test seven taps, Back, Appearance, repeated/invalid codes and account switching. Do not call a headless geometry test visual approval.
6. Stop and report the staged hashes and preview findings. Patrick will decide when to publish. The site's normal build runs pending migrations, so publishing applies additive migration 0011 to its configured database. No manual player edits are needed. Review any OTHER pending migrations instead of silently running them.

## Expected pack

SHA256: `bc22a91c0375acb4915d084ec22ec1b052af5022651cb4ee122d14dd23ca0891`
Bytes: 16,734,252
Client source: `8d10a3625181c261a3c909ded30e1e2430e39457`
HTML pack query: `index.pck?v=bc22a91c0375acb4`

## Verification and limitations

- Fresh rerun: seven-tap/client unlock checks and actual API-response contract checks (101 assertions), headless Godot.
- Existing final-code online API run: 177/177 passed; TypeScript typecheck passed.
- Rules fuzz run: 3,121,037 checks, zero failures, 2,400 games.
- Earlier aggregate npm test: 15 script-fixture failures also reproduced on unchanged backend baseline. Not a full green aggregate result.
- Migration 0011 CREATE statements and repeat were rehearsed on the existing isolated Neon rehearsal branch, with 13 players / 4 rooms / 3 matches unchanged and zero grants. No production migration was run.
- The five backgrounds are prototypes, not visually approved final artwork. Real rendered browser/phone QA and live end-to-end redemption are still outstanding.
- The iPhone's Report-ad layout change is iOS-specific and not included in this web source. This packet does not update the installed iPhone app.
- Nothing published and no production accounts modified by preparation of this transfer.

## Apple submission notes

Keep the requested free Easter eggs for testing. Before App Review, document the exact seven-tap access, every included character/background, working codes, account persistence and that no payment is required. Apple's guidelines 2.5.19 and 3.1.1 require review of this design; documentation is not a guarantee of approval. No App Store submission is made by this packet.
