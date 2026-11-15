/**
 * Lobby + authoritative turn-based play.
 *
 * Concurrency: every room write is a single atomic batch (Neon's HTTP
 * transaction is non-interactive), guarded optimistically. The batch first
 * runs `update … set rev = <new> where id = $1 and rev = <read>`, then a guard
 * `select 1 / count(*) … where rev = <new>` that divides by zero — aborting the
 * whole batch — if a concurrent writer got there first. Callers then re-read
 * and retry, so token→seat, seq, turn and legality are always checked against
 * the committed state. Match-end player record updates ride in the same batch
 * as the room status change.
 *
 * Seats: slot "a" is the host and "b" the guest; `x_slot` says which slot is
 * seat 1 (X). The first match assigns X/O randomly; each rematch swaps.
 *
 * Timeouts (checked opportunistically on list/create/join/poll/move):
 * - waiting room, host inactive for `lobbyTimeoutMs` (600 s) -> closed ("expired")
 * - finished room, both players inactive for `lobbyTimeoutMs` -> closed
 * - active match, turn clock: `turnMs` (25 s), then a "Still there?" phase of
 *   `stillThereMs` (10 s). The player due to move may restart the clock once
 *   per turn with POST /still-here during that phase. When the clock runs out
 *   the turn expires.
 * - active match, the seat NOT due to move hasn't polled/moved for `graceMs`
 *   (60 s) -> that seat is gone.
 * Until both players have moved in the current round ("both_moved"), an
 * expiry or a leave cancels the match with no record change ("no_show" /
 * "cancelled"). After that, turn expiry is a "timeout" loss, a lost grace is
 * "abandoned" and a leave is a "forfeit"; the opponent wins and records
 * update.
 */
import { canonicalHero, DEFAULT_HERO } from "./heroes.ts";
import { validateName } from "./names.ts";
import { playerByToken, type PlayerRow } from "./players.ts";
import { O, OPEN, Rules, X, type SerializedState } from "./rules.ts";
import {
  hashPassword,
  hashToken,
  newId,
  newRoomCode,
  newToken,
  verifyPassword,
} from "./security.ts";
import { ApiError, CONNECTED_MS, type Service } from "./service.ts";
import { pgCode, type Statement } from "./store.ts";

export type Slot = "a" | "b";
export type RoomStatus = "waiting" | "active" | "finished" | "closed";

export interface RoomRow {
  id: string;
  code: string;
  status: RoomStatus;
  is_private: boolean;
  password_hash: string | null;
  round: number;
  x_slot: Slot;
  state: SerializedState;
  rev: string;
  a_player_id: string | null;
  a_name: string;
  a_hero: string;
  a_token_hash: string;
  a_seen_at: Date;
  a_rematch: boolean;
  b_player_id: string | null;
  b_name: string | null;
  b_hero: string | null;
  b_token_hash: string | null;
  b_seen_at: Date | null;
  b_rematch: boolean;
  left_slot: Slot | null;
  winner_slot: Slot | null;
  end_reason: string | null;
  turn_started_at: Date | null;
  b_joined_at: Date | null;
  still_here_used: boolean;
  created_at: Date;
  updated_at: Date;
}

const PASSWORD_MAX = 64;
const SEEN_THROTTLE_MS = 10_000;
const MAX_ATTEMPTS = 5;

/** Envelope protocol version (2 = online2: turn clock, chat, players). */
export const PROTOCOL = 2;
/** Server hints for the client's next poll, by situation. */
export const POLL_AFTER_MS = {
  waiting: 3000,
  opponentTurn: 1500,
  yourTurn: 3000,
  finished: 4000,
  closed: 0, // stop polling
} as const;

const MATCH_RESULT_REASONS = ["win", "draw", "forfeit", "timeout", "abandoned"];

export const other = (s: Slot): Slot => (s === "a" ? "b" : "a");
export const seatOf = (room: RoomRow, slot: Slot): 1 | 2 => (room.x_slot === slot ? 1 : 2);
export const slotOfSeat = (room: RoomRow, seat: number): Slot =>
  seat === 1 ? room.x_slot : other(room.x_slot);
const ms = (d: Date | string | null) => (d ? new Date(d).getTime() : 0);
const iso = (d: Date | string | null) => (d ? new Date(d).toISOString() : null);

/** The current round's history has at least one move by seat 1 and one by seat 2. */
export function bothMoved(state: SerializedState): boolean {
  let x = false;
  let o = false;
  for (const m of state.history) {
    if (m.player === X) x = true;
    else if (m.player === O) o = true;
    if (x && o) return true;
  }
  return false;
}

/** The slot due to move in an active room. */
const dueSlot = (room: RoomRow): Slot => slotOfSeat(room, room.state.turn);

