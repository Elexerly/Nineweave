import { pendingMigrations } from "../../../scripts/migration-plan.mjs";
import { splitSqlStatements } from "../../../scripts/sql-split.mjs";
import type { Db } from "./store.ts";

/** Same ordering, SQL splitter and atomic per-file bookkeeping as migrate.mjs. */
export async function migrateAdminTarget(db: Db, files: Record<string, string>) {
  await db.query("create table if not exists _migrations (name text primary key, applied_at timestamptz not null default now())");
  const applied = await db.query<{ name: string }>("select name from _migrations");
  // Enforce the same non-recursive scope as migrations/*.sql, even for callers
  // other than the production Vite glob. Never provision migrations/auth/.
  const paths = Object.keys(files).filter((path) => !path.includes("/auth/"));
  for (const { name, path } of pendingMigrations(paths, applied.map((row) => row.name))) {
    await db.transaction([
      ...splitSqlStatements(files[path]).map((text) => ({ text })),
      { text: "insert into _migrations (name) values ($1)", params: [name] },
    ]);
  }
  await db.query("select id from nw_players limit 0");
}
