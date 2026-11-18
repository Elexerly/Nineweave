/**
 * In-match chat, blocks and reports.
 *
 * Chat rides the room poll (`GET /rooms/<CODE>?chat_since=<id>`); posting is
 * `POST /rooms/<CODE>/chat`. Only device players with a screen name may send.
 * Per-player rate limits are counted in the database so they hold across
 * serverless instances. Message text is never logged.
 *
 * Blocks and reports identify the other player by room code + seat, so player
 * ids never leave the server.
 */
import { CHAT_PRESETS, checkChatText, normalizeChatText } from "./chat-filter.ts";
import { requirePlayer, TOURNAMENT_CAPABILITIES, type PlayerRow } from "./players.ts";
import {
  authorizeFresh,
  roomEnvelope,
  roomsByCode,
  seatOf,
  slotOfSeat,
  touchSeen,
  type RoomRow,
  type Slot,
} from "./rooms.ts";
import { ApiError, type Service } from "./service.ts";

export const CHAT_PAGE = 50;
/** Per-player chat caps: [window ms, max messages]. */
export const CHAT_LIMITS: [number, number][] = [
  [10_000, 5],
  [5 * 60_000, 30],
];
export const REPORT_LIMIT: [number, number] = [60 * 60_000, 10];
export const REPORT_REASONS = [
  "harassment",
  "hate",
  "inappropriate_name",
  "cheating",
  "spam",
  "other",
] as const;
const NOTE_MAX = 500;
const SNAPSHOT_MAX = 20;

interface ChatRow {
  id: number;
  slot: Slot;
  name: string;
  text: string;
  preset: string | null;
  created_at: Date;
}

function chatMessage(room: RoomRow, viewer: Slot, r: ChatRow) {
  return {
    id: Number(r.id),
    seat: seatOf(room, r.slot),
    mine: r.slot === viewer,
    name: r.name,
    text: r.text,
    preset: r.preset,
    at: new Date(r.created_at).toISOString(),
  };
}

/**
 * Chat fields for a room envelope: up to 50 messages with id > `since`
 * (oldest first) and `chat_seq`, the newest id the viewer can see. Messages
 * from players the viewer blocked are never included.
 */
export async function chatFor(svc: Service, room: RoomRow, slot: Slot, since: number) {
  const viewerId = slot === "a" ? room.a_player_id : room.b_player_id;
  const hidden = `($2::text is null or c.player_id is null or not exists (
      select 1 from nw_blocks b where b.blocker_id = $2 and b.blocked_id = c.player_id))`;
  const rows = await svc.db.query<ChatRow>(
    `select c.id, c.slot, c.name, c.text, c.preset, c.created_at from nw_chat c
      where c.room_id = $1 and c.id > $3 and ${hidden}
      order by c.id limit ${CHAT_PAGE}`,
    [room.id, viewerId, since],
  );
  const seq = await svc.db.query<{ seq: number | null }>(
    `select max(c.id) as seq from nw_chat c where c.room_id = $1 and ${hidden}`,
    [room.id, viewerId],
  );
  return {
    chat: rows.map((r) => chatMessage(room, slot, r)),
    chat_seq: Number(seq[0]?.seq ?? 0),
  };
}

/** Seconds until the oldest message counted against a full window ages out. */
function retryAfter(nowMs: number, times: number[], [windowMs, max]: [number, number]): number {
  const inWindow = times.filter((t) => nowMs - t < windowMs).sort((a, b) => b - a);
  if (inWindow.length < max) return 0;
  return Math.max(1, Math.ceil((inWindow[max - 1] + windowMs - nowMs) / 1000));
}

