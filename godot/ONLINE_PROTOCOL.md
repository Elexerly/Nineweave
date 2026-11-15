# Nineweave online protocol — v1

Round 4c connects **HttpPollingTransport** to the live API at
`https://nineweave.grok.me/api/nineweave`. On the live web origin it uses the
relative `/api/nineweave` path; native, localhost and other web origins use the
live origin. `net/json_api.gd` owns the single configurable `LIVE_ORIGIN`.
The menu's “Try Local Online Demo” still uses **LoopbackTransport**, with an
explicitly simulated rival. The earlier rounds below document protocol history.
The full current endpoint contract is `nineweave-server/ONLINE_API.md`.

## Round 4c — device accounts, consent and live discovery

`net/device_store.gd` persists only device identity and legal acceptance in
`user://nineweave-device.cfg`, separately from the character profile's
`onboarded` flag. The persistent `nwd_` credential authenticates registration
follow-up, `/me`, `/leaderboard`, create and join; registration itself has no
Authorization header. The ephemeral `nws_` credential authenticates room polling
and goes in move/rematch/leave bodies. Neither secret is displayed, logged, or
put in a URL. Leave POSTs `/rooms/<CODE>/leave` from a short-lived independent
request, then clears seat state without erasing device identity.

Registration and consent use `POST /auth/device`, followed by `PATCH /me` with
`screen_name`, `tos_version`, `privacy_version`, `accepted_at` (UTC ISO 8601),
and `age_confirmed:true`. Legal versions are `2026-11-15`. Consent becomes local
only after PATCH succeeds; a token from successful registration survives PATCH
failure for retry. First launch and unregistered live entry show readable linked
agreement copy without checkboxes, with an offline route to the title.

`GET /me` restores a known canonical `last_hero_id`; confirmed hero choices PATCH
that field. Name edits PATCH `/me`, preserving the accepted name on rejection.
Public rooms refresh with `GET /rooms` every 2.5 seconds while the lobby is
visible. Private creation sends `private:true` plus `password`; joining sends
`password` when provided. The leaderboard uses `/leaderboard`, displaying full
`matches_won` and the caller's record even outside the top list. No public
small-board scores are presented.

Room polling remains single-flight, once per second. Conflicts can resynchronize
from their room snapshot; full-match `result` also handles forfeits/timeouts.
Sticky `opponent_left` emits once. Canonical character maps precede rematch
presentation, and `match.seat` controls each new round's X/O swap.

## Shared interface

`net/net_transport.gd`, a Node with signals:

- `connected`, `room_created(code)`, `joined(code, seat)` (1 = X, 2 = O).
- `opponent_joined`, `opponent_left`, `error(message)`.
- `move_received(board, cell, seq)` — authoritative acknowledgement, including the sender's own moves.
- `state_received(state, seq)` — authoritative full snapshot/resynchronization.

Methods: `create_room()`, `join_room(code)`, `send_move(board, cell, seq)`, `leave()`.

Create/join set `code`, `seat`, `player_name`, `remote_name`. A room code is five uppercase letters/digits. Seat X always moves first. Token is opaque, secret, never rendered/logged or put in query strings. The HTTP client sends `Authorization: Bearer <token>` after joining. The moves body also contains `token` for the requested contract; accept one consistently on the server. Poll approximately once per second; only one HTTPRequest is active at a time. Timeout is eight seconds. Leaving cancels polling and clears credentials. The live service expires rooms/seats by timeout; leaving POSTs the authenticated leave endpoint before clearing the seat.

## Endpoints (same origin)

`POST /api/nineweave/rooms`

```json
{"name":"Patrick"}
```

201:

```json
{"code":"N9ABC","seat":1,"token":"opaque-seat-secret","seq":0,"state":{"v":1,"cells":"81 characters, each . X or O","turn":1,"active":-1,"history":[],"redo":[]}}
```

`POST /api/nineweave/rooms/N9ABC/join`

```json
{"name":"Friend"}
```

200: same shape, seat 2, own token, `opponent: "Patrick"`, current `state` and `seq`. Return 404 for expired code, 409 for full room. Enforce exactly two seats.

`POST /api/nineweave/rooms/N9ABC/moves`

```json
{"board":4,"cell":0,"seq":13,"token":"opaque-seat-secret"}
```

200:

```json
{"seq":13,"moves":[{"board":4,"cell":0,"seq":13}],"state":{"v":1,"cells":"...","turn":2,"active":0,"history":[],"redo":[]}}
```

The abbreviated `cells` in the examples is explanatory; actual snapshots always have 81 characters and actual history. The client applies acknowledgements in sequence and can replace its state with the snapshot. Respond 409 to stale/future sequence, 403 to wrong seat/token, 422 to illegal move. Return a current snapshot on conflicts where possible. Retrying the same `(seat, seq, board, cell)` must be idempotent and return the original acknowledgement, rather than making a second move.

`GET /api/nineweave/rooms/N9ABC?since=12`

Authorization header required. 200:

```json
{"seq":13,"opponent":"Friend","opponent_left":false,"moves":[{"board":4,"cell":0,"seq":13}],"state":{"v":1,"cells":"...","turn":2,"active":0,"history":[],"redo":[]}}
```