function seenAt(room: RoomRow, slot: Slot): Date | null {
  return slot === "a" ? room.a_seen_at : room.b_seen_at;
}

function hasSlot(room: RoomRow, slot: Slot): boolean {
  return slot === "a" || room.b_token_hash !== null;
}

function isConnected(svc: Service, room: RoomRow, slot: Slot): boolean {
  const seen = seenAt(room, slot);
  return seen !== null && svc.now().getTime() - ms(seen) < CONNECTED_MS;
}

/** Turn clock of an active room: when it started, when "Still there?" shows, when it expires. */
function turnClock(svc: Service, room: RoomRow) {
  if (room.status !== "active" || !room.turn_started_at) return null;
  const start = ms(room.turn_started_at);
  return {
    start,
    stillThereAt: start + svc.turnMs,
    expiresAt: start + svc.turnMs + svc.stillThereMs,
  };
}

function pollAfterMs(room: RoomRow, slot: Slot): number {
  switch (room.status) {
    case "waiting":
      return POLL_AFTER_MS.waiting;
    case "active":
      return dueSlot(room) === slot ? POLL_AFTER_MS.yourTurn : POLL_AFTER_MS.opponentTurn;
    case "finished":
      return POLL_AFTER_MS.finished;
    default:
      return POLL_AFTER_MS.closed;
  }
}

// ---------------------------------------------------------------------------
// Envelope (never includes token or password hashes or player ids)

export function roomEnvelope(svc: Service, room: RoomRow, slot: Slot) {
  const o = other(slot);
  const seat = seatOf(room, slot);
  const characters: Record<string, string> = { [String(seatOf(room, "a"))]: room.a_hero };
  if (room.b_hero) characters[String(seatOf(room, "b"))] = room.b_hero;
  const isMatchResult = MATCH_RESULT_REASONS.includes(room.end_reason ?? "");
  const clock = turnClock(svc, room);
  const players: Record<string, { name: string; hero: string; connected: boolean }> = {};
  for (const s of ["a", "b"] as const) {
    if (!hasSlot(room, s)) continue;
    players[String(seatOf(room, s))] = {
      name: (s === "a" ? room.a_name : room.b_name) ?? "",
      hero: (s === "a" ? room.a_hero : room.b_hero) ?? DEFAULT_HERO,
      connected: s === slot || isConnected(svc, room, s),
    };
  }
  const opponentPresent = hasSlot(room, o);
  return {
    protocol: PROTOCOL,
    server_now: svc.now().toISOString(),
    code: room.code,
    seat,
    seq: room.state.history.length,
    state: room.state,
    status: room.status,
    private: room.is_private,
    opponent: (o === "a" ? room.a_name : room.b_name) ?? "",
    opponent_left: room.left_slot === o,
    characters,
    match: {
      round: room.round,
      seat,
      local: slot === "a" ? room.a_rematch : room.b_rematch,
      remote: o === "a" ? room.a_rematch : room.b_rematch,
    },
    result: isMatchResult
      ? { winner: room.winner_slot ? seatOf(room, room.winner_slot) : 0, reason: room.end_reason }
      : null,
    end_reason: room.end_reason,
    turn_expires_at: clock ? new Date(clock.expiresAt).toISOString() : null,
    turn_started_at: clock ? new Date(clock.start).toISOString() : null,
    still_there_at: clock ? new Date(clock.stillThereAt).toISOString() : null,
    still_here_used: clock ? room.still_here_used : false,
    turn_seconds: svc.turnMs / 1000,
    still_there_seconds: svc.stillThereMs / 1000,
    grace_seconds: svc.graceMs / 1000,
    both_moved: bothMoved(room.state),
    opponent_joined_at: opponentPresent
      ? iso(o === "b" ? room.b_joined_at : room.created_at)
      : null,
    opponent_last_seen_at: opponentPresent ? iso(seenAt(room, o)) : null,
    opponent_connected: opponentPresent && isConnected(svc, room, o),
    you: {
      name: (slot === "a" ? room.a_name : room.b_name) ?? "",
      hero: (slot === "a" ? room.a_hero : room.b_hero) ?? DEFAULT_HERO,
    },
    players,
    poll_after_ms: pollAfterMs(room, slot),
  };
}

// ---------------------------------------------------------------------------
// Optimistic commit

type Conflict = typeof CONFLICT;
const CONFLICT = Symbol("conflict");