/** POST /rooms/<CODE>/chat  body `{text}` or `{preset}` */
export async function postChat(
  svc: Service,
  code: string,
  body: Record<string, unknown>,
  bearer: string | null,
  chatSince: number,
) {
  for (const key of Object.keys(body))
    if (!["text", "preset", "token"].includes(key))
      throw new ApiError(400, `Unknown field: ${key}`);
  const hasText = body.text !== undefined && body.text !== null;
  const hasPreset = body.preset !== undefined && body.preset !== null;
  if (hasText === hasPreset) throw new ApiError(400, "Send either text or preset");

  const bodyToken = typeof body.token === "string" ? body.token : null;
  const { room, slot } = await authorizeFresh(svc, code, [bodyToken, bearer]);
  const playerId = slot === "a" ? room.a_player_id : room.b_player_id;
  const sender = playerId
    ? (
        await svc.db.query<{ screen_name: string | null }>(
          "select screen_name from nw_players where id = $1",
          [playerId],
        )
      )[0]
    : undefined;
  if (!sender?.screen_name) throw new ApiError(403, "Create a screen name to chat");
  const envelope = () => roomEnvelope(svc, room, slot);
  if (room.status === "waiting")
    throw new ApiError(409, "Waiting for an opponent to join", envelope());
  if (room.status === "closed") throw new ApiError(409, "This room is closed", envelope());

  let text: string;
  let preset: string | null = null;
  let filtered = false;
  if (hasPreset) {
    if (typeof body.preset !== "string" || !Object.hasOwn(CHAT_PRESETS, body.preset))
      throw new ApiError(400, "Unknown preset");
    preset = body.preset;
    text = CHAT_PRESETS[preset];
  } else {
    const checked = checkChatText(body.text);
    if (!checked.ok) throw new ApiError(400, checked.error);
    text = checked.text;
    filtered = checked.filtered;
  }

  // Insert only while under both per-player windows (counted in the database).
  const now = svc.now();
  const nowMs = now.getTime();
  const [[w1, max1], [w2, max2]] = CHAT_LIMITS;
  const inserted = await svc.db.query<{ id: number }>(
    `insert into nw_chat (room_id, round, seat, slot, player_id, name, text, preset, filtered, created_at)
     select $1, $2, $3, $4, $5, $6, $7, $8, $9, $10
      where (select count(*) from nw_chat where player_id = $5 and created_at > $11) < $12
        and (select count(*) from nw_chat where player_id = $5 and created_at > $13) < $14
     returning id`,
    [
      room.id,
      room.round,
      seatOf(room, slot),
      slot,
      playerId,
      sender.screen_name,
      text,
      preset,
      filtered,
      now,
      new Date(nowMs - w1),
      max1,
      new Date(nowMs - w2),
      max2,
    ],
  );
  if (inserted.length === 0) {
    const recent = await svc.db.query<{ created_at: Date }>(
      `select created_at from nw_chat where player_id = $1 and created_at > $2
        order by created_at desc limit $3`,
      [playerId, new Date(nowMs - w2), max2],
    );
    const times = recent.map((r) => new Date(r.created_at).getTime());
    const retry = Math.max(...CHAT_LIMITS.map((l) => retryAfter(nowMs, times, l)), 1);
    throw new ApiError(429, "You're sending messages too fast. Wait a moment.", {
      retry_after_seconds: retry,
    });
  }
  await touchSeen(svc, room, slot);
  const id = Number(inserted[0].id);
  return {
    ok: true,
    ...roomEnvelope(svc, room, slot),
    message: {
      id,
      seat: seatOf(room, slot),
      mine: true,
      name: sender.screen_name,
      text,
      preset,
      at: now.toISOString(),
      filtered,
    },
    ...(await chatFor(svc, room, slot, chatSince)),
  };
}

// ---------------------------------------------------------------------------
// Blocks and reports (device token required)

/** The caller's latest room with this code and the other player's slot for `seat`. */
async function opponentInRoom(svc: Service, caller: PlayerRow, body: Record<string, unknown>) {
  const code = typeof body.room_code === "string" ? body.room_code.trim().toUpperCase() : "";
  if (!/^[A-Z0-9]{5}$/.test(code))
    throw new ApiError(400, "room_code must be a 5-character room code");
  if (body.seat !== 1 && body.seat !== 2) throw new ApiError(400, "seat must be 1 or 2");
  const rooms = await roomsByCode(svc, code);
  if (rooms.length === 0) throw new ApiError(404, "Room not found or expired");
  const room = rooms.find((r) => r.a_player_id === caller.id || r.b_player_id === caller.id);
  if (!room) throw new ApiError(403, "You weren't in that room");
  const target = slotOfSeat(room, body.seat);
  const targetId = target === "a" ? room.a_player_id : room.b_player_id;
  if (targetId === caller.id) throw new ApiError(400, "That's your own seat");
  const hasTarget = target === "a" || room.b_token_hash !== null;
  if (!hasTarget) throw new ApiError(404, "Nobody is in that seat");
  return {
    room,
    code,
    targetId,
    targetName: (target === "a" ? room.a_name : room.b_name) ?? "",
  };
}

/** POST /players/block `{room_code, seat}` */
export async function blockPlayer(
  svc: Service,
  bearer: string | null,
  body: Record<string, unknown>,
) {
  const caller = await requirePlayer(svc, bearer);
  const { targetId } = await opponentInRoom(svc, caller, body);
  if (!targetId)
    throw new ApiError(409, "That player is playing without an account and can't be blocked");
  await svc.db.query(
    `insert into nw_blocks (blocker_id, blocked_id, created_at) values ($1, $2, $3)
     on conflict (blocker_id, blocked_id) do nothing`,
    [caller.id, targetId, svc.now()],
  );
  return { ok: true, blocked: true };
}

