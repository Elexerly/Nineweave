import { ADMIN_PASSPHRASE_HASH, ADMIN_SETUP_ENABLED } from "./admin-setup.ts";
import { handleAdminSetup } from "./admin-api.ts";
import { adminConfig } from "./config.ts";

// Inline at build time; no runtime filesystem access on Vercel.
const migrations = import.meta.glob("/migrations/*.sql", {
  query: "?raw", import: "default", eager: true,
}) as Record<string, string>;

export function handleAdminRequest(request: Request) {
  return handleAdminSetup(request, {
    enabled: ADMIN_SETUP_ENABLED,
    hash: ADMIN_PASSPHRASE_HASH,
    builtin: async () => (await import("../db.ts")).getBuiltinSql(),
    active: async () => (await import("../db.ts")).getSql(),
    connect: async (url) => (await import("../db.ts")).createDatabaseSql(url),
    config: adminConfig,
    migrations,
    env: process.env,
  });
}
