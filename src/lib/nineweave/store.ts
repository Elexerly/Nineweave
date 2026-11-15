/**
 * The database surface the Nineweave service needs: plain queries plus an
 * atomic, non-interactive statement batch. `getSql()` from `@/lib/db`
 * satisfies it (Neon HTTP transaction or PGLite); tests wrap a local PGlite.
 */
export interface Statement {
  text: string;
  params?: unknown[];
}

export interface Db {
  query<T = Record<string, unknown>>(text: string, params?: unknown[]): Promise<T[]>;
  transaction(statements: Statement[]): Promise<Record<string, unknown>[][]>;
}

interface PgliteLike {
  query<T>(text: string, params?: unknown[]): Promise<{ rows: T[] }>;
  transaction<T>(
    fn: (tx: { query<R>(text: string, params?: unknown[]): Promise<{ rows: R[] }> }) => Promise<T>,
  ): Promise<T>;
}

/** Adapt a PGlite instance (tests / embedded use). */
export function pgliteDb(pg: PgliteLike): Db {
  return {
    async query<T>(text: string, params: unknown[] = []) {
      return (await pg.query<T>(text, params)).rows;
    },
    transaction(statements) {
      return pg.transaction(async (tx) => {
        const out: Record<string, unknown>[][] = [];
        for (const s of statements)
          out.push((await tx.query<Record<string, unknown>>(s.text, s.params ?? [])).rows);
        return out;
      });
    },
  };
}

/** Postgres error code, if any (Neon and PGLite both expose `.code`). */
export function pgCode(err: unknown): string | undefined {
  const code = (err as { code?: unknown } | null)?.code;
  return typeof code === "string" ? code : undefined;
}