/** Apply `sets` to the room plus `extra` statements atomically; false on a lost race. */
async function commitRoom(
  svc: Service,
  room: RoomRow,
  sets: Partial<Record<keyof RoomRow, unknown>>,
  extra: Statement[] = [],
): Promise<boolean> {
  const newRev = newId("r");
  const params: unknown[] = [room.id, room.rev, newRev];
  const assigns = ["rev = $3"];
  for (const [col, value] of Object.entries(sets)) {
    params.push(col === "state" ? JSON.stringify(value) : value);
    assigns.push(`${col} = $${params.length}${col === "state" ? "::jsonb" : ""}`);
  }
  try {
    await svc.db.transaction([
      { text: `update nw_rooms set ${assigns.join(", ")} where id = $1 and rev = $2`, params },
      {
        text: "select 1 / count(*) as ok from nw_rooms where id = $1 and rev = $2",
        params: [room.id, newRev],
      },
      ...extra,
    ]);
    return true;
  } catch (err) {
    const code = pgCode(err);
    if (code === "22012" || code === "23505" || code === "40001") return false;
    throw err;
  }
}

async function withRetry<T>(attempt: () => Promise<T | Conflict>): Promise<T> {
  for (let i = 0; i < MAX_ATTEMPTS; i += 1) {
    const result = await attempt();
    if (result !== CONFLICT) return result as T;
  }
  throw new ApiError(503, "The room is busy. Try again in a moment.");
}

// ---------------------------------------------------------------------------
// Match end bookkeeping

/** Statements recording a finished match (log row + both players' records). */
function matchEndStatements(
  svc: Service,
  room: RoomRow,
  rules: Rules,
  winnerSlot: Slot | null,
  reason: "win" | "draw" | "forfeit" | "timeout" | "abandoned",
): Statement[] {
  const xSlot = room.x_slot;
  const oSlot = other(xSlot);
  const xBoards = rules.boardsWon(X);
  const oBoards = rules.boardsWon(O);
  const field = (slot: Slot, key: "player_id" | "name" | "hero") => room[`${slot}_${key}`];
  const now = svc.now();
  const stmts: Statement[] = [
    {
      text: `insert into nw_matches
        (room_id, round, x_player_id, o_player_id, x_name, o_name, x_hero, o_hero, result, end_reason, x_boards, o_boards, moves, ended_at)
        values ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14)`,
      params: [
        room.id,
        room.round,
        field(xSlot, "player_id"),
        field(oSlot, "player_id"),
        field(xSlot, "name") ?? "",
        field(oSlot, "name") ?? "",
        field(xSlot, "hero") ?? DEFAULT_HERO,
        field(oSlot, "hero") ?? DEFAULT_HERO,
        winnerSlot === null ? "draw" : winnerSlot === xSlot ? "x" : "o",
        reason,
        xBoards,
        oBoards,
        rules.history.length,
        now,
      ],
    },
  ];
  for (const slot of ["a", "b"] as const) {
    const playerId = room[`${slot}_player_id`];
    if (!playerId) continue;
    const won = winnerSlot === slot ? 1 : 0;
    const lost = winnerSlot !== null && winnerSlot !== slot ? 1 : 0;
    const boards = slot === xSlot ? xBoards : oBoards;
    stmts.push({
      text: `update nw_players set matches_played = matches_played + 1, matches_won = matches_won + $2,
               matches_lost = matches_lost + $3, boards_won = boards_won + $4, updated_at = $5
             where id = $1`,
      params: [playerId, won, lost, boards, now],
    });
  }
  return stmts;
}

/** End an active match by forfeit; the room closes (the loser left / timed out / abandoned). */
async function forfeit(
  svc: Service,
  room: RoomRow,
  loser: Slot,
  reason: "forfeit" | "timeout" | "abandoned",
): Promise<boolean> {
  const rules = Rules.fromHistory(room.state.history);
  const winner = other(loser);
  return commitRoom(
    svc,
    room,
    {
      status: "closed",
      left_slot: loser,
      winner_slot: winner,
      end_reason: reason,
      a_rematch: false,
      b_rematch: false,
      turn_started_at: null,
      still_here_used: false,
      updated_at: svc.now(),
    },
    matchEndStatements(svc, room, rules, winner, reason),
  );
}

/** Close an active match before both players moved: no result, no records. */
async function cancelMatch(
  svc: Service,
  room: RoomRow,
  leaver: Slot,
  reason: "cancelled" | "no_show",
): Promise<boolean> {
  return commitRoom(svc, room, {
    status: "closed",
    left_slot: leaver,
    winner_slot: null,
    end_reason: reason,
    a_rematch: false,
    b_rematch: false,
    turn_started_at: null,
    still_here_used: false,
    updated_at: svc.now(),
  });
}

/**
 * What has run out in an active room, if anything: the turn clock (the
 * player due to move) or the disconnect grace (the other player).
 */
