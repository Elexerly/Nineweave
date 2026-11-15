/**
 * Email ownership verification and email-based account recovery.
 *
 * A code is 6 random digits, emailed once and stored only as
 * sha256("nwcode:v1:<challenge id>:<code>"), so a hash can't be replayed
 * against another challenge. Each challenge lives 10 minutes and allows 5
 * guesses. Requests are throttled in the database (60 s per-player cooldown,
 * 5 per player and 5 per email per rolling hour) so the caps hold across
 * serverless instances.
 *
 * Only a *verified* address can recover an account; recovery replaces the
 * player's device token (one device per player for now).
 */
import { createHash, randomInt, timingSafeEqual } from "node:crypto";
import { buildCodeEmail, type CodePurpose } from "./mailer.ts";
import {
  invalidateOpenChallenges,
  normalizeEmail,
  playerById,
  profile,
  type PlayerRow,
} from "./players.ts";
import { hashToken, newId, newToken } from "./security.ts";
import { ApiError, type Service } from "./service.ts";
import { pgCode } from "./store.ts";

export const CODE_TTL_MS = 10 * 60_000;
export const MAX_ATTEMPTS = 5;
export const RESEND_COOLDOWN_MS = 60_000;
export const HOURLY_CAP = 5;
const HOUR_MS = 60 * 60_000;
/** Challenge rows older than this are deleted opportunistically. */
const RETAIN_MS = 24 * HOUR_MS;

const INVALID_CODE = "Invalid or expired code";
const EMAIL_TAKEN = "That email is already used by another account.";
const NOT_CONFIGURED = "Email verification is not available on this server yet";
const SEND_FAILED = "Could not send email. Try again shortly.";

function codeHash(challengeId: string, code: string): string {
  return createHash("sha256").update(`nwcode:v1:${challengeId}:${code}`, "utf8").digest("hex");
}

function sameHash(a: string, b: string): boolean {
  const x = Buffer.from(a, "hex");
  const y = Buffer.from(b, "hex");
  return x.length === y.length && x.length > 0 && timingSafeEqual(x, y);
}

function newCode(): string {
  return String(randomInt(0, 1_000_000)).padStart(6, "0");
}

function onlyFields(body: Record<string, unknown>, allowed: string[]) {
  for (const key of Object.keys(body))
    if (!allowed.includes(key)) throw new ApiError(400, `Unknown field: ${key}`);
}

function parseConfirmBody(body: Record<string, unknown>): { challengeId: string; code: string } {
  onlyFields(body, ["challenge_id", "code"]);
  const challengeId = body.challenge_id;
  if (typeof challengeId !== "string" || !challengeId || challengeId.length > 64)
    throw new ApiError(400, "challenge_id is required");
  const raw = typeof body.code === "number" ? String(body.code) : body.code;
  const code = typeof raw === "string" ? raw.replace(/\s+/g, "") : "";
  if (!/^\d{6}$/.test(code)) throw new ApiError(400, "code must be 6 digits");
  return { challengeId, code };
}

async function verifiedOwner(svc: Service, email: string): Promise<string | null> {
  const rows = await svc.db.query<{ id: string }>(
    "select id from nw_players where lower(email) = $1 and email_verified_at is not null",
    [email],
  );
  return rows[0]?.id ?? null;
}

interface Throttle {
  retryAfterMs: number;
  message: string;
}

/** The first request limit this player/email would break, if any. */
async function throttled(svc: Service, playerId: string, email: string): Promise<Throttle | null> {
  const now = svc.now().getTime();
  const hourAgo = new Date(now - HOUR_MS);
  const [byPlayer] = await svc.db.query<{ n: number; first: Date | null; last: Date | null }>(
    `select count(*)::int as n, min(created_at) as first, max(created_at) as last
       from nw_email_challenges where player_id = $1 and created_at > $2`,
    [playerId, hourAgo],
  );
  const [byEmail] = await svc.db.query<{ n: number; first: Date | null }>(
    `select count(*)::int as n, min(created_at) as first
       from nw_email_challenges where email = $1 and created_at > $2`,
    [email, hourAgo],
  );
  if (byPlayer?.last) {
    const wait = new Date(byPlayer.last).getTime() + RESEND_COOLDOWN_MS - now;
    if (wait > 0)
      return {
        retryAfterMs: wait,
        message: "Please wait a minute before requesting another code.",
      };
  }
  if (Number(byPlayer?.n ?? 0) >= HOURLY_CAP && byPlayer?.first)
    return {
      retryAfterMs: new Date(byPlayer.first).getTime() + HOUR_MS - now,
      message: "Too many codes requested. Try again later.",
    };
  if (Number(byEmail?.n ?? 0) >= HOURLY_CAP && byEmail?.first)
    return {
      retryAfterMs: new Date(byEmail.first).getTime() + HOUR_MS - now,
      message: "Too many codes requested for this email. Try again later.",
    };
  return null;
}

function throttleError(t: Throttle): ApiError {
  return new ApiError(429, t.message, {
    retry_after_seconds: Math.max(1, Math.ceil(t.retryAfterMs / 1000)),
  });
}