Return moves newer than `since`, sorted by seq, never including hidden credentials. A snapshot is optional when no state changed. The controller avoids resetting animations for an identical snapshot. Gaps need a current authoritative snapshot; duplicate acknowledgements are ignored. Error bodies: `{"error":"Human-readable explanation"}`. Missing endpoints, non-JSON HTML and transport failures produce the graceful unavailable message.

## Authority and storage requirements

The backend owns one rules kernel state per room. Under a room lock/transaction, verify token→seat, `seq == current_seq+1`, correct turn, and `is_legal(board,cell)`, then call `play()`, append the event, persist the snapshot and commit. Never accept a client-supplied board state, owner, winning line, result, turn, name as identity, or user ID as authorization. Derive winners and active board with exactly the same rules as `kernel/rules.gd`. There is no board-count tiebreak. Store tokens hashed, expire abandoned rooms, rate-limit create/join/moves, cap names to 24 characters and request sizes, use HTTPS, same-origin cookies/headers as appropriate, and set response caching to `no-store`.

`LoopbackTransport` implements these move/seat/sequence checks with a shared in-process room service and broadcasts to both weak-referenced clients. It is for tests and local demonstration, not cross-browser networking. Online hints and undo are disabled in the UI. Reconnect/reclaim-seat, moderation, presence persistence and a deployed backend remain Round 2 work.

## Round 3 — character identity (v2 cosmetic extension)

Only character IDs are shared cosmetics. Background and board/piece theme selections
are **local-only**: neither request bodies, snapshots nor room metadata carry them.
The local profile's identity envelope is not an authorization credential.

Create/join bodies now use `{"name":"Patrick","character_id":"vesper_vale"}`.
`character_id` must be a known starter ID in `characters/roster.gd`; a backend must
validate it and freeze the choice for the room. Responses and polls may include
`"characters":{"1":"vesper_vale","2":"auric_rex"}` (seat keys as strings).
Deliver that map before the first `opponent_joined` presentation. `NetTransport`
adds `character_received(seat, character_id)`, `character_id` and
`remote_character_id`; it validates received IDs transactionally. Unknown maps
produce an error rather than accepting arbitrary assets. Missing maps keep the
legacy default for compatibility with a v1 endpoint.

Round 4b pass 2 canonicalizes the five legacy IDs through `Roster.ALIASES`:
`erik_comet` → `erick_comet`, `ak_shade` → `simon_shade`,
`derrick_torque` → `devin_torque`, `nova_sable` → `aiden_vortex`, and
`mateo_ricochet` → `ethan_ricochet`. Incoming legacy seat maps remain valid;
outgoing lobby payloads and received character signals use canonical IDs.
Backends should apply the same aliases before validating/freezing selections.
`shard_jack` remains protocol-stable; its display name is Jack Sovereign.

`LoopbackTransport` stores only the two starter IDs beside its authoritative rules
state and exchanges them on joining. `HttpPollingTransport` sends the same lobby
payload and consumes the same seat map. Moves/acknowledgements and rules snapshots
are unchanged. No new endpoint or network request is introduced. Local selection
changes take effect in the next room. Theme changes never change a move, a rules
snapshot, or either player's selected character.

## Round 4 — side assignment and rematch agreement (v3 flow extension)

Player identity stays attached to the transport, not the X/O seat. The room authority
randomly assigns X/O for the first match (both choices tested with seeded RNG).
Every accepted rematch swaps the seats. X always moves first. Character IDs and
screen names stay with their players; the seat-keyed character map swaps with them.
Loopback's host/guest references remain stable even when the host is O.

New transport interface:

- `request_rematch()` requests agreement for the current, finished round.
- `rematch_changed(local_agreed, remote_agreed)` updates the result UI.
- `match_started(assigned_seat, round_number)` is the only restart authority.
- `local_rematch`, `remote_rematch`, `match_round`, `rematch_status()` expose state.

One agreement displays `WAITING FOR OPPONENT…` on that client and
`OPPONENT WANTS A REMATCH` plus ACCEPT on the other. Duplicate requests are
idempotent. Requests during a live game are ignored. Both agreements atomically
clear the rules state, sequence and agreements, increment the round, swap seats,
exchange the new character map, and emit `match_started` to both clients. The
controller then runs the 2.8-second versus screen. Leaving a room cancels it.
The explicitly labelled local demo peer agrees after a one-second simulated delay;
real HTTP peers never auto-agree.

HTTP backend extension (live in Round 4c):

`POST /api/nineweave/rooms/<CODE>/rematch`

```json
{"round":1,"token":"opaque-seat-secret"}
```

Authenticated responses and normal polls can carry:

```json
{"match":{"round":1,"seat":2,"local":false,"remote":true}}
```

When both agree, return the new round, swapped seat, reset sequence/state, and
updated character map in the same response/poll envelope. The client rejects old
round metadata, resets its sequence on a round increment, and starts presentation
only from the authoritative `match` event. A click alone cannot restart HTTP.
The backend must bind tokens to stable players, derive their current seats, require
both agreements under its room transaction, and reject stale round requests.
The base transport reports unsupported rematch clearly for a legacy backend.
