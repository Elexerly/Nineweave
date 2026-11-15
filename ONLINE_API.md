# Nineweave Online API (v1)

Authoritative backend for online Ultimate Tic Tac Toe. It implements
`godot/ONLINE_PROTOCOL.md` (rounds 1–4) and adds a few things on top: device
accounts, a leaderboard, a lobby, private rooms and leave/timeout handling.
The existing `HttpPollingTransport` works against it unchanged. Everything new
is optional for the client to use.

- **Base path:** `/api/nineweave` (same origin on `https://nineweave.grok.me`).
- **Format:** JSON request and response bodies (`Content-Type: application/json`).
  The body limit is 8 KB (`413` above that).
- **Errors:** every non-2xx response carries
  `{"error": "Human-readable explanation"}`. Conflict and illegal-move errors
  on a room also include the full room envelope (see below), so the client can
  resync.
- **Caching:** every response sends `Cache-Control: no-store`.
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

- **Room endpoints** (poll, moves, rematch, leave, cancel) accept either a
  seat token or the device token of the player in that seat. The token can
  come from the header or from a body `"token"` field (the protocol's moves
  and rematch bodies have one). If both are sent, either one may match.
- **Create/join:** the `Authorization` header, when present, must be a
  **device** token. An unknown token returns `401`. Without one, the seat is
  anonymous: it can play but has no record, so it isn't ranked.
- **`/me`:** requires a device token.
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
  "turn_expires_at": "2026-11-15T12:03:00.000Z"
}
```

| Field | Meaning |
|---|---|
| `seat` | The caller's current seat (1 = X, 2 = O). |
| `seq` | Number of moves in the current round (`state.history.length`). |
| `status` | `waiting` (no guest yet), `active` (match in progress), `finished` (round over, rematch possible), `closed` (cancelled, expired, someone left, or timed out). Terminal. |
| `opponent` | The opponent's name, or `""` while nobody has joined. It is never `null`. |
| `opponent_left` | `true` once the opponent left the room or timed out. |
| `characters` | Map from seat (string key) to canonical hero ID. While waiting, only the host's seat is present. The map swaps with seats on rematch. |
| `match.round` | Starts at 1 and goes up by one on each accepted rematch. |
| `match.seat` | Same as `seat`. On a round increment, use it as the new seat. |
| `match.local` / `match.remote` | Whether the caller and the opponent have each asked for a rematch of this round. |
| `result` | `null`, or `{"winner": 0\|1\|2, "reason": "win"\|"draw"\|"forfeit"\|"timeout"}`. `winner` is a seat, and `0` means a draw. Seats are relative to the round that ended until a rematch clears it. |
| `end_reason` | `win`, `draw`, `forfeit`, `timeout`, `cancelled`, `expired` or `null`. |
| `turn_expires_at` | ISO time when the player due to move forfeits (`active` only), otherwise `null`. |

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

#### `GET /rooms/<CODE>?since=<n>`: poll

Requires authorization (header). Poll about once per second.

`200`: the envelope plus `moves`, the moves of the current round with
`seq > since`, sorted:

```json
{"seq":13,"opponent":"Friend","opponent_left":false,"moves":[{"board":4,"cell":0,"seq":13}],"state":{"...":"…"},"match":{"round":1,"seat":1,"local":false,"remote":false},"characters":{"1":"vesper_vale","2":"auric_rex"},"status":"active", "...": "…"}
```

A full `state` snapshot is **always** included. If `since` is higher than the
current `seq` (for example from a previous round), `moves` is `[]` and you
should resync from `state`/`seq`. Polling also counts as presence (see
[Timeouts](#timeouts)).

Errors: `401` (no token), `403` (token not in this room), `404` (no room with
that code).

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

The body is optional (`{"token":"…"}` or use the header). `200`: the envelope
plus `"ok": true`.

| Status before | Effect |
|---|---|
| `waiting` | The room is cancelled (`closed`, `end_reason:"cancelled"`). It disappears from the lobby and its code stops joining. |
| `active` | **Forfeit.** The opponent wins (`result.reason:"forfeit"`) and both records update in the same transaction. The room closes and the opponent sees `opponent_left:true`. |
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
{"token":"nwd_…","player_id":"p_AbC…","player":{"player_id":"p_AbC…","screen_name":null,"last_hero_id":null,"purchases":[],"unlocks":[],"matches_won":0,"matches_played":0,"matches_lost":0,"boards_won":0,"tos_version":null,"privacy_version":null,"accepted_at":null,"age_confirmed":null,"email":null,"email_status":"none","email_verified_at":null,"capabilities":{"email":true},"rank":1}}
```

