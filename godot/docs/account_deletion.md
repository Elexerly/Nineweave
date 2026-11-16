# Own-account deletion client: unpublished preview

This feature branch is not deployed. It requires the matching authenticated server implementation in `plax/account-deletion`. The public test site remains Round 5h until an explicitly coordinated release. No production database, server or policy changes were made.

## Behavior

- Options > Account shows deletion only when the server advertises `account_deletion:true` (an unresolved attempt can be retried).
- Two confirmations, including typing `DELETE MY ACCOUNT`, precede authenticated `DELETE /api/nineweave/me` with exactly `{"confirm":"DELETE MY ACCOUNT"}`. The client never chooses a target player ID.
- Only exact successful deletion response (`deleted:true`, `retained_gameplay_label:"####"`) confirms server deletion. The client then retires request owners and clears local credentials, account/profile progress, saved game and tournament progress. It never automatically creates a replacement account.
- Warnings distinguish the active game database from hosting/email-provider records, backups and copies held by others. Active matches and active tournaments can block deletion.
- Unknown outcomes retain credentials for retry/recovery but block automatic registration. A definite first 409 rejection can clear uncertainty; a retry409 does not resolve an earlier unknown outcome.
- Explicit verified-email recovery can restore an existing account. If deletion succeeded but its response was lost, **Start fresh on this device** provides a separate local-only escape: warnings, then typing `CLEAR THIS DEVICE`. It sends no request, does not assert server deletion, and opens blank onboarding. Creating a new account remains a separate deliberate action.

## Persistence and race protection

Before DELETE, the client persists an uncertainty flag. Web builds additionally write/read a synchronous, non-secret localStorage marker scoped to deployment pathname and store path. Storage denial prevents submission.

Terminal deleted/cleared/recovered markers carry a random non-secret resolution nonce that must match the saved configuration. Terminal markers are retained so stale asynchronous browser filesystem snapshots cannot resurrect old credentials. A stale deleted/cleared marker forces local cleanup; stale recovered state remains unresolved. Marker checks also occur before refresh, registration and401 recovery in already-open tabs. Configuration save failure leaves account creation blocked.

The protocol does not defeat a user deliberately clearing all browser storage or undo actions in another independent device. No claim of provider/backups deletion, absolute anonymity or legal compliance is made.

## Verification boundaries

Tests use local fake HTTP and isolated data only. Real pointer/keyboard input covers confirmation/cancel/retry, uncertain restart, local reset and deliberate fresh onboarding. Generated marker JavaScript is also executed with a Node localStorage stub; this is not a real-browser persistence or visual rendering test. No real accounts or email sends were used. Cloud browser WebGL2 limitations prevent claiming a rendered browser walkthrough.

Release prerequisites: independent review, matching backend deployment authorization, a safe isolated integrated test target, verification of provider retention/contact details before policy publication, and explicit deployment coordination. The policy draft is separate and remains unpublished.

## Local verification (2026-11-16)

- Godot 4.7.2 focused deletion:139 checks passed, including forced failed-save followed by marker merge and real account registration guards.
- Generated browser-marker JavaScript:13 assertions passed in a Node storage stub. No actual browser integration claim.
- Web export:PASS,16,793,028-byte PCK;64 byte-identical video sidecars;20 packed Ogg assets.
- Exported pack resource smoke:326 checks passed (headless).
- Artifact PCK SHA256:`420fd67fc2f0fa3db7012e506b9b31aa5e4f57891be8b2d170a531323f1fd50d`.
- Artifact HTML SHA256:`0cf02f37063c7a403707808f9a811fec536f6ef1985643a6c6e90a84b3e04583`.
- Final aggregate:22/22 suites passed,3,201,071 checks including20 rename checks. Rules/AI unchanged during final persistence-only fix; every affected suite ran afterward against the final source.
