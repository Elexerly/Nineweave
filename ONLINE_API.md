# Nineweave Online API (protocol 2, "online2")

Authoritative backend for online Ultimate Tic Tac Toe. It implements
`godot/ONLINE_PROTOCOL.md` (rounds 1–4) and adds a few things on top: device
accounts, a leaderboard, a lobby, private rooms and leave/timeout handling.
Round 5 (protocol 2) adds a server-enforced turn clock with a "Still there?"
prompt, no-show/abandon rules, a disconnect grace, in-match chat with
moderation (block, report), screen names in the envelope and poll-rate hints;
see [Match rules v2](#match-rules-v2) and [Chat](#chat). The existing
`HttpPollingTransport` works against it unchanged. Everything new is
additive and optional for the client to use. Summary of the round 5 changes:
`ONLINE2.md`. Round 5 phase 3 adds online [Tournaments](#tournaments)
(summary: `ONLINE3.md`).

- **Base path:** `/api/nineweave` (same origin on `https://nineweave.grok.me`).
- **Format:** JSON request and response bodies (`Content-Type: application/json`).
  The body limit is 8 KB (`413` above that).
- **Errors:** every non-2xx response carries
  `{"error": "Human-readable explanation"}`. Conflict and illegal-move errors
  on a room also include the full room envelope (see below), so the client can
  resync.
- **Caching:** every response sends `Cache-Control: no-store`, except
  `GET /capabilities` (`public, max-age=60`).
- **Source:** `src/lib/nineweave/` (`api.ts` handles routing, `rooms.ts` runs
  play, `rules.ts` is the kernel).

## Authentication

There are two kinds of opaque bearer secret. Both are 256-bit random values
that the server returns **once**. The server stores only their SHA-256 hash.
Never log them, render them or put them in a URL.

| Token | Prefix | Issued by | Proves |
|---|---|---|---|
| Device token | `nwd_` | `POST /auth/device` | A persistent anonymous player (records, name, hero) |
| Seat token | `nws_` | `POST /rooms`, `POST /rooms/<CODE>/join` | One seat in one room |

Send a token as `Authorization: Bearer <token>`.

- **Room endpoints** (poll, moves, still-here, chat, rematch, leave, cancel) accept either a
  seat token or the device token of the player in that seat. The token can
  come from the header or from a body `"token"` field (the protocol's moves
  and rematch bodies have one). If both are sent, either one may match.
- **Create/join:** the `Authorization` header, when present, must be a
  **device** token. An unknown token returns `401`. Without one, the seat is
  anonymous: it can play but has no record, so it isn't ranked.
- **`/me`, `/players/block`, `/players/blocks`, `/reports`:** require a device token.
- **`/capabilities`:** public, no token.
- **`/leaderboard`:** works without a token. A valid device token adds `me`.

Seat tokens are bound to a stable player slot, not to X/O. Seats swap on
rematch and the token keeps working.

## Data shapes

### Rules snapshot (`state`)

This is identical to `rules.gd` `serialize()`:

```json
{"v":1,"cells":"<81 chars: . X O>","turn":1,"active":-1,"history":[{"board":4,"cell":0,"player":1,"active_before":-1}],"redo":[]}
```

- `cells[board*9+cell]`: `.` is empty, `X` is seat 1, `O` is seat 2.
- `turn`: `1` (X) or `2` (O). **X always moves first.**
- `active`: the board the next move must go in (`0`–`8`), or `-1` for a free
  move on any open board. A free move happens when the target board is
  already won or full.
- `history`: every move in the current round, in order. Move `seq` equals
  1-based index into `history`. `redo` is always `[]` online.

### Room envelope

Create, join, poll, moves, rematch and leave all return this envelope. Some
add fields to it.

```json
{
  "code": "N9ABC",
  "seat": 1,
  "seq": 13,
  "state": { "...": "rules snapshot" },
  "status": "active",
  "private": false,
  "opponent": "Friend",
  "opponent_left": false,
  "characters": {"1": "vesper_vale", "2": "auric_rex"},
  "match": {"round": 1, "seat": 1, "local": false, "remote": false},
  "result": null,
  "end_reason": null,
  "turn_expires_at": "2026-11-15T12:00:35.000Z",

  "protocol": 2,
  "server_now": "2026-11-15T12:00:03.000Z",
  "turn_started_at": "2026-11-15T12:00:00.000Z",
  "still_there_at": "2026-11-15T12:00:25.000Z",
  "still_here_used": false,
  "turn_seconds": 25,
  "still_there_seconds": 10,
  "grace_seconds": 60,
  "both_moved": true,
  "opponent_joined_at": "2026-11-15T11:59:40.000Z",
  "opponent_last_seen_at": "2026-11-15T12:00:01.000Z",
  "opponent_connected": true,
  "you": {"name": "Patrick", "hero": "vesper_vale"},
  "players": {
    "1": {"name": "Patrick", "hero": "vesper_vale", "connected": true},
    "2": {"name": "Friend", "hero": "auric_rex", "connected": true}
  },
  "poll_after_ms": 3000
}
```

The first block is the round 1–4 envelope; everything from `protocol` on is
protocol 2 and safe for older clients to ignore. The poll response also
carries `moves`, `chat` and `chat_seq`.

| Field | Meaning |
|---|---|
| `seat` | The caller's current seat (1 = X, 2 = O). |
| `seq` | Number of moves in the current round (`state.history.length`). |
| `status` | `waiting` (no guest yet), `active` (match in progress), `finished` (round over, rematch possible), `closed` (cancelled, expired, no-show, someone left, timed out or abandoned). Terminal. |
| `opponent` | The opponent's name, or `""` while nobody has joined. It is never `null`. |
| `opponent_left` | `true` once the opponent left the room, timed out, didn't show or abandoned. |
| `characters` | Map from seat (string key) to canonical hero ID. While waiting, only the host's seat is present. The map swaps with seats on rematch. |
| `match.round` | Starts at 1 and goes up by one on each accepted rematch. |
| `match.seat` | Same as `seat`. On a round increment, use it as the new seat. |
| `match.local` / `match.remote` | Whether the caller and the opponent have each asked for a rematch of this round. |
| `result` | `null`, or `{"winner": 0\|1\|2, "reason": "win"\|"draw"\|"forfeit"\|"timeout"\|"abandoned"}`. `winner` is a seat, and `0` means a draw. Seats are relative to the round that ended until a rematch clears it. A `cancelled` or `no_show` ending has `result: null` (no match was recorded). |
| `end_reason` | `win`, `draw`, `forfeit`, `timeout`, `abandoned`, `cancelled`, `no_show`, `expired` or `null`. |
| `turn_expires_at` | ISO hard deadline of the current turn (`active` only, else `null`): 35 s after `turn_started_at`, 10 s after an accepted still-here confirmation, or 25 s when two consecutive own late turns already occurred. When it passes, the turn expires (see [Match rules v2](#match-rules-v2)). |
| `protocol` | `2` on this server. |
| `server_now` | Server time (ISO) when the envelope was built. Use `deadline − server_now` for countdowns so device clock skew doesn't matter. |
| `turn_started_at` | ISO start of the current turn clock (the last move or match/rematch start; not reset by a still-here confirmation). `null` unless `active`. |
| `still_there_at` | ISO time the "Still there?" prompt should appear for the player due to move (`turn_started_at` + 25 s). `null` unless `active`. |
| `still_here_used` | Whether the player due to move already used this turn's one still-here confirmation. |
| `turn_seconds` / `still_there_seconds` / `grace_seconds` | `25` / `10` / `60`. |
| `both_moved` | `true` once the current round's history has at least one move by seat 1 **and** one by seat 2. Resets on every rematch. Before it is true, leaving or timing out costs nothing. |
| `opponent_joined_at` | ISO time the opponent took their seat (for the host: when the guest joined; for the guest: when the host created the room), or `null` while nobody has joined. Show "<name> joined". |
| `opponent_last_seen_at` | ISO time of the opponent's last poll / move as recorded (presence is written at most every 10 s), or `null`. |
| `opponent_connected` | `true` if the opponent was seen within the last ~20 s. |
| `you` | `{name, hero}` for the caller. |
| `players` | Map from seat (string key) to `{name, hero, connected}` for each seat that is occupied. Names are screen names for device players with one. |
| `poll_after_ms` | Server hint for when to poll next (see [Polling](#polling)). `0` means stop polling. |

Envelopes never include seat or device token hashes, password hashes, player
IDs or internal room IDs.

## Endpoints

### Lobby and play (Godot protocol)

#### `POST /rooms`: create a room

Request:

```json
{"name":"Patrick","character_id":"vesper_vale","private":true,"password":"secret"}
```

| Field | Required | Notes |
|---|---|---|
| `name` | no | Display name for this room (see [Names](#names)). If missing or blank it becomes `"Player"`. A device player's stored `screen_name` overrides it. |
| `character_id` | no | Hero ID or alias. Unknown IDs return `400`. If missing, it defaults to the device player's `last_hero_id`, otherwise `auric_rex`. |
| `private` | no | Boolean. A private room is not listed in the lobby. |
| `password` | for private rooms | 1–64 characters. Stored with scrypt. Sending a password makes the room private even without `private:true`. `private:true` with no password returns `400`. |

`201` response: the envelope (`status:"waiting"`) plus `token`, the caller's
seat token:

```json
{"code":"N9ABC","seat":2,"token":"nws_…","seq":0,"state":{"v":1,"cells":"…81 dots…","turn":1,"active":-1,"history":[],"redo":[]},"status":"waiting","opponent":"","characters":{"2":"vesper_vale"},"match":{"round":1,"seat":2,"local":false,"remote":false}, "...": "…"}
```

**X/O is assigned at random for the first match**, so the host may be seat 2
and wait for the guest's first move. A device player's chosen hero is saved
as their `last_hero_id`.

Errors: `400` (bad name, hero or password), `401` (unknown device token),
`429` (rate limited).

#### `GET /rooms` (alias `GET /lobby`): public open rooms

`200`:

```json
{"rooms":[{"code":"N9ABC","host_name":"Patrick","host_hero":"vesper_vale","created_at":"2026-11-15T12:00:00.000Z"}]}
```

The list contains only public rooms in `waiting`, newest first, up to 50. It
never includes private rooms, tokens or passwords.

#### `POST /rooms/<CODE>/join`: take the second seat

Request:

```json
{"name":"Friend","character_id":"auric_rex","password":"secret"}
```

`password` is required only for private rooms. Name and hero follow the same
rules as create. The code is matched case-insensitively.

`200`: the envelope (`status:"active"`) plus `token`, with `opponent` set to
the host's name and the full `characters` map. The match starts immediately,
and seat 1 (X) moves first.

| Status | When |
|---|---|
| 404 | No live room with that code, or it expired. |
| 403 | Wrong or missing password for a private room. |
| 409 | The room is full, already playing, or you're trying to join your own room with the same device token. |
| 400, 401, 429 | As for create. |

#### `GET /rooms/<CODE>?since=<n>&chat_since=<id>`: poll

Requires authorization (header). Poll at the envelope's `poll_after_ms`
(older clients poll about once per second, which still works).

`200`: the envelope plus `moves`, the moves of the current round with
`seq > since`, sorted, plus `chat` (messages with `id > chat_since`, see
[Chat](#chat)) and `chat_seq`:

```json
{"seq":13,"opponent":"Friend","opponent_left":false,"moves":[{"board":4,"cell":0,"seq":13}],"state":{"...":"…"},"match":{"round":1,"seat":1,"local":false,"remote":false},"characters":{"1":"vesper_vale","2":"auric_rex"},"status":"active", "...": "…"}
```

A full `state` snapshot is **always** included. If `since` is higher than the
current `seq` (for example from a previous round), `moves` is `[]` and you
should resync from `state`/`seq`. Polling also counts as presence (see
[Timeouts](#timeouts)).

Errors: `401` (no token), `403` (token not in this room), `404` (no room with
that code).

#### Polling

`poll_after_ms` in every room envelope says when to poll next:

| Situation | `poll_after_ms` |
|---|---|
| `waiting` (waiting room) | 3000 |
| `active`, opponent's turn | 1500 |
| `active`, your turn | 3000 (presence only; count down locally from `still_there_at` / `turn_expires_at` and `server_now`) |
| `finished` | 4000 |
| `closed` | 0: stop polling |

Chat rides the same poll: never poll a separate chat endpoint. Polling at
these rates keeps you well inside the 60 s disconnect grace.

#### `POST /rooms/<CODE>/still-here`: "Still there?" confirm

Body optional (`{"token":"…"}` or the header). Only the player due to move,
only while the "Still there?" prompt is showing (from `still_there_at` until
`turn_expires_at`), and **once per turn**.

`200`: the envelope plus `"ok": true`, with `still_here_used: true` and a
`turn_expires_at` = server acknowledgement time + **10 s**. The original
`turn_started_at` and `still_there_at` remain unchanged. The player must move
before this deadline: polls, reconnects and repeated confirmations do not
extend it. Expiry after confirmation is a recorded timeout loss even before
both players have moved.

| Status | When (all include the current envelope) |
|---|---|
| 403 | `It's not your turn` |
| 409 | `You already confirmed this turn` (the second confirm in a turn; the clock is **not** extended) |
| 409 | `The Still there? prompt isn't showing yet` (before `still_there_at`) |
| 409 | `No turn is running` (room not `active`, including after the turn already expired) |
| 401, 404, 429 | As for moves |

Making a move always ends the turn normally and resets the allowance for
the next turn.

#### `POST /rooms/<CODE>/moves`: play a move

```json
{"board":4,"cell":0,"seq":13,"token":"nws_…"}
```

`board`, `cell` and `seq` must be JSON integers (otherwise `400`). The token
can be in the body, in `Authorization`, or both.

The server checks in this order:

1. The token maps to a seat.
2. **Idempotent retry:** if `seq ≤ current` and history entry `seq` is the
   same `(seat, board, cell)`, it returns `200` with the original
   acknowledgement: `seq`, `moves:[{board,cell,seq}]`, and `state` as it was
   right after that move.
3. The room is `active`, `seq == current + 1`, it is the caller's turn, and
   `is_legal(board, cell)`.

`200`: the envelope plus `{"seq":13,"moves":[{"board":4,"cell":0,"seq":13}]}`.
If the move ends the match, `status` is `finished` and `result` is set, and
both players' records are updated in the same transaction.

| Status | When (all room errors include the current envelope) |
|---|---|
| 400 | `board`, `cell` or `seq` is missing or not an integer, or `seq < 1`. |
| 401 / 403 | No token / token not in this room. |
| 403 | `It's not your turn` (correct `seq` but the wrong seat). |
| 404 | No such room. |
| 409 | Stale `seq` (a different move already holds it), `seq` ahead of the server, room still `waiting`, or room `closed`. |
| 422 | Illegal move (`Choose an empty cell in the active board`) or `Game finished`. |
| 429 | Rate limited. |
| 503 | The room stayed contended after retries. Retry the same move; retries are idempotent. |

#### `POST /rooms/<CODE>/rematch`

```json
{"round":1,"token":"nws_…"}
```

`round` is optional but recommended. If given, it must equal the current
round.

| Room status | Result |
|---|---|
| `active` (live game) | `200`, request **ignored**: the envelope plus `"ignored": true`, with nothing recorded. |
| `finished`, first request | `200`: the caller's agreement is recorded (`match.local:true`). The opponent's next poll shows `match.remote:true`. |
| `finished`, duplicate request | `200`, unchanged (idempotent). |
| `finished`, opponent already agreed | `200`, **new round starts**, all in one transaction: `match.round+1`, seats swapped (`seat` / `match.seat` is the new seat), `seq:0`, fresh `state`, swapped `characters`, agreements cleared, `status:"active"`. The other player sees the same thing on their next poll. |
| `round` ≠ current | `409 Stale rematch round` |
| `waiting` | `409 No finished match to rematch` |
| `closed` | `409`, either `Your opponent left the room` (`opponent_left:true`) or `This room is closed`. |

Client handling: when `match.round` goes up, set your seat to `match.seat`,
reset your sequence to 0, then apply `state`/`seq`. Names and heroes stay
with their players. X still moves first.

#### `POST /rooms/<CODE>/leave`

The body is optional (`{"token":"…"}` or use the header).

`200`: the envelope plus `"ok": true`.

| Status before | Effect |
|---|---|
| `waiting` | The room is cancelled (`closed`, `end_reason:"cancelled"`). It disappears from the lobby and its code stops joining. No penalty. |
| `active`, `both_moved: false` | **Cancelled, no penalty** (`closed`, `end_reason:"cancelled"`, `result:null`, no records). The opponent sees `opponent_left:true`. |
| `active`, `both_moved: true` | **Forfeit.** The opponent wins (`result.reason:"forfeit"`) and both records update in the same transaction. The room closes and the opponent sees `opponent_left:true`. Client confirm text: "Leave match? This counts as a loss." |
| `finished` | The room closes with no record change. The opponent sees `opponent_left:true` and rematch returns `409`. |
| `closed` | No-op (idempotent). |

#### `POST /rooms/<CODE>/cancel`

The host-only version of leave for a `waiting` room. Returns `403` if the
caller isn't the host and `409` if the room isn't waiting.

### Players

#### `POST /auth/device`: register an anonymous player

The body is optional: `{"screen_name":"Patrick","last_hero_id":"cryon","tos_version":"2026-11-15","privacy_version":"2026-11-15","accepted_at":"2026-11-15T12:00:00.000Z","age_confirmed":true}`.
`tos_version`, `privacy_version`, `accepted_at` and `age_confirmed` are optional consent fields (see [Consent](#consent)). No other fields are accepted.

`201`:

```json
{"token":"nwd_…","player_id":"p_AbC…","player":{"player_id":"p_AbC…","screen_name":null,"last_hero_id":null,"purchases":[],"unlocks":[],"matches_won":0,"matches_played":0,"matches_lost":0,"boards_won":0,"tos_version":null,"privacy_version":null,"accepted_at":null,"age_confirmed":null,"email":null,"email_status":"none","email_verified_at":null,"capabilities":{"email":true,"online2":true,"chat":true,"tournaments":false},"rank":1}}
```

The token is shown **only here**, so store it securely on the device.
`player_id` is public and safe to display or share.

Errors: `400` (invalid name or hero), `409` (screen name taken; no player is
created), `429`.

#### `GET /me`

Requires a device token. `200`: the `player` object above. `rank` is
1 + the number of ranked players with more matches won (ties share a rank).
`401` if the token is missing or unknown.

- `capabilities`: feature flags,
  `{"email":true,"online2":true,"chat":true,"tournaments":true,"tournament_sizes":[4,8],"tournament_min_players":3,"tournament_start_options":[2,5,10,15,30,60]}`
  on this server (also on `POST /auth/device` and `PATCH /me`). `email: true` means
  this server supports the [Email](#email) fields and endpoints; clients must
  not send `email` anywhere until they see it. `online2: true` means protocol
  2 (turn clock, still-here, envelope additions); `chat: true` means
  [Chat](#chat). `tournaments: true` means [Tournaments](#tournaments).
- `tournament_wins`: online tournaments won (champion). Also on the
  leaderboard rows and `me`.
- `email`: the stored address, lowercased, or `null`. Private to the player:
  it never appears on the leaderboard or in room envelopes.
- `email_status`: server-owned, `"none"` | `"unverified"` | `"verified"`.
- `email_verified_at`: ISO-8601 time of the last successful confirmation, or
  `null`.

#### `PATCH /me`

Requires a device token. Send any subset of these fields:

```json
{"screen_name":"Patrick","last_hero_id":"vesper_vale","purchases":["sku"],"unlocks":["cryon"],"tos_version":"2026-11-15","privacy_version":"2026-11-15","accepted_at":"2026-11-15T12:00:00.000Z","age_confirmed":true,"email":"pat@example.com"}
```

- `screen_name`: see [Names](#names). Must be unique case-insensitively
  (`409` if taken).
- `last_hero_id`: hero ID or alias, stored in canonical form. Joining or
  creating a room with a `character_id` also updates it.
- `purchases` / `unlocks`: arrays of 1–64-character strings, at most 200
  items. Duplicates are removed and the array **replaces** the stored one.
  ⚠️ These are client-asserted and unverified until Apple IAP receipt
  validation exists. Never treat them as proof of payment.
- Consent fields: see [Consent](#consent).
- `email`: see [Email](#email). Stores the address only (no code is sent).
  `null` or `""` clears it.
- Unknown fields return `400`.

`200`: the updated `player` object. Errors: `400`, `401`, `409`, `429`.

#### `GET /leaderboard?limit=50`

`limit` defaults to 50 and is capped at 100. Only players with a
`screen_name` and at least one finished online match are listed. The order is
`matches_won` desc, then `matches_played` asc, then oldest account. `rank`
uses competition ranking (ties share a rank).

```json
{"players":[{"rank":1,"screen_name":"Patrick","matches_won":12,"matches_played":20,"tournament_wins":1}],
 "me":{"screen_name":"Patrick","matches_won":12,"matches_played":20,"boards_won":61,"tournament_wins":1,"last_hero_id":"vesper_vale","rank":1}}
```

`me` is present only when the request carries a valid device token. It is
included even if the caller isn't in the top list or isn't ranked (no name or
no matches). In that case `rank` is where they would stand. `boards_won`
appears only in `me`, never in the public rows.

### Chat and moderation

See [Chat](#chat) for `POST /rooms/<CODE>/chat`, `POST|DELETE /players/block`,
`GET /players/blocks` and `POST /reports`.

### Utility

- `GET /capabilities` (public, `Cache-Control: public, max-age=60`) returns
  `{"protocol":2,"online2":true,"chat":true,"tournaments":true,"email":true,"chat_presets":{"gg":"Good game!",…},"tournament_sizes":[4,8],"tournament_min_players":3,"tournament_start_options":[2,5,10,15,30,60]}`
  so a client can detect the server version without a token.
- `GET /health` returns `{"ok":true}`.
- `GET /heroes` returns `{"heroes":[…32 canonical IDs…],"aliases":{…}}`.

## Email

Players may attach one email address and prove they own it with a 6-digit
code. Only a **verified** address can be used to [recover the
account](#account-recovery-by-email) on a new device. The server owns
`email_status`; the client never sets it.

**Address rules.** Trimmed and lowercased, at most 254 characters (local
part at most 64), one `@`, a dotted domain, no spaces or consecutive dots.
Invalid addresses return `400 {"error":"Enter a valid email address (at most 254 characters)"}`.

**Changing the address resets verification.** `PATCH /me` with a different
address (or `null`/`""`) sets `email_verified_at` to `null` and kills every
unused code of that player. Re-sending the same address (any case) changes
nothing.

**Uniqueness.** A verified address belongs to exactly one player (unique
index on `lower(email)` where `email_verified_at is not null`). Unverified
copies of the same address may sit on several players. The first successful
confirm wins; every other open code for that address is then dead, and
requesting or confirming a code for it from another player returns
`409 {"error":"That email is already used by another account."}`. Storing
it unverified with `PATCH /me` is still allowed.

### `POST /me/email/verification`: send a code

Requires a device token. Body `{"email":"pat@example.com"}`, or `{}` to use
the stored address. If the address differs from the stored one it is saved
as the player's (unverified) address first.

`200`:

```json
{"challenge_id":"ec_AbC…","expires_at":"2026-11-15T12:10:00.000Z","resend_available_at":"2026-11-15T12:01:00.000Z","email":"pat@example.com"}
```

The code is emailed from `Nineweave <no-reply@nineweave.sitebloc.com>`. It is
never returned and never stored (only `sha256` over challenge id + code).
A new request supersedes the player's previous unused code.

| Status | When |
|---|---|
| `400` | Invalid address, no address given or stored, unknown field |
| `401` | Missing or unknown device token |
| `409` | Address already verified on another account, or already verified on yours |
| `429` | Cooldown or hourly cap (body adds `retry_after_seconds`), or IP limit |
| `502` | The email provider didn't accept the message: `"Could not send email. Try again shortly."` (the challenge is discarded) |
| `503` | Email isn't configured on this server: `"Email verification is not available on this server yet"` |

### `POST /me/email/verification/confirm`

Requires a device token. Body `{"challenge_id":"ec_…","code":"123456"}`
(spaces in the code are ignored; a JSON number is accepted).

`200`: the updated `player` object with `email_status:"verified"`.

| Status | When |
|---|---|
| `400` | `code` isn't 6 digits, `challenge_id` missing, or unknown field |
| `400` | `"Invalid or expired code"`: wrong code, expired, already used, superseded, address changed since, or out of attempts. One message for all of them. |
| `401` | Missing or unknown device token |
| `404` | No such challenge for this player (unknown id, or another player's) |
| `409` | Another account verified this address first |
| `429` | IP limit |

### Code limits

| Limit | Value | Where enforced |
|---|---|---|
| Code lifetime | 10 minutes | database |
| Guesses per code | 5 (the 6th is refused even if right) | database, atomic counter |
| Resend cooldown | 60 s per player | database |
| Codes per player | 5 per rolling hour | database |
| Codes per address | 5 per rolling hour (all players combined) | database |
| Requests per IP | 10/min (send), 30/min (confirm) | per instance, best-effort |

Failed sends count toward the hourly caps. The database caps hold across
serverless instances.

### Account recovery by email

Signs a player in on a new device using their **verified** address. Neither
endpoint needs a token. Unverified addresses can't recover.

`POST /auth/email/recover` with `{"email":"pat@example.com"}` always answers
`200 {"challenge_id":"ec_…","expires_at":"…","resend_available_at":"…"}`,
whether or not the address is verified on an account, throttled, or the send
failed, so it can't be used to test which addresses are registered. A code
(subject "Your Nineweave sign-in code") is sent only when the address is
verified on an account and no limit is hit. Errors: `400` (invalid address),
`429` (IP limit), `503` (email not configured).

`POST /auth/email/recover/confirm` with `{"challenge_id":"ec_…","code":"123456"}`
returns `200` in the same shape as `POST /auth/device`:

```json
{"token":"nwd_…","player_id":"p_AbC…","player":{…}}
```

The new device token **replaces** the old one: the previous device is
signed out (`401` on its next call). Multiple devices per player may come in
a later revision. Every failure (unknown id, wrong, expired, used, out of
attempts, address changed or unverified since) is
`400 {"error":"Invalid or expired code"}`. The same code limits apply; a
verification code can't be used here and vice versa.

Known limitation: a request for a verified address does a little more work
(it sends an email) than one for an unknown address, so response timing may
differ slightly.

### Server configuration

The builder must set the secret `NINEWEAVE_RESEND_API_KEY` (a Resend API key
for the `nineweave.sitebloc.com` domain). Without it, `GET /me` still
advertises `capabilities.email` and `PATCH /me` still stores addresses, but
sending a code answers `503`. The key is read at runtime and never logged.

## Records

Records are updated only when a full match ends, never per small board, and
always in the same transaction as the room's status change. Anonymous seats
(no device token) aren't recorded, but their opponent's record still is.

| Outcome | Winner | Loser | Both |
|---|---|---|---|
| Win (three boards in a line) | `matches_won+1` | `matches_lost+1` | `matches_played+1` |
| Draw (no open boards, no big line) | none | none | `matches_played+1` only |
| Forfeit (leave) / timeout / abandoned, after both moved | opponent `matches_won+1` | leaver `matches_lost+1` | `matches_played+1` |
| Cancelled / no-show, before both moved | none | none | none (no match logged) |
| Tournament draw decided by small boards (`boards`) | `matches_won+1` | `matches_lost+1` | `matches_played+1` |
| Tournament draw with level boards | none | none | none (the game is replayed) |

- `boards_won`: each player gets one point per small board they claimed
  (won, not drawn) in the match. This counts on forfeits too.
- There is **no board-count tiebreak** in regular rooms. A draw is a draw
  even if one player holds more boards. Tournament rooms differ: see
  [Tournaments](#tournaments).
- The official score (the leaderboard) is `matches_won`.

## Rules (server kernel = `rules.gd`)

- Marks: OPEN=0, X=1, O=2, DRAW=3.
- A move is legal when the game is open, `board` and `cell` are both in
  `0..8`, the board is unclaimed, the board is `active` (or `active == -1`),
  and the cell is empty.
- A move on cell C sends the opponent to board C. If board C is already won
  or full, `active` becomes `-1` instead (free move).
- A small board is claimed by three in a row (win) or by being full with no
  line (DRAW).
- The match is won with three boards in a line, using the masks
  `[7,56,448,73,146,292,273,84]`. If no board is open and there is no big
  line, it's a draw.
- The server rebuilds rules state from history and never accepts client
  board state, turn, winner or identity.

## Heroes

There are 32 canonical IDs: `cryon, aurelia, vesper_vale, auric_rex,
nyx_thread, cobalt_bastion, ember_quill, lumen_pike, shard_jack,
madame_solstice, bramble_ox, kite_hollow, professor_gilt, siren_coil,
ryan_blaze, tempest_vega, james_ii, sara, daphne, jason_danger, dylan_volt,
max_granite, kellen_byte, simon_shade, alex_wilder, rose_valor,
grayson_quake, erick_comet, devin_torque, pope_slam, ethan_ricochet,
aiden_vortex`.

The server accepts these aliases on input and always returns the canonical
ID: `erik_comet→erick_comet`, `ak_shade→simon_shade`,
`derrick_torque→devin_torque`, `nova_sable→aiden_vortex`,
`mateo_ricochet→ethan_ricochet`. Unknown IDs return `400`.

## Consent

Creating a screen name records that the player agreed to the current Terms
of Service and Privacy Policy and confirmed they are 13 or older or have a
parent or guardian's permission. The documents live at `/terms` and
`/privacy`. The current document versions are `2026-11-15`.

`POST /auth/device` and `PATCH /me` accept any subset of:

| Field | Rules |
|---|---|
| `tos_version` | 1–32 characters: letters, digits, `.`, `_` or `-`. |
| `privacy_version` | Same as `tos_version`. |
| `accepted_at` | ISO-8601 timestamp. It may not be more than one day in the future. If the other consent fields are sent without it, the server stores the current time. |
| `age_confirmed` | JSON boolean. |

`GET /me` returns all four (`null` until recorded). Existing accounts stay
valid with null columns.

## Names

This applies to screen names and in-room display names:

- Control characters are stripped, whitespace is collapsed, and the name is
  trimmed.
- Names must be 1–24 characters.
- Allowed characters: letters (any script), digits, spaces, and
  `. , ' ! ? _ - ( ) & + # :`.
- Names on a basic English profanity blocklist are rejected, including
  leetspeak and dotted variants. Ordinary names such as "Cassandra" or
  "Therapist" pass.
- Failures return `400` with a readable `error`.
- Screen names are unique case-insensitively (`409`). In-room display names
  don't need to be unique.

## Timeouts

Stale rooms are cleaned up opportunistically (no cron). The sweep runs at
most once every 5 s per server instance, on list, create, join, poll and
moves. A room's own deadlines are also checked whenever someone polls it or
acts in it. **The server enforces every deadline; the client only displays
them.**

| Situation | Timeout | Result |
|---|---|---|
| `waiting` room, host not polling | **600 s** since creation or the host's last poll | `closed`, `end_reason:"expired"` |
| `active`, player due to move hasn't moved | **25 s** turn clock | The "Still there?" phase starts (`still_there_at`). Nothing changes on the server yet. |
| `active`, unconfirmed "Still there?" phase | **10 s** more (35 s after `turn_started_at`) | Before `both_moved`: `closed`, `end_reason:"no_show"`, no records. After: the player due to move loses, `end_reason:"timeout"`. |
| `active`, accepted confirmation | **10 s** from acknowledgement | Must make a valid move before the deadline, otherwise a timeout loss even before both players have moved. |
| `active`, the seat **not** due to move hasn't polled or moved | **60 s** disconnect grace | Before `both_moved`: `closed`, `end_reason:"no_show"`, no records. After: that seat loses, `end_reason:"abandoned"`. |
| `finished` room, neither player polling | 600 s | `closed`, records unchanged |

Presence (`*_seen_at`) is written at most once every 10 s per player, so a
seat that polls at the hinted rates is never more than ~13 s stale; the
60 s grace allows for that. Polling with the same token inside the grace
simply continues the match.

## Match rules v2

Decided Nov 15, 2026 (Patrick). Applies from protocol 2 on.

| Rule | Value / behavior |
|---|---|
| Waiting room | Unchanged: `waiting` until a guest joins. Leaving or cancelling = cancel, no penalty. `opponent_joined_at` / `players` let the client show "<ScreenName> joined". |
| "Both players have moved" | The current round's history holds ≥1 move by seat 1 and ≥1 by seat 2 (`both_moved`). Each rematch round starts over. |
| Turn clock | **25 s** per turn for the player due to move. No time bank. |
| "Still there?" | After 25 s, a **10 s** prompt. Confirming with `POST /still-here` gives **10 s to make a move**, once per turn; it does not reset the normal turn clock. A second confirm in the same turn is `409` and doesn't extend. A move always ends the turn normally. |
| Turn expiry (35 s, or 10 s after a still-here confirmation) | Before `both_moved` without confirmation: `no_show`, match cancelled, no records. After confirmation, or after both moved: `timeout`, the player due to move loses, the opponent wins, records update. |
| Disconnect grace | **60 s** without a poll or move by the seat that is **not** due to move. Before `both_moved`: `no_show`. After: `abandoned` loss. While it is your turn, the turn clock governs instead. |
| Explicit leave | Before `both_moved`: `closed`, `end_reason:"cancelled"`, `result:null`, no records, opponent sees `opponent_left:true`. After: `forfeit` loss. |
| Finished / rematch | Unchanged. Each rematch round gets a fresh clock and a fresh `both_moved`. |

In every "closed" case above the opponent's envelope shows
`opponent_left:true` and `poll_after_ms: 0`.

## Chat

In-match text chat between the two players of a room, polled with the
moves. Nineweave is a 13+ game under App Store rules.

**Who can chat.** Only device players with a screen name (device token at
create/join, `screen_name` set). Anonymous seats and players without a
screen name get `403 {"error":"Create a screen name to chat"}`. Chat is
allowed while the room is `active` or `finished`. `waiting` (nobody to talk
to yet) and `closed` return `409`.

### `POST /rooms/<CODE>/chat`

Body: `{"text":"Nice one"}` **or** `{"preset":"gg"}` (exactly one, plus an
optional `token` like the other room endpoints). Optional query
`?chat_since=<id>` picks which messages come back in `chat`.

Presets (also in `GET /capabilities` as `chat_presets`):

| Key | Text |
|---|---|
| `gg` | Good game! |
| `nice` | Nice move |
| `rematch` | Rematch? |
| `gl` | Good luck! |
| `hi` | Hi! |
| `thanks` | Thanks! |
| `wow` | Wow! |
| `oops` | Oops! |

Free-text rules:

- Single line: line breaks and tabs become spaces, control / zero-width /
  bidi characters are removed, whitespace is collapsed and trimmed.
- 1–120 characters after that (`400` otherwise).
- Profanity is masked server-side with asterisks of the same length,
  including leetspeak and simple obfuscation. The message is still
  delivered, with `filtered: true` on the sender's ack.
- Slurs / hate terms and anything that looks like a URL, email address,
  phone number or messaging-app handle are refused with
  `400 {"error":"Message not allowed"}`, and nothing is stored. Contact info
  can't be shared.

`200`: the envelope plus `"ok": true`, `message` (the stored message, with
`filtered`) and `chat` / `chat_seq` as on the poll.

```json
{"ok":true,"message":{"id":42,"seat":1,"mine":true,"name":"Patrick","text":"what the ****","preset":null,"at":"2026-11-15T12:00:03.000Z","filtered":true},"chat":[…],"chat_seq":42, "...": "envelope"}
```

| Status | When |
|---|---|
| 400 | Neither or both of `text`/`preset`, unknown preset or field, empty, over 120 characters, or `Message not allowed` |
| 401 / 403 / 404 | As for moves, plus `403 Create a screen name to chat` |
| 409 | Room `waiting` or `closed` (includes the envelope) |
| 429 | Over 5 messages per 10 s or 30 per 5 minutes for this player (counted in the database, so it holds across server instances). The body adds `retry_after_seconds`. |

### Receiving: the poll

`GET /rooms/<CODE>?chat_since=<id>` (default `0`) returns:

- `chat`: up to 50 messages with `id > chat_since`, oldest first:
  `[{"id":42,"seat":1,"mine":false,"name":"NightNight","text":"Good game!","preset":"gg","at":"…"}]`.
  `seat` is the sender's **current** seat in the room (it swaps on rematch
  like everything else). `mine` is `true` for the caller's own messages.
  `name` is the sender's screen name when they sent it.
- `chat_seq`: the newest message id the caller can see (`0` if none).

Set `chat_since` to the last `id` you received. If `chat_seq` is higher than
the last `id` in a full page, poll again. The sender's own messages are
included, so dedupe by `id`. Messages from players the caller blocked are
never included.

### Mute

Mute is **client-side only**, per match: the client hides the opponent's
messages locally. Nothing is sent to the server.

### Block

`POST /players/block` with `{"room_code":"N9ABC","seat":2}` (device token
required). The server looks up the caller's room with that code (one where
the caller's device player has a seat, latest first) and blocks the player
in that seat for the caller **permanently**:

- Their chat is never delivered to the caller, in any room.
- They can't join the caller's rooms. They get `409 {"error":"Room is full"}`,
  so the block isn't revealed. Those rooms are also hidden from their lobby
  list when they send their device token on `GET /rooms`. Both rules apply
  in both directions.

`200 {"ok":true,"blocked":true}`. Repeating it is a no-op.

| Status | When |
|---|---|
| 400 | Bad `room_code` or `seat`, or your own seat |
| 401 | No device token (seat tokens can't block) |
| 403 | You weren't in that room |
| 404 | No room with that code, or nobody in that seat |
| 409 | The opponent plays anonymously and can't be blocked (anonymous players can't chat either) |

`DELETE /players/block` takes the same body, or `{"name":"NightNight"}`
(case-insensitive) to unblock by screen name. It returns
`200 {"ok":true,"blocked":false}`, or `404` when no blocked player has that
name.

`GET /players/blocks` returns `{"blocks":[{"name":"NightNight","blocked_at":"…"}]}`,
newest first. Player ids are never exposed.

### Report

`POST /reports` (device token required):

```json
{"room_code":"N9ABC","seat":2,"reason":"harassment","note":"optional, up to 500 characters"}
```

`reason` is one of `harassment`, `hate`, `inappropriate_name`, `cheating`,
`spam` or `other`. The server stores the reporter, the reported player
(anonymous seats are stored by their room name), the room code, the reason,
the note, and a snapshot of the reported player's last ≤20 chat messages in
that room. It returns `201 {"ok":true}`.

Limit: 10 reports per hour per player (`429` with `retry_after_seconds`).
Errors are the same as for block, plus `400` for an unknown reason, a note
over 500 characters or an unknown field.

### Retention

| Data | Deleted |
|---|---|
| Chat messages | 24 h after creation, or 1 h after their room closed, whichever is first |
| Reports (incl. chat snapshot) | 30 days after creation |
| Blocks | Kept until unblocked (or the player is deleted) |

Deletion runs opportunistically with the room sweep, at most once a minute
per server instance. Message text is never logged.

## Tournaments

Single-elimination online tournaments for 3–8 players. Regular 1v1 rooms are
unchanged; a tournament is an extra mode. Only device players with a screen
name can create or join (`401` without a device token, `403` without a
screen name). A player can be in one tournament at a time: registered, or
still in the bracket of a running one (`409 "You're already in a
tournament"`). Source: `src/lib/nineweave/tournaments.ts`.

### Rules

| Rule | Value |
|---|---|
| Sizes | 4 or 8 seats (`size`). |
| Start time | `starts_in_minutes` ∈ 2, 5, 10, 15, 30, 60, or `starts_at` (ISO) 2 min–24 h ahead. |
| Full bracket | Status `starting` with `starting_at` = now + 10 s; it starts then (or at `starts_at`, if sooner). A leave during the countdown goes back to `registering`. |
| Minimum | 3 players. Fewer at the start time: `cancelled`, `cancel_reason: "Not enough players joined"`, nobody penalized. |
| Players used | Everyone who joined: 6 of 8 is a 6-player tournament. |
| Bracket | Next power of two ≥ players (3–4 → 4, 5–8 → 8). Rounds: 2 or 3. |
| Seeding | Crypto-random shuffle at the start; seed 1 is the top seed. |
| Byes | Bracket − players (3 → 1, 5 → 3, 6 → 2, 7 → 1). Round 1 pairs seed *s* with seed *bracket+1−s* (8: 1v8, 4v5, 2v7, 3v6; 4: 1v4, 2v3), so the missing seeds give byes to the top seeds. Seeding is random, so byes are too. At most one per player, round 1 only. A bye auto-advances (`end_reason: "bye"`). |
| Matches | Each is a normal room (match rules v2: 25 s turn + 10 s Still there?, 60 s grace), opened as soon as both players are known. Normal W/L records. |
| One game | No rematch (`409`). A draw goes to whoever claimed more small boards (`end_reason: "boards"`, a recorded win). Level boards: the game is replayed in the same room (`match.round` + 1, seats swap, `both_moved` resets, no record). |
| Ready window | A match room opens `waiting` for 60 s (`ready_deadline`). Any request to the room with your seat or device token counts as showing up. When both have, the room turns `active` and the turn clock starts. |
| No-show | Window over with one player present: they advance (`end_reason: "no_show"`, `result.winner` set, no record change). Neither present: the higher seed (lower number) advances. |
| Leaving / stalling | Before both moved (including the ready window): the opponent advances on `no_show`, no records. After both moved: the normal v2 forfeit / timeout / abandoned loss (recorded); the loser is eliminated. |
| Leave tournament | Before the start: frees the slot, no penalty; the host passes to the next joiner, and the tournament is cancelled when the last player leaves. After the start: forfeits your current match (by the rules above) or your next one (the opponent advances with `forfeit`, no record). |
| Champion | Winner of the final. `tournament_wins + 1` on their profile (exactly once). |
| Lifecycle | `registering` → `starting` → `running` → `finished`, or `cancelled`. |
| Retention | Tournament rows (players, matches) are purged 7 days after their last update. Rooms follow the normal room sweeps. |

There is no cron. The start, no-shows and bracket steps happen on whichever
request touches the tournament first after the deadline: a tournament poll,
the list, a join, or a request to an ended match room. Each step is one
atomic batch guarded by the tournament row's version, so it happens exactly
once under concurrent polls.

### `POST /tournaments`: create

Device token required.

```json
{"size":8,"starts_in_minutes":10,"private":false,"character_id":"vesper_vale"}
```

`password` (≤ 64 characters) is required when `private` is true. Send
exactly one of `starts_in_minutes` and `starts_at`. `character_id` defaults
to the player's `last_hero_id`. `201`: the tournament envelope (the creator
has joined and is the host). Errors: `400`, `401`, `403`, `409`, `429`.

### `GET /tournaments`: public lobby

No token needed. Public tournaments in `registering` that aren't full, newest
first, at most 50. Private ones are never listed.

```json
{"server_now":"…","tournaments":[{"code":"T7KQ2M","size":8,"joined":3,"min_players":3,"host":"Kai","starts_at":"…","created_at":"…"}],"poll_after_ms":5000}
```

### `POST /tournaments/<CODE>/join`

Device token required. Body `{"password"?, "character_id"?}`. `200`: the
envelope. Joining again is a no-op `200`. Errors: `403` (wrong password, no
screen name), `404`, `409` (full, started, ended, or already in another
tournament).

### `POST /tournaments/<CODE>/leave`

Device token required. `200`: `{"ok":true, …envelope}` (`you` is `null`
after leaving before the start). `409` if you're not in it. See the rules
above for what leaving does.

### `GET /tournaments/<CODE>`: poll

Device token required. Entrants and anyone (for a public tournament) can
poll; private tournaments return `403` to non-entrants. The envelope:

```json
{
  "code": "T7KQ2M", "status": "running", "size": 8, "joined": 6, "min_players": 3,
  "bracket_size": 8, "starts_at": "…", "starting_at": null, "started_at": "…",
  "finished_at": null, "server_now": "…", "private": false, "host": "Kai",
  "is_host": false, "cancel_reason": null,
  "you": {"seed": 3, "name": "Mo", "hero": "cryon", "state": "playing"},
  "players": [{"seed": 1, "name": "Kai", "hero": "vesper_vale", "eliminated": false}],
  "rounds": [
    [{"slot": 0, "a": {"name": "Kai", "hero": "vesper_vale", "seed": 1}, "b": null,
      "bye": true, "status": "done", "score": null, "winner": "a", "end_reason": "bye"},
     {"slot": 1, "a": {"name": "Ana", "hero": "sara", "seed": 4},
      "b": {"name": "Bo", "hero": "cryon", "seed": 5}, "bye": false, "status": "live",
      "score": {"a": 3, "b": 2}, "winner": null, "end_reason": null}]
  ],
  "your_match": {"room_code": "QX7P2", "token": "nws_…", "seat": 1, "round": 1, "slot": 3,
                 "status": "ready", "opponent": {"name": "Cy", "hero": "daphne"},
                 "ready_deadline": "…"},
  "champion": null,
  "poll_after_ms": 1000
}
```

- `players`: screen names, hero ids and seeds only (seeds are `null` before
  the start; the list is in join order then). Never player ids, token hashes
  or room ids.
- `rounds`: empty before the start. `rounds[r][k]` is round `r+1`, slot `k`;
  its winner plays in round `r+2`, slot `k>>1`, side `a` for even `k` and
  `b` for odd. `a`/`b` are `null` until known (or for a bye). `status`:
  `pending` (players not both known), `ready` (room open, ready window),
  `live` (being played), `done`.
- `score`: small boards won by each side, from the room's current game for
  `live` matches (e.g. "Ana 3 – 2 Bo") and the final game for `done` ones.
  `null` otherwise. Cells and moves of other matches are never included (no
  spectating).
- `you.state`: `registered` (before the start, or a cancelled tournament),
  `playing` (your match room is open), `waiting` (still in, waiting for your
  next opponent), `bye` (through on a round-1 bye, next opponent not decided
  yet), `eliminated` (lost or left), `champion`.
- `your_match`: only for you, only while your match is `ready`/`live`. `token`
  is your seat token for that room. It's stable across polls and derived from
  your device token, so it works only for you. Use it with the normal room
  endpoints: poll, moves, still-here, chat, leave. `seat` is 1 (X, moves
  first) or 2. Your device token also works on those endpoints.
- `champion`: `{name, hero}` once finished.

`poll_after_ms`:

| Situation | ms |
|---|---|
| `registering` | 5000 |
| last 15 s before `starts_at`, or `starting` (countdown) | 2000 |
| running, your match open and you haven't entered the room yet | 1000 |
| running, otherwise (waiting room, playing, eliminated) | 4000 |
| `finished` / `cancelled` | 0 (stop) |

### Tournament rooms

Tournament match rooms are ordinary rooms with these differences:

- The envelope has `tournament: {code, round, slot, ready_deadline,
  ready: {you, opponent}, rematch: false}` (`null` in normal rooms).
- They are private and pre-seated: `join` answers `403`/`409`, `cancel`
  answers `409`, `rematch` answers `409 "Tournament matches are one game: no
  rematch"`. They never show in `GET /rooms`.
- `status` is `waiting` during the ready window (`poll_after_ms: 1000`), then
  `active` once both players have opened the room.
- New end reasons: `no_show` with a `result` (someone advances) and `boards`
  (a draw decided by small boards won).

## Rate limits

Limits are per client IP and per server instance, in a fixed one-minute
window, so treat them as best-effort. Exceeding one returns `429`.

| Request | Limit per minute |
|---|---|
| `POST /auth/device` | 10 |
| `POST /rooms` | 20 |
| `POST /rooms/<CODE>/join` | 40 |
| `POST /tournaments` | shares the `POST /rooms` limit (20) |
| `POST /tournaments/<CODE>/join` | shares the room join limit (40) |
| `POST /tournaments/<CODE>/leave` | shares the moves limit (180) |
| moves, still-here, rematch, leave and cancel combined | 180 |
| `POST /rooms/<CODE>/chat` | 60 (plus the per-player database caps in [Chat](#chat)) |
| block, unblock and report combined | 30 |
| `PATCH /me` | 30 |
| `POST /me/email/verification` + `POST /auth/email/recover` | 10 |
| `POST /me/email/verification/confirm` + `POST /auth/email/recover/confirm` | 30 |

Email codes also have per-player and per-address caps enforced in the
database; see [Code limits](#code-limits). Chat (5 per 10 s, 30 per 5 min)
and reports (10 per hour) are capped per player in the database.

## CORS

These origins are allowed and reflected in `Access-Control-Allow-Origin`
(with `Vary: Origin`):

- `https://elexerly.github.io` (this covers `/Nineweave`)
- `https://nineweave.grok.me`
- `http://localhost:8060`, `http://localhost:8080`
- `http://127.0.0.1:8060`, `http://127.0.0.1:8080`

Allowed headers are `Authorization, Content-Type`. Allowed methods are
`GET, POST, PATCH, DELETE, OPTIONS` (`DELETE` is for unblocking). `Access-Control-Max-Age` is `600`. `OPTIONS`
returns `204`. Credentials and cookies aren't used, so there is no
`Allow-Credentials` header.

## Server not configured

A production build with no database URL returns
`503 {"error":"Online play is not configured on this server yet"}` on every
API path. Preflight still returns `204`, and the rest of the site is
unaffected. The Godot client's existing 503 handling shows "Online server not
available yet".

## Status code summary

| Code | Meaning |
|---|---|
| 200 / 201 | OK / created (`POST /rooms`, `POST /auth/device`) |
| 204 | CORS preflight |
| 400 | Malformed JSON or invalid field |
| 401 | Missing or unknown token where one is required |
| 403 | Token not in this room, not your turn (moves, still-here), wrong room or tournament password, not the host (cancel), no screen name (chat, tournaments), not in that room (block/report), or a private tournament you haven't joined |
| 404 | Unknown path, no such room or no such tournament |
| 405 | Wrong method |
| 404 | Email verification challenge not found for this player |
| 409 | Room full or state conflict (stale/future seq, stale round, closed, waiting); still-here already used or not showing; chat in a waiting/closed room; anonymous player can't be blocked; name taken; email already verified elsewhere; rematch or cancel in a tournament room; tournament full, started or ended; already in another tournament; leaving a tournament you're not in |
| 413 | Body over 8 KB |
| 422 | Illegal move or game finished |
| 429 | Rate limited (chat and report caps add `retry_after_seconds`) |
| 500 | Unexpected server error (details are logged, not returned) |
| 502 | Email provider didn't accept a code email |
| 503 | Not configured (database, or email for code requests), or room / tournament contention (retry) |

## Godot client notes (additive changes)

- The current client works as-is: create, join, poll, moves, rematch.
- Optional: send `Authorization: Bearer <device token>` on create and join to
  rank the player. Keep the device token separate from the seat token, which
  goes in the moves/rematch body and the poll header.
- Optional: call `POST /rooms/<CODE>/leave` from `leave()` before clearing
  credentials. Otherwise an abandoned match ends by the turn clock (35 s) or
  the 60 s disconnect grace (see [Match rules v2](#match-rules-v2)).
- `opponent_left` stays `true` on every later poll, so emit once client-side.
- Email (Round 4e): wait until `GET /me` returns `capabilities.email: true`.
  Until then keep the address local and send nothing. Once advertised:
  `PATCH /me {"email": …}` to store it, `POST /me/email/verification` to
  send a code, show the code-entry stage with `expires_at` /
  `resend_available_at`, then `POST /me/email/verification/confirm`. Treat
  `email_status` / `email_verified_at` from the server as the only truth and
  feed them to `set_verification_status`. On `409` show the error text; on
  `429` use `retry_after_seconds`; on `502`/`503` show "Email isn't
  available right now".
- Sign in on a new device: `POST /auth/email/recover`, then
  `POST /auth/email/recover/confirm`; store the returned device token in
  place of the old one.
- **Online2 (Round 5).** Detect it with `GET /capabilities` (`protocol: 2`)
  or `capabilities.online2` on `/me`. Then:
  - Poll at `poll_after_ms` and stop at `0`. Send `chat_since=<last chat id>`.
  - Countdown: show the turn timer from `turn_started_at` to `still_there_at`
    (25 s). At `still_there_at`, show "Still there?" to the player due to
    move with a 10 s countdown to `turn_expires_at`. Compute the remaining
    time as `deadline − server_now` from the latest envelope, then count
    down locally. On "I'm here", call `POST /rooms/<CODE>/still-here` (only
    while `still_here_used` is false, and hide the button after use). The
    server decides expiry, so just render the next envelope you get.
  - Leave button: if `both_moved` is false, leave without a warning. If it
    is true, confirm with "Leave match? This counts as a loss."
  - Endings: `no_show` or `cancelled` with `result:null` means "Match
    cancelled, no result". `timeout`, `abandoned` and `forfeit` show a win or
    loss from `result.winner`. Older clients that don't know `abandoned`
    can treat it like `timeout`.
  - Waiting room: show the room code, `you.hero` and a Leave button, then
    "<players[opponent seat].name> joined" when `opponent_joined_at`
    appears. Show `opponent_connected` as a presence dot.
  - Chat: show the chat button only to players with a screen name. Label
    messages with `name`, align them by `mine` and dedupe by `id`. Mute is
    local. Block and report send the opponent's `seat` and the room code
    with the device token.
- **Tournaments (Round 5, phase 3).** Detect them with
  `capabilities.tournaments`. Then:
  - Create: offer `tournament_sizes` and `tournament_start_options` from
    capabilities, plus public / password. Lobby: `GET /tournaments`. Join by
    code: `POST /tournaments/<CODE>/join`.
  - Poll `GET /tournaments/<CODE>` at `poll_after_ms` with the device token.
    Count down locally to `starting_at` / `starts_at` from `server_now`.
  - Bracket / waiting room: draw `rounds` and show `score` for `live`
    matches ("Kai 3 – 2 Mo"). Grey out `players[].eliminated`.
  - When `your_match` appears, show the versus screen and open the room right
    away with `your_match.room_code` + `your_match.token`, like a joined room
    (seat from `your_match.seat`). Opening it within the 60 s
    `ready_deadline` counts as ready; a "Ready" button can simply be that
    first room poll. Use the normal room flow from there.
  - On match end (`finished`, or `closed` with `result`), skip the rematch
    UI and go back to the tournament poll. `you.state` tells you whether you
    advance (`waiting` / `playing`), are out (`eliminated`) or won
    (`champion`, with `champion` filled for everyone).
  - Leave: confirm "Leave tournament?" after the start, because it forfeits
    your match.

## Account-scoped tutorial completion

`GET /me` and profile responses include `tutorial_completed: boolean` and
`capabilities.tutorial_completion: true`. A new account starts false.
`POST /me/tutorial/complete` with Bearer device authentication and `{}` marks
only that account true and returns the same profile as `GET /me`. It is
idempotent and cannot reset completion. Extra body fields are rejected (400).
No authentication returns 401. The marker survives email recovery/token
rotation and is deleted with its player; there is no independent history.

Show the automatic tutorial after account setup and before entering matchmaking,
never while an opponent waits. Write completion only after completing or
explicitly skipping, not opening it. Local offline completion must be associated
with the same account before syncing; never carry one account's marker into
another. Manual How to Play remains available. Deploy additive migration
`0008_nineweave_tutorial_idle.sql` before this server version.

## Three consecutive late own turns

Every room envelope includes `consecutive_late_turns`,
`opponent_consecutive_late_turns` (mapped to the requesting seat), and
`turn_late_limit: 3`. Each player's streak is independent. A legal move before
that player's 25-second prompt resets their streak; the opponent's turns do
not. A move at/after the prompt counts as late even without an acknowledgement.
The first two late turns retain the existing one-time acknowledgement and ten
seconds to move. On the third consecutive late own turn, the player forfeits
**at the 25-second prompt boundary**, without a third acknowledgement window.
When two prior late turns exist, `turn_expires_at` therefore equals
`still_there_at` from the start of the next own turn: warn before this deadline.

The persisted counters represent completed turns; the envelope also includes
one current strike if the current own turn has reached the prompt. Polling,
reconnecting, invalid moves, duplicate moves and acknowledgements cannot
increment or reset the counters. Only a new accepted legal move advances them.
Both counters reset for a rematch or tournament draw replay. Tournament timeout
results advance the opponent normally. Migration
`0009_nineweave_late_turn_streak.sql` must precede this server version.
