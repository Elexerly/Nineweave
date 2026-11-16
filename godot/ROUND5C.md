# Round 5c — Patrick's four playtest changes

Client-only changes under `godot/`. No commits, server edits, new art, board changes,
or rules changes. The existing Godot game and Round 5b bracket remain the base.

## 1. Both versus videos

The player is the left intro lane and the opponent the right lane. Both ready
streams start in the same frame, on native bundled files and verified web
sidecars. The two web download slots now prioritize the pair's intros before
victories; if selection already started a victory download, it is paused/requeued
so it cannot delay the other intro. A missing/unloaded clip keeps that hero's
still art. A decoder that stops without a completion signal also falls back to
that hero's art and cannot trap the player.

The display letterboxes at the actual 540 × 720 clip aspect. Each player uses
100 ms buffering instead of 500 ms. At most two decoders run on the versus view;
Skip/completion tears down streams and releases both cache pins. The existing
64 MiB/eight-clip encoded-file cache and two-download cap remain. Display scaling
does not reduce source decode resolution: actual browser memory/frame rate still
needs a rendered playtest (see capture limitation below).

Files: `characters/hero_video.gd`, `characters/hero_video_cache.gd`,
`characters/hero_video_overlay.gd`.

## 2. One combined victory/result screen

The winner's victory video occupies the left lane, alongside the result title,
original screen-name win line, “<Hero> won and defeated <Opponent>”, board counts,
online ending detail, and result buttons on the right. A loss selects the
opponent's video and matching text. Buttons are available while the clip plays.
Completion stays in the same composition with still art; it does not open a
second end card. Missing clips and reduced motion retain the illustrated result.
Short landscape uses a single row of actions. Resize preserves the live clip.

The computer-tournament champion video also stays in its hero lane, leaving
trophy information and Try Again/Menu accessible. Legacy analytic animation
seeks remain available to the earlier deterministic capture/regression tools;
live victories use the combined view.

Files: `characters/cinematic.gd`, `characters/hero_video_overlay.gd`,
`main/main.gd`, `tournament/screen.gd`.

## 3. Tournament chooser and online3 client

Tournament first offers **Vs Computer** and **Online**. Vs Computer retains the
Round 5b hero selection, saved bracket, rising AI difficulty, and trophies.

Online provides public listing/join, private code/password join, creation,
visibility/password, and start options (2, 5, 10, 15, 30, 60 minutes). The requested
3–8 group-size picker explicitly shows the server capacity: **3–4 maps to 4
seats, 5–8 maps to 8 seats**. This is necessary because `ONLINE3.md`, the tournament
plan, and `tournaments.ts` only accept `size: 4|8`. All joined players (minimum 3)
play at start time; byes come from the authoritative server. A size-3 selection
is not a three-seat cap. No unsupported size or new server field is sent.

The client matches `/api/nineweave` endpoints exactly:

- `GET /capabilities`, `GET /tournaments`.
- `POST /tournaments`: `size`, `starts_in_minutes`, `private`, optional
  `password`, `character_id`.
- `POST /tournaments/<CODE>/join`: optional `password`, `character_id`.
- `GET /tournaments/<CODE>` and `POST /tournaments/<CODE>/leave`.

Authenticated tournament operations use the existing device token. A matched
room opens by immediate `GET /rooms/<room_code>?since=0` using the returned seat
token and seat, with no room-join request and no device-token overwrite. A
three-second countdown (or Ready) leads through the existing versus intro and
normal authoritative room flow. Tournament rooms reject client rematch actions.
After the combined result, View Bracket or a five-second automatic return resumes
tournament polling; a later match auto-opens with its new room/opponent/seat.
Equal-board replays stay in the normal room protocol. A no-show with a server
winner also shows the combined outcome. Leaving a running tournament asks for
confirmation; registration can be left without penalty.

`online_model.gd` converts server seeds into opaque entrant IDs, including when
two entrants chose the same hero. It feeds the **same Round 5b BracketView**:
advance trails, result flips, lit path, defeated portrait crack/dim, and current
match pulse. Cyan/gold dots identify live/ready matches and row scores are small
boards won. Changed scores preserve animation age; newly resolved matches feed
result events. Byes are displayed as already advanced, never simulated locally.
The roster scrolls before seeding. The server supplies all results, player states,
and the champion. Polling follows `poll_after_ms` and stops at zero; start-time
countdowns use `server_now` to compensate for device clock skew.

