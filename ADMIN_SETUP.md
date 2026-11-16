# Temporary Nineweave admin setup

The temporary setup page is `/admin/setup`. Its API is
`/api/nineweave/admin/setup`. Both return **404** until a valid passphrase hash
is configured, and whenever `ADMIN_SETUP_ENABLED` is false.

## Enable and use

1. Apply the regular top-level migrations (the normal build does this when a
   database is configured). `0007_nineweave_admin_config.sql` creates only
   `nw_admin_config`. It must exist in the host's built-in `DATABASE_URL`
   database. The deploy migrator provisions this table there even if an env
   override directs Nineweave's other migrations to a separate Neon database.
2. Supply a strong, unique passphrase through the environment variable
   `NINEWEAVE_ADMIN_PASSPHRASE` to `node scripts/hash-admin-passphrase.mjs`.
   The script prints only `scrypt$<saltHex>$<hashHex>` using scrypt
   N=16384, r=8, p=1, keylen=32 and a random 16-byte salt. It never prints
   the passphrase. Do not put the passphrase in source, shell history, a `.env`
   file, or logs. Remove it from the process environment after hashing.
3. Replace `ADMIN_PASSPHRASE_HASH = "UNSET"` in
   `src/lib/nineweave/admin-setup.ts` with that hash, leaving
   `ADMIN_SETUP_ENABLED = true`, then deploy. The hash and authentication logic
   stay server-side; they are not embedded in the setup HTML.
4. Open `/admin/setup` over HTTPS and enter the passphrase. Use **Check status**
   to inspect the current configuration. Enter a Neon Postgres connection URL,
   a Resend API key, or both, then select **Save connections**. Blank fields
   preserve their settings. Each action requires the passphrase; the page
   clears it after the action and never stores credentials in browser storage.
5. A Neon submission connects with `@neondatabase/serverless`, applies pending
   `migrations/*.sql` in filename order with one transaction per file, records
   each filename in `_migrations`, and verifies `nw_players` exists. Auth
   migrations under `migrations/auth/` are excluded. Only after this succeeds
   are the submitted settings saved atomically in the built-in database.
   Migration or connection failures save neither setting. Successfully applied
   earlier files can remain on the target after a later file fails; resubmit
   to continue. **No existing players or other game data are copied to Neon.**
6. Check status again. Optional **Send test email** sends only to
   `patrick@probeyahngroup.com`, using the active saved/env key and the existing
   Nineweave sender address. Save a key before sending; sender verification at
   Resend is still required.

Status shows built-in versus Neon, only the active Neon's hostname, whether a
Resend key is set and its final four characters, and applied migration names
and timestamps. It never returns credentials or the full URL/key. Environment
overrides are labeled so a saved configuration cannot silently appear active.
Responses use `Cache-Control: no-store`; credentials are never placed in URLs.

## Resolution and persistence

- Nineweave database: `NINEWEAVE_DATABASE_URL` environment override, then the
  built-in `nw_admin_config` key `nineweave_database_url`, then `DATABASE_URL`.
- Email: `NINEWEAVE_RESEND_API_KEY` environment override, then config key
  `resend_api_key`, then no mailer (email actions return 503).
- Config and admin rate-limit accounting always use the built-in database,
  even after the game switches to Neon. Auth's bootstrap database remains
  separate from the Nineweave game target. Development without a host database
  retains the existing ephemeral PGLite fallback.
- Config reads are cached for approximately 60 seconds per server instance.
  Saving invalidates the writer's cache immediately. Other running instances
  converge within 60 seconds. The active service refreshes with changed DB/key.
- Config values are stored as text in the built-in database, as requested.
  Protect access to that database and its backups; these are server credentials.
- Re-submit the connection string to apply any newly added migrations to the
  saved Neon target. Regular deploy-time migrations cannot discover a saved
  target without querying the runtime config store.

