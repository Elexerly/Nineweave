# Nineweave online backend: deploying

**Do not merge `online-server` into `main` without Patrick's OK.** Grok
hosting (nineweave.grok.me) appears to deploy from pushes to `main`. This
repo has no GitHub Actions and no GitHub Pages workflow, and nothing in the
repo sets up preview deploys for other branches. So merging is deploying, and
until then nothing here is live.

## Going live checklist (after Patrick approves the merge)

1. **Set the platform secret `DATABASE_URL`** to the Nineweave Neon
   connection string. This is the Neon project that already exists for
   Nineweave, not the Escape the Avalanche Deux database. It must be a
   `postgres://` or `postgresql://` URL. No other secret names are needed or
   read in production.
   - `NINEWEAVE_DATABASE_URL` is only a local/dev alias on the build box. If
     `DATABASE_URL` is missing, the app extracts the first postgres URL from
     it, so it can even be a pasted `.env` block. Don't configure it on the
     platform.
   - Never commit a `.env` file or a connection string.
2. **Migrations run automatically during the build.** `npm run build` runs
   `vite build && npm run db:migrate`, and `scripts/migrate.mjs` applies any
   pending `migrations/*.sql` through `@neondatabase/serverless` over HTTPS.
   Each file runs in one transaction and is recorded in `_migrations`, so
   reruns are safe. `migrations/auth/` is never applied.
   To migrate by hand first, run `npm run db:migrate` with `DATABASE_URL`
   (or the local `NINEWEAVE_DATABASE_URL`) set. This applies
   `0002_nineweave_online.sql` to that database.
3. Merge and push `main`, then check:
   - `GET https://nineweave.grok.me/api/nineweave/health` returns
     `{"ok":true}`.
   - `503 "Online play is not configured…"` means `DATABASE_URL` is missing
     or isn't a postgres URL. The homepage keeps working either way.

## Runtime notes

- Database access uses the Neon serverless HTTP driver. TCP 5432 is never
  used. Room writes are atomic HTTP transactions with optimistic version
  checks, so no long-lived connections or pools are needed.
- Rate limits are in memory per serverless instance, so they're best-effort.
- Without a database URL, the **dev** server uses in-memory PGLite (data
  resets on restart). Production builds never fall back to PGLite.

## ⚠️ Footgun on this box

`NINEWEAVE_DATABASE_URL` is set in this machine's environment. That means
`npm run build`, `npm run db:migrate` and `npm run dev`, run here as-is, all
target the **real Nineweave Neon database**: build migrates it and dev reads
and writes it. For local work that must not touch Neon, prefix the command:
`env -u NINEWEAVE_DATABASE_URL -u DATABASE_URL npm run build`.
`npm test` never touches a database URL, because tests use their own
in-process PGlite.
