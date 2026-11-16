# Round 5e — tutorial controls and reliable versus intros

Client-only continuation from `1ee00067` (Round 5d signup fixes). No database,
server, admin, game rules, or board-renderer changes.

## Tutorial
- Back and Next are always visible; Next becomes Done at the last step.
- Starts with the existing three-second automatic progression.
- Back/Next, keyboard navigation, and manual tap-to-advance stop automatic
  progression for the rest of that tutorial session.
- Skip remains available. Existing persistent completion-on-finish-or-skip and
  explicit How to Play replay behavior is unchanged.
- Rotation preserves the current step and manual reading state; replay resets it.

## Versus intros
The web overlay previously sampled the cache once, so cold downloads finishing
later never played. It now waits up to 12 seconds for both intro downloads and
starts available streams together. Loading remains skippable; timeout, missing
media, and decoder failure cannot trap the match. Victory behavior is unchanged.

## Online tournaments
Existing source client and main-branch backend are implemented. Read-only checks
on November 16 confirmed live capabilities advertise tournaments and the public
listing returns JSON. The old Round 5c report's undeployed-backend note is stale.
Live multiplayer end-to-end play is not yet verified. Local backend tests use
isolated in-memory storage, not the live database.

## Verification
See the handoff report for final test results and remaining rendered-QA limits.

Validation on Godot 4.7.2:
- 19 Godot suites passed, 3,200,818 checks. First aggregate run had one obsolete
  assertion requiring Next to be absent; after updating that superseded contract,
  the affected Round 4g suite passed. Other 18 suites were unchanged and passed.
- Production web export passed: 16,769,148-byte PCK, 64 byte-identical video
  sidecars, 20 packed audio clips.
- Exported PCK smoke passed 326 checks (including 320 hero textures).
- Existing backend tests at main passed: 125 tests / 26 suites, isolated in-memory
  PGlite only. No live accounts, matches, tournaments or database writes.
- No rendered/playback claim: local build could not be reached from the available
  cloud browser (HTTP response failure), and this executor has no native display.
