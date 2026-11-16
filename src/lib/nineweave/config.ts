/** Server-side bootstrap settings. Values must never be logged or serialized. */
import { extractPostgresUrl } from "../../../scripts/database-url.mjs";
import type { Db } from "./store.ts";

export type ConfigKey = "nineweave_database_url" | "resend_api_key";
export type ConfigValues = Partial<Record<ConfigKey, string>>;

export function createConfigStore(getBuiltin: () => Promise<Db>, now = Date.now) {
  let cache: { values: ConfigValues; until: number } | undefined;
  let loading: Promise<ConfigValues> | undefined;
  let generation = 0;
  return {
    invalidate() {
      generation += 1;
      cache = undefined;
      loading = undefined;
    },
    async read(): Promise<ConfigValues> {
      if (cache && now() < cache.until) return cache.values;
      const current = generation;
      loading ??= (async () => {
        const db = await getBuiltin();
        let rows: { key: ConfigKey; value: string | null }[];
        try {
          rows = await db.query(
            "select key, value from nw_admin_config where key in ('nineweave_database_url', 'resend_api_key')",
          );
        } catch (error) {
          // Older installations keep working until the bootstrap migration runs.
          if ((error as { code?: string })?.code !== "42P01") throw error;
          rows = [];
        }
        const values: ConfigValues = {};
        for (const row of rows) if (row.value) values[row.key] = row.value;
        if (generation === current) cache = { values, until: now() + 60_000 };
        return values;
      })();
      try {
        return await loading;
      } finally {
        if (generation === current) loading = undefined;
      }
    },
    async save(values: ConfigValues) {
      const db = await getBuiltin();
      await db.transaction(Object.entries(values).map(([key, value]) => ({
        text: "insert into nw_admin_config (key, value) values ($1, $2) on conflict (key) do update set value = excluded.value, updated_at = now()",
        params: [key, value],
      })));
      this.invalidate();
    },
  };
}

export type ConfigStore = ReturnType<typeof createConfigStore>;
type Env = Record<string, string | undefined>;

export async function resolveNineweaveDatabaseUrl(env: Env, store: ConfigStore) {
  const override = extractPostgresUrl(env.NINEWEAVE_DATABASE_URL);
  if (override) return override;
  return (await store.read()).nineweave_database_url ?? extractPostgresUrl(env.DATABASE_URL);
}

export async function resolveResendKey(env: Env, store: ConfigStore) {
  return env.NINEWEAVE_RESEND_API_KEY?.trim() || (await store.read()).resend_api_key;
}

// The lazy import avoids a bootstrap cycle: getBuiltinSql never reads settings.
export const adminConfig = createConfigStore(async () => (await import("../db.ts")).getBuiltinSql());
