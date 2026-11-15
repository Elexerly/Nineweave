# Nineweave Round 4e — first-play guide and optional email

All changes are inside `godot/`. The rules kernel, board renderer and layout,
hero-video layer, roster (including **Beth Solstice**), web app, server and
database are unchanged. No commits, tags, pushes, remote changes, or live-service
requests were made.

## Tutorial

The first match opens a six-step guided demo after the existing versus/hero
intro finishes. Direct match starts and resumed games also check the flag.
`settings/store.gd` saves `tutorial_completed` in `user://nineweave.cfg` on
completion **or Skip**. An interrupted guide can run again; a finished or skipped
guide never runs automatically again on that installation.

`ui/tutorial.gd` temporarily lends its own rules model to the existing board
renderer. Its demonstration moves, claims and win never enter the real match,
transport, undo history, or resume data. Board geometry and rendering stay
unchanged. Surrounding controls are shielded, the match clock and AI pause, and
drawn arrows explain cell-to-board routing. Tap the scene or Next to advance;
Skip is always visible, Escape skips, and Enter/Space advance. Reduced motion
shows completed arrows immediately and uses the existing reduced-motion marks.

The examples cover an opening square, the matching destination, the opponent's
reply, claiming three small squares, winning three big boards, and free choice
when a destination is full or won. The final free-choice example is calculated
by the real rules kernel. How to Play in the main menu and Settings replays the
guide and returns to the prior screen. Online updates remain authoritative in
the real model while the demo is visible; closing the guide restores the latest
position or match-result presentation.

## Screen name and optional email

The existing Create Screen Name form and linked Terms/Privacy/13-or-parent
consent sentence remain first, with no checkboxes. Successful name creation
opens **Add an email to back up your account (optional)**. Save validates and
stores a trimmed email; **Continue without email** stores only the decision.
Both paths continue to the intended menu or online lobby. If the app closes
between name creation and that decision, it resumes the optional step. Existing
accounts are offered the step once when they next launch.

Settings → **Account email** uses the same form to add/change an address later.
It prefills the saved address, retains drafts through resizing, supports Enter
to save, and leaves the prior saved address intact on invalid input or Return.
Email and `email_prompt_done` live in `user://nineweave-device.cfg` alongside the
existing local device account. All saved addresses are **Not verified**.

The form explicitly explains that local storage alone does **not** enable
backup or account transfer yet. No email request is sent to the current server,
including registration, consent PATCH, rename, hero update and refresh. The
account controller is the persistence boundary (`save_email`, `email_changed`);
the reusable form has an independent verification status and status-update
method so a future code-entry stage can be added without replacing onboarding
or the Settings flow. Local config cannot establish verified ownership.

## Server integration note — needed later, not implemented

Current `/api/nineweave/me` does not accept `email`. Before enabling sync:

1. Add an explicitly advertised capability, for example
   `GET /api/nineweave/me` → `capabilities.email: true`. Until it is advertised,
   the client must continue storing email locally without sending probe writes.
2. Extend authenticated `PATCH /api/nineweave/me` to accept an optional
   `email: string` (basic validation, max 254 characters), scoped to the device
   bearer identity. Return `email` plus server-owned `email_status` and/or
   `email_verified_at` from PATCH and GET. Changing an address resets ownership
   verification; an unverified address must not grant recovery or transfer.
3. Add authenticated `POST /api/nineweave/me/email/verification` to send a
   short-lived code and return a challenge ID/expiry, then
   `POST /api/nineweave/me/email/verification/confirm` accepting
   `{challenge_id, code}`. Enforce expiry, retry limits and resend throttling on
   the server. Only a successful server confirmation may mark the email
   verified. These endpoint names are a proposed contract for backend work.
4. Wire the controller's verification response into the same form's
   `set_verification_status` and a code-entry stage. Recovery/transfer requires
   its own authenticated server flow; it is not provided by this local feature.

## Tests and review

Run `sh godot/tools/run_tests.sh` with Godot 4.7.2. The runner includes
`tests/run_round4e_tests.gd`; its fixtures use fake HTTP only. The prior Round 4c
suite now advances through the optional step and marks established-player
fixtures as having completed the guide.

Round 4e covers first-match start, intro ordering, completion and skip across
restart, menu/Settings replay, real-match isolation, opponent-first AI, online
updates/resync/results during the guide, reduced motion, synthetic touch/mouse
deduplication, both email paths, optional-step restart, validation, later edits,
draft retention, local persistence, absence of email network writes, unchanged
consent, Beth's name, and touch/layout bounds at seven phone/desktop sizes.

Capture fixtures added to `tools/capture_shots.gd`: `tutorial`,
`tutorial_claim`, `tutorial_win`, `email`, `account_email`. They use the new UI
and never contact the service. Real pixel capture was attempted using Xvfb;
the sandbox could not establish display sockets, so visual inspection was not
possible. Headless geometry/text checks do not certify rendered pixels.

Godot 4.7.2 results:

- `sh godot/tools/run_tests.sh`: **PASS, 14/14 suites**, including **378 Round
  4e checks**; no script errors, engine errors or warnings. Full output:
  `tests/ROUND4E_LAST_RUN.txt`.
- `sh godot/tools/export_web.sh godot/.godot/round4e-web`: **PASS**; release
  PCK **16,704,632 bytes**, 20 audio recordings checked, and all three hero-video
  sidecars byte-identical. Output: `tests/ROUND4E_EXPORT.txt`.
- `tools/check_round4e_pack.gd` run with `--main-pack` against that release PCK:
  **PASS**. Checks first-play/skip/persistence/replay, email save/continue and
  unchanged consent from the compiled release resources, using local-only
  fixtures and no network. Output: `tests/ROUND4E_PACK.txt`.

To repeat the packed release check (with the usual temporary XDG test dirs):

```sh
/workspace/tools/godot/Godot_v4.7.2-stable_linux.x86_64 --headless \
  --main-pack godot/.godot/round4e-web/index.pck \
  --script /workspace/nineweave/godot/tools/check_round4e_pack.gd
```
