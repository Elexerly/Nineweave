# Nineweave online protocol — v1

Round 1 ships a complete in-process **LoopbackTransport** and an **HttpPollingTransport** client for a future backend. No backend is included or advertised as live. The menu's “Try Local Online Demo” creates a local room; “Invite demo rival” pairs a second local transport, driven by the AI. This is labelled LOCAL DEMO. Real create/join fails with “Online server not available yet” when the API is absent. The native client intentionally has no default remote host; the Web client uses `window.location.origin`.

## Shared interface

`net/net_transport.gd`, a Node with signals:

- `connected`, `room_created(code)`, `joined(code, seat)` (1 = X, 2 = O).
- `opponent_joined`, `opponent_left`, `error(message)`.
- `move_received(board, cell, seq)` — authoritative acknowledgement, including the sender's own moves.
- `state_received(state, seq)` — authoritative full snapshot/resynchronization.

Methods: `create_room()`, `join_room(code)`, `send_move(board, cell, seq)`, `leave()`.

Create/join set `code`, `seat`, `player_name`, `remote_name`. A room code is five uppercase letters/digits. Seat X always moves first. Token is opaque, secret, never rendered/logged or put in query strings. The HTTP client sends `Authorization: Bearer <token>` after joining. The moves body also contains `token` for the requested contract; accept one consistently on the server. Poll approximately once per second; only one HTTPRequest is active at a time. Timeout is eight seconds. Leaving cancels polling and clears credentials. A future server should expire rooms/seats by heartbeat/TTL; no unrequested leave endpoint is assumed.

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
