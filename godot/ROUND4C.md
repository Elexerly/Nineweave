# Nineweave Round 4c — live online client

Changes are confined to `godot/`. No git commands, network calls, installs,
source-art edits, or visual inspection were used. The producer owns screenshot
and real two-device review.

## Live API and credentials

- `net/json_api.gd` owns `LIVE_ORIGIN = "https://nineweave.grok.me"` and
  `/api/nineweave`. The matching web origin uses relative URLs; other web
  origins and native use the live origin. The JSON boundary queues account
  requests, allows one request at a time, times out after eight seconds, and
  converts network failures, non-JSON responses, and HTTP errors into readable
  messages without engine JSON-parser errors.
- `net/device_store.gd` persists the `nwd_` device token, screen name, legal
  versions, UTC acceptance time, and age confirmation in
  `user://nineweave-device.cfg`. This is independent of the character profile
  and its character-select `onboarded` flag. Seat tokens cannot replace the
  stored device token.
- `HttpPollingTransport` keeps the ephemeral seat token separately. Create/join
  use the device Authorization header; polling uses the seat header; moves,
  rematches and leave include the seat token in the body. No credential is
  displayed, logged, or placed in a URL.
- Leave POSTs the room's `/leave` endpoint before clearing seat state. Its
  short-lived request belongs to the scene-tree root, so closing the room UI
  cannot cancel the forfeit/cancellation. Failure never blocks navigation.
  Device identity remains saved.

## Account and onboarding

- Fresh launch starts on a navy/gold/cyan screen with the slanted screen-name
  plate, the exact **Create Screen Name** button, and the agreement directly
  above it in pale 18px Rajdhani text. There are no consent checkboxes.
- The Terms and Privacy spans open their absolute Nineweave URLs with
  `OS.shell_open`. Local validation requires 1–24 characters. Server 400/409
  errors remain visible beside the retry action.
- Registration sends the legal fields and is followed by a confirming
  `PATCH /me`. Existing devices PATCH instead of registering again. Local
  consent is saved only after the confirming PATCH succeeds. Registration's
  device token survives a failed PATCH so the same account can retry.
- Success continues to the title on first launch, or to the lobby when entered
  through Play Online. The offline/main-menu action is always available;
  server failures explain that Computer and Pass & Play still work.
- Settings name edits have a Save action (and Enter submission), PATCH `/me`,
  and retain the last accepted local name on rejection. Confirmed hero choices
  persist locally and PATCH their canonical ID. Startup `/me` restores a known
  last hero, including aliases, without overwriting a selection made while the
  response was pending.

## Lobby, match and leaderboard

- Public rooms refresh every 2.5 seconds only while the lobby is visible. Rows
  show the host, hero and code and can be tapped to join. Errors retain usable
  controls and an explicit server message; the local demo stays labelled
  **Try Local Online Demo**.
- Public creation needs no password. Private Rooms offers masked 1–64 character
  password entry, private creation, and five-character-code/password joining.
  Waiting shows code, public/private identity, Copy and Cancel/Leave.
- Room polling remains single-flight at one second. Moves replay in sequence;
  gaps and room-conflict errors use the authoritative snapshot. Identical
  snapshots preserve animation. Initial random seats and rematch `match.seat`
  determine X/O; X starts. Canonical character maps arrive before the versus
  presentation on each new round.
- Rematches use both players' agreement, retaining the existing waiting/Accept
  controls and Round 4b cinematics. Sticky `opponent_left` emits once. Official
  full-match results, including forfeits and timeouts, use the existing winner
  presentation. A closed room cannot rematch.
- The lobby's Leaderboard shows rank, screen name and full matches won, plus
  the caller's record even outside the top list. Zero-game players see an
  honest unranked/play-a-match state. `boards_won` is excluded from the public
  presentation. Opening the screen fetches fresh records with device auth.

## Preservation and producer captures

The rules kernel, board renderer, last-move gold highlight, Round 3e layout and
snapshot, title drawing, source art, roster IDs, selection layouts, sound system
and audio tests were not edited. Computer-only Undo/Hint, Pass & Play, local
online demonstration, and loopback rematches retain their existing behavior.
Existing controller tests now set an explicit `test_online_bypass` before tree
entry; this bypass does not rely on `profile.data.onboarded` and suppresses
automatic real HTTP. Capture helpers use the same opt-out.

`tools/capture_shots.gd` additionally accepts these fixture-only scenarios:
`onboarding`, `online_lobby`, `online_private`, `online_leaderboard`, and
`online_unranked`. Existing capture scenarios remain available. Example for
producer review with a working display:

```sh
GODOT=/workspace/tools/godot/Godot_v4.7.2-stable_linux.x86_64
"$GODOT" --path godot --resolution 390x844 --script res://tools/capture_shots.gd -- --scenario onboarding --out godot/onboarding-review.png
```

No screenshots were produced or inspected here. Live connectivity, deployed
browser CORS/TLS behavior, legal-link browser opening, and a real two-device
match/rematch still need producer review. Headless fixtures verify the client
mapping and flow; they do not certify the live service.

## Validation

`tests/run_round4c_tests.gd` uses `tests/fake_http.gd` and fixed envelopes;
it never contacts the live API. The new suite covers URLs, auth headers,
credential persistence and leave lifetime, queued/single-flight JSON requests,
canonical IDs/aliases, private create/join bodies, rematch bodies and seat swaps,
ordered replay/gap and conflict resync, consent payloads, failed name/consent
retries, checkbox-free onboarding and legal links, offline navigation, last-hero
restoration, leaderboard mapping, and responsive touch-target bounds.

The test runner includes the new suite and reports twelve suites. Final command
and results are recorded below and in `tests/LAST_RUN.txt`.

Executed with Godot 4.7.2:

```sh
sh godot/tools/run_tests.sh > godot/tests/LAST_RUN.txt 2>&1
```

**PASS — 12/12 suites, exit 0**, with no script errors, engine errors or warnings.

| Suite | Checks | Result |
|---|---:|---|
| Rules | 3,121,037 | PASS |
| AI | 2,566 | PASS |
| Layout | 1,948 | PASS |
| UI | 887 | PASS |
| Round 3 | 912 | PASS |
| Round 3b | 597 | PASS |
| Round 3c | 6,734 | PASS |
| Audio | 270 | PASS |
| Round 3e | 965 | PASS |
| Round 4 | 2,023 | PASS |
| Round 4b | 57,940 | PASS |
| Round 4c | 340 | PASS |

The existing Round 4b real-pixel probe remains display-dependent; the headless
run reports its transform/clip checks as passing and makes no pixel-render claim.
