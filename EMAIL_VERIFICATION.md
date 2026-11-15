# Nineweave email verification: handoff

Server-side email verification (and email account recovery) for the
Nineweave online API, branch `online-server`. Not deployed (Patrick
publishes). The migration has been applied to Patrick's Neon. The full
contract is in `ONLINE_API.md` → [Email](ONLINE_API.md#email).

## Endpoints

All paths are under `/api/nineweave`. `/me…` routes need
`Authorization: Bearer <device token>` (same as the existing `/me`).

| Method + path | Body | 200 response |
|---|---|---|
| `GET /me` | — | `player` object (new fields below) |
| `PATCH /me` | any existing field, plus `email` (string, `null` or `""`) | updated `player` |
| `POST /me/email/verification` | `{"email": "…"}` or `{}` (use stored address) | `{"challenge_id","expires_at","resend_available_at","email"}` |
| `POST /me/email/verification/confirm` | `{"challenge_id","code"}` | updated `player` (`email_status:"verified"`) |
| `POST /auth/email/recover` | `{"email"}` | always `{"challenge_id","expires_at","resend_available_at"}` |
| `POST /auth/email/recover/confirm` | `{"challenge_id","code"}` | `{"token","player_id","player"}` |

New fields on the `player` object (from register, `GET /me`, `PATCH /me`,
confirm):

```json
{"email":"pat@example.com","email_status":"unverified","email_verified_at":null,"capabilities":{"email":true}}
```

- `email`: lowercased string or `null`. Never on the leaderboard.
- `email_status`: `"none"` | `"unverified"` | `"verified"` (server-owned).
- `email_verified_at`: ISO-8601 string or `null`.
- `capabilities.email`: always `true` on this server.

### Status codes

**`PATCH /me` (email):** `400` invalid address or unknown field, `401`.
PATCH only stores; it never sends a code.

**`POST /me/email/verification`:**

| Code | Meaning |
|---|---|
| 200 | Code sent |
| 400 | Invalid address / none given or stored / unknown field |
| 401 | Missing or unknown device token |
| 409 | `"That email is already used by another account."`, or already verified on your own account |
| 429 | 60 s cooldown, hourly cap (body has `retry_after_seconds`), or per-IP limit |
| 502 | `"Could not send email. Try again shortly."` (provider rejected; challenge discarded) |
| 503 | `"Email verification is not available on this server yet"` (no API key) |

**`POST /me/email/verification/confirm`:**

| Code | Meaning |
|---|---|
| 200 | Verified; updated profile |
| 400 | Malformed body (code not 6 digits, missing `challenge_id`, unknown field) |
| 400 | `"Invalid or expired code"`: wrong, expired, used, superseded, address changed, or 5 attempts used |
| 401 | Missing or unknown device token |
| 404 | Challenge id unknown or belongs to another player |
| 409 | Another account verified this address first |
| 429 | Per-IP limit |

**Recovery:** request is always `200` (except `400` invalid address, `429`
IP limit, `503` not configured). Confirm is `200` or a uniform
`400 "Invalid or expired code"` (also for unknown ids), `429`.

### Limits

- Code: 6 random digits (`crypto.randomInt`), stored only as
  `sha256("nwcode:v1:<challenge_id>:<code>")`, compared with
  `timingSafeEqual`.
- 10-minute expiry; 5 guesses per challenge (atomic counter, so concurrent
  guesses can't exceed it).
- 60 s resend cooldown per player; 5 codes per player per hour; 5 codes per
  address per hour across all players. All enforced in the database (and
  re-checked inside the insert transaction with the player row locked), so
  they hold across serverless instances. Failed sends count.
- Per-IP in-memory limits: 10/min for code requests, 30/min for confirms.
- A new request supersedes that player's unused codes. Changing or clearing
  the address (PATCH or a request with a new address) kills open codes and
  resets verification.

## Uniqueness rule

A verified email belongs to exactly one player: unique partial index
`nw_players_verified_email` on `lower(email) where email_verified_at is not null`.
Unverified copies may exist on several players at once. The first confirm
wins (the confirm is a single statement guarded by that index); afterwards
all other open verification codes for that address are invalidated, and
requests/confirms for it from any other player get `409`. Unverified
addresses never grant recovery.

## Migration

`migrations/0004_nineweave_email.sql` was applied to Patrick's Neon on
2026-11-15 after the tests passed. The next publish's `db:migrate` step will
see it already recorded in `_migrations` and leave it alone.

- `nw_players.email text`, `nw_players.email_verified_at timestamptz` (nullable).
- `nw_players_verified_email` (unique, partial) and `nw_players_email_lower`
  (lookup) indexes.
- `nw_email_challenges` (`id, player_id → nw_players on delete cascade, email,
  purpose 'verify'|'recover', code_hash, expires_at, attempt_count,
  max_attempts, consumed_at, invalidated_at, created_at`) with indexes on
  `(player_id, created_at)`, `(email, created_at)` and `created_at`. Rows
  older than 24 h are deleted opportunistically on each new request.

The existing test truncate already cascades to the new table through its
foreign key; `email.test.ts` lists it explicitly.

## Test results

Run in this sandbox against in-memory PGlite only, with a fake mailer (no
network, no real email):

- `npm run test:online`: **68/68 pass** (rules 11, online 23, new email
  suite 34).
- `npm run typecheck`: **pass**.
- Full `npm test`: online suite passes; `node --test 'scripts/**/*.test.mjs'`
  has **15 failures that also fail identically on unmodified `HEAD`**
  (template/brand tooling tests; unrelated to this change), which stops the
  `&&` chain. The remaining app-data/auth suites, run directly: **59/59 pass**.

New tests (`src/lib/nineweave/email.test.ts`, hooked into `test:online`)
cover: capabilities on register/GET/PATCH; PATCH lowercasing, reset on
change, keep on same address, clear with `null`/`""`; invalid addresses;
leaderboard has no email; happy path with GET showing verified; DB holds
only a hash; wrong code, 6th attempt locked, right code on 5th; expiry;
supersede; PATCH kills open codes; challenge scoping (404); 401s; cooldown,
per-player and per-email hourly caps, IP limit; 409 on verified elsewhere,
first-confirm-wins, unique-index race; 503 without mailer/key; 502 on
provider failure; Resend request shape and sender; no key/code/recipient in
logs; email HTML has no links/images and escapes the recipient; full
recovery flow (token replaced, old one 401), no-oracle responses, purpose
separation, silent throttling, lockout, and recovery dying after an address
change.

## What the Godot client must do (for Codex)

1. Keep storing the email locally and send nothing until `GET /me` returns
   `capabilities.email == true`.
2. Then `PATCH /me {"email": "<address>"}` to store it (or `null` to remove).
3. `POST /me/email/verification` (body `{}` or `{"email": …}`) to send a
   code. Save `challenge_id`; show the code-entry stage; use
   `resend_available_at` for the "Resend" button and `expires_at` for the
   timer.
4. `POST /me/email/verification/confirm {"challenge_id","code"}`. On `200`,
   take the returned profile.
5. Treat `email_status` / `email_verified_at` from the server as the only
   truth and pass them to `set_verification_status`. Never mark verified
   locally.
6. Errors: show the server's `error` text on `400`/`409`; on `429` use
   `retry_after_seconds`; on `502`/`503` show "Email isn't available right
   now"; on `404` ask for a new code.
7. New-device sign-in (optional UI): `POST /auth/email/recover`, then
   `POST /auth/email/recover/confirm`; replace the stored device token with
   the returned `token`. The old device is signed out.

## Changes from ROUND4E.md

- Matches the proposed endpoint names and fields. Additions:
  `email_status` *and* `email_verified_at` are both returned; the request
  response also echoes the normalized `email`; `429` bodies carry
  `retry_after_seconds`.
- Requesting a code for an address already verified on your own account
  returns `409`.
- `PATCH /me` accepts an address that is verified elsewhere (stored
  unverified); the `409` comes when a code is requested/confirmed.
- Recovery endpoints (ROUND4E left them out of scope) are implemented.

## Recover

**Implemented**, with tests, mailer mocked. Only verified addresses get a
code; the request endpoint gives the same response for unknown, unverified
and throttled addresses; the confirm endpoint replaces the device token
(single device per player; multi-device may come later). Known limitation:
response timing can differ slightly between verified and unknown addresses.

## Builder note

Add the secret `NINEWEAVE_RESEND_API_KEY` (Resend key for
`nineweave.sitebloc.com`) in the project's secrets, then pull this branch
and publish. Do not merge; Patrick publishes. Without the key, code requests
answer `503` and everything else keeps working.