function pendingExpiry(svc: Service, room: RoomRow): { kind: "turn" | "grace"; slot: Slot } | null {
  const clock = turnClock(svc, room);
  if (!clock) return null;
  const now = svc.now().getTime();
  const due = dueSlot(room);
  if (now >= clock.expiresAt) return { kind: "turn", slot: due };
  const idle = other(due);
  const seen = seenAt(room, idle);
  if (seen && now - ms(seen) >= svc.graceMs) return { kind: "grace", slot: idle };
  return null;
}

/**
 * Resolve an expired turn or a lost disconnect grace. Before both players
 * have moved this round it is a no-show (cancelled, no records); after, the
 * expired player loses ("timeout" / "abandoned"). True when something was due.
 */
async function applyExpiry(svc: Service, room: RoomRow): Promise<boolean> {
  const due = pendingExpiry(svc, room);
  if (!due) return false;
  // A lost race means someone else already resolved it.
  if (!bothMoved(room.state)) await cancelMatch(svc, room, due.slot, "no_show");
  else await forfeit(svc, room, due.slot, due.kind === "turn" ? "timeout" : "abandoned");
  return true;
}

/** Chat older than this is deleted. */
export const CHAT_TTL_MS = 24 * 60 * 60 * 1000;
/** Chat of a room closed for longer than this is deleted. */
export const CLOSED_ROOM_CHAT_TTL_MS = 60 * 60 * 1000;
/** Reports (and their chat snapshots) older than this are deleted. */
export const REPORT_TTL_MS = 30 * 24 * 60 * 60 * 1000;

/** Delete expired chat and reports. Throttled separately; `force` skips the throttle. */
export async function runRetention(svc: Service, force = false): Promise<void> {
  const nowMs = svc.now().getTime();
  if (!force && nowMs - svc.lastRetentionMs < svc.retentionIntervalMs) return;
  svc.lastRetentionMs = nowMs;
  await svc.db.query("delete from nw_chat where created_at < $1", [new Date(nowMs - CHAT_TTL_MS)]);
  await svc.db.query(
    `delete from nw_chat where room_id in
       (select id from nw_rooms where status = 'closed' and updated_at < $1)`,
    [new Date(nowMs - CLOSED_ROOM_CHAT_TTL_MS)],
  );
  await svc.db.query("delete from nw_reports where created_at < $1", [
    new Date(nowMs - REPORT_TTL_MS),
  ]);
}

/** Opportunistic, throttled sweep of stale rooms. `force` skips the throttle. */
export async function runCleanup(svc: Service, force = false): Promise<void> {
  const nowMs = svc.now().getTime();
  if (!force && nowMs - svc.lastCleanupMs < svc.cleanupIntervalMs) return;
  svc.lastCleanupMs = nowMs;
  const now = new Date(nowMs);
  const lobbyCutoff = new Date(nowMs - svc.lobbyTimeoutMs);
  await svc.db.query(
    `update nw_rooms set status = 'closed', end_reason = 'expired', rev = $2, updated_at = $3
      where status = 'waiting' and greatest(updated_at, a_seen_at) < $1`,
    [lobbyCutoff, newId("r"), now],
  );
  await svc.db.query(
    `update nw_rooms set status = 'closed', a_rematch = false, b_rematch = false, rev = $2, updated_at = $3
      where status = 'finished' and greatest(updated_at, a_seen_at, coalesce(b_seen_at, a_seen_at)) < $1`,
    [lobbyCutoff, newId("r"), now],
  );
  const stale = await svc.db.query<RoomRow>(
    `select * from nw_rooms
      where status = 'active' and (turn_started_at <= $1 or least(a_seen_at, b_seen_at) <= $2)
      order by updated_at limit 25`,
    [new Date(nowMs - svc.turnMs - svc.stillThereMs), new Date(nowMs - svc.graceMs)],
  );
  for (const room of stale) await applyExpiry(svc, room);
  await runRetention(svc, force);
}

// ---------------------------------------------------------------------------
// Lookup / authorization

export async function roomsByCode(svc: Service, code: string): Promise<RoomRow[]> {
  return svc.db.query<RoomRow>(
    `select * from nw_rooms where code = $1 order by (status <> 'closed') desc, created_at desc limit 10`,
    [code],
  );
}

export async function reloadRoom(svc: Service, id: string): Promise<RoomRow> {
  const rows = await svc.db.query<RoomRow>("select * from nw_rooms where id = $1", [id]);
  if (!rows[0]) throw new ApiError(404, "Room not found or expired");
  return rows[0];
}

/**
 * Resolve the caller's slot from seat tokens or a device token. Candidates
 * are the body `token` and the `Authorization: Bearer` value.
 */
