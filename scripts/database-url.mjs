// @ts-check
/**
 * Resolve the Postgres connection string shared by `src/lib/db.ts` (runtime)
 * and `scripts/migrate.mjs` (deploy). Never logs or returns anything but the
 * URL itself — callers must not print it.
 *
 * 1. `DATABASE_URL`, when it is a `postgres://` / `postgresql://` URL (this is
 *    the platform secret injected on deploy).
 * 2. Else `NINEWEAVE_DATABASE_URL` — a local/dev alias on the build box that
 *    may hold a pasted `.env` block, so the first postgres URL is extracted.
 * 3. Else undefined -> callers fall back to embedded PGLite / skip migrating.
 *
 * Empty or whitespace-only values count as unset.
 */

const URL_PATTERN = /postgres(?:ql)?:\/\/[^\s'"`]+/i;

/**
 * @param {Record<string, string | undefined>} [env]
 * @returns {string | undefined}
 */
export function resolveDatabaseUrl(env = typeof process !== "undefined" ? process.env : {}) {
  const direct = env.DATABASE_URL?.trim();
  if (direct && /^postgres(?:ql)?:\/\//i.test(direct)) return direct;
  const alias = env.NINEWEAVE_DATABASE_URL?.trim();
  if (alias) {
    const match = alias.match(URL_PATTERN);
    if (match) return match[0];
  }
  return undefined;
}

/**
 * True when `DATABASE_URL` is set to something that is not a postgres URL — a
 * misconfiguration worth warning about (without echoing the value).
 * @param {Record<string, string | undefined>} [env]
 */
export function databaseUrlLooksMisconfigured(
  env = typeof process !== "undefined" ? process.env : {},
) {
  const direct = env.DATABASE_URL?.trim();
  return Boolean(direct) && !/^postgres(?:ql)?:\/\//i.test(direct ?? "");
}
