# Nineweave Round 5a (client): waiting room, leave rules, turn timer, chat

Client side of Patrick's "online next" items 1–5. The server contract is
`nineweave-server` `ONLINE_API.md` / `ONLINE2.md` (protocol 2, branch
`online-server`, **not deployed yet**). The client works against both servers.

## Capability gate

| Signal | Effect |
|---|---|
| `GET /capabilities` (probed when Online opens, cached 60 s) | `online2`/`protocol: 2` → turn clock, Still there?, joined beat; `chat` → chat, block, report, Blocked players. `chat_presets` fill the quick-chat chips. |
| 404 / network failure / non-JSON | Old server: every new feature stays off. |
| `capabilities` on `/me` | Can turn `online2`/`chat` on (never off). |
| `protocol: 2` in a room envelope | Turns on the turn clock for that room (chat still needs `capabilities.chat`). |

Against an old (round 4g) server the client sends nothing new: no `/chat`,
`/still-here`, `/players/*`, `/reports`, and no `chat_since` on polls
(`/capabilities` is the only probe). Create/join/poll/move/rematch/leave are
unchanged, a join goes straight into the versus intro as in round 4g, the chat
button is hidden, and the only timer is a plain "Turn time m:ss" countdown from
`turn_expires_at`. The round 5a test suite asserts this request by request.

`?api=http://127.0.0.1:PORT` (or `localhost`) overrides the API base for local
QA, only when the page itself is served from `localhost`/`127.0.0.1` and only
if the value is a local http(s) origin (`turn_clock.gd` `api_override`). Any
other origin ignores it.

## Rules as displayed (the server decides everything)

- **Waiting room** (1v1): "Waiting for other player…", big room code with Copy,
  public/private line, your hero portrait and screen name, an empty rival slot,
  Leave (posts `/rooms/<CODE>/leave`; no penalty) and the chat button when
  chat is advertised. When the rival arrives (protocol 2): "<ScreenName> joined"
  with their hero for 1.6 s, then the existing versus intro. A joiner whose room
  still reports `waiting` sees the same screen.
- **Leave mid-match**: the in-game back button asks first.
  `both_moved: true` → "Leave match? This counts as a loss."; `false` →
  "Leave match? No one gets a loss yet." An old server (no `both_moved`) gets
  the loss copy, since it records a forfeit.
- **Endings** (`end_reason`, `opponent_left`, `result.winner`):
  no_show "NightNight didn't show up — match cancelled, no loss" (or "You didn't
  move in time…"), cancelled "NightNight left — match cancelled, no loss",
  forfeit "NightNight left — you win" / "You left — this counts as a loss",
  timeout "NightNight ran out of time — you win" / "Time ran out — you lose",
  abandoned "NightNight disconnected — you win" / "Connection lost — you lose",
  expired "This room expired — no result". Results with no winner show a
  MATCH CANCELLED card (Online lobby / Main menu); wins and losses use the
  existing victory flow with the line above the Rematch button.
- **Turn timer**: a ring around the active player's portrait shrinks over the
  25 s turn: cyan, amber in the last 8 s, red in the last 3 s and during the
  10 s Still there? phase. Under the board: "Your move · 0:18" or
  "Waiting for NightNight… 0:08", plus "First moves — no-shows cancel with no
  loss" while `both_moved` is false. Reduced motion: no pulsing.
- **Still there?** (your turn, from `still_there_at`): a panel under the board
  with a 10 s countdown and "I'm here", which posts `/still-here` once per turn
  (keyed by `turn_started_at`). After `still_here_used` (or a 409) the button
  is gone and the panel reads "Move now!". Making a move dismisses it at once.
- **Clock skew**: `clock_offset = server_now − device clock` when each envelope
  arrives; deadlines count down from there. An older envelope (earlier
  `server_now`) never rewinds the clock.
- **Disconnects**: `opponent_connected: false` → "NightNight reconnecting…".
  Our own failed polls (network, 5xx, 408, 429) → "Reconnecting…", retried after
  1, 2, 4, then 5 s with no error spam (the server grace is 60 s).
- **Screen names** come from `players` / `you` (fallback: the old `opponent`
  string) on the waiting screen, versus intro, plates, chat and end lines.

## Chat and moderation (only with `capabilities.chat`)

Speech-bubble button with an unread badge in the waiting room, the game header
and the result screen. The panel is a sheet under the board on phones (never
over the cells at 390×844) and the side column on desktop. It shows sender
names (yours right-aligned, markup escaped), preset chips, a single-line
120-character input with counter, and Send. Messages ride the room poll
(`chat_since` = last id) and are de-duplicated by id. Errors shown: 429 "Slow
down — try again in N s" (no resend until then), 400 "Message not allowed",
403 "Create a screen name to chat". Tapping the opponent's name opens
Mute (local, this match), Block (confirm, then `POST /players/block`
`{room_code, seat}`; their messages disappear) and Report (reason picker +
optional note ≤ 500 → `POST /reports`; toast "Thanks — we'll review it").
Settings → **Blocked players** lists `GET /players/blocks` with Unblock
(`DELETE /players/block {name}`).

## Endpoints used

Old and new: `POST /rooms`, `POST /rooms/<CODE>/join`, `GET /rooms/<CODE>?since=`,
`POST …/moves`, `POST …/rematch`, `POST …/leave`, `GET /rooms` (lobby).
Probe: `GET /capabilities`. Protocol 2 / chat only: `…?chat_since=`,
`POST …/still-here`, `POST …/chat`, `POST|DELETE /players/block`,
`GET /players/blocks`, `POST /reports`.

## Polling

`poll_after_ms` from the envelope; 0 stops polling. Without it: waiting 3 s,
opponent's turn 1.5 s, own turn 3 s, finished 4 s, closed stop. A hidden tab
(`document.visibilityState`) or an unfocused/backgrounded app polls at
max(hint, 5 s), never stops, and goes back to the normal rate on focus. A full
chat page (50) triggers an immediate follow-up poll. Chat and still-here use a
separate request queue so they never wait behind or cancel a move.

## Files

New: `net/turn_clock.gd` (pure timing/copy/poll helpers), `net/social.gd`
(capabilities, block, report), `ui/chat_panel.gd`, `tests/run_round5a_tests.gd`,
`tools/capture_r5a.gd`, `tools/capture_r5a.sh`, this file.
Changed: `net/http_polling_transport.gd`, `net/json_api.gd` (`?api`),
`ui/online_screen.gd` (waiting room), `main/main.gd`, `tools/run_tests.sh`,
`tools/export_web.sh` (build title).

Screenshots: `xvfb-run -a sh godot/tools/capture_r5a.sh` →
`/workspace/nineweave-r5a-shots/` (390×844 for all nine scenarios; 1366×768 for
waiting and chat_open). HTTP is faked; nothing touches the network.

## Needs the server published

Everything new is dormant until the `online-server` branch (protocol 2,
migration `0005_nineweave_online2.sql`) is deployed to the API the site uses.
Until then the GitHub Pages build behaves like round 4g plus the new waiting
screen and leave confirmation. Once it is live, the client picks up chat, the
turn clock and Still there? on the next capabilities probe, with no client
release needed. The privacy policy's chat section ships with the server.