Authentication uses a constant-time hash comparison. A shared, atomic DB row
reserves attempts before hashing so concurrent/serverless requests cannot
bypass limits: five failed attempts per IP in a rolling 15 minutes and twenty
failed attempts globally in a rolling hour. Successful authentications release
the reservation. Over-budget requests return 429 (with Retry-After); wrong
passphrases return 401. Only hashed IPs and attempt IDs/times are stored.
Forwarded IP headers must be supplied/normalized by the trusted hosting proxy.
Cross-origin requests are rejected; the admin API does not expose CORS access.

## Clear test accounts

**Clear test accounts** asks for confirmation and deletes only players whose
`screen_name` starts with the case-sensitive prefixes `T4c` or `NWSmoke`, on
the **active** game database. It also removes dependent email challenges,
blocks, reports, chat, matches, associated rooms, and associated tournaments
and their membership/bracket rows. Whole associated rooms/tournaments are
removed to avoid broken live brackets; participating real players themselves
remain. The action is atomic and returns per-table deletion counts. It never
clears the built-in database when Neon is active and never copies data.

## Disable after setup

Set the single exported constant **`ADMIN_SETUP_ENABLED = false`** in
`src/lib/nineweave/admin-setup.ts`, then redeploy. Both page and API return 404.
The saved database and mailer configuration continue to work: their resolution
is independent of the admin flag. Re-enable the same flag and redeploy to
restore the temporary page. Leaving the hash `UNSET` also makes both routes
return 404. No player-login or OAuth changes are needed.

## Validation

`npm run test:online` includes `admin-setup.test.ts`, covering route gating,
constant-time verifier behavior, shared rolling rate limits and concurrent
attempts, resolution/cache precedence, target migrations and rollback, no data
copying, masked status, sanitized failures, fixed-recipient fake mail, input
validation, cross-origin rejection, and active-database test-account cleanup.
Tests use isolated PGLite database doubles and an injected recording mailer;
they do not connect to live Neon or send real email.

Compile without database credentials:
`env -u NINEWEAVE_DATABASE_URL -u DATABASE_URL npm run build`.

## Implementation file inventory

- `src/lib/nineweave/admin-setup.ts`: single switch and UNSET hash placeholder.
- `src/lib/nineweave/admin-api.ts`: authentication, shared rate limit, status,
  saving, test email, and test-account cleanup.
- `src/lib/nineweave/admin-migrations.ts`: transactional target migrator.
- `src/lib/nineweave/admin-page.ts`, `admin-setup.html`: gated setup page.
- `src/lib/nineweave/admin-runtime.server.ts`: production dependency wiring.
- `src/lib/nineweave/config.ts`: bootstrap store, cache, and resolution order.
- `src/lib/nineweave/admin-setup.test.ts`: thirteen isolated admin tests.
- `src/lib/nineweave/server.ts`, `src/lib/db.ts`: runtime game DB/mailer refresh
  and separate built-in database access.
- `src/routes/admin/setup.ts`, `src/routes/api/nineweave/admin/setup.ts`,
  `src/routeTree.gen.ts`: page/API route registration.
- `migrations/0007_nineweave_admin_config.sql`: bootstrap config table only.
- `scripts/hash-admin-passphrase.mjs`: passphrase hash helper.
- `scripts/migrate.mjs`: provision bootstrap table separately when needed;
  sanitize migration failures.
- `package.json`: include admin tests in the full Nineweave suite.
- `ADMIN_SETUP.md`: this guide and change inventory.

Validation completed: all seven Nineweave test files pass; the admin file's
thirteen individual tests pass; typecheck and the build with both DB URL env
vars removed pass; `git diff --check` passes. The broader `npm test` reaches
unrelated template script failures (including absent `.grok` skill references
and restricted subprocess behavior); its five template TypeScript test files,
run separately, pass. Browser QA could not run: preview listening and Chromium
launch both fail with sandbox permission errors. No live credentials were used
or real emails sent. `startup.sh` matches git HEAD exactly; no commit was made.
