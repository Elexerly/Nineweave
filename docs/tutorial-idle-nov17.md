# Tutorial and online idle changes (Nov 17)

## User-visible behavior

- After account setup (including finishing/skipping optional email), show the first tutorial before character selection, lobby or matchmaking. A returning account refreshes its saved completion first. Starting the tutorial does not mark it complete; finishing or Skip does. Manual How to Play remains available outside an active online match.
- Tutorial completion is per account. Legacy local completion is adopted only for the currently stored account, then the global flag is retired. Offline completion queues a retry. A different account cannot inherit completion; email recovery restores the server value.
- The portrait ring starts immediately with the server's 25-second turn: cyan/blue, amber with 8 seconds remaining, red with 3. Both seats see the active player's same deadline. Reduced motion disables the pulse, not the countdown.
- At 25 seconds the first two consecutive late own turns offer the existing “Still there?” prompt. Without a response or move, the original deadline is 35 seconds. One accepted “I'm here” grants exactly 10 seconds from that acknowledgment to make a legal move, not another full turn. Acknowledging and failing to move is a loss, including on the opening turn. Unacknowledged initial no-shows retain cancellation without loss.
- Three consecutive own turns reaching the 25-second prompt forfeit. After two late turns, the next own turn displays a final warning and its authoritative expiry is 25 seconds. There is no third acknowledgment window. A timely legal own move resets only that player's streak. Opponent moves, invalid attempts, polls and reconnects do not reset it. A late move without clicking “I'm here” still counts, so declining to acknowledge is not a bypass. Rematches reset both streaks.
- Reconnecting does not pause or extend the displayed clock. Expiry waits for the server result rather than awarding a local victory.

## Server work and deployment boundary

Server commits (separate backend branch `plax/tutorial-idle-server-nov17`):
- `6b2571d`: tutorial completion and fixed 10-second acknowledgment.
- `28f7403`: three consecutive late own turns and warning metadata.

Apply these diffs onto the **actual current backend**, preserving its Sitebloc CORS allowance, database environment, admin settings, live files and unrelated later changes. The backend branch's historical base is not a replacement for the live publishing project.

New additive migrations:
- `0008_nineweave_tutorial_idle.sql`: account tutorial boolean and current acknowledgment timestamp.
- `0009_nineweave_late_turn_streak.sql`: per-seat late-turn counters.

Apply migrations before the corresponding server code is served. No migration has been run on Neon, no production account modified, and nothing deployed by this work. Tutorial state is a minimal preference stored on the account and removed by existing account deletion. No new analytics or email sending added.

API additions:
- Authenticated `POST /api/nineweave/me/tutorial/complete` with `{}`; monotonic/idempotent.
- Profile `tutorial_completed`; capability `tutorial_completion: true`.
- Room `consecutive_late_turns`, `opponent_consecutive_late_turns`, `turn_late_limit: 3`; existing `turn_expires_at` is authoritative, including the third-turn cutoff.

Deploy backend and client together in a coordinated release. An older server supports local tutorial completion only and cannot enforce the new rule. An older client can display authoritative deadlines but lacks the explicit strike warning, so prompt testers to refresh/restart after deployment.

## QA and screenshots

Cloud source runner now contains 37 suites. Tests use fake HTTP or isolated in-memory database fixtures, never live Neon.

For actual rendering on a graphical Mac, use `godot/tools/capture_idle_timer.gd` with a chosen window resolution and positional arguments after `--`:

`-- final /tmp/idle-final.png`

Scenarios: `blue`, `amber`, `red`, `confirmed`, `final`, `expired`, `tutorial`; optional third argument `opponent` flips local seat perspective. Capture at 320x568, 390x844, 867x553 and 1366x768. Verify shrinking ring around active portrait, warning readability, exact10-second extension, both seats, and tutorial board visible on the title screen. Script uses fake HTTP. Cloud geometry tests cover screen containment and nonoverlap; rendered Mac verification remains separate.

Native integration must preserve native-only Retina/scaling configuration, including the latest installed scaling fix. Do not overwrite the native worktree with this source branch wholesale.