The token is shown **only here**, so store it securely on the device.
`player_id` is public and safe to display or share.

Errors: `400` (invalid name or hero), `409` (screen name taken; no player is
created), `429`.

#### `GET /me`

Requires a device token. `200`: the `player` object above. `rank` is
1 + the number of ranked players with more matches won (ties share a rank).
`401` if the token is missing or unknown.

- `capabilities`: feature flags. `capabilities.email: true` means this server
  supports the [Email](#email) fields and endpoints. Clients must not send
  `email` anywhere until they see it.
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
{"players":[{"rank":1,"screen_name":"Patrick","matches_won":12,"matches_played":20}],
 "me":{"screen_name":"Patrick","matches_won":12,"matches_played":20,"boards_won":61,"last_hero_id":"vesper_vale","rank":1}}
```

`me` is present only when the request carries a valid device token. It is
included even if the caller isn't in the top list or isn't ranked (no name or
no matches). In that case `rank` is where they would stand. `boards_won`
appears only in `me`, never in the public rows.

### Utility

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
| Forfeit (leave) / timeout | opponent `matches_won+1` | leaver `matches_lost+1` | `matches_played+1` |

- `boards_won`: each player gets one point per small board they claimed
  (won, not drawn) in the match. This counts on forfeits too.
- There is **no board-count tiebreak**. A draw is a draw even if one player
  holds more boards.
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

Stale rooms are cleaned up opportunistically. The sweep runs at most once
every 5 s per server instance, on list, create, join, poll and moves. A
room's own turn timeout is also checked whenever someone polls it or plays a
move in it.

| Situation | Timeout | Result |
|---|---|---|
| `waiting` room, host not polling | **600 s** since creation or the host's last poll | `closed`, `end_reason:"expired"` |
| `active` match, no move | **180 s** since the last move or match start | **The player due to move forfeits** (`end_reason:"timeout"`), which is the same as leaving: the opponent wins, records update, the room closes and the opponent sees `opponent_left:true`. |
| `finished` room, neither player polling | 600 s | `closed`, records unchanged |

The 180 s rule applies to the player whose turn it is, even if they are still
polling. Use `turn_expires_at` to show a countdown. Presence (`*_seen_at`) is
written at most once every 10 s per player.

## Rate limits

Limits are per client IP and per server instance, in a fixed one-minute
window, so treat them as best-effort. Exceeding one returns `429`.

| Request | Limit per minute |
|---|---|
| `POST /auth/device` | 10 |
| `POST /rooms` | 20 |
| `POST /rooms/<CODE>/join` | 40 |
| moves, rematch, leave and cancel combined | 180 |
| `PATCH /me` | 30 |
| `POST /me/email/verification` + `POST /auth/email/recover` | 10 |
| `POST /me/email/verification/confirm` + `POST /auth/email/recover/confirm` | 30 |

Email codes also have per-player and per-address caps enforced in the
database; see [Code limits](#code-limits).

## CORS

These origins are allowed and reflected in `Access-Control-Allow-Origin`
(with `Vary: Origin`):

- `https://elexerly.github.io` (this covers `/Nineweave`)
- `https://nineweave.grok.me`
- `http://localhost:8060`, `http://localhost:8080`
- `http://127.0.0.1:8060`, `http://127.0.0.1:8080`

Allowed headers are `Authorization, Content-Type`. Allowed methods are
`GET, POST, PATCH, OPTIONS`. `Access-Control-Max-Age` is `600`. `OPTIONS`
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
| 403 | Token not in this room, not your turn, wrong room password, or not the host (cancel) |
| 404 | Unknown path or no such room |
| 405 | Wrong method |
| 404 | Email verification challenge not found for this player |
| 409 | Room full or state conflict (stale/future seq, stale round, closed, waiting); name taken; email already verified elsewhere |
| 413 | Body over 8 KB |
| 422 | Illegal move or game finished |
| 429 | Rate limited |
| 500 | Unexpected server error (details are logged, not returned) |
| 502 | Email provider didn't accept a code email |
| 503 | Not configured (database, or email for code requests), or room contention (retry) |

## Godot client notes (additive changes)

- The current client works as-is: create, join, poll, moves, rematch.
- Optional: send `Authorization: Bearer <device token>` on create and join to
  rank the player. Keep the device token separate from the seat token, which
  goes in the moves/rematch body and the poll header.
- Optional: call `POST /rooms/<CODE>/leave` from `leave()` before clearing
  credentials. Otherwise an abandoned match is forfeited after 180 s by the
  player due to move.
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
