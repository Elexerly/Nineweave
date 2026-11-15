/**
 * Service context shared by the player and room modules: database, clock,
 * randomness, timeouts, the rate limiter and the mailer. Tests inject PGlite,
 * a fake clock and a recording mailer; production builds one from `getSql()`
 * and the Resend key (see `server.ts`).
 */
import type { Mailer } from "./mailer.ts";
import { RateLimiter, type RateLimits } from "./rate-limit.ts";
import type { Db } from "./store.ts";

export const TURN_TIMEOUT_MS = 180_000; // active match: player due to move forfeits
export const LOBBY_TIMEOUT_MS = 600_000; // waiting / finished room with no activity closes

export interface Service {
  db: Db;
  now: () => Date;
  random: () => number;
  limiter: RateLimiter;
  turnTimeoutMs: number;
  lobbyTimeoutMs: number;
  /** Minimum gap between opportunistic global cleanup sweeps. */
  cleanupIntervalMs: number;
  lastCleanupMs: number;
  /** Outgoing email; `null` when not configured (email endpoints answer 503). */
  mailer: Mailer | null;
}

export interface ServiceOptions {
  db: Db;
  now?: () => Date;
  random?: () => number;
  limits?: Partial<RateLimits>;
  turnTimeoutMs?: number;
  lobbyTimeoutMs?: number;
  cleanupIntervalMs?: number;
  mailer?: Mailer | null;
}

export function createService(opts: ServiceOptions): Service {
  return {
    db: opts.db,
    now: opts.now ?? (() => new Date()),
    random: opts.random ?? Math.random,
    limiter: new RateLimiter(opts.limits),
    turnTimeoutMs: opts.turnTimeoutMs ?? TURN_TIMEOUT_MS,
    lobbyTimeoutMs: opts.lobbyTimeoutMs ?? LOBBY_TIMEOUT_MS,
    cleanupIntervalMs: opts.cleanupIntervalMs ?? 5_000,
    lastCleanupMs: Number.NEGATIVE_INFINITY,
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
