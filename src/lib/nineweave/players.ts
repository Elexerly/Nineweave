/**
 * Anonymous device-token players: registration, profile and leaderboard.
 *
 * Future Sign in with Apple: `nw_players.apple_sub` is reserved (nullable,
 * unique). A later endpoint can verify an Apple identity token and either
 * attach its `sub` to the caller's device player or re-issue a device token
 * for the player already holding that `sub`. Nothing reads it yet.
 */
import { canonicalHero } from "./heroes.ts";
import { validateName } from "./names.ts";
import { hashToken, newId, newToken } from "./security.ts";
import { ApiError, type Service } from "./service.ts";
import { pgCode } from "./store.ts";

export const TOS_VERSION = "2026-11-15";
export const PRIVACY_VERSION = "2026-11-15";
const VERSION_MAX = 32;
const VERSION_RE = /^[A-Za-z0-9._-]{1,32}$/;

export interface PlayerRow {
  id: string;
  screen_name: string | null;
  purchases: unknown[];
  unlocks: unknown[];
  last_hero_id: string | null;
  matches_won: number;
  matches_lost: number;
  matches_played: number;
  boards_won: number;
  tournament_wins: number;
  created_at: Date;
  tos_version: string | null;
  privacy_version: string | null;
  accepted_at: Date | null;
  age_confirmed: boolean | null;
  email: string | null;
  email_verified_at: Date | null;
}

const PLAYER_COLUMNS =
  "id, screen_name, purchases, unlocks, last_hero_id, matches_won, matches_lost, matches_played, boards_won, tournament_wins, created_at, tos_version, privacy_version, accepted_at, age_confirmed, email, email_verified_at";

/** Feature flags the client checks before using newer endpoints. */
export const CAPABILITIES = {
  email: true,
  online2: true,
  chat: true,
  tournaments: true,
} as const;

/** Tournament options advertised by GET /capabilities. */
export const TOURNAMENT_CAPABILITIES = {
  tournament_sizes: [4, 8],
  tournament_min_players: 3,
  tournament_start_options: [2, 5, 10, 15, 30, 60],
} as const;

export type EmailStatus = "none" | "unverified" | "verified";

export function emailStatus(p: Pick<PlayerRow, "email" | "email_verified_at">): EmailStatus {
  if (!p.email) return "none";
  return p.email_verified_at ? "verified" : "unverified";
}

