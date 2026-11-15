/**
 * Best-effort fixed-window rate limiter, in memory per server instance.
 * Serverless instances don't share it, so it blunts bursts from one client
 * rather than enforcing a global quota.
 */
export interface RateLimits {
  device: number;
  create: number;
  join: number;
  move: number;
  write: number;
  email: number;
  verify: number;
}

export const DEFAULT_LIMITS: RateLimits = {
  device: 10, // new device tokens per minute per IP
  create: 20,
  join: 40,
  move: 180, // moves + rematch + leave
  write: 30, // PATCH /me
  email: 10, // code requests: verification + recovery
  verify: 30, // code confirmations: verification + recovery
};

export class RateLimiter {
  private windows = new Map<string, { start: number; count: number }>();
  private readonly limits: RateLimits;
  private readonly windowMs: number;

  constructor(limits: Partial<RateLimits> = {}, windowMs = 60_000) {
    this.limits = { ...DEFAULT_LIMITS, ...limits };
    this.windowMs = windowMs;
  }

  /** Count one hit; false when over the limit for this window. */
  hit(bucket: keyof RateLimits, client: string, nowMs: number): boolean {
    const key = `${bucket}:${client}`;
    const w = this.windows.get(key);
    if (!w || nowMs - w.start >= this.windowMs) {
      if (this.windows.size > 10_000) this.sweep(nowMs);
      this.windows.set(key, { start: nowMs, count: 1 });
      return true;
    }
    w.count += 1;
    return w.count <= this.limits[bucket];
  }

  private sweep(nowMs: number) {
    for (const [k, w] of this.windows) if (nowMs - w.start >= this.windowMs) this.windows.delete(k);
  }
}