async function authorize(svc: Service, code: string, tokens: (string | null | undefined)[]) {
  const candidates = [
    ...new Set(tokens.filter((t): t is string => typeof t === "string" && t.length > 0)),
  ];
  if (candidates.length === 0)
    throw new ApiError(401, "Authorization required: send Authorization: Bearer <token>");
  const rooms = await roomsByCode(svc, code);
  if (rooms.length === 0) throw new ApiError(404, "Room not found or expired");
  const hashes = candidates.map(hashToken);
  for (const room of rooms) {
    if (hashes.includes(room.a_token_hash)) return { room, slot: "a" as Slot };
    if (room.b_token_hash && hashes.includes(room.b_token_hash)) return { room, slot: "b" as Slot };
  }
  const placeholders = hashes.map((_, i) => `$${i + 1}`).join(", ");
  const players = await svc.db.query<{ id: string }>(
    `select id from nw_players where token_hash in (${placeholders})`,
    hashes,
  );
  const ids = players.map((p) => p.id);
  for (const room of rooms) {
    if (room.a_player_id && ids.includes(room.a_player_id)) return { room, slot: "a" as Slot };
    if (room.b_player_id && ids.includes(room.b_player_id)) return { room, slot: "b" as Slot };
  }
  throw new ApiError(403, "That token does not belong to this room");
}

/** Authorize, apply any due turn expiry / lost grace, and return the fresh room. */
export async function authorizeFresh(
  svc: Service,
  code: string,
  tokens: (string | null | undefined)[],
) {
  const { room, slot } = await authorize(svc, code, tokens);
  if (await applyExpiry(svc, room)) return { room: await reloadRoom(svc, room.id), slot };
  return { room, slot };
}

export async function touchSeen(svc: Service, room: RoomRow, slot: Slot): Promise<void> {
  const now = svc.now();
  const seen = slot === "a" ? room.a_seen_at : room.b_seen_at;
  if (seen && now.getTime() - ms(seen) < SEEN_THROTTLE_MS) return;
  // Not a versioned write: it touches only the seen column, never game state.
  await svc.db.query(`update nw_rooms set ${slot}_seen_at = $2 where id = $1`, [room.id, now]);
  if (slot === "a") room.a_seen_at = now;
  else room.b_seen_at = now;
}

// ---------------------------------------------------------------------------
// Participants

interface Participant {
  player: PlayerRow | null;
  name: string;
  hero: string;
}

async function resolveParticipant(
  svc: Service,
  body: Record<string, unknown>,
  bearer: string | null,
): Promise<Participant> {
  let player: PlayerRow | null = null;
  if (bearer) {
    player = await playerByToken(svc, bearer);
    if (!player) throw new ApiError(401, "Unknown device token");
  }
  let name: string;
  if (player?.screen_name) {
    name = player.screen_name;
  } else if (
    body.name === undefined ||
    body.name === null ||
    (typeof body.name === "string" && !body.name.trim())
  ) {
    name = "Player";
  } else {
    const res = validateName(body.name, "Name");
    if (!res.ok) throw new ApiError(400, res.error);
    name = res.name;
  }
  let hero: string;
  if (body.character_id === undefined || body.character_id === null || body.character_id === "") {
    hero = player?.last_hero_id ?? DEFAULT_HERO;
  } else {
    const canonical = canonicalHero(body.character_id);
    if (!canonical) throw new ApiError(400, "Unknown character_id");
    hero = canonical;
  }
  return { player, name, hero };
}

function rememberHero(svc: Service, p: Participant): Statement[] {
  if (!p.player) return [];
  return [
    {
      text: "update nw_players set last_hero_id = $2, last_seen_at = $3 where id = $1",
      params: [p.player.id, p.hero, svc.now()],
    },
  ];
}

function readPassword(body: Record<string, unknown>): string | null {
  const pw = body.password;
  if (pw === undefined || pw === null || pw === "") return null;
  if (typeof pw !== "string") throw new ApiError(400, "password must be text");
  if (pw.length > PASSWORD_MAX)
    throw new ApiError(400, `password must be ${PASSWORD_MAX} characters or fewer`);
  return pw;
}

// ---------------------------------------------------------------------------
// Endpoints

