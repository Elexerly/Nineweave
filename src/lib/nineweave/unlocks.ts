/** Server-owned cosmetic entitlements. Codes are not credentials or purchases. */
import { ApiError, type Service } from "./service.ts";
import type { PlayerRow } from "./players.ts";
import { pgCode } from "./store.ts";

const BACKGROUND_CODES: Readonly<Record<string, string>> = Object.freeze({
  BLIZZARD: "blizzard",
  TICTACTOE: "tictactoe",
  "010127": "new_year",
  "0704027": "fourth_july",
  PATRICK: "st_patrick",
});
const HERO_CODES: Readonly<Record<string, string>> = Object.freeze({ N2026: "nick", PROF26: "professor_gilt", JB2026: "jb_rocker" });
const RESERVED_HERO_CODES = new Set([
  "W2026",
  "G2026",
  "J2026",
  "B2026",
  "E2026",
  "T2026",
  "JY2026",
  "GM2026",
  "D2026",
]);
export const UNLOCK_ATTEMPTS_PER_MINUTE = 10;

export async function accountUnlocks(svc: Service, playerId: string) {
  const rows = await svc.db.query<{ kind: string; unlock_id: string }>(
    "select kind, unlock_id from nw_account_unlocks where player_id=$1 order by unlock_id",
    [playerId],
  );
  return {
    unlocked_backgrounds: rows.filter((r) => r.kind === "background").map((r) => r.unlock_id),
    unlocked_heroes: rows.filter((r) => r.kind === "hero").map((r) => r.unlock_id),
  };
}

export async function redeemUnlock(svc: Service, player: PlayerRow, body: Record<string, unknown>) {
  // Atomic SQL quota, not merely a per-process limiter. Rejected requests count too.
  // No raw code, IP, email, or token is retained in this table.
  let quota: { attempts: number }[];
  try {
    quota = await svc.db.query<{ attempts: number }>(
      `
      insert into nw_unlock_rate(player_id,window_start,attempts) values($1,$2,1)
      on conflict(player_id) do update set
        attempts=case when nw_unlock_rate.window_start <= $2::timestamptz - interval '1 minute'
          then 1 else least(nw_unlock_rate.attempts + 1, 11) end,
        window_start=case when nw_unlock_rate.window_start <= $2::timestamptz - interval '1 minute'
          then $2 else nw_unlock_rate.window_start end
      returning attempts`,
      [player.id, svc.now()],
    );
  } catch (err) {
    if (pgCode(err) === "23503") throw new ApiError(401, "Account no longer exists");
    throw err;
  }
  if (Number(quota[0].attempts) > UNLOCK_ATTEMPTS_PER_MINUTE)
    throw new ApiError(429, "Too many code attempts. Wait a minute and try again.", {
      code: "rate_limited",
    });
  if (
    Object.keys(body).some((k) => k !== "code") ||
    typeof body.code !== "string" ||
    body.code.length > 64 ||
    !/^[a-zA-Z0-9]{1,32}$/.test(body.code.trim())
  )
    throw new ApiError(400, "Enter a valid unlock code.", { code: "invalid_code" });
  const code = body.code.trim().toUpperCase();
  if (RESERVED_HERO_CODES.has(code))
    throw new ApiError(
      409,
      "This secret character is not available yet. Keep the code and try again when the character arrives.",
      { code: "code_unavailable" },
    );
  const kind = Object.hasOwn(HERO_CODES, code) ? "hero" : "background";
  const id =
    kind === "hero"
      ? HERO_CODES[code]
      : Object.hasOwn(BACKGROUND_CODES, code)
        ? BACKGROUND_CODES[code]
        : undefined;
  if (!id)
    throw new ApiError(400, "That unlock code was not recognized.", { code: "invalid_code" });
  let granted: { unlock_id: string }[];
  try {
    granted = await svc.db.query<{ unlock_id: string }>(
      `
      insert into nw_account_unlocks(player_id,kind,unlock_id,granted_at)
      values($1,$2,$3,$4) on conflict do nothing returning unlock_id`,
      [player.id, kind, id, svc.now()],
    );
  } catch (err) {
    if (pgCode(err) === "23503") throw new ApiError(401, "Account no longer exists");
    throw err;
  }
  return {
    ok: true,
    unlock: { kind, id },
    already_owned: !granted.length,
    ...(await accountUnlocks(svc, player.id)),
  };
}
