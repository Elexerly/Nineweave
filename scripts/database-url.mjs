// @ts-check
/**
 * Resolve the Postgres connection string shared by `src/lib/db.ts` (runtime)
 * and `scripts/migrate.mjs` (deploy). Never logs or returns anything but the
 * URL itself — callers must not print it.
 *
 * Preference (Nineweave tables and `migrations/*.sql` only; auth still reads
 * `DATABASE_URL` directly and `migrations/auth/` is not auto-applied):
 *
 * 1. `NINEWEAVE_DATABASE_URL`, when a `postgres://` / `postgresql://` URL can
 *    be extracted (Patrick's Neon). The value may be a plain URL or a pasted
 *    `.env` block — the first postgres URL is used.
 * 2. Else `DATABASE_URL`, extracted the same way (the platform secret).
 * 3. Else undefined -> callers fall back to embedded PGLite / skip migrating.
 *
 * Empty or whitespace-only values count as unset.
 */

const URL_PATTERN = /postgres(?:ql)?:\/\/[^\s'"`]+/i;

/**
 * @param {string | undefined} value
 * @returns {string | undefined}
 */
export function extractPostgresUrl(value) {
  const text = value?.trim();
  if (!text) return undefined;
  const match = text.match(URL_PATTERN);
  return match ? match[0] : undefined;
}

/**
 * @param {Record<string, string | undefined>} [env]
 * @returns {string | undefined}
 */
export function resolveDatabaseUrl(env = typeof process !== "undefined" ? process.env : {}) {
  return extractPostgresUrl(env.NINEWEAVE_DATABASE_URL) ?? extractPostgresUrl(env.DATABASE_URL);
}

/**
 * True when a database env var is set but no postgres URL could be extracted —
 * a misconfiguration worth warning about (without echoing the value).
 * @param {Record<string, string | undefined>} [env]
 */
export function databaseUrlLooksMisconfigured(
  env = typeof process !== "undefined" ? process.env : {},
) {
  const nine = Boolean(env.NINEWEAVE_DATABASE_URL?.trim());
  const direct = Boolean(env.DATABASE_URL?.trim());
  return (nine || direct) && !resolveDatabaseUrl(env);
}