/** POST /rooms */
export async function createRoom(
  svc: Service,
  body: Record<string, unknown>,
  bearer: string | null,
) {
  await runCleanup(svc);
  const participant = await resolveParticipant(svc, body, bearer);
  const password = readPassword(body);
  if (body.private !== undefined && typeof body.private !== "boolean")
    throw new ApiError(400, "private must be true or false");
  const isPrivate = body.private === true || password !== null;
  if (isPrivate && !password) throw new ApiError(400, "Private rooms need a password");
  const passwordHash = password ? await hashPassword(password) : null;

  const token = newToken("nws");
  const now = svc.now();
  const xSlot: Slot = svc.random() < 0.5 ? "a" : "b";
  const state = new Rules().serialize();
  for (let attempt = 0; attempt < 8; attempt += 1) {
    const id = newId("room");
    const code = newRoomCode();
    try {
      await svc.db.transaction([
        {
          text: `insert into nw_rooms
            (id, code, status, is_private, password_hash, round, x_slot, state, rev,
             a_player_id, a_name, a_hero, a_token_hash, a_seen_at, created_at, updated_at)
            values ($1, $2, 'waiting', $3, $4, 1, $5, $6::jsonb, $7, $8, $9, $10, $11, $12, $12, $12)`,
          params: [
            id,
            code,
            isPrivate,
            passwordHash,
            xSlot,
            JSON.stringify(state),
            newId("r"),
            participant.player?.id ?? null,
            participant.name,
            participant.hero,
            hashToken(token),
            now,
          ],
        },
        ...rememberHero(svc, participant),
      ]);
    } catch (err) {
      if (pgCode(err) === "23505") continue; // live code collision: pick another
      throw err;
    }
    const room = await reloadRoom(svc, id);
    return { ...roomEnvelope(svc, room, "a"), token };
  }
  throw new ApiError(503, "Couldn't allocate a room code. Try again.");
}

/**
 * GET /rooms — open public rooms waiting for a guest. With a device token,
 * rooms whose host blocked the caller (or that the caller blocked) are hidden.
 */
export async function listRooms(svc: Service, bearer: string | null = null) {
  await runCleanup(svc);
  const caller = bearer ? await playerByToken(svc, bearer) : null;
  const rows = await svc.db.query<{
    code: string;
    a_name: string;
    a_hero: string;
    created_at: Date;
  }>(
    `select code, a_name, a_hero, created_at from nw_rooms r
      where status = 'waiting' and not is_private
        and ($1::text is null or r.a_player_id is null or not exists (
          select 1 from nw_blocks b
           where (b.blocker_id = r.a_player_id and b.blocked_id = $1)
              or (b.blocker_id = $1 and b.blocked_id = r.a_player_id)))
      order by created_at desc limit 50`,
    [caller?.id ?? null],
  );
  return {
    rooms: rows.map((r) => ({
      code: r.code,
      host_name: r.a_name,
      host_hero: r.a_hero,
      created_at: new Date(r.created_at).toISOString(),
    })),
  };
}

/** POST /rooms/:code/join */
export async function joinRoom(
  svc: Service,
  code: string,
  body: Record<string, unknown>,
  bearer: string | null,
) {
  await runCleanup(svc);
  const participant = await resolveParticipant(svc, body, bearer);
  const password = readPassword(body);
  const token = newToken("nws");
  let checkedPasswordFor: string | null = null;
  return withRetry(async () => {
    const room = (await roomsByCode(svc, code)).find((r) => r.status !== "closed");
    if (!room) throw new ApiError(404, "Room not found or expired");
    if (room.is_private && checkedPasswordFor !== room.id) {
      if (!password || !room.password_hash || !(await verifyPassword(password, room.password_hash)))
        throw new ApiError(403, "Wrong room password");
      checkedPasswordFor = room.id;
    }
    if (room.status !== "waiting" || room.b_token_hash) throw new ApiError(409, "Room is full");
    if (participant.player && participant.player.id === room.a_player_id)
      throw new ApiError(409, "You can't join your own room");
    // A block (either way) looks exactly like a full room.
    if (
      participant.player &&
      room.a_player_id &&
      (await isBlockedEitherWay(svc, room.a_player_id, participant.player.id))
    )
      throw new ApiError(409, "Room is full");
    const now = svc.now();
    const ok = await commitRoom(
      svc,
      room,
      {
        status: "active",
        b_player_id: participant.player?.id ?? null,
        b_name: participant.name,
        b_hero: participant.hero,
        b_token_hash: hashToken(token),
        b_seen_at: now,
        b_joined_at: now,
        turn_started_at: now,
        still_here_used: false,
        updated_at: now,
      },
      rememberHero(svc, participant),
    );
    if (!ok) return CONFLICT;
    const fresh = await reloadRoom(svc, room.id);
    return { ...roomEnvelope(svc, fresh, "b"), token };
  });
}

function movesSince(state: SerializedState, since: number) {
  return state.history
    .map((m, i) => ({ board: m.board, cell: m.cell, seq: i + 1 }))
    .filter((m) => m.seq > since);
}

