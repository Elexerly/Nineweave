/**
 * Service context shared by the player and room modules: database, clock,
 * randomness, timeouts, the rate limiter and the mailer. Tests inject PGlite,
 * a fake clock and a recording mailer; production builds one from `getSql()`
 * and the Resend key (see `server.ts`).
 */
import type { Mailer } from "./mailer.ts";
import { RateLimiter, type RateLimits } from "./rate-limit.ts";
import type { Db } from "./store.ts";

export const TURN_MS = 25_000; // turn clock before the "Still there?" prompt
export const STILL_THERE_MS = 10_000; // "Still there?" phase; the turn expires after it
export const GRACE_MS = 60_000; // disconnect grace for the seat that is not due to move
export const CONNECTED_MS = 20_000; // a seat seen this recently counts as connected
/** Total turn length (25 s + 10 s). */
export const TURN_TIMEOUT_MS = TURN_MS + STILL_THERE_MS;
export const LOBBY_TIMEOUT_MS = 600_000; // waiting / finished room with no activity closes

export interface Service {
  db: Db;
  now: () => Date;
  random: () => number;
  limiter: RateLimiter;
  /** Turn clock before the "Still there?" phase. */
  turnMs: number;
  /** Length of the "Still there?" phase. */
  stillThereMs: number;
  /** Disconnect grace for the seat that is not due to move. */
  graceMs: number;
  lobbyTimeoutMs: number;
  /** Minimum gap between opportunistic global cleanup sweeps. */
  cleanupIntervalMs: number;
  lastCleanupMs: number;
  /** Minimum gap between chat / report retention sweeps. */
  retentionIntervalMs: number;
  lastRetentionMs: number;
  /** Last tournament sweep (due starts, purge); shares `cleanupIntervalMs`. */
  lastTournamentSweepMs: number;
  /** Outgoing email; `null` when not configured (email endpoints answer 503). */
  mailer: Mailer | null;
}

export interface ServiceOptions {
  db: Db;
  now?: () => Date;
  random?: () => number;
  limits?: Partial<RateLimits>;
  turnMs?: number;
  stillThereMs?: number;
  graceMs?: number;
  lobbyTimeoutMs?: number;
  cleanupIntervalMs?: number;
  retentionIntervalMs?: number;
  mailer?: Mailer | null;
}

export function createService(opts: ServiceOptions): Service {
  return {
    db: opts.db,
    now: opts.now ?? (() => new Date()),
    random: opts.random ?? Math.random,
    limiter: new RateLimiter(opts.limits),
    turnMs: opts.turnMs ?? TURN_MS,
    stillThereMs: opts.stillThereMs ?? STILL_THERE_MS,
    graceMs: opts.graceMs ?? GRACE_MS,
    lobbyTimeoutMs: opts.lobbyTimeoutMs ?? LOBBY_TIMEOUT_MS,
    cleanupIntervalMs: opts.cleanupIntervalMs ?? 5_000,
    lastCleanupMs: Number.NEGATIVE_INFINITY,
    retentionIntervalMs: opts.retentionIntervalMs ?? 60_000,
    lastRetentionMs: Number.NEGATIVE_INFINITY,
    lastTournamentSweepMs: Number.NEGATIVE_INFINITY,
    mailer: opts.mailer ?? null,
  };
}

/** An error that maps straight onto an HTTP response `{"error": message, ...extra}`. */
export class ApiError extends Error {
  readonly status: number;
  readonly extra: Record<string, unknown>;
  constructor(status: number, message: string, extra: Record<string, unknown> = {}) {
    super(message);
    this.status = status;
    this.extra = extra;
  }
}