export const EMAIL_MAX = 254;
const EMAIL_LOCAL_MAX = 64;
const EMAIL_RE =
  /^[a-z0-9.!#$%&'*+/=?^_`{|}~-]+@[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?)+$/;

/**
 * Trim + lowercase + basic shape check. Returns `null` for an empty value
 * (meaning "clear"), or throws 400.
 */
export function normalizeEmail(value: unknown, field = "email"): string | null {
  if (value === null) return null;
  if (typeof value !== "string") throw new ApiError(400, `${field} must be a string or null`);
  const email = value.trim().toLowerCase();
  if (!email) return null;
  const at = email.lastIndexOf("@");
  if (
    email.length > EMAIL_MAX ||
    at < 1 ||
    at > EMAIL_LOCAL_MAX ||
    email.includes("..") ||
    email.startsWith(".") ||
    email.slice(0, at).endsWith(".") ||
    !EMAIL_RE.test(email)
  )
    throw new ApiError(400, "Enter a valid email address (at most 254 characters)");
  return email;
}

export async function playerById(svc: Service, id: string): Promise<PlayerRow | null> {
  const rows = await svc.db.query<PlayerRow>(
    `select ${PLAYER_COLUMNS} from nw_players where id = $1`,
    [id],
  );
  return rows[0] ?? null;
}

/** Players eligible for the public leaderboard. */
const LEADERBOARD_WHERE = "screen_name is not null and matches_played > 0";

export async function playerByToken(
  svc: Service,
  token: string | null | undefined,
): Promise<PlayerRow | null> {
  if (!token) return null;
  const rows = await svc.db.query<PlayerRow>(
    `select ${PLAYER_COLUMNS} from nw_players where token_hash = $1`,
    [hashToken(token)],
  );
  return rows[0] ?? null;
}

/** Resolve a required device token or throw 401. */
export async function requirePlayer(svc: Service, token: string | null): Promise<PlayerRow> {
  if (!token) throw new ApiError(401, "Sign in first: send Authorization: Bearer <device token>");
  const player = await playerByToken(svc, token);
  if (!player) throw new ApiError(401, "Unknown device token");
  return player;
}

async function rankOf(svc: Service, matchesWon: number): Promise<number> {
  const rows = await svc.db.query<{ ahead: number }>(
    `select count(*) as ahead from nw_players where ${LEADERBOARD_WHERE} and matches_won > $1`,
    [matchesWon],
  );
  return Number(rows[0]?.ahead ?? 0) + 1;
}

export async function profile(svc: Service, p: PlayerRow) {
  return {
    player_id: p.id,
    screen_name: p.screen_name,
    last_hero_id: p.last_hero_id,
    purchases: p.purchases,
    unlocks: p.unlocks,
    matches_won: p.matches_won,
    matches_played: p.matches_played,
    matches_lost: p.matches_lost,
    boards_won: p.boards_won,
    tournament_wins: p.tournament_wins,
    tos_version: p.tos_version,
    privacy_version: p.privacy_version,
    accepted_at: p.accepted_at ? new Date(p.accepted_at).toISOString() : null,
    age_confirmed: p.age_confirmed,
    email: p.email,
    email_status: emailStatus(p),
    email_verified_at: p.email_verified_at ? new Date(p.email_verified_at).toISOString() : null,
    capabilities: {
      ...CAPABILITIES,
      ...TOURNAMENT_CAPABILITIES,
      tournament_sizes: [...TOURNAMENT_CAPABILITIES.tournament_sizes],
      tournament_start_options: [...TOURNAMENT_CAPABILITIES.tournament_start_options],
    },
    rank: await rankOf(svc, p.matches_won),
  };
}

function screenNameTaken(err: unknown): boolean {
  return pgCode(err) === "23505" && String((err as Error).message).includes("screen_name");
}

/** POST /auth/device — create a player, returning the raw token exactly once. */
export async function registerDevice(svc: Service, body: Record<string, unknown>) {
  const fields = validateProfileFields(body, [
    "screen_name",
    "last_hero_id",
    "tos_version",
    "privacy_version",
    "accepted_at",
    "age_confirmed",
  ]);
  const token = newToken("nwd");
  const id = newId("p");
  const now = svc.now();
  const acceptedAt = fields.accepted_at ?? (fields.tos_version ? now : null);
  try {
    await svc.db.query(
      `insert into nw_players (id, token_hash, screen_name, last_hero_id, tos_version, privacy_version, accepted_at, age_confirmed, created_at, updated_at, last_seen_at)
       values ($1, $2, $3, $4, $5, $6, $7, $8, $9, $9, $9)`,
      [
        id,
        hashToken(token),
        fields.screen_name ?? null,
        fields.last_hero_id ?? null,
        fields.tos_version ?? null,
        fields.privacy_version ?? null,
        acceptedAt,
        fields.age_confirmed ?? null,
        now,
      ],
    );
  } catch (err) {
    if (screenNameTaken(err)) throw new ApiError(409, "That screen name is taken");
    throw err;
  }
  const player = (await playerById(svc, id))!;
  return { token, player_id: id, player: await profile(svc, player) };
}

const LIST_MAX_ITEMS = 200;
const LIST_ITEM_MAX = 64;

function validateStringList(value: unknown, field: string): string[] {
  if (!Array.isArray(value)) throw new ApiError(400, `${field} must be an array of strings`);
  if (value.length > LIST_MAX_ITEMS)
    throw new ApiError(400, `${field} can hold at most ${LIST_MAX_ITEMS} items`);
  const out: string[] = [];
  for (const item of value) {
    if (typeof item !== "string" || !item.trim() || item.length > LIST_ITEM_MAX)
      throw new ApiError(
        400,
        `${field} items must be non-empty strings of at most ${LIST_ITEM_MAX} characters`,
      );
    if (!out.includes(item.trim())) out.push(item.trim());
  }
  return out;
}

interface ProfileFields {
  screen_name?: string;
  last_hero_id?: string;
  purchases?: string[];
  unlocks?: string[];
  tos_version?: string;
  privacy_version?: string;
  accepted_at?: Date;
  age_confirmed?: boolean;
  /** `null` clears the address. */
  email?: string | null;
}

function validateProfileFields(
  body: Record<string, unknown>,
  allowed: (keyof ProfileFields)[],
): ProfileFields {
  const out: ProfileFields = {};
  for (const key of Object.keys(body)) {
    if (!allowed.includes(key as keyof ProfileFields))
      throw new ApiError(400, `Unknown field: ${key}`);
  }
  if (body.screen_name !== undefined && body.screen_name !== null) {
    const res = validateName(body.screen_name);
    if (!res.ok) throw new ApiError(400, res.error);
    out.screen_name = res.name;
  }
  if (body.last_hero_id !== undefined && body.last_hero_id !== null) {
    const hero = canonicalHero(body.last_hero_id);
    if (!hero) throw new ApiError(400, "Unknown hero id");
    out.last_hero_id = hero;
  }
  if (body.purchases !== undefined) out.purchases = validateStringList(body.purchases, "purchases");
  if (body.unlocks !== undefined) out.unlocks = validateStringList(body.unlocks, "unlocks");
  if (body.tos_version !== undefined && body.tos_version !== null)
    out.tos_version = validateVersion(body.tos_version, "tos_version");
  if (body.privacy_version !== undefined && body.privacy_version !== null)
    out.privacy_version = validateVersion(body.privacy_version, "privacy_version");
  if (body.accepted_at !== undefined && body.accepted_at !== null)
    out.accepted_at = validateAcceptedAt(body.accepted_at);
  if (body.age_confirmed !== undefined && body.age_confirmed !== null) {
    if (typeof body.age_confirmed !== "boolean")
      throw new ApiError(400, "age_confirmed must be a boolean");
    out.age_confirmed = body.age_confirmed;
  }
  if (body.email !== undefined) out.email = normalizeEmail(body.email);
  return out;
}

function validateVersion(value: unknown, field: string): string {
  if (typeof value !== "string") throw new ApiError(400, `${field} must be a string`);
  const v = value.trim();
  if (!v || v.length > VERSION_MAX || !VERSION_RE.test(v))
    throw new ApiError(
      400,
      `${field} must be 1–${VERSION_MAX} letters, digits, dots, underscores or dashes`,
    );
  return v;
}

function validateAcceptedAt(value: unknown): Date {
  const date = value instanceof Date ? value : typeof value === "string" ? new Date(value) : null;
  if (!date || Number.isNaN(date.getTime()))
    throw new ApiError(400, "accepted_at must be an ISO-8601 timestamp");
  if (date.getTime() - Date.now() > 24 * 60 * 60 * 1000)
    throw new ApiError(400, "accepted_at cannot be in the future");
  return date;
}

/**
 * PATCH /me. `purchases` / `unlocks` are stored as client-asserted data only:
 * there is no receipt validation yet (Apple IAP later), so nothing may treat
 * them as proof of payment.
 */
export async function updateMe(svc: Service, player: PlayerRow, body: Record<string, unknown>) {
  const fields = validateProfileFields(body, [
    "screen_name",
    "last_hero_id",
    "purchases",
    "unlocks",
    "tos_version",
    "privacy_version",
    "accepted_at",
    "age_confirmed",
    "email",
  ]);
  const sets: string[] = [];
  const params: unknown[] = [player.id];
  const add = (col: string, value: unknown, cast = "") => {
    params.push(value);
    sets.push(`${col} = $${params.length}${cast}`);
  };
  if (fields.screen_name !== undefined) add("screen_name", fields.screen_name);
  if (fields.last_hero_id !== undefined) add("last_hero_id", fields.last_hero_id);
  if (fields.purchases !== undefined) add("purchases", JSON.stringify(fields.purchases), "::jsonb");
  if (fields.unlocks !== undefined) add("unlocks", JSON.stringify(fields.unlocks), "::jsonb");
  if (fields.tos_version !== undefined) add("tos_version", fields.tos_version);
  if (fields.privacy_version !== undefined) add("privacy_version", fields.privacy_version);
  const acceptedAt =
    fields.accepted_at ??
    (fields.tos_version !== undefined ||
    fields.privacy_version !== undefined ||
    fields.age_confirmed !== undefined
      ? svc.now()
      : undefined);
  if (acceptedAt !== undefined) add("accepted_at", acceptedAt);
  if (fields.age_confirmed !== undefined) add("age_confirmed", fields.age_confirmed);
  // A new (or cleared) address drops ownership verification; re-sending the
  // same address keeps it.
  const emailChanged = fields.email !== undefined && fields.email !== (player.email ?? null);
  if (emailChanged) {
    add("email", fields.email);
    add("email_verified_at", null);
  }
  add("updated_at", svc.now());
  try {
    await svc.db.query(`update nw_players set ${sets.join(", ")} where id = $1`, params);
  } catch (err) {
    if (screenNameTaken(err)) throw new ApiError(409, "That screen name is taken");
    throw err;
  }
  if (emailChanged) await invalidateOpenChallenges(svc, player.id);
  return profile(svc, (await playerById(svc, player.id))!);
}

/** Kill every unused email code of this player (address changed or cleared). */
export async function invalidateOpenChallenges(svc: Service, playerId: string, purpose?: string) {
  await svc.db.query(
    `update nw_email_challenges set invalidated_at = $2
      where player_id = $1 and consumed_at is null and invalidated_at is null
        and ($3::text is null or purpose = $3)`,
    [playerId, svc.now(), purpose ?? null],
  );
}

export const LEADERBOARD_DEFAULT = 50;
export const LEADERBOARD_MAX = 100;

/** GET /leaderboard — ranked by matches won (ties share a rank). */
export async function leaderboard(
  svc: Service,
  limitParam: string | null,
  caller: PlayerRow | null,
) {
  let limit = Number.parseInt(limitParam ?? "", 10);
  if (!Number.isFinite(limit) || limit < 1) limit = LEADERBOARD_DEFAULT;
  limit = Math.min(limit, LEADERBOARD_MAX);
  const rows = await svc.db.query<{
    screen_name: string;
    matches_won: number;
    matches_played: number;
    tournament_wins: number;
    rank: number;
  }>(
    `select screen_name, matches_won, matches_played, tournament_wins,
            rank() over (order by matches_won desc) as rank
       from nw_players
      where ${LEADERBOARD_WHERE}
      order by matches_won desc, matches_played asc, created_at asc
      limit $1`,
    [limit],
  );
  const result: Record<string, unknown> = {
    players: rows.map((r) => ({
      rank: Number(r.rank),
      screen_name: r.screen_name,
      matches_won: r.matches_won,
      matches_played: r.matches_played,
      tournament_wins: r.tournament_wins,
    })),
  };
  if (caller) {
    result.me = {
      screen_name: caller.screen_name,
      matches_won: caller.matches_won,
      matches_played: caller.matches_played,
      boards_won: caller.boards_won,
      tournament_wins: caller.tournament_wins,
      last_hero_id: caller.last_hero_id,
      rank: await rankOf(svc, caller.matches_won),
    };
  }
  return result;
}