/** GET /rooms/:code?since=n — `extras` adds fields computed from the fresh room (chat). */
export async function pollRoom(
  svc: Service,
  code: string,
  since: number,
  tokens: (string | null)[],
  extras?: (room: RoomRow, slot: Slot) => Promise<Record<string, unknown>>,
) {
  await runCleanup(svc);
  const { room, slot } = await authorizeFresh(svc, code, tokens);
  await touchSeen(svc, room, slot);
  return {
    ...roomEnvelope(svc, room, slot),
    moves: movesSince(room.state, since),
    ...(extras ? await extras(room, slot) : {}),
  };
}

export async function isBlockedEitherWay(svc: Service, p1: string, p2: string): Promise<boolean> {
  const rows = await svc.db.query(
    `select 1 from nw_blocks
      where (blocker_id = $1 and blocked_id = $2) or (blocker_id = $2 and blocked_id = $1) limit 1`,
    [p1, p2],
  );
  return rows.length > 0;
}

function requireInt(value: unknown, field: string): number {
  if (typeof value !== "number" || !Number.isInteger(value))
    throw new ApiError(400, `${field} must be an integer`);
  return value;
}

/** POST /rooms/:code/moves */
export async function playMove(
  svc: Service,
  code: string,
  body: Record<string, unknown>,
  bearer: string | null,
) {
  const board = requireInt(body.board, "board");
  const cell = requireInt(body.cell, "cell");
  const seq = requireInt(body.seq, "seq");
  if (seq < 1) throw new ApiError(400, "seq must be 1 or greater");
  const bodyToken = typeof body.token === "string" ? body.token : null;
  await runCleanup(svc);
  return withRetry(async () => {
    const { room, slot } = await authorizeFresh(svc, code, [bodyToken, bearer]);
    const seat = seatOf(room, slot);
    const history = room.state.history;
    const current = history.length;
    const snapshot = () => ({ ...roomEnvelope(svc, room, slot), moves: [] as unknown[] });

    // Idempotent retry of an already-accepted move: return the original ack.
    if (seq <= current) {
      const m = history[seq - 1];
      if (m.board === board && m.cell === cell && m.player === seat) {
        const replay = Rules.fromHistory(history.slice(0, seq));
        return {
          ...roomEnvelope(svc, room, slot),
          seq,
          moves: [{ board, cell, seq }],
          state: replay.serialize(),
        };
      }
      throw new ApiError(409, "Stale move sequence", snapshot());
    }
    if (room.status === "waiting")
      throw new ApiError(409, "Waiting for an opponent to join", snapshot());
    if (room.status === "finished") throw new ApiError(422, "Game finished", snapshot());
    if (room.status === "closed") throw new ApiError(409, "This room is closed", snapshot());
    if (seq !== current + 1)
      throw new ApiError(409, "Move sequence is ahead of the server", snapshot());

    const rules = Rules.fromHistory(history);
    if (rules.turn !== seat) throw new ApiError(403, "It's not your turn", snapshot());
    if (!rules.play(board, cell)) throw new ApiError(422, rules.lastError, snapshot());

    const now = svc.now();
    const sets: Partial<Record<keyof RoomRow, unknown>> = {
      state: rules.serialize(),
      updated_at: now,
      turn_started_at: now,
      still_here_used: false,
      [`${slot}_seen_at`]: now,
    };
    let extra: Statement[] = [];
    if (rules.status !== OPEN) {
      const winnerSeat = rules.winner();
      const winnerSlot = winnerSeat === 0 ? null : slotOfSeat(room, winnerSeat);
      Object.assign(sets, {
        status: "finished",
        winner_slot: winnerSlot,
        end_reason: winnerSlot ? "win" : "draw",
        turn_started_at: null,
        a_rematch: false,
        b_rematch: false,
      });
      extra = matchEndStatements(svc, room, rules, winnerSlot, winnerSlot ? "win" : "draw");
    }
    if (!(await commitRoom(svc, room, sets, extra))) return CONFLICT;
    const fresh = await reloadRoom(svc, room.id);
    return { ...roomEnvelope(svc, fresh, slot), seq, moves: [{ board, cell, seq }] };
  });
}

/**
 * POST /rooms/:code/rematch. Ignored (200, `ignored: true`) while a match is
 * live; 409 when there is no finished match, the opponent has left, or the
 * round is stale.
 */
