# Nineweave online2 (Round 5, phase 1 server)

Server changes for the waiting room, leave/forfeit rules, the turn clock with
"Still there?", in-match chat with moderation, and screen names in the room
envelope. Everything is additive: the deployed round4g Godot client keeps
working (it ignores the new fields). The only behavior an old client notices
is the new timing below. Full contract: `ONLINE_API.md` ("Match rules v2",
"Timeouts", "Polling", "Chat").

## For the builder

- **Migration `migrations/0005_nineweave_online2.sql` must be applied.**
  `npm run build` applies it automatically on publish (`npm run db:migrate`
  runs after `vite build`). It is idempotent (`if not exists` / drop-then-add
  constraint) and adds:
  - `nw_rooms.b_joined_at`, `nw_rooms.still_here_used`
  - an `abandoned` value in the `nw_matches.end_reason` check
  - tables `nw_chat`, `nw_blocks`, `nw_reports` (with indexes)
- No new secrets or environment variables, and no new dependencies.
- The API route now also answers `DELETE` (used for unblocking), and CORS
  allows `DELETE`.
- PII: chat text, sender screen names and report notes / snapshots. Chat is
  deleted after 24 h (or 1 h after its room closes), reports after 30 days,
  by the opportunistic sweep (no cron). Message text is never logged.
- `legal/privacy.md` (rendered at `/privacy`) has a new "In-game chat"
  section. The effective date stays November 15, 2026.

## Rules as implemented

| Rule | Value |
|---|---|
| Turn clock | 25 s, then a 10 s "Still there?" phase. The turn expires 35 s after `turn_started_at`. |
| Still-here | `POST /rooms/<CODE>/still-here`, only for the player due to move during the prompt, once per turn. It restarts the clock (fresh 25 s + 10 s). A second confirm returns `409` and doesn't extend. |
| `both_moved` | Seat 1 and seat 2 have each moved at least once in the current round. Resets on rematch. |
| Before `both_moved` | Turn expiry or lost grace gives `no_show` (closed, no records). Leave gives `cancelled` (closed, no records, `result:null`). |
| After `both_moved` | Turn expiry gives a `timeout` loss. Lost grace gives an `abandoned` loss. Leave gives a `forfeit` loss. The opponent wins and records update. |
| Disconnect grace | 60 s without a poll/move by the seat **not** due to move. Presence writes are still throttled to every 10 s. |
| Waiting room | Unchanged (leave = cancel, no penalty). |

**Change for old clients.** The old 180 s turn timeout is now 35 s. Before
both players have moved, a stalled match is cancelled instead of being
recorded as a loss.

## For the client (Godot)

Detect support with `GET /capabilities` (public, cached 60 s), which returns
`{protocol:2, online2:true, chat:true, tournaments:false, email:true, chat_presets:{…}}`,
or with `capabilities.online2` on `/me`, register and `PATCH /me`.

Every room envelope now has:

- `protocol: 2`, `server_now`, `poll_after_ms`
- `turn_started_at`, `still_there_at`, `turn_expires_at`, `turn_seconds: 25`,
  `still_there_seconds: 10`, `still_here_used`, `grace_seconds: 60`
- `both_moved`
- `opponent_joined_at`, `opponent_last_seen_at`, `opponent_connected`
- `you: {name, hero}`, `players: {"1": {name, hero, connected}, "2": …}`

The poll also returns `chat` (with `?chat_since=<id>`) and `chat_seq`.

Client duties:

1. Honor `poll_after_ms`: waiting 3000, opponent's turn 1500, your turn
   3000, finished 4000, and 0 = stop.
2. Count down locally from `server_now` to `still_there_at` and
   `turn_expires_at`. Show "Still there?" and call `/still-here` once. The
   server enforces the deadlines.
3. Leave confirm: "Leave match? This counts as a loss." only when
   `both_moved` is true.
4. New endings: `no_show` and `cancelled` (`result:null`, no record), and
   `abandoned` (a recorded loss, like `timeout`).
5. Waiting room: show "<name> joined" from `players` / `opponent_joined_at`.
6. Chat: `POST /rooms/<CODE>/chat` with `{text}` or `{preset}` (screen-name
   players only, 120 characters, 5 per 10 s and 30 per 5 min). Profanity is
   masked server-side. Links, emails, phone numbers, handles and slurs return
   `400 "Message not allowed"`. Mute is client-side.
7. Moderation: `POST`/`DELETE /players/block` (`{room_code, seat}` or
   `{name}`), `GET /players/blocks`, and `POST /reports`
   `{room_code, seat, reason, note?}`, all with the device token.

## Files

- New: `migrations/0005_nineweave_online2.sql`, `src/lib/nineweave/chat.ts`
  (chat, blocks, reports, capabilities), `src/lib/nineweave/chat-filter.ts`
  (text rules and word lists), `src/lib/nineweave/online2.test.ts`,
  `src/lib/nineweave/chat-filter.test.ts`, this file.
- Changed: `rooms.ts` (turn clock, still-here, no-show/abandoned, grace,
  envelope, retention sweep, block checks on join/lobby), `api.ts` (routes,
  cacheable `/capabilities`), `service.ts` (timing constants),
  `players.ts` (capabilities), `rate-limit.ts` (chat and moderation buckets),
  `cors.ts` and `src/routes/api/nineweave/$.ts` (`DELETE`), `ONLINE_API.md`,
  `legal/privacy.md`, `package.json` (`test:online` runs the new tests).
- Tests changed on purpose: the 180 s timeout tests in `online.test.ts` now
  check the 35 s rule after both players moved; the CORS test expects
  `DELETE`; the capability assertions in `email.test.ts` expect the new
  flags; the truncates include the new tables.
