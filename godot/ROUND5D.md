# Round 5d — onboarding email verification

Fixed both client paths that could skip verification. Changes are confined to
`godot/`; no git commands, server changes, board changes, or mechanics changes.

- A 401 from GET/PATCH `/me`, consent, or any email operation clears the device
  token on disk and in memory, discards queued requests with that token, and
  silently registers again with the saved name and original consent. Email
  recovery stores the address under the new identity and requests a fresh code;
  old challenges and code drafts are discarded. A registration 409 returns to
  the mandatory name screen with a clear name-taken message. Repeated credential
  rejection is bounded and offers a name retry instead of looping.
- Save waits for registration, consent, and the player response's email
  capability, showing **“Setting up your account…”**. It then stores the email,
  sends the code, and opens code entry. Save no longer navigates out of
  onboarding. An unavailable server, an older/disabled email capability, or a
  25-second setup timeout displays an explicit local-only, unverified save
  message on the email screen. Leaving requires an explicit Continue action.
- Mandatory screen-name creation and **“Continue without verifying”** on the
  code stage are preserved. Settings retains its existing local-save behavior.

Files changed: `net/device_account.gd`, `main/main.gd`,
`tests/run_round5d_tests.gd` (new), `tests/run_round4e_tests.gd`,
`tests/run_round4g_tests.gd`, `tools/run_tests.sh`, and this report.

Validation: `LOGS=/workspace/nineweave/godot/.godot/r5d/test-logs sh godot/tools/run_tests.sh`
from the repository root: **PASS: 19/19 suites,
3,200,776 checks, zero failures**, with no script errors or warnings.
Round 5d contributes **188 checks** using injected HTTP only: stale-token
recovery, consent preservation, each email endpoint, conflicts, queued stale
requests, pending registration/capabilities, code entry, explicit fallback,
timeouts, cancellation, and bounded retries. Earlier email suites now assert
that local-only onboarding Save stays visible until Continue.

Evidence: `.godot/r5d/full-tests.log`, `.godot/r5d/test-logs/`.
Native screenshot verification was attempted, but X11/Wayland display startup
failed; no rendered screenshot verification is claimed. Details:
`.godot/r5d/capture.log`. No live accounts or email were created during tests.
