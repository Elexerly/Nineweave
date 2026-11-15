# Nineweave online backend: deploying

Grok hosting (nineweave.grok.me) deploys from pushes to `main`.

## Going live checklist

1. **Set the project secret `NINEWEAVE_DATABASE_URL`** to Patrick's Neon
   connection string (the `moviewatchers2kx` Neon account, not the Grok
   platform database). A plain `postgres://` or `postgresql://` URL is
   enough; the pooled connection string from the Neon dashboard is fine.
   The resolver also accepts a pasted `.env` block and uses the first
   postgres URL in it. Never commit a `.env` file or a connection string.
   - Nineweave tables, `getSql()`, and `npm run db:migrate` prefer
     `NINEWEAVE_DATABASE_URL` when it is set, and fall back to the
     platform `DATABASE_URL` only if it is not.
   - Auth (disabled on this site) still reads `DATABASE_URL` directly.
     `migrations/auth/` is never auto-applied.
2. **Migrations run automatically during the build.** `npm run build` runs
   `vite build && npm run db:migrate`, and `scripts/migrate.mjs` applies any
   pending `migrations/*.sql` through `@neondatabase/serverless` over HTTPS.
   Each file runs in one transaction and is recorded in `_migrations`, so
   reruns are safe. To migrate by hand first, run `npm run db:migrate` with
   `NINEWEAVE_DATABASE_URL` (or `DATABASE_URL`) set. This applies
   `0002_nineweave_online.sql` and `0003_nineweave_consent.sql`.
3. Pull and publish `main`, then check:
   - `https://nineweave.grok.me/` loads the Nineweave game.
   - `https://nineweave.grok.me/terms` and `/privacy` load.
   - `GET https://nineweave.grok.me/api/nineweave/health` returns
     `{"ok":true}`.
   - `503 "Online play is not configured…"` means neither
     `NINEWEAVE_DATABASE_URL` nor `DATABASE_URL` yielded a postgres URL.
     The homepage keeps working either way.

## Runtime notes

- Database access uses the Neon serverless HTTP driver. TCP 5432 is never
  used. Room writes are atomic HTTP transactions with optimistic version
  checks, so no long-lived connections or pools are needed.
- Rate limits are in memory per serverless instance, so they're best-effort.
- Without a database URL, the **dev** server uses in-memory PGLite (data
  resets on restart). Production builds never fall back to PGLite.

## ⚠️ Footgun on this box

`NINEWEAVE_DATABASE_URL` is set in this machine's environment, and the app
prefers it over `DATABASE_URL`. That means `npm run build`, `npm run db:migrate`
and `npm run dev`, run here as-is, all target **Patrick's Neon**: build
migrates it and dev reads and writes it. For local work that must not touch
Neon, prefix the command:
`env -u NINEWEAVE_DATABASE_URL -u DATABASE_URL npm run build`.
`npm test` never touches a database URL, because tests use their own
in-process PGlite.

## Game at the site root

`/` serves the Godot web export (`public/index.html` plus `index.js`,
`index.wasm`, `index.pck`, worklets and icons). `/api/nineweave`, `/terms`
and `/privacy` are unchanged app routes.

The wasm (~38 MB) and pck (~16 MB) are under GitHub's 100 MB file limit and
the 50 MB warning, and are served as Vercel CDN static files (not bundled
into the serverless function). `vercel.json` sets `application/wasm` and
`application/octet-stream` for those two files. Filenames are unhashed, so
they are not cached as immutable.
