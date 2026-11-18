# Permanent account unlocks (staged, not deployed)

Base server: `28f7403` (tutorial and idle fairness). No dependency on the separate minimum-version gate. Migration `0011_nineweave_account_unlocks.sql` deliberately leaves `0010` available for that independent change.

## Contract

Authenticated `POST /api/nineweave/me/unlocks`, same Bearer device token as `/me`, body strictly `{ "code": "Blizzard" }`.

Success 200:

```json
{"ok":true,"unlock":{"kind":"background","id":"blizzard"},"already_owned":false,"unlocked_backgrounds":["blizzard"],"unlocked_heroes":[]}
```

Replays return 200 and `already_owned:true`; no duplicate rows or consumption. A code is reusable by different accounts. Codes trim surrounding whitespace and normalize ASCII letters to uppercase. Codes do not select or change gameplay. `/me`, registration, and email recovery profiles return both ownership arrays. `account_unlocks:true` is advertised in capabilities.

| Code | Background ID |
| --- | --- |
| Blizzard | blizzard |
| TicTacToe | tictactoe |
| 010127 | new_year |
| 0704027 | fourth_july |
| Patrick | st_patrick |

Reserved character codes: W2026, G2026, J2026, B2026, N2026, E2026, JB2026, T2026, JY2026, GM2026, D2026. These return 409 `{error:<readable explanation>,code:"code_unavailable"}` and **never grant a placeholder character**. Before enabling them, configure actual roster IDs and enforce entitlement checks on hero selection/online seat creation, as well as client selection. The current change grants backgrounds only.

Unknown/malformed codes return 400 `invalid_code`; unauthenticated requests return 401. Per-account SQL quota is ten attempts per minute, shared across server instances and token rotations. All parsed code attempts including duplicate, invalid and reserved codes count. Malformed JSON is rejected before the account quota; the existing per-IP write limiter still applies. Exceeding quota returns 429 `rate_limited`; wait one minute, not an automatic retry loop. Existing best-effort per-IP write limiter also applies. Only one quota row/account is retained. No raw code, token or email is stored in these tables.

Ownership keys are the durable player ID, not screen name or email. Account email recovery rotates tokens on that same player, preserving ownership. The existing authentication system supports one active token per account; this change does not change simultaneous-device login policy. Account deletion cascades both ownership and quota; a newly created account does not inherit deleted ownership.

## Legacy / security

Migration preserves the old `nw_players.unlocks` JSON unchanged but NEVER imports it. The legacy PATCH /me API accepts client-asserted unlocks, so even recognized IDs in that field are untrusted and cannot establish ownership. No local-only prototype grants shipped; do not upload/trust a local ownership list. A user can redeem a recognized code again after signing in. Client attempts to assign the new entitlement arrays with PATCH or a caller-provided player_id are rejected. Legacy PATCH /me {unlocks:[...]} remains compatible but cannot grant or revoke actual entitlements.

## Deployment boundaries

No database, live server, web export, CORS setting, privacy policy, or client was changed by this work. This branch retains its base CORS file; the hosted project's Sitebloc CORS additions must be preserved when transferring the small patch. Apply migration before exposing profile/API code that queries the new tables. The existing build script applies pending migrations; do not run it against production by accident. Test migration on an isolated database branch before production rollout. Existing players need no manual edits. Rollback server code leaves additive tables harmless; do not drop them and erase ownership.

Verification is PGlite/in-memory, not a claim of live Neon deployment. Tests cover authenticated boundaries, case normalization, every background, reserved codes, unknown/forged data, concurrent redemption, cross-instance rate limiting, token rotation, deletion cascade and legacy spoofing and migration reruns.

## Verification result

- Online API suite: 177/177 passed (includes 10 unlock tests).
- TypeScript typecheck passed.
- Remaining TypeScript helper suites: 59/59 passed.
- All migration files applied successfully through the actual deployment SQL splitter in isolated PGlite transactions.
- Aggregate `npm test` stops in script fixtures: 192/207 pass, 15 fail. The same 15 failures reproduce on unchanged base `28f7403` (missing `.grok` branding/app-env fixture sources); these are not unlock regressions. No production build or database migration was run.