/**
 * Insert a challenge, superseding the player's open ones of this purpose.
 * The insert re-checks every cap inside the transaction (after locking the
 * player row), so concurrent requests from one player can't both pass.
 * Returns null if a cap was hit in the meantime.
 */
async function insertChallenge(
  svc: Service,
  playerId: string,
  email: string,
  purpose: CodePurpose,
  code: string,
) {
  const id = newId("ec");
  const now = svc.now();
  const expiresAt = new Date(now.getTime() + CODE_TTL_MS);
  const hourAgo = new Date(now.getTime() - HOUR_MS);
  const cooldownStart = new Date(now.getTime() - RESEND_COOLDOWN_MS);
  const results = await svc.db.transaction([
    { text: "select id from nw_players where id = $1 for update", params: [playerId] },
    {
      text: "delete from nw_email_challenges where created_at < $1",
      params: [new Date(now.getTime() - RETAIN_MS)],
    },
    {
      text: `update nw_email_challenges set invalidated_at = $3
              where player_id = $1 and purpose = $2 and consumed_at is null and invalidated_at is null`,
      params: [playerId, purpose, now],
    },
    {
      text: `insert into nw_email_challenges
               (id, player_id, email, purpose, code_hash, expires_at, max_attempts, created_at)
             select $1, $2, $3, $4, $5, $6, $7, $8
              where (select count(*) from nw_email_challenges where player_id = $2 and created_at > $9) < $11
                and (select count(*) from nw_email_challenges where email = $3 and created_at > $9) < $11
                and not exists (select 1 from nw_email_challenges where player_id = $2 and created_at > $10)
             returning id`,
      params: [
        id,
        playerId,
        email,
        purpose,
        codeHash(id, code),
        expiresAt,
        MAX_ATTEMPTS,
        now,
        hourAgo,
        cooldownStart,
        HOURLY_CAP,
      ],
    },
  ]);
  if (results[3].length === 0) return null;
  return {
    challenge_id: id,
    expires_at: expiresAt.toISOString(),
    resend_available_at: new Date(now.getTime() + RESEND_COOLDOWN_MS).toISOString(),
  };
}

async function invalidateChallenge(svc: Service, id: string) {
  await svc.db.query(
    "update nw_email_challenges set invalidated_at = $2 where id = $1 and invalidated_at is null",
    [id, svc.now()],
  );
}

/** Send the code; on failure kill the challenge and answer 502. */
async function deliver(
  svc: Service,
  challengeId: string,
  to: string,
  code: string,
  purpose: CodePurpose,
) {
  try {
    await svc.mailer!(buildCodeEmail(to, code, purpose, CODE_TTL_MS / 60_000));
  } catch {
    await invalidateChallenge(svc, challengeId);
    throw new ApiError(502, SEND_FAILED);
  }
}

/** POST /me/email/verification */
export async function requestVerification(
  svc: Service,
  player: PlayerRow,
  body: Record<string, unknown>,
) {
  onlyFields(body, ["email"]);
  const email = body.email === undefined ? player.email : normalizeEmail(body.email);
  if (!email) throw new ApiError(400, "Add an email address first");
  if (!svc.mailer) throw new ApiError(503, NOT_CONFIGURED);
  const changed = email !== player.email;
  if (!changed && player.email_verified_at)
    throw new ApiError(409, "That email is already verified on your account.");
  const owner = await verifiedOwner(svc, email);
  if (owner && owner !== player.id) throw new ApiError(409, EMAIL_TAKEN);
  const limited = await throttled(svc, player.id, email);
  if (limited) throw throttleError(limited);

  if (changed) {
    await svc.db.query(
      "update nw_players set email = $2, email_verified_at = null, updated_at = $3 where id = $1",
      [player.id, email, svc.now()],
    );
    await invalidateOpenChallenges(svc, player.id);
  }
  const code = newCode();
  const challenge = await insertChallenge(svc, player.id, email, "verify", code);
  if (!challenge) {
    throw throttleError(
      (await throttled(svc, player.id, email)) ?? {
        retryAfterMs: RESEND_COOLDOWN_MS,
        message: "Please wait a minute before requesting another code.",
      },
    );
  }
  await deliver(svc, challenge.challenge_id, email, code, "verify");
  return { ...challenge, email };
}

interface ChallengeRow {
  id: string;
  player_id: string;
  email: string;
  code_hash: string;
}

/**
 * Spend one attempt on a live challenge and check the code. Returns the
 * challenge when the code matched, null otherwise (wrong, expired, spent,
 * superseded, locked out). The attempt counter is bumped atomically, so at
 * most `max_attempts` guesses are ever compared.
 */
async function spendAttempt(
  svc: Service,
  challengeId: string,
  purpose: CodePurpose,
  code: string,
  playerId: string | null,
): Promise<ChallengeRow | null> {
  const rows = await svc.db.query<ChallengeRow>(
    `update nw_email_challenges set attempt_count = attempt_count + 1
      where id = $1 and purpose = $2 and ($3::text is null or player_id = $3)
        and consumed_at is null and invalidated_at is null
        and expires_at > $4 and attempt_count < max_attempts
      returning id, player_id, email, code_hash`,
    [challengeId, purpose, playerId, svc.now()],
  );
  const row = rows[0];
  if (!row) return null;
  return sameHash(row.code_hash, codeHash(row.id, code)) ? row : null;
}

