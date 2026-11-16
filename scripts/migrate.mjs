#!/usr/bin/env node
/**
 * Deploy-time database migrator (Neon serverless driver over HTTPS).
 *
 * Runs during `npm run build` — on every Vercel deploy — applying pending files
 * in ../migrations to the configured database. Each file is applied in one
 * transaction and recorded in a `_migrations` table, so it runs once and is
 * safe to re-run.
 *
 * Uses `@neondatabase/serverless` HTTP (port 443), not `pg` TCP: direct 5432
 * is not reachable from every build box. The HTTP endpoint runs one statement
 * per query, so a file is split into statements (scripts/sql-split.mjs) and
 * sent, together with its `_migrations` insert, as one HTTP transaction.
 *
 * The read is non-recursive, so the opt-in auth schema under migrations/auth/
 * is not applied to an app that never asked for sign-in.
 *
 * Connection string: see scripts/database-url.mjs (NINEWEAVE_DATABASE_URL
 * when set, else DATABASE_URL). Never printed. None configured ->
 * skip; the PGLite fallback applies the same files at startup instead.
 */
import { readdir, readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { neon } from "@neondatabase/serverless";
import { pendingMigrations } from "./migration-plan.mjs";
import { databaseUrlLooksMisconfigured, extractPostgresUrl, resolveDatabaseUrl } from "./database-url.mjs";
import { splitSqlStatements } from "./sql-split.mjs";

const databaseUrl = resolveDatabaseUrl();
if (!databaseUrl) {
  if (databaseUrlLooksMisconfigured()) {
    console.error(
      "[migrate] a database env var is set but no postgres:// URL could be extracted — refusing to guess.",
    );
    process.exit(1);
  }
  console.log("[migrate] no database configured — skipping (the PGLite fallback migrates itself).");
  process.exit(0);
}

const migrationsDir = join(dirname(fileURLToPath(import.meta.url)), "..", "migrations");

async function apply(url, onlyBootstrap = false) {
  let entries;
  try {
    entries = await readdir(migrationsDir);
  } catch {
    console.log("[migrate] no migrations/ directory — nothing to do.");
    return;
  }
  // An app with no schema of its own must not pay for a database connection.
  if (pendingMigrations(entries, []).length === 0) {
    console.log("[migrate] no migrations — nothing to do.");
    return;
  }

  if (onlyBootstrap) entries = entries.filter((name) => name === "0007_nineweave_admin_config.sql");
  const sql = neon(url);
  await sql.query(
    "CREATE TABLE IF NOT EXISTS _migrations (name TEXT PRIMARY KEY, applied_at TIMESTAMPTZ NOT NULL DEFAULT now())",
  );
  const applied = (await sql.query("SELECT name FROM _migrations")).map((r) => r.name);

  let count = 0;
  for (const { name } of pendingMigrations(entries, applied)) {
    const text = await readFile(join(migrationsDir, name), "utf8");
    const statements = splitSqlStatements(text);
    try {
      // One non-interactive HTTP transaction: every statement plus the
      // bookkeeping row commit together or not at all.
      await sql.transaction([
        ...statements.map((stmt) => sql.query(stmt)),
        sql.query("INSERT INTO _migrations (name) VALUES ($1)", [name]),
      ]);
    } catch (err) {
      console.error(`[migrate] error applying ${name} (rolled back)`);
      throw err;
    }
    console.log(`[migrate] applied ${name} (${statements.length} statement(s))`);
    count += 1;
  }
  console.log(count ? `[migrate] done — ${count} migration(s) applied.` : "[migrate] up to date.");
}

async function main() {
  const builtinUrl = extractPostgresUrl(process.env.DATABASE_URL);
  // Even when Nineweave uses a separate env override, the bootstrap settings
  // table must exist in the host DB. Do not provision player/auth tables here.
  if (builtinUrl && builtinUrl !== databaseUrl) await apply(builtinUrl, true);
  await apply(databaseUrl);
}

main().catch(() => {
  // Driver error messages/details can contain credentials or connection URLs.
  console.error("[migrate] failed — check database connectivity and migration SQL");
  process.exit(1);
});