Absent capabilities or missing root endpoints (including an HTML 404) show
**“Online tournaments are coming soon”** with a working Vs Computer action. An
unknown tournament code produces a code-specific message instead of disabling
the feature. All verification uses a mocked API; live online3 is not deployed.
Tournament room credentials and current membership are held in memory, matching
the existing online-room lifecycle, rather than persisted as a new account mode.

Files: `tournament/online_flow.gd`, `tournament/online_model.gd`,
`tournament/online_screen.gd`, `tournament/bracket_view.gd`, `main/main.gd`,
`net/http_polling_transport.gd`.

## 4. Readable online copy

A charcoal/gray gradient backs the left-side arena title, public-games list,
instructions, empty state, and status copy. The rest of the wide arena background
remains visible. The same contrast treatment backs tournament chooser, creation,
join, coming-soon, registration, and live-bracket copy. Forms scroll on phones
and short windows; controls remain at least 44 px tall.

Files: `ui/readability.gd`, `ui/online_screen.gd`, `tournament/online_screen.gd`.

## Tests and export

`tools/run_tests.sh` includes the new `tests/run_round5c_tests.gd` suite plus
`tests/round5c_fixtures.gd`. It covers native and mocked streamed dual intros,
priority/pins/cleanup/fallback, simultaneous victory information/actions,
actual winner identity, responsive layouts, feature 404s, exact authenticated
create/join/leave payloads, live scores/byes/result animation, sequential room
handoffs and changed seats, no-show outcomes, no rematch, automatic bracket
return, and terminal polling. Prior tests were updated only for superseded
video-before-results/chooser/aspect expectations or explicit analytic seeking.

- Full runner: **PASS, 18/18 suites**; Round 5c **188 checks, zero failures** (3,200,585 checks across all suites).
- Rules: 2,400 fuzz games / 141,611 moves, no failures.
- `bash godot/tools/export_web.sh godot/.godot/r5c/web`: **PASS**.
- Production PCK headless smoke: **PASS, 326 checks**, including all 320 hero
  textures and chooser / 404 fallback / bracket / versus / combined result.
  Tool: `tools/check_round5c_pack.gd`; log: `.godot/r5c/pack-check.log`.
- PCK: **16,765,020 bytes**, below the 18 MB target and 20 MB limit.
- The required Round 5c BUILD_INFO title is set in `tools/export_web.sh`.
- Export checks all 64 byte-identical sidecars, no videos in the PCK, 20 packed
  audio clips, and the package-size budget.
- Logs: `.godot/r5c/full-tests.log`, `.godot/r5c/round5c.log`,
  `.godot/r5c/export.log`. Build: `.godot/r5c/web/index.html` and `BUILD_INFO.txt`.

## Screenshot attempt and limitation

Added `tools/capture_r5c.gd` / `tools/capture_r5c.sh`, following the existing
`capture_*` tooling. The 27 planned captures include phone/desktop versus,
victory, defeat, still fallback, chooser, public/private tournament forms,
coming-soon, registration, live bracket/countdown, regular online lobby, and
short-landscape victory/chooser/bracket. The media captures check that both real
native decoder positions advance before saving pixels.

Attempted:

```sh
xvfb-run -a sh godot/tools/capture_r5c.sh /workspace/nineweave/godot/.godot/r5c/shots
```

**No PNGs were produced.** This sandbox denies X11 listener socket creation:
Xvfb reports “Cannot establish any listening sockets”; Godot reports “X11 Display
is not available” and cannot initialize Wayland either. A separate Chromium
headless launch also fails with `shutdown: Operation not permitted`. Thus no
native or web screenshot, real visual inspection, dual-decoder frame-rate/memory
profile, or browser-render claim is made. No permission escalation was attempted.

Destination/status: `.godot/r5c/shots/CAPTURE_STATUS.txt`. Evidence:
`.godot/r5c/captures.log`, `.godot/r5c/xvfb.log`,
`.godot/r5c/display-check.log`. The capture scripts remain ready for an allowed
display environment; geometry and mocked-state tests passed here.