/** POST /me/email/verification/confirm */
export async function confirmVerification(
  svc: Service,
  player: PlayerRow,
  body: Record<string, unknown>,
) {
  const { challengeId, code } = parseConfirmBody(body);
  const known = await svc.db.query<{ id: string }>(
    "select id from nw_email_challenges where id = $1 and purpose = 'verify' and player_id = $2",
    [challengeId, player.id],
  );
  if (known.length === 0) throw new ApiError(404, "Verification not found. Request a new code.");
  const challenge = await spendAttempt(svc, challengeId, "verify", code, player.id);
  if (!challenge) throw new ApiError(400, INVALID_CODE);

  const owner = await verifiedOwner(svc, challenge.email);
  if (owner && owner !== player.id) {
    await invalidateChallenge(svc, challenge.id);
    throw new ApiError(409, EMAIL_TAKEN);
  }
  const now = svc.now();
  let updated: { id: string }[];
  try {
    // One statement: consume the challenge and mark the address verified,
    // only if the player still holds that address. The unique partial index
    // makes the first confirm for an address win.
    updated = await svc.db.query<{ id: string }>(
      `with c as (
         update nw_email_challenges set consumed_at = $3
          where id = $1 and player_id = $2 and consumed_at is null and invalidated_at is null
          returning email
       )
       update nw_players p set email_verified_at = $3, updated_at = $3
         from c where p.id = $2 and p.email = c.email
       returning p.id`,
      [challenge.id, player.id, now],
    );
  } catch (err) {
    if (pgCode(err) === "23505") {
      await invalidateChallenge(svc, challenge.id);
      throw new ApiError(409, EMAIL_TAKEN);
    }
    throw err;
  }
  if (updated.length === 0) throw new ApiError(400, INVALID_CODE);
  // Leftover codes for this address (any player) can no longer verify it.
  await svc.db.query(
    `update nw_email_challenges set invalidated_at = $2
      where email = $1 and purpose = 'verify' and consumed_at is null and invalidated_at is null`,
    [challenge.email, now],
  );
  return profile(svc, (await playerById(svc, player.id))!);
}

/**
 * POST /auth/email/recover — always the same 200 shape, whether or not the
 * address is verified on an account, throttled, or unknown, so it can't be
 * used to probe which emails are registered. Only a verified address gets
 * a code.
 */
export async function requestRecovery(svc: Service, body: Record<string, unknown>) {
  onlyFields(body, ["email"]);
  const email = normalizeEmail(body.email);
  if (!email) throw new ApiError(400, "Enter a valid email address (at most 254 characters)");
  if (!svc.mailer) throw new ApiError(503, NOT_CONFIGURED);
  const now = svc.now().getTime();
  const generic = {
    challenge_id: newId("ec"),
    expires_at: new Date(now + CODE_TTL_MS).toISOString(),
    resend_available_at: new Date(now + RESEND_COOLDOWN_MS).toISOString(),
  };
  const ownerId = await verifiedOwner(svc, email);
  if (!ownerId) return generic;
  if (await throttled(svc, ownerId, email)) return generic;
  const code = newCode();
  const challenge = await insertChallenge(svc, ownerId, email, "recover", code);
  if (!challenge) return generic;
  try {
    await deliver(svc, challenge.challenge_id, email, code, "recover");
  } catch {
    // A delivery failure would otherwise reveal that the address exists.
    return generic;
  }
  return challenge;
}

/**
 * POST /auth/email/recover/confirm — on success, issue a fresh device token
 * for the account and retire the old one. Every failure, including an
 * unknown challenge, is the same 400.
 */
export async function confirmRecovery(svc: Service, body: Record<string, unknown>) {
  const { challengeId, code } = parseConfirmBody(body);
  const challenge = await spendAttempt(svc, challengeId, "recover", code, null);
  if (!challenge) throw new ApiError(400, INVALID_CODE);
  const token = newToken("nwd");
  const now = svc.now();
  const updated = await svc.db.query<{ id: string }>(
    `with c as (
       update nw_email_challenges set consumed_at = $3
        where id = $1 and player_id = $2 and consumed_at is null and invalidated_at is null
        returning email
     )
     update nw_players p set token_hash = $4, updated_at = $3, last_seen_at = $3
       from c where p.id = $2 and p.email = c.email and p.email_verified_at is not null
     returning p.id`,
    [challenge.id, challenge.player_id, now, hashToken(token)],
  );
  if (updated.length === 0) throw new ApiError(400, INVALID_CODE);
  await invalidateOpenChallenges(svc, challenge.player_id, "recover");
  const player = (await playerById(svc, challenge.player_id))!;
  return { token, player_id: player.id, player: await profile(svc, player) };
}