/** DELETE /players/block `{room_code, seat}` or `{name}` */
export async function unblockPlayer(
  svc: Service,
  bearer: string | null,
  body: Record<string, unknown>,
) {
  const caller = await requirePlayer(svc, bearer);
  let targetId: string | null;
  if (typeof body.name === "string" && body.room_code === undefined) {
    const rows = await svc.db.query<{ blocked_id: string }>(
      `select b.blocked_id from nw_blocks b join nw_players p on p.id = b.blocked_id
        where b.blocker_id = $1 and lower(p.screen_name) = lower($2)`,
      [caller.id, body.name.trim()],
    );
    if (rows.length === 0) throw new ApiError(404, "You haven't blocked anyone by that name");
    targetId = rows[0].blocked_id;
  } else {
    targetId = (await opponentInRoom(svc, caller, body)).targetId;
  }
  if (targetId)
    await svc.db.query("delete from nw_blocks where blocker_id = $1 and blocked_id = $2", [
      caller.id,
      targetId,
    ]);
  return { ok: true, blocked: false };
}

/** GET /players/blocks */
export async function listBlocks(svc: Service, bearer: string | null) {
  const caller = await requirePlayer(svc, bearer);
  const rows = await svc.db.query<{ name: string | null; created_at: Date }>(
    `select p.screen_name as name, b.created_at from nw_blocks b
       join nw_players p on p.id = b.blocked_id
      where b.blocker_id = $1 order by b.created_at desc`,
    [caller.id],
  );
  return {
    blocks: rows.map((r) => ({
      name: r.name ?? "Player",
      blocked_at: new Date(r.created_at).toISOString(),
    })),
  };
}

/** POST /reports `{room_code, seat, reason, note?}` */
export async function reportPlayer(
  svc: Service,
  bearer: string | null,
  body: Record<string, unknown>,
) {
  const caller = await requirePlayer(svc, bearer);
  for (const key of Object.keys(body))
    if (!["room_code", "seat", "reason", "note"].includes(key))
      throw new ApiError(400, `Unknown field: ${key}`);
  if (
    typeof body.reason !== "string" ||
    !(REPORT_REASONS as readonly string[]).includes(body.reason)
  )
    throw new ApiError(400, `reason must be one of: ${REPORT_REASONS.join(", ")}`);
  let note: string | null = null;
  if (body.note !== undefined && body.note !== null) {
    if (typeof body.note !== "string") throw new ApiError(400, "note must be text");
    note = normalizeChatText(body.note) || null;
    if (note && [...note].length > NOTE_MAX)
      throw new ApiError(400, `note must be ${NOTE_MAX} characters or fewer`);
  }
  const { room, code, targetId, targetName } = await opponentInRoom(svc, caller, body);

  const now = svc.now();
  const nowMs = now.getTime();
  const [windowMs, max] = REPORT_LIMIT;
  const recent = await svc.db.query<{ created_at: Date }>(
    `select created_at from nw_reports where reporter_id = $1 and created_at > $2
      order by created_at desc limit $3`,
    [caller.id, new Date(nowMs - windowMs), max],
  );
  if (recent.length >= max) {
    const times = recent.map((r) => new Date(r.created_at).getTime());
    throw new ApiError(429, "You've sent a lot of reports. Try again later.", {
      retry_after_seconds: retryAfter(nowMs, times, REPORT_LIMIT),
    });
  }
  const snapshot = targetId
    ? (
        await svc.db.query<{
          text: string;
          preset: string | null;
          filtered: boolean;
          created_at: Date;
        }>(
          `select text, preset, filtered, created_at from nw_chat
            where room_id = $1 and player_id = $2 order by id desc limit ${SNAPSHOT_MAX}`,
          [room.id, targetId],
        )
      )
        .reverse()
        .map((r) => ({
          text: r.text,
          preset: r.preset,
          filtered: r.filtered,
          at: new Date(r.created_at).toISOString(),
        }))
    : [];
  await svc.db.query(
    `insert into nw_reports (reporter_id, reported_id, reported_name, room_code, reason, note, chat_snapshot, created_at)
     values ($1, $2, $3, $4, $5, $6, $7::jsonb, $8)`,
    [caller.id, targetId, targetName, code, body.reason, note, JSON.stringify(snapshot), now],
  );
  return { ok: true };
}

/** GET /capabilities — public, cacheable server feature detection. */
export function capabilities() {
  return {
    account_unlocks: true,
    protocol: 2,
    online2: true,
    chat: true,
    tournaments: true,
    email: true,
    account_deletion: true,
    chat_presets: { ...CHAT_PRESETS },
    tournament_sizes: [...TOURNAMENT_CAPABILITIES.tournament_sizes],
    tournament_min_players: TOURNAMENT_CAPABILITIES.tournament_min_players,
    tournament_start_options: [...TOURNAMENT_CAPABILITIES.tournament_start_options],
  };
}