export async function requestRematch(
  svc: Service,
  code: string,
  body: Record<string, unknown>,
  bearer: string | null,
) {
  if (body.round !== undefined && (typeof body.round !== "number" || !Number.isInteger(body.round)))
    throw new ApiError(400, "round must be an integer");
  const bodyToken = typeof body.token === "string" ? body.token : null;
  return withRetry(async () => {
    const { room, slot } = await authorizeFresh(svc, code, [bodyToken, bearer]);
    const envelope = () => roomEnvelope(svc, room, slot);
    if (room.status === "active") return { ...envelope(), ignored: true };
    if (room.status === "waiting")
      throw new ApiError(409, "No finished match to rematch", envelope());
    if (room.status === "closed")
      throw new ApiError(
        409,
        room.left_slot ? "Your opponent left the room" : "This room is closed",
        envelope(),
      );
    if (body.round !== undefined && body.round !== room.round)
      throw new ApiError(409, "Stale rematch round", envelope());

    const otherAgreed = slot === "a" ? room.b_rematch : room.a_rematch;
    const mineAgreed = slot === "a" ? room.a_rematch : room.b_rematch;
    const now = svc.now();
    if (mineAgreed && !otherAgreed) return envelope(); // duplicate request
    const ok = otherAgreed
      ? await commitRoom(svc, room, {
          status: "active",
          round: room.round + 1,
          x_slot: other(room.x_slot),
          state: new Rules().serialize(),
          a_rematch: false,
          b_rematch: false,
          winner_slot: null,
          end_reason: null,
          left_slot: null,
          turn_started_at: now,
          still_here_used: false,
          updated_at: now,
          [`${slot}_seen_at`]: now,
        })
      : await commitRoom(svc, room, {
          [`${slot}_rematch`]: true,
          updated_at: now,
          [`${slot}_seen_at`]: now,
        });
    if (!ok) return CONFLICT;
    return { ...roomEnvelope(svc, await reloadRoom(svc, room.id), slot), moves: [] };
  });
}

/**
 * POST /rooms/:code/still-here — the player due to move confirms during the
 * "Still there?" phase. Restarts the turn clock (fresh 25 s + 10 s) once per
 * turn; a second confirm in the same turn is 409 and doesn't extend.
 */
export async function stillHere(
  svc: Service,
  code: string,
  body: Record<string, unknown>,
  bearer: string | null,
) {
  const bodyToken = typeof body.token === "string" ? body.token : null;
  return withRetry(async () => {
    const { room, slot } = await authorizeFresh(svc, code, [bodyToken, bearer]);
    const envelope = () => roomEnvelope(svc, room, slot);
    const clock = turnClock(svc, room);
    if (!clock) throw new ApiError(409, "No turn is running", envelope());
    if (dueSlot(room) !== slot) throw new ApiError(403, "It's not your turn", envelope());
    if (room.still_here_used)
      throw new ApiError(409, "You already confirmed this turn", envelope());
    const now = svc.now();
    if (now.getTime() < clock.stillThereAt)
      throw new ApiError(409, "The Still there? prompt isn't showing yet", envelope());
    const ok = await commitRoom(svc, room, {
      turn_started_at: now,
      still_here_used: true,
      updated_at: now,
      [`${slot}_seen_at`]: now,
    });
    if (!ok) return CONFLICT;
    return { ok: true, ...roomEnvelope(svc, await reloadRoom(svc, room.id), slot) };
  });
}

/**
 * POST /rooms/:code/leave. Waiting -> cancelled; active before both players
 * moved -> cancelled (no records); active after -> forfeit (opponent wins,
 * records updated); finished -> closed (no record change); closed -> no-op.
 */
export async function leaveRoom(
  svc: Service,
  code: string,
  body: Record<string, unknown>,
  bearer: string | null,
  opts: { hostCancelOnly?: boolean } = {},
) {
  const bodyToken = typeof body.token === "string" ? body.token : null;
  return withRetry(async () => {
    const { room, slot } = await authorizeFresh(svc, code, [bodyToken, bearer]);
    if (opts.hostCancelOnly) {
      if (slot !== "a") throw new ApiError(403, "Only the host can cancel a room");
      if (room.status !== "waiting")
        throw new ApiError(409, "Only a room that is still waiting can be cancelled");
    }
    const now = svc.now();
    let ok = true;
    if (room.status === "waiting") {
      ok = await commitRoom(svc, room, {
        status: "closed",
        end_reason: "cancelled",
        left_slot: slot,
        updated_at: now,
      });
    } else if (room.status === "active") {
      ok = bothMoved(room.state)
        ? await forfeit(svc, room, slot, "forfeit")
        : await cancelMatch(svc, room, slot, "cancelled");
    } else if (room.status === "finished") {
      ok = await commitRoom(svc, room, {
        status: "closed",
        left_slot: slot,
        a_rematch: false,
        b_rematch: false,
        updated_at: now,
      });
    }
    if (!ok) return CONFLICT;
    return { ok: true, ...roomEnvelope(svc, await reloadRoom(svc, room.id), slot) };
  });
}
